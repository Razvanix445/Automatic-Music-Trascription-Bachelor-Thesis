import numpy as np
import librosa
import mido
from scipy import ndimage
from scipy.signal import find_peaks
import tensorflow as tf


class MusicTranscriptionPostprocessor:
    """
    Enhanced postprocessing for piano transcription with music theory knowledge
    """

    def __init__(self,
                 onset_threshold=0.3,
                 frame_threshold=0.3,
                 min_note_duration=0.05,
                 max_note_duration=8.0,  # Realistic max for piano
                 merge_gap_threshold=0.05,
                 time_resolution=0.032):  # Match your model's time resolution

        self.onset_threshold = onset_threshold
        self.frame_threshold = frame_threshold
        self.min_note_duration = min_note_duration
        self.max_note_duration = max_note_duration
        self.merge_gap_threshold = merge_gap_threshold
        self.time_resolution = time_resolution

    def smooth_predictions(self, predictions, sigma=1.0):
        """Reduce noise in model predictions using Gaussian smoothing"""
        return ndimage.gaussian_filter1d(predictions, sigma=sigma, axis=0)

    def detect_onsets_with_peaks(self, onset_predictions):
        """Find note starts using sophisticated peak detection"""
        onset_times = []
        onset_pitches = []
        onset_confidences = []

        for pitch_idx in range(onset_predictions.shape[1]):
            onset_curve = onset_predictions[:, pitch_idx]

            # Find peaks with musical constraints
            peaks, properties = find_peaks(
                onset_curve,
                height=self.onset_threshold,
                distance=int(0.05 / self.time_resolution),  # Min 50ms between onsets
                prominence=0.1  # Must be a clear peak
            )

            for peak_idx in peaks:
                onset_times.append(peak_idx)
                onset_pitches.append(pitch_idx)
                onset_confidences.append(onset_curve[peak_idx])

        return onset_times, onset_pitches, onset_confidences

    def find_note_endings_from_frames(self, frame_predictions, onset_times, onset_pitches):
        """Determine note endings using frame activity analysis"""
        note_endings = []

        for onset_time, pitch_idx in zip(onset_times, onset_pitches):
            remaining_frames = frame_predictions[onset_time:, pitch_idx]

            # Find where activity drops below threshold
            below_threshold_indices = np.where(remaining_frames < self.frame_threshold)[0]

            if len(below_threshold_indices) > 0:
                candidate_end = below_threshold_indices[0]
                confirmation_frames = max(1, int(0.02 / self.time_resolution))

                if candidate_end + confirmation_frames < len(remaining_frames):
                    next_frames = remaining_frames[candidate_end:candidate_end + confirmation_frames]

                    if np.all(next_frames < self.frame_threshold):
                        actual_end_time = onset_time + candidate_end
                        note_endings.append((actual_end_time, pitch_idx))
                    else:
                        # Look for next real ending
                        for i in range(candidate_end + 1, len(remaining_frames) - confirmation_frames):
                            test_frames = remaining_frames[i:i + confirmation_frames]
                            if np.all(test_frames < self.frame_threshold):
                                actual_end_time = onset_time + i
                                note_endings.append((actual_end_time, pitch_idx))
                                break
                        else:
                            # Use default duration
                            default_duration_frames = int(0.5 / self.time_resolution)
                            end_time = min(onset_time + default_duration_frames,
                                           onset_time + len(remaining_frames) - 1)
                            note_endings.append((end_time, pitch_idx))
                else:
                    end_time = onset_time + candidate_end
                    note_endings.append((end_time, pitch_idx))
            else:
                # Use default duration if no clear ending
                default_duration_frames = int(1.0 / self.time_resolution)
                end_time = min(onset_time + default_duration_frames, len(frame_predictions) - 1)
                note_endings.append((end_time, pitch_idx))

        return note_endings

    def create_notes_from_onsets_and_endings(self, onset_times, onset_pitches, onset_confidences, note_endings):
        """Match onsets with endings to create complete notes"""
        notes = []

        onset_data = list(zip(onset_times, onset_pitches, onset_confidences))
        onset_data.sort(key=lambda x: x[0])

        endings_data = list(note_endings)
        endings_data.sort(key=lambda x: x[0])

        for onset_time, pitch_idx, confidence in onset_data:
            matching_ending = None

            for end_time, end_pitch in endings_data:
                if end_pitch == pitch_idx and end_time > onset_time:
                    matching_ending = end_time
                    break

            if matching_ending is not None:
                duration_frames = matching_ending - onset_time
                duration_seconds = duration_frames * self.time_resolution

                if self.min_note_duration <= duration_seconds <= self.max_note_duration:
                    notes.append({
                        'onset_frame': onset_time,
                        'offset_frame': matching_ending,
                        'pitch_idx': pitch_idx,
                        'duration_seconds': duration_seconds,
                        'onset_confidence': confidence
                    })

        return notes

    def add_velocity_to_notes(self, notes, velocity_predictions):
        """Add realistic velocity information to notes"""
        for note in notes:
            onset_frame = note['onset_frame']
            pitch_idx = note['pitch_idx']

            raw_velocity = velocity_predictions[onset_frame, pitch_idx]
            velocity_scaled = np.clip(raw_velocity, 0.0, 1.0)
            velocity_midi = int(velocity_scaled * 127)

            # Ensure minimum velocity for audible notes
            if velocity_midi < 20:
                velocity_midi = 60

            note['velocity_raw'] = float(raw_velocity)
            note['velocity_scaled'] = float(velocity_scaled)
            note['velocity_midi'] = velocity_midi

    def clean_and_merge_notes(self, notes):
        """Remove artifacts and merge fragmented notes"""
        if not notes:
            return notes

        notes.sort(key=lambda x: (x['pitch_idx'], x['onset_frame']))
        cleaned_notes = []

        for pitch_idx in range(88):
            pitch_notes = [n for n in notes if n['pitch_idx'] == pitch_idx]
            if not pitch_notes:
                continue

            merged_notes = []
            i = 0
            while i < len(pitch_notes):
                current_note = pitch_notes[i]

                # Look for nearby notes to merge
                j = i + 1
                while j < len(pitch_notes):
                    next_note = pitch_notes[j]
                    gap_frames = next_note['onset_frame'] - current_note['offset_frame']
                    gap_seconds = gap_frames * self.time_resolution

                    if gap_seconds <= self.merge_gap_threshold:
                        # Merge notes
                        current_note['offset_frame'] = next_note['offset_frame']
                        current_note['duration_seconds'] = ((current_note['offset_frame'] -
                                                             current_note['onset_frame']) *
                                                            self.time_resolution)

                        if 'velocity_midi' in next_note:
                            current_note['velocity_midi'] = max(
                                current_note.get('velocity_midi', 60),
                                next_note['velocity_midi']
                            )
                        j += 1
                    else:
                        break

                merged_notes.append(current_note)
                i = j

            cleaned_notes.extend(merged_notes)

        # Final filter for minimum duration
        final_notes = [note for note in cleaned_notes
                       if note['duration_seconds'] >= self.min_note_duration]

        return final_notes

    def apply_musical_constraints(self, notes):
        """Apply music theory constraints to improve realism"""
        filtered_notes = []

        for note in notes:
            duration = note['duration_seconds']
            pitch_idx = note['pitch_idx']

            # Remove impossibly long notes
            if duration > self.max_note_duration:
                print(f"Filtered impossibly long note: pitch {pitch_idx}, duration {duration:.2f}s")
                continue

            # Remove very high or low pitches that are unlikely
            midi_pitch = pitch_idx + 21
            if midi_pitch < 21 or midi_pitch > 108:  # Piano range A0 to C8
                continue

            # Keep notes that pass all constraints
            filtered_notes.append(note)

        return filtered_notes

    def convert_to_music_format(self, processed_notes):
        """Convert to your backend's expected format"""
        music_notes = []

        for note in processed_notes:
            pitch_idx = note['pitch_idx']
            midi_pitch = pitch_idx + 21
            onset_time = note['onset_frame'] * self.time_resolution
            duration = note['duration_seconds']
            velocity_midi = note.get('velocity_midi', 80)
            velocity_raw = note.get('velocity_raw', 0.6)

            music_note = {
                "note_name": self.pitch_to_note_name(midi_pitch),
                "time": float(onset_time),
                "duration": float(duration),
                "velocity": float(velocity_raw),
                "velocity_midi": velocity_midi,
                "pitch": int(midi_pitch),
                "frequency": librosa.midi_to_hz(midi_pitch)
            }
            music_notes.append(music_note)

        music_notes.sort(key=lambda x: x["time"])
        return music_notes

    def pitch_to_note_name(self, pitch):
        """Convert MIDI pitch to note name"""
        note_names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
        octave = (pitch // 12) - 1
        note = note_names[pitch % 12]
        return f"{note}{octave}"

    def process_predictions(self, predictions):
        """Main processing function that enhances your model's raw predictions"""
        print("🎼 Starting enhanced postprocessing...")

        # Handle different model output formats
        if len(predictions) == 3:
            onset_preds = predictions[0][0]  # [time_steps, 88]
            frame_preds = predictions[1][0]  # [time_steps, 88]
            velocity_preds = predictions[2][0]  # [time_steps, 88]
        elif len(predictions) == 4:
            onset_preds = predictions[0][0]
            frame_preds = predictions[1][0]
            offset_preds = predictions[2][0]  # Available but we'll still use frame analysis
            velocity_preds = predictions[3][0]
        else:
            raise ValueError(f"Expected 3 or 4 model outputs, got {len(predictions)}")

        print(
            f"📊 Processing shapes: onset{onset_preds.shape}, frame{frame_preds.shape}, velocity{velocity_preds.shape}")

        # Step 1: Smooth predictions to reduce noise
        print("🔧 Smoothing predictions...")
        onset_preds = self.smooth_predictions(onset_preds, sigma=1.0)
        frame_preds = self.smooth_predictions(frame_preds, sigma=0.5)

        # Step 2: Detect onsets using peak detection
        print("🎯 Detecting note onsets...")
        onset_times, onset_pitches, onset_confidences = self.detect_onsets_with_peaks(onset_preds)
        print(f"   Found {len(onset_times)} potential onsets")

        # Step 3: Find note endings
        print("⏹️ Finding note endings...")
        note_endings = self.find_note_endings_from_frames(frame_preds, onset_times, onset_pitches)
        print(f"   Found {len(note_endings)} note endings")

        # Step 4: Create complete notes
        print("🎵 Creating complete notes...")
        notes = self.create_notes_from_onsets_and_endings(onset_times, onset_pitches, onset_confidences, note_endings)
        print(f"   Created {len(notes)} raw notes")

        # Step 5: Add velocity information
        print("🔊 Adding velocity information...")
        self.add_velocity_to_notes(notes, velocity_preds)

        # Step 6: Apply musical constraints
        print("🎼 Applying musical constraints...")
        constrained_notes = self.apply_musical_constraints(notes)
        print(f"   Filtered to {len(constrained_notes)} realistic notes")

        # Step 7: Clean and merge notes
        print("🧹 Cleaning and merging notes...")
        cleaned_notes = self.clean_and_merge_notes(constrained_notes)
        print(f"   Final result: {len(cleaned_notes)} refined notes")

        # Step 8: Convert to expected format
        print("📋 Converting to output format...")
        music_notes = self.convert_to_music_format(cleaned_notes)

        print(f"✅ Postprocessing complete: {len(music_notes)} high-quality notes")
        return music_notes