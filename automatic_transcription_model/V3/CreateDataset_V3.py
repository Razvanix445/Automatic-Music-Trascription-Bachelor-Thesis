import os
import glob
import numpy as np
import tensorflow as tf


def determine_model_output_shape(model, input_shape):
    """
    Function to determine the output shape of the model for a given input shape.
    """
    dummy_input = np.zeros((1,) + input_shape, dtype=np.float32)

    dummy_output = model.predict(dummy_input, verbose=0)

    output_shapes = {}
    if isinstance(dummy_output, list):
        output_names = [output.name.split('/')[0] for output in model.outputs]
        for i, name in enumerate(output_names):
            output_shapes[name] = dummy_output[i].shape[1]
    else:
        output_shapes[model.output.name.split('/')[0]] = dummy_output.shape[1]

    return output_shapes


def load_numpy_pair(spec_path, label_base_path, time_dim=None):
    """
    Loads a spectrogram and corresponding labels, ensuring time dimensions match.
    """
    spec = np.load(spec_path).T
    # print("Max ", np.max(spec))
    # print("Min ", np.min(spec))
    if spec.ndim == 2:
        spec = np.expand_dims(spec, axis=-1)

    if time_dim is None:
        input_time = spec.shape[0]
        time_dim = input_time // 8

    base_dir = os.path.dirname(label_base_path)
    base_name = os.path.basename(label_base_path)
    if '_labels.npy' in base_name:
        base_name = base_name.replace('_labels.npy', '')

    onset_path = os.path.join(base_dir, f"{base_name}_onset_labels.npy")
    frame_path = os.path.join(base_dir, f"{base_name}_frame_labels.npy")
    offset_path = os.path.join(base_dir, f"{base_name}_offset_labels.npy")
    velocity_path = os.path.join(base_dir, f"{base_name}_velocity_labels.npy")

    if all(os.path.exists(p) for p in [onset_path, frame_path, offset_path, velocity_path]):
        onset_data = np.load(onset_path).T.astype(np.float32)
        frame_data = np.load(frame_path).T.astype(np.float32)
        offset_data = np.load(offset_path).T.astype(np.float32)
        velocity_data = np.load(velocity_path).T.astype(np.float32)
    else:
        old_label_path = os.path.join(base_dir, f"{base_name}_labels.npy")
        if not os.path.exists(old_label_path):
            raise FileNotFoundError(f"Cannot find label files for {base_name}")

        labels_raw = np.load(old_label_path).T.astype(np.float32)

        frame_data = labels_raw

        onset_data = np.zeros_like(frame_data)
        onset_data[0, :] = frame_data[0, :]
        onset_data[1:, :] = np.maximum(0, frame_data[1:, :] - frame_data[:-1, :])

        offset_data = np.zeros_like(frame_data)
        offset_data[:-1, :] = np.maximum(0, frame_data[:-1, :] - frame_data[1:, :])
        offset_data[-1, :] = frame_data[-1, :]

        velocity_data = frame_data / 127.0

    def resize_to_target(data, target_length, mode='bilinear'):
        """Resize label data to target length using various methods"""
        if data.shape[0] == target_length:
            return data

        result = np.zeros((target_length, data.shape[1]), dtype=data.dtype)

        if mode == 'bilinear':
            x_original = np.linspace(0, 1, data.shape[0])
            x_new = np.linspace(0, 1, target_length)

            for i in range(data.shape[1]):
                result[:, i] = np.interp(x_new, x_original, data[:, i])

        elif mode == 'nearest':
            ratio = data.shape[0] / target_length
            for i in range(target_length):
                idx = min(int(i * ratio), data.shape[0] - 1)
                result[i] = data[idx]

        elif mode == 'max_pool':
            for i in range(target_length):
                start_idx = int(i * data.shape[0] / target_length)
                end_idx = int((i + 1) * data.shape[0] / target_length)
                end_idx = min(end_idx, data.shape[0])
                if start_idx < end_idx:
                    result[i] = np.max(data[start_idx:end_idx], axis=0)
                elif start_idx < data.shape[0]:
                    result[i] = data[start_idx]

        return result

    onset_resized = resize_to_target(onset_data, time_dim, mode='max_pool')
    offset_resized = resize_to_target(offset_data, time_dim, mode='max_pool')
    frame_resized = resize_to_target(frame_data, time_dim, mode='bilinear')
    velocity_resized = resize_to_target(velocity_data, time_dim, mode='bilinear')

    onset_resized = (onset_resized > 0.5).astype(np.float32)
    offset_resized = (offset_resized > 0.5).astype(np.float32)
    frame_resized = (frame_resized > 0.5).astype(np.float32)

    label_dict = {
        'onset_dense': onset_resized,
        'frame_dense': frame_resized,
        'offset_dense': offset_resized,
        'velocity_dense': velocity_resized
    }
    # TODO changed spec dim
    # return spec, label_dict
    return spec/80, label_dict


def create_train_val_datasets(dataset_dir, batch_size=8, shuffle_buffer=100, val_split=0.1, target_time_dim=78):
    """
    Creates datasets with labels exactly matching the model output shape
    """
    spec_files = sorted(glob.glob(os.path.join(dataset_dir, '*_spec.npy')))

    label_base_paths = []
    for spec_path in spec_files:
        base_path = spec_path.replace('_spec.npy', '')
        label_base_paths.append(base_path)

    total_samples = len(spec_files)
    indices = np.arange(total_samples)
    np.random.shuffle(indices)

    num_val = int(total_samples * val_split)
    # TODO trained on smaller dataset
    val_indices = indices[:1000]
    train_indices = indices[1001:1100]

    train_spec_files = [spec_files[i] for i in train_indices]
    train_label_base_paths = [label_base_paths[i] for i in train_indices]
    val_spec_files = [spec_files[i] for i in val_indices]
    val_label_base_paths = [label_base_paths[i] for i in val_indices]

    train_dataset = tf.data.Dataset.from_tensor_slices((train_spec_files, train_label_base_paths))
    val_dataset = tf.data.Dataset.from_tensor_slices((val_spec_files, val_label_base_paths))

    def _py_load(spec_path, label_base_path):
        spec_path = spec_path.numpy().decode('utf-8')
        label_base_path = label_base_path.numpy().decode('utf-8')
        spec, labels = load_numpy_pair(spec_path, label_base_path, time_dim=target_time_dim)
        return (spec, labels['onset_dense'], labels['frame_dense'],
                labels['offset_dense'], labels['velocity_dense'])

    def _load_and_preprocess(spec_path, label_base_path):
        outputs = tf.py_function(
            _py_load,
            [spec_path, label_base_path],
            [tf.float32, tf.float32, tf.float32, tf.float32, tf.float32]
        )
        spec = outputs[0]
        labels = {
            'onset_dense': outputs[1],
            'frame_dense': outputs[2],
            'offset_dense': outputs[3],
            'velocity_dense': outputs[4]
        }
        spec.set_shape([None, None, 1])
        for key in labels:
            labels[key].set_shape([target_time_dim, 88])
        return spec, labels

    train_dataset = train_dataset.map(_load_and_preprocess,
                                    num_parallel_calls=tf.data.experimental.AUTOTUNE)
    train_dataset = train_dataset.shuffle(shuffle_buffer).batch(batch_size).prefetch(tf.data.experimental.AUTOTUNE)

    val_dataset = val_dataset.map(_load_and_preprocess,
                                num_parallel_calls=tf.data.experimental.AUTOTUNE)
    val_dataset = val_dataset.batch(batch_size).prefetch(tf.data.experimental.AUTOTUNE)

    return train_dataset, val_dataset


def find_correct_time_dimension(model, input_shape=(625, 229, 1)):
    """
    Find the correct time dimension for all model outputs.
    """
    output_shapes = determine_model_output_shape(model, input_shape)
    print(f"Model output time dimensions: {output_shapes}")

    time_dim = min(output_shapes.values())
    print(f"Target time dimension to use: {time_dim}")
    return time_dim


if __name__ == '__main__':
    dataset_dir = "dataset/spectrograms_mel"
    batch_size = 8
    # train_dataset, val_dataset = create_train_val_datasets(dataset_dir, batch_size=batch_size, val_split=0.1)
