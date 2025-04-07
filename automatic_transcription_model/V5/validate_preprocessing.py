import numpy as np
import matplotlib.pyplot as plt
import os
import librosa
import glob
import soundfile as sf
import pretty_midi


def visualize_segment(output_dir, base_name, segment_num):
    """
    Visualize a processed segment with its corresponding labels.

    Parameters:
    -----------
    output_dir : str
        Directory where processed files are stored
    base_name : str
        Base name of the processed files
    segment_num : int
        Segment number to visualize
    """
    spec_filename = f"{base_name}_segment_{segment_num}_spec.npy"
    spec_path = os.path.join(output_dir, spec_filename)

    if not os.path.exists(spec_path):
        print(f"Error: Spectrogram file not found: {spec_path}")
        return

    log_mel_spec = np.load(spec_path)

    labels = {}
    for label_type in ['onset', 'frame', 'offset', 'velocity']:
        label_filename = f"{base_name}_segment_{segment_num}_{label_type}_labels.npy"
        label_path = os.path.join(output_dir, label_filename)

        if not os.path.exists(label_path):
            print(f"Warning: Label file not found: {label_path}")
            continue

        labels[label_type] = np.load(label_path)

    fig, axes = plt.subplots(5, 1, figsize=(14, 16), gridspec_kw={'height_ratios': [3, 2, 2, 2, 2]})

    im_spec = axes[0].imshow(log_mel_spec, origin='lower', aspect='auto', interpolation='nearest', cmap='viridis')
    axes[0].set_title(f"Log Mel Spectrogram - {base_name} - Segment {segment_num}")
    axes[0].set_ylabel("Mel Frequency Bin")
    plt.colorbar(im_spec, ax=axes[0], format='%+2.0f dB')

    for i, (label_type, label_data) in enumerate(labels.items(), start=1):
        cmap = {
            'onset': 'Greens',
            'frame': 'Blues',
            'offset': 'Reds',
            'velocity': 'plasma'
        }.get(label_type, 'Greys')

        im = axes[i].imshow(label_data, origin='lower', aspect='auto', interpolation='nearest', cmap=cmap)
        axes[i].set_title(f"{label_type.capitalize()} Labels")
        axes[i].set_ylabel("Piano Key (0-87)")
        plt.colorbar(im, ax=axes[i])

    plt.tight_layout()
    plt.show()

    print(f"Spectrogram shape: {log_mel_spec.shape}")
    for label_type, label_data in labels.items():
        print(f"{label_type.capitalize()} labels shape: {label_data.shape}")
        print(f"{label_type.capitalize()} non-zero values: {np.count_nonzero(label_data)}")

    if 'onset' in labels and 'frame' in labels:
        onset_sum = np.sum(labels['onset'], axis=1)
        frame_sum = np.sum(labels['frame'], axis=1)

        print("\nNotes per key:")
        for i in range(88):
            if onset_sum[i] > 0:
                note_name = librosa.midi_to_note(i + 21)
                print(f"Key {i} ({note_name}): {int(onset_sum[i])} onsets, active for {int(frame_sum[i])} frames")

    return fig


def validate_preprocessed_data(output_dir, base_name=None):
    """
    Perform validation checks on preprocessed data to ensure quality and correctness.

    Parameters:
    -----------
    output_dir : str
        Directory where processed files are stored
    base_name : str, optional
        If provided, only check files for this base_name
    """
    if base_name:
        spec_files = glob.glob(os.path.join(output_dir, f"{base_name}_segment_*_spec.npy"))
    else:
        spec_files = glob.glob(os.path.join(output_dir, "*_segment_*_spec.npy"))

    if not spec_files:
        print(f"No spectrogram files found in {output_dir}")
        return

    print(f"Found {len(spec_files)} spectrogram files")

    valid_count = 0
    issues = []

    for spec_file in spec_files:
        filename = os.path.basename(spec_file)
        base = filename.split("_segment_")[0]
        seg_num = int(filename.split("_segment_")[1].split("_")[0])

        print(f"Checking {base} segment {seg_num}...", end="")

        all_files_exist = True
        missing_files = []

        try:
            spec = np.load(spec_file)
            spec_shape = spec.shape
        except Exception as e:
            issues.append(f"{filename}: Could not load spectrogram file: {e}")
            print(" FAILED (could not load spectrogram)")
            continue

        label_shapes = {}
        label_issues = []

        for label_type in ['onset', 'frame', 'offset', 'velocity']:
            label_file = os.path.join(output_dir, f"{base}_segment_{seg_num}_{label_type}_labels.npy")

            if not os.path.exists(label_file):
                missing_files.append(f"{label_type}_labels.npy")
                all_files_exist = False
                continue

            try:
                label_data = np.load(label_file)
                label_shapes[label_type] = label_data.shape

                if label_type == 'onset' or label_type == 'offset':
                    if np.max(label_data) > 1 or np.min(label_data) < 0:
                        label_issues.append(
                            f"{label_type} values outside [0,1] range: min={np.min(label_data)}, max={np.max(label_data)}")

                elif label_type == 'frame':
                    if np.max(label_data) > 1 or np.min(label_data) < 0:
                        label_issues.append(
                            f"frame values outside [0,1] range: min={np.min(label_data)}, max={np.max(label_data)}")

                elif label_type == 'velocity':
                    if np.max(label_data) > 1 or np.min(label_data) < 0:
                        label_issues.append(
                            f"velocity values outside [0,1] range: min={np.min(label_data)}, max={np.max(label_data)}")

            except Exception as e:
                issues.append(f"{label_file}: Could not load label file: {e}")
                all_files_exist = False

        if all_files_exist:
            expected_onset_shape = (88, spec_shape[1])
            shape_issues = []

            for label_type, shape in label_shapes.items():
                if shape[0] != 88:
                    shape_issues.append(f"{label_type} has {shape[0]} keys instead of 88")

                if shape[1] != spec_shape[1]:
                    shape_issues.append(f"{label_type} has {shape[1]} frames but spectrogram has {spec_shape[1]}")

            log_issues = []
            if 'onset' in label_shapes and 'frame' in label_shapes:
                onset_data = np.load(os.path.join(output_dir, f"{base}_segment_{seg_num}_onset_labels.npy"))
                frame_data = np.load(os.path.join(output_dir, f"{base}_segment_{seg_num}_frame_labels.npy"))

                for key in range(88):
                    onset_positions = np.where(onset_data[key] > 0.5)[0]
                    for pos in onset_positions:
                        if pos < frame_data.shape[1] - 1:
                            if frame_data[key, pos] == 0:
                                log_issues.append(f"Key {key} has onset at frame {pos} but frame is not active")

            if missing_files:
                issues.append(f"{filename}: Missing files: {', '.join(missing_files)}")

            if shape_issues:
                issues.append(f"{filename}: Shape issues: {'; '.join(shape_issues)}")

            if label_issues:
                issues.append(f"{filename}: Label issues: {'; '.join(label_issues)}")

            if log_issues:
                issues.append(f"{filename}: Logical issues: {'; '.join(log_issues[:5])}")
                if len(log_issues) > 5:
                    issues[-1] += f" (and {len(log_issues) - 5} more)"

        if all_files_exist and not shape_issues and not label_issues and not log_issues:
            valid_count += 1
            print(" OK")
        else:
            print(" ISSUES FOUND")

    print("\n===== VALIDATION SUMMARY =====")
    print(f"Total files checked: {len(spec_files)}")
    print(f"Valid files: {valid_count} ({valid_count / len(spec_files) * 100:.1f}%)")
    print(f"Files with issues: {len(spec_files) - valid_count}")

    if issues:
        print("\n===== ISSUES FOUND =====")
        for i, issue in enumerate(issues[:20], 1):
            print(f"{i}. {issue}")

        if len(issues) > 20:
            print(f"...and {len(issues) - 20} more issues (see log file for details)")

        log_file = os.path.join(output_dir, "validation_issues.log")
        with open(log_file, 'w') as f:
            f.write(f"Validation issues for {output_dir}\n")
            f.write(
                f"Total files: {len(spec_files)}, Valid: {valid_count}, With issues: {len(spec_files) - valid_count}\n\n")
            for i, issue in enumerate(issues, 1):
                f.write(f"{i}. {issue}\n")

        print(f"\nDetailed issues saved to {log_file}")
    else:
        print("\nNo issues found! All files look good.")


def labels_to_midi(onset_labels, frame_labels, offset_labels, velocity_labels, fps):
    """
    Convert label matrices back to MIDI note events.

    Parameters:
    -----------
    onset_labels : numpy.ndarray
        Binary matrix indicating note onsets (shape: 88 x num_frames)
    frame_labels : numpy.ndarray
        Binary matrix indicating active notes (shape: 88 x num_frames)
    offset_labels : numpy.ndarray
        Binary matrix indicating note offsets (shape: 88 x num_frames)
    velocity_labels : numpy.ndarray
        Matrix with note velocities (shape: 88 x num_frames)
    fps : float
        Frames per second (depends on hop_length and sample rate)

    Returns:
    --------
    list : List of note events as dictionaries
    """
    midi_events = []

    for pitch in range(88):
        onset_frames = np.where(onset_labels[pitch] > 0.5)[0]

        for onset_frame in onset_frames:
            offset_frames = np.where(offset_labels[pitch] > 0.5)[0]
            offset_frames = offset_frames[offset_frames > onset_frame]

            if len(offset_frames) > 0:
                offset_frame = offset_frames[0]
            else:
                active_frames = np.where(frame_labels[pitch] > 0.5)[0]
                active_frames = active_frames[active_frames >= onset_frame]

                if len(active_frames) > 0:
                    offset_frame = active_frames[-1] + 1
                else:
                    offset_frame = onset_frame + 1

            vel_values = velocity_labels[pitch, onset_frame:offset_frame + 1]
            if len(vel_values) > 0:
                velocity = np.max(vel_values) * 127
            else:
                velocity = 64

            start_time = onset_frame / fps
            end_time = offset_frame / fps

            note_event = {
                'pitch': pitch + 21,
                'start': start_time,
                'end': end_time,
                'velocity': int(velocity)
            }

            midi_events.append(note_event)

    return midi_events


def midi_events_to_midi_file(midi_events, output_file):
    """
    Convert MIDI events to a MIDI file.
    """
    midi = pretty_midi.PrettyMIDI()
    piano = pretty_midi.Instrument(program=0)

    for event in midi_events:
        note = pretty_midi.Note(
            velocity=event['velocity'],
            pitch=event['pitch'],
            start=event['start'],
            end=event['end']
        )
        piano.notes.append(note)

    midi.instruments.append(piano)
    midi.write(output_file)


def create_piano_audio(midi_file, output_file, sr=16000, duration=None):
    """
    Create piano audio from MIDI file using fluidsynth.
    """
    midi_data = pretty_midi.PrettyMIDI(midi_file)
    if duration is not None:
        audio = midi_data.fluidsynth(fs=sr, duration=duration)
    else:
        audio = midi_data.fluidsynth(fs=sr)
    sf.write(output_file, audio, sr)


def test_midi_reconstruction(output_dir, base_name, segment_num, sr=16000, hop_length=512):
    """
    Test reconstruction of MIDI from label files and create audio for comparison.

    Parameters:
    -----------
    output_dir : str
        Directory where processed files are stored
    base_name : str
        Base name of the processed files
    segment_num : int
        Segment number to reconstruct
    sr : int
        Sample rate
    hop_length : int
        Hop length used in preprocessing
    """
    onset_file = os.path.join(output_dir, f"{base_name}_segment_{segment_num}_onset_labels.npy")
    frame_file = os.path.join(output_dir, f"{base_name}_segment_{segment_num}_frame_labels.npy")
    offset_file = os.path.join(output_dir, f"{base_name}_segment_{segment_num}_offset_labels.npy")
    velocity_file = os.path.join(output_dir, f"{base_name}_segment_{segment_num}_velocity_labels.npy")

    try:
        onset_labels = np.load(onset_file)
        frame_labels = np.load(frame_file)
        offset_labels = np.load(offset_file)
        velocity_labels = np.load(velocity_file)
    except Exception as e:
        print(f"Error loading label files: {e}")
        return

    fps = sr / hop_length

    midi_events = labels_to_midi(onset_labels, frame_labels, offset_labels, velocity_labels, fps)

    print(f"Reconstructed {len(midi_events)} notes from labels")

    recon_dir = os.path.join(output_dir, "reconstructions")
    os.makedirs(recon_dir, exist_ok=True)

    midi_file = os.path.join(recon_dir, f"{base_name}_segment_{segment_num}_reconstructed.mid")
    midi_events_to_midi_file(midi_events, midi_file)
    print(f"Saved reconstructed MIDI to {midi_file}")

    duration = len(frame_labels[0]) / fps
    audio_file = os.path.join(recon_dir, f"{base_name}_segment_{segment_num}_reconstructed.wav")
    try:
        create_piano_audio(midi_file, audio_file, sr=sr, duration=duration)
        print(f"Created audio file from reconstructed MIDI: {audio_file}")
    except Exception as e:
        print(f"Error creating audio file: {e}")

    spec_file = os.path.join(output_dir, f"{base_name}_segment_{segment_num}_spec.npy")
    if os.path.exists(spec_file):
        print(f"Original spectrogram file exists for comparison")

    return {
        'midi_file': midi_file,
        'audio_file': audio_file,
        'num_notes': len(midi_events)
    }


if __name__ == "__main__":
    # Step 1: Visualize plots (spectrogram label - MIDI labels)
    visualize_segment("dataset/spectrograms_mel", "MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav", 0)

    # Step 2: Checks
    validate_preprocessed_data("dataset/spectrograms_mel", "MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav")

    # Step 3: MIDI Reconstruction Test
    test_midi_reconstruction("dataset/spectrograms_mel", "MIDI-Unprocessed_SMF_02_R1_2004_01-05_ORIG_MID--AUDIO_02_R1_2004_05_Track05_wav", 0)
