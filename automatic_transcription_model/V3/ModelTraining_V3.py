import os
import glob

import numpy as np
import tensorflow as tf
from tensorflow.keras.optimizers import Adam

import Callbacks
import CreateDataset_V3
import ModelArchitecture_V3


def weighted_binary_crossentropy(pos_weight):
    """
    Function for giving more weight to the positive class (where the notes are being played)
    """

    def loss(y_true, y_pred):
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1.0 - 1e-7)
        loss_pos = -pos_weight * y_true * tf.math.log(y_pred)
        loss_neg = -(1 - y_true) * tf.math.log(1 - y_pred)

        loss = loss_pos + loss_neg

        return tf.reduce_mean(loss)

    return loss


def focal_loss(gamma=2.0, alpha=0.25):
    """
    Function for reducing more loss to the positive class (where the notes are being played)
    and focuses on hard, misclassified examples.
    """

    def loss_fn(y_true, y_pred):
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1 - 1e-7)

        bce = -y_true * tf.math.log(y_pred) - (1 - y_true) * tf.math.log(1 - y_pred)

        p_t = (y_true * y_pred) + ((1 - y_true) * (1 - y_pred))
        alpha_factor = y_true * alpha + (1 - y_true) * (1 - alpha)
        modulating_factor = tf.pow(1.0 - p_t, gamma)

        loss = alpha_factor * modulating_factor * bce

        return tf.reduce_mean(loss)

    return loss_fn


def compute_class_weights(dataset, samples=100):
    """
    Function to determine class weights
    """
    print("Estimating class weights from dataset...")

    total_pixels = 0
    onset_positives = 0
    frame_positives = 0
    offset_positives = 0

    for i, (_, labels) in enumerate(dataset.take(samples)):
        if i >= samples:
            break

        onset_positives += tf.reduce_sum(labels['onset_dense'])
        frame_positives += tf.reduce_sum(labels['frame_dense'])
        offset_positives += tf.reduce_sum(labels['offset_dense'])

        total_pixels += tf.reduce_prod(tf.cast(tf.shape(labels['onset_dense']), tf.float32))

    onset_pos_weight = (total_pixels - onset_positives) / (onset_positives + 1e-7)
    frame_pos_weight = (total_pixels - frame_positives) / (frame_positives + 1e-7)
    offset_pos_weight = (total_pixels - offset_positives) / (offset_positives + 1e-7)

    max_weight = 100.0
    onset_pos_weight = min(onset_pos_weight, max_weight)
    frame_pos_weight = min(frame_pos_weight, max_weight)
    offset_pos_weight = min(offset_pos_weight, max_weight)

    weights = {
        'onset': float(onset_pos_weight),
        'frame': float(frame_pos_weight),
        'offset': float(offset_pos_weight)
    }

    print(f"Estimated class weights: {weights}")
    return weights


def load_data(spectrogram_dir):
    """
        Loads spectrograms and separate label files for each task.
    """
    spec_files = sorted(glob.glob(os.path.join(spectrogram_dir, '*_spec.npy')))

    X, Y_onset, Y_frame, Y_offset, Y_velocity = [], [], [], [], []

    for spec_file in spec_files:
        base_path = spec_file.replace('_spec.npy', '')

        onset_path = f"{base_path}_onset_labels.npy"
        frame_path = f"{base_path}_frame_labels.npy"
        offset_path = f"{base_path}_offset_labels.npy"
        velocity_path = f"{base_path}_velocity_labels.npy"

        if not all(os.path.exists(path) for path in [onset_path, frame_path, offset_path, velocity_path]):
            print(f"Skipping {base_path}, missing some label files.")
            continue

        spec = np.load(spec_file).T
        spec = np.expand_dims(spec, axis=-1)

        onset_labels = np.load(onset_path).T.astype(np.float32)
        frame_labels = np.load(frame_path).T.astype(np.float32)
        offset_labels = np.load(offset_path).T.astype(np.float32)
        velocity_labels = np.load(velocity_path).T.astype(np.float32)

        X.append(spec)
        Y_onset.append(onset_labels)
        Y_frame.append(frame_labels)
        Y_offset.append(offset_labels)
        Y_velocity.append(velocity_labels)

    X = np.array(X)
    Y = {
        'onset_dense': np.array(Y_onset),
        'frame_dense': np.array(Y_frame),
        'offset_dense': np.array(Y_offset),
        'velocity_dense': np.array(Y_velocity)
    }

    return X, Y


if __name__ == "__main__":
    dataset_dir = "../dataset/spectrograms_mel_20s"

    np.random.seed(42)
    tf.random.set_seed(42)

    batch_logger = Callbacks.BatchMetricsLogger(csv_file='../batch_metrics_20s_V3.csv')

    batch_size = 16
    val_split = 0.1
    input_shape = (625, 229, 1)

    print("Building model...")
    model = ModelArchitecture_V3.build_model(input_shape, training=True)

    print("Determining model output dimensions...")
    target_time_dim = CreateDataset_V3.find_correct_time_dimension(model, input_shape)
    print(f"Using target time dimension: {target_time_dim}")

    print("Creating datasets...")
    train_dataset, val_dataset = CreateDataset_V3.create_train_val_datasets(
        dataset_dir,
        batch_size=batch_size,
        val_split=val_split,
        target_time_dim=target_time_dim
    )

    class_weights = compute_class_weights(train_dataset, samples=20)
    print(f"Original calculated weights: {class_weights}")
    print(f"Modified weights: {class_weights}")

    loss_approach = 'weighted_bce'
    if loss_approach == 'weighted_bce':
        losses = {
            # TODO changed to fixed weight
            # 'onset_dense': weighted_binary_crossentropy(pos_weight=class_weights['onset']),
            # 'frame_dense': weighted_binary_crossentropy(pos_weight=class_weights['frame']),
            # 'offset_dense': weighted_binary_crossentropy(pos_weight=class_weights['offset']),
            'onset_dense': weighted_binary_crossentropy(pos_weight=10),
            'frame_dense': weighted_binary_crossentropy(pos_weight=10),
            'offset_dense': weighted_binary_crossentropy(pos_weight=10),
            'velocity_dense': tf.keras.losses.MeanSquaredError(),
        }
    else:
        losses = {
            'onset_dense': focal_loss(gamma=2.0, alpha=0.75),
            'frame_dense': focal_loss(gamma=2.0, alpha=0.75),
            'offset_dense': focal_loss(gamma=2.0, alpha=0.75),
            'velocity_dense': tf.keras.losses.MeanSquaredError(),
        }

    # TODO changed loss weights
    loss_weights = {
        'onset_dense': 1.0,
        'frame_dense': 0.0,
        'offset_dense': 0.0,
        'velocity_dense': 0.0,
    }

    metrics = {
        'onset_dense': [
            tf.keras.metrics.BinaryAccuracy(name='onset_accuracy'),
            tf.keras.metrics.Precision(name="onset_precision"),
            tf.keras.metrics.Recall(name="onset_recall"),
            Callbacks.F1Score(name="onset_f1")
        ],
        'frame_dense': [
            tf.keras.metrics.BinaryAccuracy(name='frame_accuracy'),
            tf.keras.metrics.Precision(name="frame_precision"),
            tf.keras.metrics.Recall(name="frame_recall")
        ],
        'offset_dense': [
            tf.keras.metrics.BinaryAccuracy(name='offset_accuracy'),
            tf.keras.metrics.Precision(name="offset_precision"),
            tf.keras.metrics.Recall(name="offset_recall")
        ],
        'velocity_dense': [
            tf.keras.metrics.MeanAbsoluteError(name='velocity_mae')
        ],
    }

    print("Compiling model...")
    model.compile(
        optimizer=Adam(learning_rate=5e-5),
        loss=losses,
        loss_weights=loss_weights,
        metrics=metrics
    )

    model.summary()

    checkpoint_cb = tf.keras.callbacks.ModelCheckpoint(
        'model_best.keras',
        save_best_only=True,
        monitor='val_loss')

    early_stop_cb = tf.keras.callbacks.EarlyStopping(
        patience=10,
        restore_best_weights=True
    )

    reduce_lr_cb = tf.keras.callbacks.ReduceLROnPlateau(
        monitor='val_loss',
        factor=0.5,
        patience=5,
        min_lr=1e-6,
        verbose=1
    )

    visualization_callback = Callbacks.VisualizationAfterBatchesCallback(
        validation_dataset=val_dataset,
        batch_interval=20,
        num_examples=5,
        threshold=0.3
    )

    separate_visualization_callback = Callbacks.SeparateVisualizationCallback(
        validation_dataset=val_dataset,
        batch_interval=20,
        num_examples=5,
        threshold=0.3
    )

    print("Starting training...")
    history = model.fit(
        train_dataset,
        epochs=100,
        validation_data=val_dataset,
        callbacks=[checkpoint_cb, early_stop_cb, batch_logger, visualization_callback, separate_visualization_callback])

    model.save('model_final.keras')

    print("Training complete!")