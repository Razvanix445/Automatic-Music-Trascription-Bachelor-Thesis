"""
Simplified postprocessing for piano transcription
Robust and memory-efficient version for HuggingFace Spaces
"""

import numpy as np
import librosa
from scipy.signal import find_peaks
import logging

logger = logging.getLogger(__name__)

class MusicTranscriptionPostprocessor:
    """Simplified postprocessor for robust operation"""
    
    def __init__(self,
                 onset_threshold=0.3,
                 frame_threshold=0.3,
                 min_note_duration=0.05,
                 max_note_duration=8.0,
                 time_resolution=0.032):
        
        self.onset_threshold = onset_threshold
        self.frame_threshold = frame_threshold
        self.min_note_duration = min_note_duration
        self.max_note_duration = max_note_duration
        self.time_resolution = time_resolution

    def process_predictions(self, predictions):
        """Main processing function - simplified and robust"""
        try:
            logger.info("🎼 Processing model predictions...")
            
            # Handle different output formats
            if len(predictions) >= 3:
                onset_preds = predictions[0][0]
                frame_preds = predictions[1][0] 
                velocity_preds = predictions[2][0] if len(predictions) > 2 else None
            else:
                raise ValueError(f"Expected at least 3 model outputs, got {len(predictions)}")
            
            logger.info(f"📊 Prediction shapes: onset{onset_preds.shape}, frame{frame_preds.shape}")
            
            # Extract notes using simple but reliable method
            notes = self._extract_notes_simple(onset_preds, frame_preds, velocity_preds)
            
            # Clean up the notes
            cleaned_notes = self._clean_notes(notes)
            
            logger.info(f"✅ Extracted {len(cleaned_notes)} notes")
            return cleaned_notes
            
        except Exception as e:
            logger.error(f"❌ Postprocessing failed: {e}")
            return self._fallback_notes()
    
    def _extract_notes_simple(self, onset_preds, frame_preds, velocity_preds):
        """Simple but robust note extraction"""
        notes = []
        
        try:
            # Process each pitch
            for pitch_idx in range(min(88, onset_preds.shape[1])):
                onset_curve = onset_preds[:, pitch_idx]
                frame_curve = frame_preds[:, pitch_idx]
                
                # Find onset peaks
                peaks, _ = find_peaks(
                    onset_curve,
                    height=self.onset_threshold,
                    distance=max(1, int(0.05 / self.time_resolution))  # Min 50ms apart
                )
                
                # Create notes from peaks
                for peak in peaks:
                    # Find note duration using frame predictions
                    duration = self._find_note_duration(peak, frame_curve)
                    
                    if duration >= self.min_note_duration:
                        # Get velocity
                        velocity = self._get_velocity(peak, pitch_idx, velocity_preds)
                        
                        # Create note
                        midi_pitch = pitch_idx + 21  # Piano range starts at A0 (21)
                        note = {
                            "note_name": self._pitch_to_note_name(midi_pitch),
                            "time": float(peak * self.time_resolution),
                            "duration": float(duration),
                            "velocity": float(velocity),
                            "velocity_midi": int(min(127, max(1, velocity * 127))),
                            "pitch": int(midi_pitch),
                            "frequency": librosa.midi_to_hz(midi_pitch)
                        }
                        notes.append(note)
        
        except Exception as e:
            logger.error(f"Note extraction error: {e}")
        
        return notes
    
    def _find_note_duration(self, onset_frame, frame_curve):
        """Find note duration using frame predictions"""
        try:
            # Look for where the frame prediction drops below threshold
            remaining_frames = frame_curve[onset_frame:]
            
            # Find first point below threshold
            below_threshold = np.where(remaining_frames < self.frame_threshold)[0]
            
            if len(below_threshold) > 0:
                duration_frames = below_threshold[0]
            else:
                # Default duration if no clear ending
                duration_frames = min(int(0.5 / self.time_resolution), len(remaining_frames))
            
            duration = duration_frames * self.time_resolution
            return min(self.max_note_duration, max(self.min_note_duration, duration))
            
        except Exception:
            return 0.5  # Default duration
    
    def _get_velocity(self, onset_frame, pitch_idx, velocity_preds):
        """Get velocity for the note"""
        try:
            if velocity_preds is not None:
                raw_velocity = velocity_preds[onset_frame, pitch_idx]
                return float(np.clip(raw_velocity, 0.0, 1.0))
            else:
                return 0.8  # Default velocity
        except Exception:
            return 0.8
    
    def _clean_notes(self, notes):
        """Clean and filter notes"""
        if not notes:
            return notes
        
        # Sort by time
        notes.sort(key=lambda x: x["time"])
        
        # Remove duplicates and very short notes
        cleaned = []
        for note in notes:
            if (note["duration"] >= self.min_note_duration and 
                note["time"] >= 0 and
                21 <= note["pitch"] <= 108):  # Valid piano range
                cleaned.append(note)
        
        return cleaned
    
    def _pitch_to_note_name(self, pitch):
        """Convert MIDI pitch to note name"""
        note_names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
        octave = (pitch // 12) - 1
        note = note_names[pitch % 12]
        return f"{note}{octave}"
    
    def _fallback_notes(self):
        """Fallback notes if processing fails"""
        logger.warning("Using fallback notes")
        return [
            {
                "note_name": "C4",
                "time": 0.0,
                "duration": 1.0,
                "velocity": 0.8,
                "velocity_midi": 80,
                "pitch": 60,
                "frequency": 261.63
            }
        ]