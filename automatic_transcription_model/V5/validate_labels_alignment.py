import matplotlib.pyplot as plt
import numpy as np

from create_dataset import load_numpy_pair

def visualize_data_pair(spec, labels, sample_idx=0, title=None):
    """
    Visualize spectrogram and corresponding labels to verify alignment and quality.

    Parameters:
    -----------
    spec : numpy.ndarray
        Spectrogram data, shape (time, freq, channels)
    labels : dict
        Dictionary of label arrays
    sample_idx : int
        Index of the sample to visualize (when batched)
    title : str, optional
        Title for the plot
    """
    if spec.ndim == 4:
        spec = spec[sample_idx]

    onset = labels['onset_dense']
    frame = labels['frame_dense']
    offset = labels['offset_dense']
    velocity = labels['velocity_dense']

    if onset.ndim == 3:
        onset = onset[sample_idx]
        frame = frame[sample_idx]
        offset = offset[sample_idx]
        velocity = velocity[sample_idx]

    plt.figure(figsize=(15, 12))

    plt.subplot(5, 1, 1)
    plt.imshow(spec[:, :, 0].T, aspect='auto', origin='lower', cmap='viridis')
    plt.colorbar(format='%+2.0f')
    plt.title('Spectrogram')
    plt.ylabel('Frequency bin')

    # Onset labels
    plt.subplot(5, 1, 2)
    plt.imshow(onset.T, aspect='auto', origin='lower', cmap='Greens', vmin=0, vmax=1)
    plt.colorbar()
    plt.title('Onset Labels')
    plt.ylabel('Piano key')

    # Frame labels
    plt.subplot(5, 1, 3)
    plt.imshow(frame.T, aspect='auto', origin='lower', cmap='Blues', vmin=0, vmax=1)
    plt.colorbar()
    plt.title('Frame Labels')
    plt.ylabel('Piano key')

    # Offset labels
    plt.subplot(5, 1, 4)
    plt.imshow(offset.T, aspect='auto', origin='lower', cmap='Reds', vmin=0, vmax=1)
    plt.colorbar()
    plt.title('Offset Labels')
    plt.ylabel('Piano key')

    # Velocity labels
    plt.subplot(5, 1, 5)
    plt.imshow(velocity.T, aspect='auto', origin='lower', cmap='plasma', vmin=0, vmax=1)
    plt.colorbar()
    plt.title('Velocity Labels')
    plt.ylabel('Piano key')
    plt.xlabel('Time frame')

    if title:
        plt.suptitle(title, fontsize=16)

    plt.tight_layout()
    plt.show()

    print(f"Spectrogram shape: {spec.shape}")
    print(f"Onset labels shape: {onset.shape}")
    print(f"Frame labels shape: {frame.shape}")
    print(f"Offset labels shape: {offset.shape}")
    print(f"Velocity labels shape: {velocity.shape}")

    print("\nData statistics:")
    print(f"Spectrogram - Min: {np.min(spec):.2f}, Max: {np.max(spec):.2f}, Mean: {np.mean(spec):.2f}")
    print(f"Number of onset events: {np.sum(onset)}")
    print(f"Number of active frames: {np.sum(frame)}")
    print(f"Number of offset events: {np.sum(offset)}")
    print(f"Average velocity: {np.mean(velocity[frame > 0.5]) if np.any(frame > 0.5) else 0:.2f}")

if __name__ == '__main__':
    spec_path = "dataset/spectrograms_mel/MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav_segment_0_spec.npy"
    label_base_path = "dataset/spectrograms_mel/MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav_segment_0"

    spec, labels = load_numpy_pair(spec_path, label_base_path)
    visualize_data_pair(spec, labels, title="Sample Data Check")
