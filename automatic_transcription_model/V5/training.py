import os
import numpy as np
import tensorflow as tf
import matplotlib.pyplot as plt
from tensorflow.keras.optimizers import Adam

from create_dataset import find_correct_time_dimension, create_train_val_datasets
from architecture import build_model
from pythonProject.V5.VisualizationCallback import VisualizationCallback, plot_detailed_metrics, \
    visualize_data_alignment
from utils import F1Score, BatchMetricsLogger, VisualizationAfterBatchesCallback, SeparateVisualizationCallback
from note_tracking import visualize_note_tracking, note_tracking, apply_music_language_constraints


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
    def loss_fn(y_true, y_pred):
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1 - 1e-7)

        bce = -y_true * tf.math.log(y_pred) - (1 - y_true) * tf.math.log(1 - y_pred)

        p_t = (y_true * y_pred) + ((1 - y_true) * (1 - y_pred))
        alpha_factor = y_true * alpha + (1 - y_true) * (1 - alpha)
        modulating_factor = tf.pow(1.0 - p_t, gamma)

        loss = alpha_factor * modulating_factor * bce

        return tf.reduce_mean(loss)

    return loss_fn


def compute_class_weights(dataset, samples=20):
    """
    Calculate class weights from dataset statistics
    """
    print("Estimating class weights from dataset...")

    total_frames = 0
    onset_positives = 0
    frame_positives = 0
    offset_positives = 0

    for i, (_, labels) in enumerate(dataset.take(samples)):
        onset_positives += tf.reduce_sum(labels['onset_dense'])
        frame_positives += tf.reduce_sum(labels['frame_dense'])
        offset_positives += tf.reduce_sum(labels['offset_dense'])

        total_frames += tf.reduce_prod(tf.cast(tf.shape(labels['onset_dense']), tf.float32))

    onset_ratio = onset_positives / (total_frames + 1e-7)
    frame_ratio = frame_positives / (total_frames + 1e-7)
    offset_ratio = offset_positives / (total_frames + 1e-7)

    print(f"Class ratios - Onset: {onset_ratio:.6f}, Frame: {frame_ratio:.6f}, Offset: {offset_ratio:.6f}")

    max_weight = 100.0
    onset_weight = min(1.0 / (onset_ratio + 1e-7), max_weight)
    frame_weight = min(1.0 / (frame_ratio + 1e-7), max_weight)
    offset_weight = min(1.0 / (offset_ratio + 1e-7), max_weight)

    weights = {
        'onset': float(onset_weight),
        'frame': float(frame_weight),
        'offset': float(offset_weight)
    }

    print(f"Calculated class weights: {weights}")
    return weights


def count_dataset_samples(dataset):
    """Count the number of samples in a dataset"""
    count = 0
    for _ in dataset:
        count += 1
    return count


def create_callbacks(model_save_path, val_dataset):
    """Create training callbacks"""
    callbacks = []
    vis_path = os.path.join(model_save_path, 'plots')
    os.makedirs(vis_path, exist_ok=True)

    checkpoint_cb = tf.keras.callbacks.ModelCheckpoint(
        os.path.join(model_save_path, 'model_best.keras'),
        save_best_only=True,
        monitor='val_loss',
        verbose=1
    )
    callbacks.append(checkpoint_cb)

    csv_logger = tf.keras.callbacks.CSVLogger(
        os.path.join(model_save_path, 'training_log.csv')
    )
    callbacks.append(csv_logger)

    lr_scheduler = tf.keras.callbacks.ReduceLROnPlateau(
        monitor='val_loss',
        factor=0.5,
        patience=3,
        min_lr=1e-7,
        verbose=1
    )
    callbacks.append(lr_scheduler)

    early_stop = tf.keras.callbacks.EarlyStopping(
        monitor='val_loss',
        patience=10,
        restore_best_weights=True,
        verbose=1
    )
    callbacks.append(early_stop)

    tensorboard_cb = tf.keras.callbacks.TensorBoard(
        log_dir=os.path.join(model_save_path, 'logs'),
        histogram_freq=1,
        write_graph=True,
        update_freq='epoch'
    )
    callbacks.append(tensorboard_cb)

    visualization_callback = VisualizationCallback(
        validation_dataset=val_dataset,
        batch_interval=20,
        epoch_interval=1,
        num_examples=3,
        threshold=[0.3, 0.5],
        save_dir=vis_path
    )
    callbacks.append(visualization_callback)

    # visualization_callback = VisualizationAfterBatchesCallback(
    #     validation_dataset=val_dataset,
    #     batch_interval=20,
    #     num_examples=5,
    #     threshold=0.3
    # )
    # callbacks.append(visualization_callback)
    #
    # separate_visualization_callback = SeparateVisualizationCallback(
    #     validation_dataset=val_dataset,
    #     batch_interval=20,
    #     num_examples=5,
    #     threshold=0.3
    # )
    # callbacks.append(separate_visualization_callback)

    return callbacks


def train_model(dataset_dir, model_save_path, batch_size=8, epochs=50):
    """
    Train the piano transcription model
    """
    os.makedirs(model_save_path, exist_ok=True)
    vis_path = os.path.join(model_save_path, 'plots')
    os.makedirs(vis_path, exist_ok=True)

    np.random.seed(42)
    tf.random.set_seed(42)

    print("Building model...")
    model = build_model(training=True, input_shape=(626, 229, 1))
    print("Using architecture.")

    print("Determining output time dimension...")
    target_time_dim = find_correct_time_dimension(model, input_shape=(626, 229, 1))
    print(f"Using target time dimension: {target_time_dim}")

    print("Creating datasets...")
    val_split = 0.2 # TODO for overfit use 0.5 instead of 0.2

    train_dataset, val_dataset = create_train_val_datasets(
        dataset_dir,
        batch_size=batch_size,
        val_split=val_split
        # TODO Modified
    )

    print("Counting dataset samples...")
    train_size = count_dataset_samples(train_dataset)
    val_size = count_dataset_samples(val_dataset)
    print(f"Training dataset size: {train_size} batches (approx. {train_size * batch_size} samples)")
    print(f"Validation dataset size: {val_size} batches (approx. {val_size * batch_size} samples)")

    for i, (x_batch, y_batch) in enumerate(train_dataset.take(1)):
        for j in range(min(3, len(x_batch))):
            visualize_data_alignment(
                x_batch[j].numpy(),
                {
                    'onset_dense': y_batch['onset_dense'][j].numpy(),
                    'frame_dense': y_batch['frame_dense'][j].numpy(),
                    'offset_dense': y_batch['offset_dense'][j].numpy(),
                    'velocity_dense': y_batch['velocity_dense'][j].numpy()
                },
                save_path=vis_path,
                index=j
            )

    print("Computing class weights from the dataset...")
    class_weights = compute_class_weights(train_dataset)

    print("Configuring loss functions...")
    # losses = {
    #     'onset_dense': weighted_binary_crossentropy(pos_weight=class_weights['onset']['positive']),
    #     'frame_dense': weighted_binary_crossentropy(pos_weight=class_weights['frame']['positive']),
    #     'offset_dense': weighted_binary_crossentropy(pos_weight=class_weights['offset']['positive']),
    #     'velocity_dense': tf.keras.losses.MeanSquaredError(),
    # }
    losses = {
        'onset_dense': weighted_binary_crossentropy(pos_weight=50),
        'frame_dense': weighted_binary_crossentropy(pos_weight=20),
        'offset_dense': weighted_binary_crossentropy(pos_weight=50),
        'velocity_dense': tf.keras.losses.MeanSquaredError()
    }
    # losses = {
    #     'onset_dense': tf.keras.losses.BinaryCrossentropy(),
    #     'frame_dense': tf.keras.losses.BinaryCrossentropy(),
    #     'offset_dense': tf.keras.losses.BinaryCrossentropy(),
    #     'velocity_dense': tf.keras.losses.MeanSquaredError()
    # }
    # losses = {
    #     'onset_dense': focal_loss(gamma=2.0, alpha=0.7),  # TODO maybe increasing alpha to 0.85/0.9
    #     'frame_dense': focal_loss(gamma=2.0, alpha=0.7),
    #     'offset_dense': focal_loss(gamma=2.0, alpha=0.7),
    #     'velocity_dense': tf.keras.losses.MeanSquaredError(),
    # }

    loss_weights = {
        'onset_dense': 1.0,
        'frame_dense': 1.0,
        'offset_dense': 1.0,
        'velocity_dense': 0.5,
    }

    metrics = {
        'onset_dense': [
            tf.keras.metrics.BinaryAccuracy(name='accuracy'),
            tf.keras.metrics.Precision(name="precision"),
            tf.keras.metrics.Recall(name="recall"),
            F1Score(name="f1", threshold=0.2)
        ],
        'frame_dense': [
            tf.keras.metrics.BinaryAccuracy(name='accuracy'),
            tf.keras.metrics.Precision(name="precision"),
            tf.keras.metrics.Recall(name="recall"),
            F1Score(name="f1", threshold=0.2)
        ],
        'offset_dense': [
            tf.keras.metrics.BinaryAccuracy(name='accuracy'),
            tf.keras.metrics.Precision(name="precision"),
            tf.keras.metrics.Recall(name="recall"),
            F1Score(name="f1", threshold=0.2)
        ],
        'velocity_dense': [
            tf.keras.metrics.MeanAbsoluteError(name='mae')
        ],
    }

    print("Compiling model...")
    model.compile(
        optimizer=Adam(learning_rate=1e-4, clipnorm=1.0),
        loss=losses,
        loss_weights=loss_weights,
        metrics=metrics
    )

    model.summary()

    callbacks = create_callbacks(model_save_path, val_dataset)

    print("Starting training...")
    history = model.fit(
        train_dataset,
        epochs=epochs,
        validation_data=val_dataset,
        callbacks=callbacks
    )

    plot_detailed_metrics(history, model_save_path)

    print("Testing model with note tracking...")
    test_model_with_note_tracking(model, val_dataset)

    model.save(os.path.join(model_save_path, 'model_final.keras'))

    print("Training complete!")
    return model, history


def test_model_with_note_tracking(model, dataset, threshold=0.5, num_examples=3):
    """
    Test the model with note tracking post-processing
    """
    for x_batch, y_batch in dataset.take(1):
        if len(x_batch.shape) == 3:
            x_batch = tf.expand_dims(x_batch, axis=-1)

        predictions = model.predict(x_batch)
        onset_preds = predictions[0]
        frame_preds = predictions[1]
        offset_preds = predictions[2]
        velocity_preds = predictions[3]

        for i in range(min(num_examples, len(x_batch))):
            spec = x_batch[i].numpy()

            piano_roll = note_tracking(
                onset_preds[i],
                frame_preds[i],
                offset_preds[i],
                onset_threshold=threshold,
                frame_threshold=threshold * 0.8,
                offset_threshold=threshold
            )

            piano_roll_constrained = apply_music_language_constraints(
                piano_roll,
                max_polyphony=12,
                min_note_duration=3
            )

            visualize_note_tracking(
                spec[:, :, 0],
                onset_preds[i],
                frame_preds[i],
                offset_preds[i],
                velocity_preds[i],
                piano_roll_constrained
            )



if __name__ == "__main__":
    dataset_dir = "../dataset/spectrograms_mel_20s_V3"
    model_save_path = "piano_transcription_model"
    batch_size = 16
    epochs = 50

    model, history = train_model(
        dataset_dir=dataset_dir,
        model_save_path=model_save_path,
        batch_size=batch_size,
        epochs=epochs
    )
