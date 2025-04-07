import csv

import matplotlib.pyplot as plt
import matplotlib.patches as patches

import numpy as np
import tensorflow as tf


class VisualizationAfterBatchesCallback(tf.keras.callbacks.Callback):
    """
    Callback that displays visualizations after a specified number of batches.
    Shows ground truth labels compared to model predictions using a fixed threshold.
    """

    def __init__(self, validation_dataset, batch_interval=10, num_examples=5, threshold=0.3):
        super(VisualizationAfterBatchesCallback, self).__init__()
        self.validation_dataset = validation_dataset
        self.batch_interval = batch_interval
        self.num_examples = num_examples
        self.threshold = threshold
        self.batch_count = 0

    def on_batch_end(self, batch, logs=None):
        self.batch_count += 1
        if self.batch_count % self.batch_interval == 0:
            print(f"\n--- Visualizing predictions after {self.batch_count} batches ---")
            self.visualize_piano_roll_predictions()

    def visualize_piano_roll_predictions(self):
        """
        Create visualizations showing ground truth vs model predictions
        """
        example_count = 0

        for x_batch, y_batch in self.validation_dataset.take(1):
            if len(x_batch.shape) == 3:
                x_batch = tf.expand_dims(x_batch, axis=-1)

            expected_time_dim = 625
            if x_batch.shape[1] != expected_time_dim:
                x_batch = tf.image.resize(x_batch, [expected_time_dim, x_batch.shape[2]])

            predictions = self.model.predict(x_batch)
            onset_preds = predictions[0]
            frame_preds = predictions[1]
            offset_preds = predictions[2]

            onset_true = y_batch['onset_dense'].numpy()
            frame_true = y_batch['frame_dense'].numpy()

            for i in range(min(x_batch.shape[0], self.num_examples)):
                # Create figure
                fig = plt.figure(figsize=(15, 12))

                plt.subplot(3, 1, 1)
                spec = x_batch[i].numpy()
                plt.imshow(spec[:, :, 0].T, aspect='auto', origin='lower', cmap='magma')
                plt.title("Mel Spectrogram")
                plt.ylabel("Mel Frequency Bins")
                plt.xlabel("Time Frames")

                plt.subplot(3, 2, 3)
                onset_true_binary = onset_true[i] > 0.5
                plt.imshow(onset_true_binary.T, aspect='auto', origin='lower', cmap='Blues', alpha=0.7)
                plt.title("Ground Truth Onsets")
                plt.ylabel("MIDI Note Number")

                plt.subplot(3, 2, 4)
                onset_pred_binary = onset_preds[i] > self.threshold
                plt.imshow(onset_pred_binary.T, aspect='auto', origin='lower', cmap='Reds', alpha=0.7)
                plt.title(f"Predicted Onsets (threshold={self.threshold:.2f})")

                plt.subplot(3, 1, 3)
                frame_comparison = np.zeros((frame_true[i].shape[0], frame_true[i].shape[1], 3))

                frame_true_binary = frame_true[i] > 0.5
                frame_pred_binary = frame_preds[i] > self.threshold

                tp_mask = np.logical_and(frame_true_binary, frame_pred_binary)
                frame_comparison[tp_mask, 1] = 1.0

                fp_mask = np.logical_and(np.logical_not(frame_true_binary), frame_pred_binary)
                frame_comparison[fp_mask, 0] = 1.0

                fn_mask = np.logical_and(frame_true_binary, np.logical_not(frame_pred_binary))
                frame_comparison[fn_mask, 2] = 1.0

                plt.imshow(frame_comparison.transpose(1, 0, 2), aspect='auto', origin='lower')
                plt.title("Frame Comparison (Green=Correct, Red=False Pos., Blue=False Neg.)")
                plt.ylabel("MIDI Note Number")
                plt.xlabel("Time Frames")

                legend_elements = [
                    patches.Patch(facecolor='green', label='True Positive'),
                    patches.Patch(facecolor='red', label='False Positive'),
                    patches.Patch(facecolor='blue', label='False Negative')
                ]
                plt.legend(handles=legend_elements, loc='upper right')

                tp_total = np.sum(np.logical_and(frame_true_binary, frame_pred_binary))
                fp_total = np.sum(np.logical_and(np.logical_not(frame_true_binary), frame_pred_binary))
                fn_total = np.sum(np.logical_and(frame_true_binary, np.logical_not(frame_pred_binary)))

                precision = tp_total / (tp_total + fp_total + 1e-8)
                recall = tp_total / (tp_total + fn_total + 1e-8)
                f1 = 2 * precision * recall / (precision + recall + 1e-8)

                plt.figtext(0.5, 0.01,
                            f"Overall: Precision={precision:.3f}, Recall={recall:.3f}, F1={f1:.3f}",
                            fontsize=12, weight='bold', ha='center')

                plt.tight_layout(rect=[0, 0.05, 1, 0.95])
                plt.suptitle(
                    f"Piano Transcription Visualization - Batch {self.batch_count} (Example {example_count + 1})",
                    fontsize=16)
                plt.subplots_adjust(top=0.92)

                plt.show()

                example_count += 1

            print("\n=== Raw Prediction Values ===")
            print(f"Onset predictions:")
            print(f"  Min value: {np.min(onset_preds):.10f}")
            print(f"  Max value: {np.max(onset_preds):.10f}")
            print(f"  Mean value: {np.mean(onset_preds):.10f}")
            print(f"  Median value: {np.median(onset_preds):.10f}")

            for thresh in [0.01, 0.05, 0.1, 0.2, 0.5]:
                percent_above = 100 * np.mean(onset_preds > thresh)
                print(f"  Values > {thresh}: {percent_above:.4f}%")

            print(f"\nFrame predictions:")
            print(f"  Min value: {np.min(frame_preds):.10f}")
            print(f"  Max value: {np.max(frame_preds):.10f}")
            print(f"  Mean value: {np.mean(frame_preds):.10f}")
            print(f"  Median value: {np.median(frame_preds):.10f}")

            for thresh in [0.01, 0.05, 0.1, 0.2, 0.5]:
                percent_above = 100 * np.mean(frame_preds > thresh)
                print(f"  Values > {thresh}: {percent_above:.4f}%")

            break


class SeparateVisualizationCallback(tf.keras.callbacks.Callback):
    """
    Callback that displays visualizations for all four prediction types
    after a specified number of batches.
    """

    def __init__(self, validation_dataset, batch_interval=10, num_examples=5, threshold=0.3):
        super(SeparateVisualizationCallback, self).__init__()
        self.validation_dataset = validation_dataset
        self.batch_interval = batch_interval
        self.num_examples = num_examples
        self.threshold = threshold
        self.batch_count = 0

    def on_batch_end(self, batch, logs=None):
        self.batch_count += 1
        if self.batch_count % self.batch_interval == 0:
            print(f"\n--- Visualizing all predictions after {self.batch_count} batches ---")
            display_predictions_vs_truth(self.model, self.validation_dataset,
                                         self.num_examples, self.threshold)


def display_predictions_vs_truth(model, dataset, num_examples=5, threshold=0.3):
    """
    Displays model predictions vs ground truth for all four prediction types
    (onset, frame, offset, velocity) for examples from the provided dataset.
    """
    import matplotlib.pyplot as plt
    import numpy as np

    example_count = 0

    for x_batch, y_batch in dataset.take(1):
        predictions = model.predict(x_batch)

        onset_preds = predictions[0]
        frame_preds = predictions[1]
        offset_preds = predictions[2]
        velocity_preds = predictions[3]

        onset_true = y_batch['onset_dense'].numpy()
        frame_true = y_batch['frame_dense'].numpy()
        offset_true = y_batch['offset_dense'].numpy()
        velocity_true = y_batch['velocity_dense'].numpy()

        for i in range(min(x_batch.shape[0], num_examples)):
            fig = plt.figure(figsize=(18, 14))

            plt.subplot(5, 1, 1)
            spec = x_batch[i].numpy()
            plt.imshow(spec[:, :, 0].T, aspect='auto', origin='lower', cmap='magma')
            plt.title("Mel Spectrogram")
            plt.ylabel("Mel Frequency Bins")
            plt.xlabel("Time Frames")

            plt.subplot(5, 2, 3)
            onset_true_binary = onset_true[i] > 0.5
            plt.imshow(onset_true_binary.T, aspect='auto', origin='lower', cmap='Blues')
            plt.title("Ground Truth Onsets")
            plt.ylabel("MIDI Note Number")

            plt.subplot(5, 2, 4)
            onset_pred_binary = onset_preds[i] > threshold
            plt.imshow(onset_pred_binary.T, aspect='auto', origin='lower', cmap='Blues')
            plt.title(f"Predicted Onsets (threshold={threshold:.2f})")

            plt.subplot(5, 2, 5)
            frame_true_binary = frame_true[i] > 0.5
            plt.imshow(frame_true_binary.T, aspect='auto', origin='lower', cmap='Greens')
            plt.title("Ground Truth Frames")
            plt.ylabel("MIDI Note Number")

            plt.subplot(5, 2, 6)
            frame_pred_binary = frame_preds[i] > threshold
            plt.imshow(frame_pred_binary.T, aspect='auto', origin='lower', cmap='Greens')
            plt.title(f"Predicted Frames (threshold={threshold:.2f})")

            plt.subplot(5, 2, 7)
            offset_true_binary = offset_true[i] > 0.5
            plt.imshow(offset_true_binary.T, aspect='auto', origin='lower', cmap='Reds')
            plt.title("Ground Truth Offsets")
            plt.ylabel("MIDI Note Number")

            plt.subplot(5, 2, 8)
            offset_pred_binary = offset_preds[i] > threshold
            plt.imshow(offset_pred_binary.T, aspect='auto', origin='lower', cmap='Reds')
            plt.title(f"Predicted Offsets (threshold={threshold:.2f})")

            plt.subplot(5, 2, 9)
            plt.imshow(velocity_true[i].T, aspect='auto', origin='lower', cmap='viridis')
            plt.title("Ground Truth Velocity")
            plt.ylabel("MIDI Note Number")
            plt.xlabel("Time Frames")

            plt.subplot(5, 2, 10)
            plt.imshow(velocity_preds[i].T, aspect='auto', origin='lower', cmap='viridis')
            plt.title("Predicted Velocity")
            plt.xlabel("Time Frames")

            onset_tp = np.sum(np.logical_and(onset_true_binary, onset_pred_binary))
            onset_fp = np.sum(np.logical_and(np.logical_not(onset_true_binary), onset_pred_binary))
            onset_fn = np.sum(np.logical_and(onset_true_binary, np.logical_not(onset_pred_binary)))

            frame_tp = np.sum(np.logical_and(frame_true_binary, frame_pred_binary))
            frame_fp = np.sum(np.logical_and(np.logical_not(frame_true_binary), frame_pred_binary))
            frame_fn = np.sum(np.logical_and(frame_true_binary, np.logical_not(frame_pred_binary)))

            offset_tp = np.sum(np.logical_and(offset_true_binary, offset_pred_binary))
            offset_fp = np.sum(np.logical_and(np.logical_not(offset_true_binary), offset_pred_binary))
            offset_fn = np.sum(np.logical_and(offset_true_binary, np.logical_not(offset_pred_binary)))

            onset_precision = onset_tp / (onset_tp + onset_fp + 1e-8)
            onset_recall = onset_tp / (onset_tp + onset_fn + 1e-8)
            onset_f1 = 2 * onset_precision * onset_recall / (onset_precision + onset_recall + 1e-8)

            frame_precision = frame_tp / (frame_tp + frame_fp + 1e-8)
            frame_recall = frame_tp / (frame_tp + frame_fn + 1e-8)
            frame_f1 = 2 * frame_precision * frame_recall / (frame_precision + frame_recall + 1e-8)

            offset_precision = offset_tp / (offset_tp + offset_fp + 1e-8)
            offset_recall = offset_tp / (offset_tp + offset_fn + 1e-8)
            offset_f1 = 2 * offset_precision * offset_recall / (offset_precision + offset_recall + 1e-8)

            velocity_mae = np.mean(np.abs(velocity_true[i] - velocity_preds[i]))

            plt.figtext(0.5, 0.01,
                        f"Metrics: Onset F1={onset_f1:.3f}, Frame F1={frame_f1:.3f}, Offset F1={offset_f1:.3f}, Velocity MAE={velocity_mae:.3f}",
                        fontsize=12, weight='bold', ha='center')

            plt.tight_layout(rect=[0, 0.03, 1, 0.95])
            plt.suptitle(f"Piano Transcription Evaluation - Example {example_count + 1}", fontsize=16)
            plt.subplots_adjust(top=0.92, hspace=0.4)

            plt.show()

            example_count += 1

        print("\n=== Prediction Statistics ===")
        print(f"Onset predictions:")
        print(f"  Min value: {np.min(onset_preds):.4f}")
        print(f"  Max value: {np.max(onset_preds):.4f}")
        print(f"  Mean value: {np.mean(onset_preds):.4f}")

        print(f"\nFrame predictions:")
        print(f"  Min value: {np.min(frame_preds):.4f}")
        print(f"  Max value: {np.max(frame_preds):.4f}")
        print(f"  Mean value: {np.mean(frame_preds):.4f}")

        print(f"\nOffset predictions:")
        print(f"  Min value: {np.min(offset_preds):.4f}")
        print(f"  Max value: {np.max(offset_preds):.4f}")
        print(f"  Mean value: {np.mean(offset_preds):.4f}")

        print(f"\nVelocity predictions:")
        print(f"  Min value: {np.min(velocity_preds):.4f}")
        print(f"  Max value: {np.max(velocity_preds):.4f}")
        print(f"  Mean value: {np.mean(velocity_preds):.4f}")

        break


class BatchMetricsLogger(tf.keras.callbacks.Callback):
    def __init__(self, csv_file='batch_metrics_20s_V3.csv'):
        super(BatchMetricsLogger, self).__init__()
        self.csv_file = csv_file
        self.fieldnames = None
        self.file = open(self.csv_file, 'w', newline='')
        self.writer = None

    def on_batch_end(self, batch, logs=None):
        logs = logs or {}
        if self.fieldnames is None:
            self.fieldnames = ['batch'] + sorted(logs.keys())
            self.writer = csv.DictWriter(self.file, fieldnames=self.fieldnames)
            self.writer.writeheader()

        metrics_line = f"Batch {batch} metrics: " + ", ".join([f"{key}: {value:.4f}" for key, value in logs.items()])
        print(metrics_line)

        row = {'batch': batch}
        for key in self.fieldnames:
            if key != 'batch':
                row[key] = logs.get(key, None)
        self.writer.writerow(row)
        self.file.flush()

    def on_train_end(self, logs=None):
        self.file.close()


class F1Score(tf.keras.metrics.Metric):
    def __init__(self, name='f1_score', threshold=0.3, **kwargs):
        super(F1Score, self).__init__(name=name, **kwargs)
        self.threshold = threshold
        self.precision = tf.keras.metrics.Precision(thresholds=threshold)
        self.recall = tf.keras.metrics.Recall(thresholds=threshold)

    def update_state(self, y_true, y_pred, sample_weight=None):
        self.precision.update_state(y_true, y_pred, sample_weight)
        self.recall.update_state(y_true, y_pred, sample_weight)

    def result(self):
        p = self.precision.result()
        r = self.recall.result()
        return tf.math.divide_no_nan(2 * p * r, p + r)

    def reset_states(self):
        self.precision.reset_states()
        self.recall.reset_states()
