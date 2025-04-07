import numpy as np
import matplotlib.pyplot as plt


def note_tracking(onset_posteriogram, frame_posteriogram, offset_posteriogram,
                  onset_threshold=0.5, frame_threshold=0.3, offset_threshold=0.5,
                  min_duration=2):
    """
    Convert posteriograms to a clean piano roll using note tracking logic

    Parameters:
        onset_posteriogram: Onset detection results (88 x Time)
        frame_posteriogram: Frame activation results (88 x Time)
        offset_posteriogram: Offset detection results (88 x Time)
        onset_threshold: Threshold for detecting note beginnings
        frame_threshold: Threshold for continuing notes
        offset_threshold: Threshold for detecting note endings
        min_duration: Minimum note duration in frames

    Returns:
        piano_roll: Clean piano roll matrix (88 x Time)
    """
    piano_roll = np.zeros_like(frame_posteriogram)

    onset_peaks = onset_posteriogram > onset_threshold
    frame_active = frame_posteriogram > frame_threshold
    offset_peaks = offset_posteriogram > offset_threshold

    # For each pitch, track note activation
    for pitch in range(onset_peaks.shape[0]):
        t = 0
        while t < onset_peaks.shape[1]:
            # Check for note onset
            if onset_peaks[pitch, t]:
                # Note begins here
                start_t = t
                t += 1

                # Track until we find a strong offset or frame activation drops
                while (t < frame_posteriogram.shape[1] and
                       (frame_active[pitch, t] or t - start_t < 2) and
                       not offset_peaks[pitch, t]):
                    t += 1

                end_t = t
                duration = end_t - start_t

                # Only keep notes longer than minimum duration
                if duration >= min_duration:
                    piano_roll[pitch, start_t:end_t] = 1
            else:
                t += 1

    return piano_roll


def get_note_events(piano_roll, velocity_posteriogram, frame_rate = 31.25):
    """
    Convert piano roll to a list of note events with timing and velocity

    Parameters:
        piano_roll: Binary piano roll matrix (88 x Time)
        velocity_posteriogram: Velocity prediction results (88 x Time)
        frame_time_step: Time in seconds per frame

    Returns:
        notes: List of dicts with keys {'pitch', 'start', 'end', 'velocity'}
    """
    frame_time_step = 1.0 / frame_rate
    notes = []

    for pitch in range(piano_roll.shape[0]):
        t = 0
        while t < piano_roll.shape[1]:
            if piano_roll[pitch, t] > 0:
                # Note begins here
                start_t = t
                start_time = start_t * frame_time_step

                # Find when note ends
                while t < piano_roll.shape[1] and piano_roll[pitch, t] > 0:
                    t += 1

                end_t = t
                end_time = end_t * frame_time_step

                active_range = range(start_t, min(end_t, velocity_posteriogram.shape[1]))
                if len(active_range) > 0:
                    onset_portion = min(10, len(active_range))
                    onset_velocity = np.mean(velocity_posteriogram[pitch, start_t:start_t + onset_portion])
                    sustained_velocity = np.mean(velocity_posteriogram[pitch, active_range])
                    avg_velocity = 0.7 * onset_velocity + 0.3 * sustained_velocity
                else:
                    avg_velocity = 0.5

                midi_pitch = pitch + 21

                notes.append({
                    'pitch': midi_pitch,
                    'start': start_time,
                    'end': end_time,
                    'velocity': int(avg_velocity * 127)
                })
            else:
                t += 1

    notes.sort(key=lambda x: x['start'])

    return notes


def visualize_note_tracking(spectrogram, onset_posteriogram, frame_posteriogram,
                            offset_posteriogram, velocity_posteriogram, piano_roll):
    """
    Visualize the note tracking process
    """
    fig, axes = plt.subplots(6, 1, figsize=(12, 16))

    axes[0].imshow(spectrogram.T, aspect='auto', origin='lower', cmap='magma')
    axes[0].set_title("Mel Spectrogram")
    axes[0].set_ylabel("Frequency Bins")

    # Onset posteriogram
    axes[1].imshow(onset_posteriogram.T, aspect='auto', origin='lower', cmap='Blues')
    axes[1].set_title("Onset Posteriogram")
    axes[1].set_ylabel("MIDI Note")

    # Frame posteriogram
    axes[2].imshow(frame_posteriogram.T, aspect='auto', origin='lower', cmap='Greens')
    axes[2].set_title("Frame Posteriogram")
    axes[2].set_ylabel("MIDI Note")

    # Offset posteriogram
    axes[3].imshow(offset_posteriogram.T, aspect='auto', origin='lower', cmap='Reds')
    axes[3].set_title("Offset Posteriogram")
    axes[3].set_ylabel("MIDI Note")

    # Velocity posteriogram
    axes[4].imshow(velocity_posteriogram.T, aspect='auto', origin='lower', cmap='viridis')
    axes[4].set_title("Velocity Posteriogram")
    axes[4].set_ylabel("MIDI Note")

    # Resulting piano roll
    axes[5].imshow(piano_roll.T, aspect='auto', origin='lower', cmap='Purples')
    axes[5].set_title("Final Piano Roll After Note Tracking")
    axes[5].set_ylabel("MIDI Note")
    axes[5].set_xlabel("Time Frames")

    plt.tight_layout()
    plt.show()

    return fig


def apply_music_language_constraints(piano_roll, max_polyphony=12, min_note_duration=3):
    """
    Apply music language constraints to correct unlikely note patterns

    Parameters:
        piano_roll: Binary piano roll matrix (88 x Time)
        max_polyphony: Maximum number of simultaneous notes
        min_note_duration: Minimum allowed note duration in frames

    Returns:
        corrected_piano_roll: Corrected piano roll with musical constraints applied
    """
    corrected = np.copy(piano_roll)

    # 1. Remove very short notes
    gap_threshold = 3
    for pitch in range(piano_roll.shape[0]):
        note_segments = []
        note_on = False
        start_t = 0

        for t in range(piano_roll.shape[1]):
            if piano_roll[pitch, t] > 0 and not note_on:
                # Note start
                note_on = True
                start_t = t
            elif (piano_roll[pitch, t] == 0 or t == piano_roll.shape[1] - 1) and note_on:
                # Note end
                note_on = False
                end_t = t if t < piano_roll.shape[1] - 1 else t + 1
                duration = end_t - start_t

                note_segments.append((start_t, end_t, duration))

        # First pass: remove very short notes
        for start_t, end_t, duration in note_segments:
            if duration < min_note_duration:
                corrected[pitch, start_t:end_t] = 0

        # Second pass: merge notes with small gaps
        if len(note_segments) >= 2:
            merged_segments = []
            current_segment = note_segments[0]

            for i in range(1, len(note_segments)):
                prev_end = current_segment[1]
                current_start = note_segments[i][0]

                # If gap is small enough, merge segments
                if current_start - prev_end <= gap_threshold:
                    # Create merged segment
                    current_segment = (current_segment[0], note_segments[i][1],
                                       note_segments[i][1] - current_segment[0])
                else:
                    # Add current segment and move to next
                    merged_segments.append(current_segment)
                    current_segment = note_segments[i]

            # Add final segment
            merged_segments.append(current_segment)

            # Apply merged segments to corrected piano roll
            for start_t, end_t, _ in merged_segments:
                corrected[pitch, start_t:end_t] = 1

    # 2. Limit polyphony at each frame
    for t in range(piano_roll.shape[1]):
        active_notes = np.where(corrected[:, t] > 0)[0]
        if len(active_notes) > max_polyphony:
            confidences = np.array([piano_roll[pitch, t] for pitch in active_notes])
            keep_indices = np.argsort(confidences)[-max_polyphony:]
            notes_to_remove = [active_notes[i] for i in range(len(active_notes)) if i not in keep_indices]
            corrected[notes_to_remove, t] = 0

    return corrected


def merge_overlapping_predictions(all_predictions, overlap_size, blend_method='linear'):
    """
    Merge predictions from overlapping segments

    Parameters:
        all_predictions: List of (prediction, start_frame, end_frame) tuples
        overlap_size: Number of frames overlapping between segments
        blend_method: How to blend overlapping predictions ('linear', 'max', 'avg')

    Returns:
        merged_prediction: Merged prediction for the entire piece
    """
    if not all_predictions:
        return None

    max_end = max([end for _, _, end in all_predictions])
    num_pitches = all_predictions[0][0].shape[0]

    merged = np.zeros((num_pitches, max_end))
    weights = np.zeros(max_end)

    for pred, start, end in all_predictions:
        if blend_method == 'linear':
            segment_len = end - start
            ramp_len = min(overlap_size, segment_len // 4)

            weight = np.ones(segment_len)
            if ramp_len > 0:
                weight[:ramp_len] = np.linspace(0, 1, ramp_len)
                weight[-ramp_len:] = np.linspace(1, 0, ramp_len)

        elif blend_method == 'max':
            weight = np.ones(end - start)
        else:
            weight = np.ones(end - start)

        for pitch in range(num_pitches):
            merged[pitch, start:end] += pred[pitch, :end - start] * weight

        weights[start:end] += weight

    nonzero_weights = weights > 0
    for pitch in range(num_pitches):
        merged[pitch, nonzero_weights] /= weights[nonzero_weights]

    if blend_method == 'max':
        return merged

    return merged
