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


def load_numpy_pair(spec_path, label_base_path):
    """
    Loads a spectrogram and corresponding labels, ensuring time dimensions match.
    """
    spec = np.load(spec_path).T
    # print("Max ", np.max(spec))
    # print("Min ", np.min(spec))
    if spec.ndim == 2:
        spec = np.expand_dims(spec, axis=-1)

    base_dir = os.path.dirname(label_base_path)
    base_name = os.path.basename(label_base_path)
    if '_labels.npy' in base_name:
        base_name = base_name.replace('_labels.npy', '')

    onset_path = os.path.join(base_dir, f"{base_name}_onset_labels.npy")
    frame_path = os.path.join(base_dir, f"{base_name}_frame_labels.npy")
    offset_path = os.path.join(base_dir, f"{base_name}_offset_labels.npy")
    velocity_path = os.path.join(base_dir, f"{base_name}_velocity_labels.npy")

    onset_data = np.load(onset_path).T.astype(np.float32)
    frame_data = np.load(frame_path).T.astype(np.float32)
    offset_data = np.load(offset_path).T.astype(np.float32)
    velocity_data = np.load(velocity_path).T.astype(np.float32)

    if not (onset_data.shape == frame_data.shape == offset_data.shape == velocity_data.shape):
        raise ValueError(
            f"Label shapes don't match: onset {onset_data.shape}, frame {frame_data.shape}, offset {offset_data.shape}, velocity {velocity_data.shape}")

    if spec.shape[0] != onset_data.shape[0]:
        print(f"WARNING: Spectrogram time dimension ({spec.shape[0]}) doesn't match labels ({onset_data.shape[0]})")

    onset_data = (onset_data > 0.5).astype(np.float32)
    offset_data = (offset_data > 0.5).astype(np.float32)
    frame_data = (frame_data > 0.5).astype(np.float32)

    label_dict = {
        'onset_dense': onset_data,
        'frame_dense': frame_data,
        'offset_dense': offset_data,
        'velocity_dense': velocity_data
    }

    # spec_mean = np.mean(spec)
    # spec_std = np.std(spec)
    # if spec_std > 0:
    #     spec_normalized = (spec - spec_mean) / spec_std
    # else:
    #     spec_normalized = spec - spec_mean
    #
    # # return spec_normalized, label_dict
    return spec, label_dict

def create_train_val_datasets(dataset_dir, batch_size=8, shuffle_buffer=100, val_split=0.1):
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
    val_indices = indices[:64]
    train_indices = indices[101:500]
    train_indices = val_indices # TODO changed to overfit test

    train_spec_files = [spec_files[i] for i in train_indices]
    train_label_base_paths = [label_base_paths[i] for i in train_indices]
    val_spec_files = [spec_files[i] for i in val_indices]
    val_label_base_paths = [label_base_paths[i] for i in val_indices]

    print(f"Training on {len(train_spec_files)} samples, validating on {len(val_spec_files)} samples")

    train_dataset = tf.data.Dataset.from_tensor_slices((train_spec_files, train_label_base_paths))
    val_dataset = tf.data.Dataset.from_tensor_slices((val_spec_files, val_label_base_paths))

    def _py_load(spec_path, label_base_path):
        spec_path = spec_path.numpy().decode('utf-8')
        label_base_path = label_base_path.numpy().decode('utf-8')
        spec, labels = load_numpy_pair(spec_path, label_base_path)
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
            labels[key].set_shape([None, 88])
        return spec, labels

    train_dataset = train_dataset.map(_load_and_preprocess,
                                    num_parallel_calls=tf.data.experimental.AUTOTUNE)
    train_dataset = train_dataset.shuffle(shuffle_buffer).batch(batch_size).prefetch(tf.data.experimental.AUTOTUNE)

    val_dataset = val_dataset.map(_load_and_preprocess,
                                num_parallel_calls=tf.data.experimental.AUTOTUNE)
    val_dataset = val_dataset.batch(batch_size).prefetch(tf.data.experimental.AUTOTUNE)

    return train_dataset, val_dataset


def find_correct_time_dimension(model, input_shape):
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
