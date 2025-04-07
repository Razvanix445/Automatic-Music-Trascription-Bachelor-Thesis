import glob
import os

import librosa
import numpy as np
import pretty_midi
import matplotlib.pyplot as plt

def parse_midi(midi_path):
    """
    Parse a MIDI file and return a list of note events.
    Each event is a dictionary with keys: 'pitch', 'start', 'end', 'velocity'.
    """
    midi_data = pretty_midi.PrettyMIDI(midi_path)
    note_events = []
    for instrument in midi_data.instruments:
        if not instrument.is_drum:
            for note in instrument.notes:
                note_events.append({
                    "pitch": note.pitch,
                    "start": note.start,
                    "end": note.end,
                    "velocity": note.velocity
                })
    return note_events

def align_midi_to_frames(midi_events, time_frames):
    """
    Creates separate label matrices for onsets, frames, offsets, and velocities.
    frame_labels - binary matrix showing which of the 88 piano keys are active at each time frame
    onset_labels - binary matrix marking when each note starts
    offset_labels - binary matrix marking when each note ends
    velocity_labels - continuous values (0-1) representing note intensity
    """
    num_frames = len(time_frames)
    frame_labels = np.zeros((88, num_frames))
    onset_labels = np.zeros((88, num_frames))
    offset_labels = np.zeros((88, num_frames))
    velocity_labels = np.zeros((88, num_frames))

    frame_times = np.array(time_frames)
    frame_intervals = np.concatenate([frame_times, [frame_times[-1] + (frame_times[-1] - frame_times[-2])]])

    for note in midi_events:
        pitch = note['pitch'] - 21
        if 0 <= pitch < 88:
            start_time = note['start']
            end_time = note['end']
            velocity = note['velocity']

            onset_frame_no = np.searchsorted(frame_intervals, start_time) - 1
            onset_frame = max(0, min(onset_frame_no, num_frames-1))

            offset_frame_no = np.searchsorted(frame_intervals, end_time) - 1
            offset_frame = max(0, min(offset_frame_no, num_frames-1))

            if onset_frame < num_frames and offset_frame < num_frames:
                onset_labels[pitch, onset_frame] = 1

                frame_range = range(onset_frame, min(offset_frame + 1, num_frames))
                frame_labels[pitch, frame_range] = 1

                velocity_labels[pitch, frame_range] = velocity / 127.0

                if offset_frame < num_frames:
                    offset_labels[pitch, offset_frame] = 1

    return {
        'onset': onset_labels,
        'frame': frame_labels,
        'offset': offset_labels,
        'velocity': velocity_labels
    }


def OLD_segment_and_save_audio_midi_OLD(audio_path, midi_path, output_dir,
                                segment_duration, overlap_duration, sr,
                                n_mels, hop_length, n_fft):
    """
    Function to process audio and MIDI files into training examples.
    """
    os.makedirs(output_dir, exist_ok=True)
    audio, _ = librosa.load(audio_path, sr=sr)
    total_duration = librosa.get_duration(y=audio, sr=sr)

    segment_hop = segment_duration - overlap_duration
    num_complete_segments = max(1, int(np.floor((total_duration - segment_duration) / segment_hop) + 1))

    midi_events = parse_midi(midi_path)
    base_name = os.path.splitext(os.path.basename(audio_path))[0]

    for seg in range(num_complete_segments):
        segment_start_time = seg * segment_hop
        segment_end_time = segment_start_time + segment_duration

        if segment_end_time > total_duration:
            continue

        start_sample = int(segment_start_time * sr)
        end_sample = int(segment_end_time * sr)
        segment_audio = audio[start_sample:end_sample]

        desired_samples = int(segment_duration * sr)
        if len(segment_audio) < desired_samples:
            print(f"Skipping segment {seg} for file {base_name} (too short: {len(segment_audio)} samples)")
            continue

        mel_spec = librosa.feature.melspectrogram(y=segment_audio, sr=sr,
                                                n_mels=n_mels, hop_length=hop_length, n_fft=n_fft)
        log_mel_spec = librosa.power_to_db(mel_spec, ref=np.max)

        num_frames = log_mel_spec.shape[1]
        time_frames = librosa.frames_to_time(np.arange(num_frames), sr=sr, hop_length=hop_length)
        time_frames = segment_start_time + time_frames

        if log_mel_spec.shape[1] != len(time_frames):
            min_frames = min(log_mel_spec.shape[1], len(time_frames))
            log_mel_spec = log_mel_spec[:, :min_frames]
            time_frames = time_frames[:min_frames]
            print(f"Adjusted frame count to {min_frames} (segment {seg})")

        num_frames = len(time_frames)

        segment_midi_events = []
        for event in midi_events:
            if event['end'] <= segment_start_time or event['start'] >= segment_end_time:
                continue

            new_event = event.copy()
            segment_midi_events.append(new_event)

        labels = align_midi_to_frames(segment_midi_events, time_frames)

        adjusted_labels = labels

        for label_type, label_data in adjusted_labels.items():
            if label_data.shape[1] != log_mel_spec.shape[1]:
                print(f"WARNING: Dimension mismatch in segment {seg}: "
                      f"spectrogram has {log_mel_spec.shape[1]} frames but {label_type} has {label_data.shape[1]}")

        spec_filename = f"{base_name}_segment_{seg}_spec.npy"
        np.save(os.path.join(output_dir, spec_filename), log_mel_spec)

        for label_type, label_data in adjusted_labels.items():
            label_filename = f"{base_name}_segment_{seg}_{label_type}_labels.npy"
            np.save(os.path.join(output_dir, label_filename), label_data)

        print(f"Saved segment {seg} for file {base_name} ({segment_start_time:.2f}s - {segment_end_time:.2f}s)")

    print(f"\nFinished processing '{base_name}'")
    print(f"Total duration (seconds): {total_duration:.2f}")
    print(f"Number of segments (each {segment_duration}s with {overlap_duration}s overlap): {num_complete_segments}")

def segment_and_save_audio_midi(audio_path, midi_path, output_dir,
                                segment_duration, sr,
                                n_mels, hop_length, n_fft):
    """
    Function to process audio and MIDI files into training examples.
    """
    os.makedirs(output_dir, exist_ok=True)
    audio, _ = librosa.load(audio_path, sr=sr)
    total_duration = librosa.get_duration(y=audio, sr=sr)
    num_segments = int(np.ceil(total_duration / segment_duration))
    midi_events = parse_midi(midi_path)
    base_name = os.path.splitext(os.path.basename(audio_path))[0]

    for seg in range(num_segments):
        segment_start_time = seg * segment_duration
        segment_end_time = min((seg + 1) * segment_duration, total_duration)
        start_sample = int(segment_start_time * sr)
        end_sample = int(segment_end_time * sr)
        segment_audio = audio[start_sample:end_sample]

        desired_samples = int(segment_duration * sr)
        if len(segment_audio) < desired_samples:
            pad_width = desired_samples - len(segment_audio)
            segment_audio = np.pad(segment_audio, (0, pad_width), mode='constant')

        mel_spec = librosa.feature.melspectrogram(y=segment_audio, sr=sr,
                                                n_mels=n_mels, hop_length=hop_length, n_fft=n_fft)
        log_mel_spec = librosa.power_to_db(mel_spec, ref=np.max)

        num_frames = log_mel_spec.shape[1]
        time_frames = librosa.frames_to_time(np.arange(num_frames), sr=sr, hop_length=hop_length)
        time_frames = segment_start_time + time_frames

        segment_midi_events = []
        for event in midi_events:
            if event['end'] <= segment_start_time or event['start'] >= segment_end_time:
                continue
            new_event = event.copy()
            segment_midi_events.append(new_event)

        labels = align_midi_to_frames(segment_midi_events, time_frames)

        for label_type, label_data in labels.items():
            if label_data.shape[1] != log_mel_spec.shape[1]:
                print(f"Error: Label shape {label_data.shape} doesn't match spectrogram shape {log_mel_spec.shape}")

            label_filename = f"{base_name}_segment_{seg}_{label_type}_labels.npy"
            np.save(os.path.join(output_dir, label_filename), label_data)

        spec_filename = f"{base_name}_segment_{seg}_spec.npy"
        np.save(os.path.join(output_dir, spec_filename), log_mel_spec)

        print(f"Saved segment {seg} for file {base_name}")

    print(f"\nFinished processing '{base_name}'")
    print(f"Total duration (seconds): {total_duration:.2f}")
    print(f"Number of segments (each {segment_duration} seconds): {num_segments}")

def process_maestro_dataset(maestro_root, output_root):
    """
    Create the dataset of spectrograms and corresponding MIDI segments.
    """
    os.makedirs(output_root, exist_ok=True)

    year_dirs = [d for d in os.listdir(maestro_root)
                 if os.path.isdir(os.path.join(maestro_root, d))]

    year_dirs.sort()

    for year in year_dirs:
        year_path = os.path.join(maestro_root, year)
        if not os.path.isdir(year_path):
            continue

        print(f"\n--- Processing year directory: {year_path} ---")

        audio_files = glob.glob(os.path.join(year_path, '*.wav'))

        for audio_file in audio_files:
            midi_file = audio_file.replace('.wav', '.midi')

            if not os.path.exists(midi_file):
                print(f"Warning: MIDI file not found for {audio_file}")
                continue

            segment_and_save_audio_midi(
                audio_path=audio_file,
                midi_path=midi_file,
                output_dir=output_root,
                segment_duration=20.0,
                # overlap_duration=5.0,
                sr=16000,
                n_mels=229,
                hop_length=512,
                n_fft=2048
            )


def display_statistics_and_last_spectrograms(output_dir):
    """
    Prints the number of generated spectrograms and displays the last 5 spectrograms.
    """
    spec_files = [f for f in os.listdir(output_dir) if f.endswith('_spec.npy')]
    num_specs = len(spec_files)
    print(f"\nNumber of generated spectrogram segments: {num_specs}")

    spec_files.sort(key=lambda x: int(x.split('_segment_')[1].split('_')[0]))

    last_files = spec_files[-5:]

    fig, axes = plt.subplots(1, len(last_files), figsize=(15, 5))
    if len(last_files) == 1:
        axes = [axes]
    for i, spec_file in enumerate(last_files):
        spec = np.load(os.path.join(output_dir, spec_file))
        ax = axes[i]
        ax.imshow(spec, aspect='auto', origin='lower', cmap='magma')
        ax.set_title(spec_file)
        ax.set_xlabel("Time Frames")
        ax.set_ylabel("Mel Bins")
    plt.tight_layout()
    plt.show()


def display_all_segments_for_recording(output_dir, base_name):
    """
    Displays all segments for a specific recording, along with their corresponding label arrays.
    Pattern:
      {base_name}_segment_{seg}_spec.npy
      {base_name}_segment_{seg}_frame_labels.npy
      {base_name}_segment_{seg}_onset_labels.npy
      {base_name}_segment_{seg}_offset_labels.npy
      {base_name}_segment_{seg}_velocity_labels.npy
    """
    segment_numbers = set()

    for f in os.listdir(output_dir):
        if f.startswith(base_name) and '_segment_' in f and f.endswith('_spec.npy'):
            segment_part = f.split('_segment_')[1]
            segment_num = segment_part.split('_')[0]
            segment_numbers.add(int(segment_num))

    if not segment_numbers:
        print(f"No segments found for base name '{base_name}' in {output_dir}")
        return

    for seg_num in sorted(segment_numbers):
        spec_file = f"{base_name}_segment_{seg_num}_spec.npy"
        frame_file = f"{base_name}_segment_{seg_num}_frame_labels.npy"
        onset_file = f"{base_name}_segment_{seg_num}_onset_labels.npy"
        offset_file = f"{base_name}_segment_{seg_num}_offset_labels.npy"
        velocity_file = f"{base_name}_segment_{seg_num}_velocity_labels.npy"

        all_files = [spec_file, frame_file, onset_file, offset_file, velocity_file]
        missing_files = [f for f in all_files if not os.path.exists(os.path.join(output_dir, f))]

        if missing_files:
            print(f"Warning: Missing files for segment {seg_num}: {missing_files}")
            continue

        spec = np.load(os.path.join(output_dir, spec_file))
        frame_labels = np.load(os.path.join(output_dir, frame_file))
        onset_labels = np.load(os.path.join(output_dir, onset_file))
        offset_labels = np.load(os.path.join(output_dir, offset_file))
        velocity_labels = np.load(os.path.join(output_dir, velocity_file))

        fig, axes = plt.subplots(5, 1, figsize=(12, 15))

        ax_spec = axes[0]
        im_spec = ax_spec.imshow(spec, aspect='auto', origin='lower', cmap='magma')
        ax_spec.set_title(f"Spectrogram: Segment {seg_num}")
        ax_spec.set_xlabel("Time Frames")
        ax_spec.set_ylabel("Mel Bins")
        fig.colorbar(im_spec, ax=ax_spec, fraction=0.046, pad=0.04)

        ax_frame = axes[1]
        im_frame = ax_frame.imshow(frame_labels, aspect='auto', origin='lower', cmap='Blues')
        ax_frame.set_title(f"Frame Labels: Which notes are active")
        ax_frame.set_xlabel("Time Frames")
        ax_frame.set_ylabel("Piano Key (0-87)")
        fig.colorbar(im_frame, ax=ax_frame, fraction=0.046, pad=0.04)

        ax_onset = axes[2]
        im_onset = ax_onset.imshow(onset_labels, aspect='auto', origin='lower', cmap='Greens')
        ax_onset.set_title(f"Onset Labels: When notes begin")
        ax_onset.set_xlabel("Time Frames")
        ax_onset.set_ylabel("Piano Key (0-87)")
        fig.colorbar(im_onset, ax=ax_onset, fraction=0.046, pad=0.04)

        ax_offset = axes[3]
        im_offset = ax_offset.imshow(offset_labels, aspect='auto', origin='lower', cmap='Reds')
        ax_offset.set_title(f"Offset Labels: When notes end")
        ax_offset.set_xlabel("Time Frames")
        ax_offset.set_ylabel("Piano Key (0-87)")
        fig.colorbar(im_offset, ax=ax_offset, fraction=0.046, pad=0.04)

        ax_velocity = axes[4]
        im_velocity = ax_velocity.imshow(velocity_labels, aspect='auto', origin='lower', cmap='viridis')
        ax_velocity.set_title(f"Velocity Labels: How hard notes are played")
        ax_velocity.set_xlabel("Time Frames")
        ax_velocity.set_ylabel("Piano Key (0-87)")
        fig.colorbar(im_velocity, ax=ax_velocity, fraction=0.046, pad=0.04)

        plt.suptitle(f"{base_name} - Segment {seg_num}", fontsize=16)
        plt.tight_layout(rect=[0, 0, 1, 0.97])
        plt.show()

        if len(segment_numbers) > 1:
            if input("Press Enter to continue to next segment, or 'q' to quit: ").lower() == 'q':
                break

if __name__ == '__main__':
    maestro_root = "../dataset/maestro-v3.0.0"
    spectrograms_directory = "../dataset/spectrograms_mel_20s_V3"

    process_maestro_dataset(maestro_root, spectrograms_directory)
    print("Finalized generating the spectrograms with the parameters: segment_duration=20.0, sr=16000, n_mels=229, hop_length=512, n_fft=2048")

    # display_statistics_and_last_spectrograms(spectrograms_directory)

    # base_name = "MIDI-UNPROCESSED_01-03_R1_2014_MID--AUDIO_01_R1_2014_wav--1"
    # display_all_segments_for_recording(spectrograms_directory, base_name)