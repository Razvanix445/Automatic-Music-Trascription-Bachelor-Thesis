import os
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
import tensorflow as tf


def plot_detailed_metrics(history, save_path):
    """Plot detailed training and validation metrics per task"""
    os.makedirs(save_path, exist_ok=True)

    if not history.history:
        print("Warning: History object is empty, skipping metrics plotting")
        return

    loss_metrics = [m for m in history.history.keys() if 'loss' in m and not m.startswith('val_')]
    accuracy_metrics = [m for m in history.history.keys() if 'accuracy' in m and not m.startswith('val_')]
    f1_metrics = [m for m in history.history.keys() if 'f1' in m and not m.startswith('val_')]
    precision_metrics = [m for m in history.history.keys() if 'precision' in m and not m.startswith('val_')]
    recall_metrics = [m for m in history.history.keys() if 'recall' in m and not m.startswith('val_')]
    mae_metrics = [m for m in history.history.keys() if 'mae' in m and not m.startswith('val_')]

    # Create separate plots for each metric type
    metric_groups = [
        ('Loss', loss_metrics),
        ('Accuracy', accuracy_metrics),
        ('F1 Score', f1_metrics),
        ('Precision', precision_metrics),
        ('Recall', recall_metrics),
        ('Mean Absolute Error', mae_metrics)
    ]

    for title, metrics in metric_groups:
        if not metrics:
            continue

        plt.figure(figsize=(12, 6))

        for metric in metrics:
            plt.plot(history.history[metric], label=metric)
            val_metric = f'val_{metric}'
            if val_metric in history.history:
                plt.plot(history.history[val_metric], label=val_metric, linestyle='--')

        plt.title(title)
        plt.xlabel('Epoch')
        plt.ylabel('Value')
        plt.legend()
        plt.grid(True)

        plt.tight_layout()
        plt.savefig(os.path.join(save_path, f'{title.lower().replace(" ", "_")}_metrics.png'))
        plt.close()

    # Save all metrics in a single image for overview
    all_metrics = [m for m in history.history.keys() if not m.startswith('val_')]
    num_metrics = len(all_metrics)

    if num_metrics > 0:
        fig_rows = (num_metrics + 1) // 2
        plt.figure(figsize=(15, 5 * fig_rows))

        for i, metric in enumerate(all_metrics):
            plt.subplot(fig_rows, 2, i + 1)
            plt.plot(history.history[metric], label=f'Training')

            val_metric = f'val_{metric}'
            if val_metric in history.history:
                plt.plot(history.history[val_metric], label=f'Validation')

            plt.title(f'{metric}')
            plt.xlabel('Epoch')
            plt.ylabel('Value')
            plt.legend()
            plt.grid(True)

        plt.tight_layout()
        plt.savefig(os.path.join(save_path, 'training_metrics_all.png'))
        plt.close()


def visualize_data_alignment(spectrogram, labels, threshold=0.5, save_path=None, index=0):
    """
    Visualize alignment between spectrogram and labels (onset, frame, offset, velocity)
    """
    if len(spectrogram.shape) == 3:
        spectrogram = spectrogram[:, :, 0]

    onset_data = labels['onset_dense'] if isinstance(labels, dict) else labels[0]
    frame_data = labels['frame_dense'] if isinstance(labels, dict) else labels[1]
    offset_data = labels['offset_dense'] if isinstance(labels, dict) else labels[2]
    velocity_data = labels['velocity_dense'] if isinstance(labels, dict) else labels[3]

    if isinstance(onset_data, tf.Tensor):
        onset_data = onset_data.numpy()
        frame_data = frame_data.numpy()
        offset_data = offset_data.numpy()
        velocity_data = velocity_data.numpy()

    fig, axes = plt.subplots(5, 1, figsize=(14, 16), sharex=True)

    axes[0].imshow(spectrogram.T, aspect='auto', origin='lower', cmap='viridis')
    axes[0].set_title('Mel Spectrogram')
    axes[0].set_ylabel('Mel Bins')

    onset_cmap = LinearSegmentedColormap.from_list('onset', ['white', 'red'])
    frame_cmap = LinearSegmentedColormap.from_list('frame', ['white', 'blue'])
    offset_cmap = LinearSegmentedColormap.from_list('offset', ['white', 'green'])
    velocity_cmap = LinearSegmentedColormap.from_list('velocity', ['white', 'purple'])

    axes[1].imshow(onset_data.T, aspect='auto', origin='lower', cmap=onset_cmap, vmin=0, vmax=1)
    axes[1].set_title('Onset Labels')
    axes[1].set_ylabel('Piano Key')

    axes[2].imshow(frame_data.T, aspect='auto', origin='lower', cmap=frame_cmap, vmin=0, vmax=1)
    axes[2].set_title('Frame Labels')
    axes[2].set_ylabel('Piano Key')

    axes[3].imshow(offset_data.T, aspect='auto', origin='lower', cmap=offset_cmap, vmin=0, vmax=1)
    axes[3].set_title('Offset Labels')
    axes[3].set_ylabel('Piano Key')

    im = axes[4].imshow(velocity_data.T, aspect='auto', origin='lower', cmap=velocity_cmap, vmin=0, vmax=1)
    axes[4].set_title('Velocity Labels')
    axes[4].set_ylabel('Piano Key')
    axes[4].set_xlabel('Time Frame')

    cbar = fig.colorbar(im, ax=axes[4])
    cbar.set_label('Velocity (0-1)')

    plt.tight_layout()

    if save_path:
        os.makedirs(save_path, exist_ok=True)
        plt.savefig(os.path.join(save_path, f'data_alignment_{index}.png'))
        plt.close()
    else:
        plt.show()


class VisualizationCallback(tf.keras.callbacks.Callback):
    """
    Callback to visualize model predictions and alignment during training
    """

    def __init__(self, validation_dataset, batch_interval=100, epoch_interval=1,
                 num_examples=3, threshold=0.5, save_dir='./visualizations'):
        super().__init__()
        self.validation_dataset = validation_dataset
        self.batch_interval = batch_interval
        self.epoch_interval = epoch_interval
        self.num_examples = num_examples

        # Support for multiple thresholds
        if isinstance(threshold, list):
            self.threshold = threshold
        else:
            self.threshold = [threshold]

        self.save_dir = save_dir
        self.batch_counter = 0
        self.custom_history = {}
        self.epochs_completed = 0

        os.makedirs(save_dir, exist_ok=True)

    def on_train_begin(self, logs=None):
        """Initialize custom history at the beginning of training"""
        self.custom_history = {}

    def on_batch_end(self, batch, logs=None):
        self.batch_counter += 1

        if self.batch_counter % self.batch_interval == 0:
            self._visualize_examples(f'batch_{self.batch_counter}')

    def on_epoch_end(self, epoch, logs=None):
        # Store metrics in custom history
        if logs:
            for key, value in logs.items():
                if key not in self.custom_history:
                    self.custom_history[key] = []
                self.custom_history[key].append(float(value))

        self.epochs_completed += 1

        if (epoch + 1) % self.epoch_interval == 0:
            self._visualize_examples(f'epoch_{epoch + 1}')

            # Only plot metrics if we have at least one complete epoch
            if self.custom_history and all(len(v) > 0 for v in self.custom_history.values()):
                custom_history_obj = type('obj', (object,), {'history': self.custom_history})
                plot_detailed_metrics(custom_history_obj, self.save_dir)
                print(f"Epoch {epoch + 1} metrics plotting completed.")
            else:
                print(f"Epoch {epoch + 1} - Not enough data to plot metrics yet.")

    def _visualize_examples(self, prefix):
        """Visualize predictions on validation examples"""
        for i, (x_batch, y_batch) in enumerate(self.validation_dataset.take(1)):
            predictions = self.model.predict(x_batch)

            if not isinstance(predictions, list) or len(predictions) < 4:
                print(f"Warning: Expected predictions to be a list of 4 arrays, got {type(predictions)}")
                continue

            onset_preds, frame_preds, offset_preds, velocity_preds = predictions

            for j in range(min(self.num_examples, len(x_batch))):
                self._create_full_comparison_plot(
                    x_batch[j].numpy(),
                    {
                        'onset_dense': y_batch['onset_dense'][j].numpy(),
                        'frame_dense': y_batch['frame_dense'][j].numpy(),
                        'offset_dense': y_batch['offset_dense'][j].numpy(),
                        'velocity_dense': y_batch['velocity_dense'][j].numpy()
                    },
                    {
                        'onset_dense': onset_preds[j],
                        'frame_dense': frame_preds[j],
                        'offset_dense': offset_preds[j],
                        'velocity_dense': velocity_preds[j]
                    },
                    f'{prefix}_example_{j}'
                )

    def _create_full_comparison_plot(self, spec, true_labels, pred_labels, title_prefix):
        """Create a plot comparing ground truth and predictions for all label types"""
        if len(spec.shape) == 3:
            spec_display = spec[:, :, 0]
        else:
            spec_display = spec

        fig, axes = plt.subplots(9, 1, figsize=(14, 24), sharex=True)

        axes[0].imshow(spec_display.T, aspect='auto', origin='lower', cmap='viridis')
        axes[0].set_title('Mel Spectrogram')
        axes[0].set_ylabel('Mel Bins')

        onset_cmap = LinearSegmentedColormap.from_list('onset', ['white', 'red'])
        frame_cmap = LinearSegmentedColormap.from_list('frame', ['white', 'blue'])
        offset_cmap = LinearSegmentedColormap.from_list('offset', ['white', 'green'])
        velocity_cmap = LinearSegmentedColormap.from_list('velocity', ['white', 'purple'])

        # Plot onsets (ground truth and predictions)
        axes[1].imshow(true_labels['onset_dense'].T, aspect='auto', origin='lower', cmap=onset_cmap, vmin=0, vmax=1)
        axes[1].set_title('Ground Truth Onsets')
        axes[1].set_ylabel('Piano Key')

        axes[2].imshow(pred_labels['onset_dense'].T, aspect='auto', origin='lower', cmap=onset_cmap, vmin=0, vmax=1)
        axes[2].set_title('Predicted Onsets')
        axes[2].set_ylabel('Piano Key')

        # Plot frames (ground truth and predictions)
        axes[3].imshow(true_labels['frame_dense'].T, aspect='auto', origin='lower', cmap=frame_cmap, vmin=0, vmax=1)
        axes[3].set_title('Ground Truth Frames')
        axes[3].set_ylabel('Piano Key')

        axes[4].imshow(pred_labels['frame_dense'].T, aspect='auto', origin='lower', cmap=frame_cmap, vmin=0, vmax=1)
        axes[4].set_title('Predicted Frames')
        axes[4].set_ylabel('Piano Key')

        # Plot offsets (ground truth and predictions)
        axes[5].imshow(true_labels['offset_dense'].T, aspect='auto', origin='lower', cmap=offset_cmap, vmin=0, vmax=1)
        axes[5].set_title('Ground Truth Offsets')
        axes[5].set_ylabel('Piano Key')

        axes[6].imshow(pred_labels['offset_dense'].T, aspect='auto', origin='lower', cmap=offset_cmap, vmin=0, vmax=1)
        axes[6].set_title('Predicted Offsets')
        axes[6].set_ylabel('Piano Key')

        # Plot velocities (ground truth and predictions)
        axes[7].imshow(true_labels['velocity_dense'].T, aspect='auto', origin='lower', cmap=velocity_cmap, vmin=0,
                       vmax=1)
        axes[7].set_title('Ground Truth Velocities')
        axes[7].set_ylabel('Piano Key')

        axes[8].imshow(pred_labels['velocity_dense'].T, aspect='auto', origin='lower', cmap=velocity_cmap, vmin=0,
                       vmax=1)
        axes[8].set_title('Predicted Velocities')
        axes[8].set_ylabel('Piano Key')
        axes[8].set_xlabel('Time Frame')

        plt.suptitle(title_prefix, fontsize=16)
        plt.tight_layout()

        plt.savefig(os.path.join(self.save_dir, f'{title_prefix}_full_comparison.png'))
        plt.close()

        self._create_thresholded_comparison(true_labels, pred_labels, title_prefix)

    def _create_thresholded_comparison(self, true_labels, pred_labels, title_prefix):
        """Create binary comparison views with different thresholds"""
        for threshold in self.threshold:
            fig, axes = plt.subplots(3, 3, figsize=(15, 12))
            plt.suptitle(f"{title_prefix} (threshold={threshold})", fontsize=16)

            pred_types = [
                ('onset_dense', 0, 0, 'Onsets'),
                ('frame_dense', 0, 1, 'Frames'),
                ('offset_dense', 0, 2, 'Offsets')
            ]

            for pred_type, row, col, title in pred_types:
                # Ground truth (binary)
                binary_true = (true_labels[pred_type] > 0.5).astype(np.float32)
                axes[row, col].imshow(binary_true.T, aspect='auto', origin='lower', cmap='Greys', vmin=0, vmax=1)
                axes[row, col].set_title(f'True {title}')
                axes[row, col].set_ylabel('Piano Key')

                # Predictions (continuous)
                axes[row + 1, col].imshow(pred_labels[pred_type].T, aspect='auto', origin='lower', cmap='viridis',
                                          vmin=0, vmax=1)
                axes[row + 1, col].set_title(f'Pred {title} (Continuous)')
                axes[row + 1, col].set_ylabel('Piano Key')

                # Predictions (binary threshold)
                binary_pred = (pred_labels[pred_type] > threshold).astype(np.float32)
                axes[row + 2, col].imshow(binary_pred.T, aspect='auto', origin='lower', cmap='Greys', vmin=0, vmax=1)
                axes[row + 2, col].set_title(f'Pred {title} (Binary t={threshold})')
                axes[row + 2, col].set_ylabel('Piano Key')
                axes[row + 2, col].set_xlabel('Time Frame')

            plt.tight_layout()
            plt.savefig(os.path.join(self.save_dir, f'{title_prefix}_threshold_{threshold}.png'))
            plt.close()
