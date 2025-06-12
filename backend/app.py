import os
import uuid
from datetime import datetime
import json

import keras
import numpy as np
import tensorflow as tf
import librosa
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import mido
import tempfile
from scipy import ndimage
from scipy.signal import find_peaks

import subprocess
import shutil
from pathlib import Path
import atexit
import time

from keras.src.layers import *
from pydub import AudioSegment
import boto3

import sys

from werkzeug.utils import secure_filename

from models.model_loader import ModelLoader

from utils.utils import weighted_binary_crossentropy, focal_loss, F1Score

from models.architecture import acoustic_feature_extractor, vertical_dependencies_layer, lstm_with_attention, onset_subnetwork, frame_subnetwork, offset_subnetwork, velocity_subnetwork, build_model

from postprocessing.postprocessing import MusicTranscriptionPostprocessor


print(sys.executable)

# Use absolute paths for directories
UPLOAD_FOLDER = '/app/uploads'
OUTPUT_FOLDER = '/app/output'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(OUTPUT_FOLDER, exist_ok=True)


def setup_virtual_display():
    """Set up virtual display for MuseScore in headless environment"""
    display = ':99'
    
    try:
        # Set display environment
        os.environ['DISPLAY'] = display
        
        # Start Xvfb if not already running
        try:
            # Check if Xvfb is already running
            result = subprocess.run(['pgrep', 'Xvfb'], capture_output=True)
            if result.returncode != 0:
                print("🖥️ Starting virtual display...")
                xvfb_process = subprocess.Popen([
                    'Xvfb', display, 
                    '-screen', '0', '1024x768x24',
                    '-ac', '+extension', 'GLX'
                ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                
                # Give Xvfb time to start
                time.sleep(2)
                
                # Register cleanup
                atexit.register(lambda: xvfb_process.terminate())
                print(f"✅ Virtual display started: {display}")
            else:
                print(f"✅ Virtual display already running: {display}")
                
        except Exception as e:
            print(f"⚠️ Virtual display setup warning: {e}")
            # Continue anyway - might work without explicit Xvfb start
            
    except Exception as e:
        print(f"❌ Display setup error: {e}")
        
    return display

def comprehensive_musescore_test():
    """Complete MuseScore test including conversion"""
    print("🎼 Running comprehensive MuseScore test...")
    
    # Test 1: Version check
    commands_to_test = ['musescore3', 'musescore', 'mscore3', 'mscore']
    working_command = None
    
    for cmd in commands_to_test:
        try:
            result = subprocess.run([cmd, '--version'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                working_command = cmd
                print(f"✅ {cmd} version check passed: {result.stdout.strip()}")
                break
        except Exception as e:
            print(f"   {cmd}: {e}")
    
    if not working_command:
        return False, "No working MuseScore command found"
    
    # Test 2: Conversion test with a minimal MIDI
    try:
        # Create a minimal test MIDI file
        test_midi = os.path.join(OUTPUT_FOLDER, 'test_minimal.mid')
        minimal_midi_bytes = bytes([
            0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06,  # MThd header
            0x00, 0x00, 0x00, 0x01, 0x00, 0x60,              # Format 0, 1 track, 96 tpqn
            0x4D, 0x54, 0x72, 0x6B, 0x00, 0x00, 0x00, 0x0B,  # MTrk header
            0x00, 0x90, 0x40, 0x40,                          # Note on C4
            0x48, 0x80, 0x40, 0x40,                          # Note off C4
            0x00, 0xFF, 0x2F, 0x00                           # End of track
        ])
        
        with open(test_midi, 'wb') as f:
            f.write(minimal_midi_bytes)
        
        # Test MusicXML conversion
        test_xml = os.path.join(OUTPUT_FOLDER, 'test_output.musicxml')
        result = subprocess.run([working_command, '-o', test_xml, test_midi], 
                              capture_output=True, text=True, timeout=20)
        
        if result.returncode == 0 and os.path.exists(test_xml):
            print("✅ MusicXML conversion test passed")
            
            # Test PDF conversion
            test_pdf = os.path.join(OUTPUT_FOLDER, 'test_output.pdf')
            result = subprocess.run([working_command, '-o', test_pdf, test_xml], 
                                  capture_output=True, text=True, timeout=20)
            
            if result.returncode == 0 and os.path.exists(test_pdf):
                print("✅ PDF conversion test passed")
                conversion_success = True
            else:
                print(f"⚠️ PDF conversion failed: {result.stderr}")
                conversion_success = False
            
            # Clean up test files
            for test_file in [test_midi, test_xml, test_pdf]:
                if os.path.exists(test_file):
                    os.remove(test_file)
                    
            return conversion_success, working_command
        else:
            print(f"❌ MusicXML conversion failed: {result.stderr}")
            return False, f"{working_command} conversion failed"
            
    except Exception as e:
        print(f"❌ Conversion test error: {e}")
        return False, str(e)

# ENHANCED STARTUP SEQUENCE
print("=" * 60)
print("🚀 STARTING WAVE2NOTES WITH MUSESCORE SUPPORT")
print("=" * 60)

# 1. Set up virtual display
display = setup_virtual_display()

# 2. Test MuseScore comprehensively  
conversion_works, musescore_status = comprehensive_musescore_test()

if conversion_works:
    print(f"🎼 ✅ MuseScore fully operational: {musescore_status}")
    print("   📄 Sheet music generation enabled")
else:
    print(f"🎼 ❌ MuseScore issues: {musescore_status}")
    print("   📄 Sheet music generation disabled")

# 3. Verify directories
print("📁 Checking directories...")
for folder_name, folder_path in [("Upload", UPLOAD_FOLDER), ("Output", OUTPUT_FOLDER)]:
    try:
        os.makedirs(folder_path, mode=0o755, exist_ok=True)
        if os.access(folder_path, os.W_OK):
            print(f"✅ {folder_name} folder ready: {folder_path}")
        else:
            print(f"⚠️ {folder_name} folder not writable: {folder_path}")
    except Exception as e:
        print(f"❌ {folder_name} folder error: {e}")

print("=" * 60)
print("🎵 Ready for piano transcription!")
print("=" * 60)


app = Flask(__name__)
CORS(app)

# AWS S3 Configuration
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
AWS_BUCKET_NAME = "flutter-audio-uploads"
AWS_ACCESS_KEY = os.environ.get("AWS_ACCESS_KEY")
AWS_SECRET_KEY = os.environ.get("AWS_SECRET_KEY")

s3_client = boto3.client(
    's3',
    aws_access_key_id=AWS_ACCESS_KEY,
    aws_secret_access_key=AWS_SECRET_KEY,
    region_name=AWS_REGION
)

print("Model loader initialized - model will load on first recordings endpoint request")
model_loader = ModelLoader()


def save_generated_files_to_s3(user_id, recording_id, result_data):
    """Save generated MIDI and PDF files to S3 and update metadata AND result_data"""
    try:
        print("💾 Saving generated files to S3...")
        
        # Get the recording folder and metadata
        recording_folder = f"users/{user_id}/recordings/{recording_id}"
        metadata_key = f"{recording_folder}/metadata.json"
        
        # Load existing metadata
        try:
            metadata_response = s3_client.get_object(
                Bucket="flutter-audio-uploads",
                Key=metadata_key
            )
            metadata = json.loads(metadata_response['Body'].read().decode('utf-8'))
        except Exception as e:
            print(f"❌ Could not load metadata: {e}")
            return result_data  # Return original data if metadata fails
        
        files_saved = 0
        
        # Save MIDI file if it exists
        if 'midi_file' in result_data and result_data['midi_file']:
            midi_url = result_data['midi_file']  # e.g., "/api/download/filename.mid"
            if midi_url.startswith('/api/download/'):
                midi_filename = midi_url.replace('/api/download/', '')
                midi_local_path = os.path.join(OUTPUT_FOLDER, midi_filename)
                
                if os.path.exists(midi_local_path):
                    # Upload to S3
                    midi_s3_path = f"{recording_folder}/transcription.mid"
                    upload_file_to_s3(midi_local_path, midi_s3_path, 'audio/midi')
                    
                    # Generate S3 URL
                    midi_s3_url = f"https://flutter-audio-uploads.s3.amazonaws.com/{midi_s3_path}"
                    
                    # Add to metadata
                    metadata['files']['midi'] = {
                        'filename': 'transcription.mid',
                        'original_name': 'AI_Generated_Transcription.mid',
                        'content_type': 'audio/midi',
                        's3_path': midi_s3_path,
                        'url': midi_s3_url,
                        'generated_date': datetime.now().isoformat(),
                        'generated_by': 'ai_transcription'
                    }
                    
                    # 🔥 IMPORTANT: Update the result_data with S3 URL
                    result_data['midi_file'] = midi_s3_url
                    
                    print(f"✅ MIDI saved to S3: {midi_s3_path}")
                    print(f"🔗 MIDI URL updated to: {midi_s3_url}")
                    files_saved += 1
                    
                    # Clean up local file
                    try:
                        os.remove(midi_local_path)
                    except:
                        pass
        
        # Save PDF file if it exists
        if 'sheet_music' in result_data and result_data['sheet_music']:
            sheet_info = result_data['sheet_music']
            if 'fileUrl' in sheet_info and sheet_info['fileUrl']:
                pdf_url = sheet_info['fileUrl']  # e.g., "/api/download/filename.pdf"
                if pdf_url.startswith('/api/download/'):
                    pdf_filename = pdf_url.replace('/api/download/', '')
                    pdf_local_path = os.path.join(OUTPUT_FOLDER, pdf_filename)
                    
                    if os.path.exists(pdf_local_path):
                        # Upload to S3
                        pdf_s3_path = f"{recording_folder}/sheet_music.pdf"
                        upload_file_to_s3(pdf_local_path, pdf_s3_path, 'application/pdf')
                        
                        # Generate S3 URL
                        pdf_s3_url = f"https://flutter-audio-uploads.s3.amazonaws.com/{pdf_s3_path}"
                        
                        # Add to metadata
                        metadata['files']['pdf'] = {
                            'filename': 'sheet_music.pdf',
                            'original_name': 'AI_Generated_Sheet_Music.pdf',
                            'content_type': 'application/pdf',
                            's3_path': pdf_s3_path,
                            'url': pdf_s3_url,
                            'generated_date': datetime.now().isoformat(),
                            'generated_by': 'ai_transcription'
                        }
                        
                        # 🔥 IMPORTANT: Update the result_data with S3 URL
                        result_data['sheet_music']['fileUrl'] = pdf_s3_url
                        
                        print(f"✅ PDF saved to S3: {pdf_s3_path}")
                        print(f"🔗 PDF URL updated to: {pdf_s3_url}")
                        files_saved += 1
                        
                        # Clean up local file
                        try:
                            os.remove(pdf_local_path)
                        except:
                            pass
        
        # Update metadata if files were saved
        if files_saved > 0:
            metadata['last_transcription'] = {
                'date': datetime.now().isoformat(),
                'files_saved': files_saved
            }
            
            # Save updated metadata back to S3
            save_metadata_to_s3(metadata, metadata_key)
            print(f"✅ Metadata updated with {files_saved} new files")
        
        # Return the updated result_data with S3 URLs
        return result_data
        
    except Exception as e:
        print(f"❌ Error saving files to S3: {e}")
        return result_data  # Return original data if S3 save fails
        

def perform_transcription(audio_file_path, title="Piano Transcription", sheet_format="pdf", tempo=120):
    """
    Core transcription logic that can be used by multiple endpoints
    Returns: (success, result_data, error_message)
    """
    try:
        print(f"🎵 Starting transcription for: {audio_file_path}")
        
        # Process the audio file
        wav_path = os.path.splitext(audio_file_path)[0] + ".wav"
        if not audio_file_path.lower().endswith('.wav'):
            convert_audio_to_wav(audio_file_path, wav_path)
        else:
            wav_path = audio_file_path

        # Extract features and run through model
        print("🔊 Extracting mel spectrogram...")
        mel_spec = extract_mel_spectrogram(wav_path)
        mel_spec = process_spectrogram_for_model(mel_spec)
        print(f"📊 Processed spectrogram shape: {mel_spec.shape}")

        # Get model and run prediction
        try:
            print("🤖 Loading AI model...")
            current_model = model_loader.get_model()
            print("✅ Model loaded successfully for transcription")
        except Exception as model_e:
            print(f"❌ Error loading model: {model_e}")
            return False, None, f"Model loading failed: {str(model_e)}"

        print("🧠 Running AI model prediction...")
        predictions = current_model.predict(mel_spec)
        print("✅ Model prediction completed")
        
        # Debug model output structure
        print(f"🔍 Model output debug:")
        print(f"  - Predictions type: {type(predictions)}")
        print(f"  - Number of outputs: {len(predictions)}")
        for i, pred in enumerate(predictions):
            print(f"  - Output {i} shape: {pred.shape}")

        # Extract notes with improved error handling
        try:
            notes = extract_notes_from_predictions(predictions)
            print(f"🎼 Extracted {len(notes)} notes successfully")
        except Exception as extraction_error:
            print(f"❌ Note extraction failed: {extraction_error}")
            return False, None, f"Note extraction failed: {str(extraction_error)}"

        # Generate MIDI file
        midi_filename = f"{uuid.uuid4()}.mid"
        midi_path = os.path.join(OUTPUT_FOLDER, midi_filename)
        create_midi_from_notes(notes, midi_path)

        # Check MuseScore availability
        musescore_available, musescore_info = check_musescore_installation()
        
        sheet_music_result = None
        
        # Generate sheet music if MuseScore is available
        if musescore_available and os.path.exists(midi_path):
            try:
                print("🎼 Generating sheet music...")
                
                # Create output filenames
                sheet_uuid = str(uuid.uuid4())
                musicxml_filename = f"{sheet_uuid}.musicxml"
                musicxml_path = os.path.join(OUTPUT_FOLDER, musicxml_filename)
                
                pdf_filename = f"{sheet_uuid}.pdf"
                pdf_path = os.path.join(OUTPUT_FOLDER, pdf_filename)
                
                # Convert MIDI to MusicXML first
                success, message = convert_midi_to_musicxml(midi_path, musicxml_path)
                
                if success and sheet_format.lower() == 'pdf':
                    # Convert MusicXML to PDF
                    pdf_success, pdf_message = convert_musicxml_to_pdf(musicxml_path, pdf_path)
                    
                    if pdf_success:
                        sheet_music_result = {
                            "fileUrl": f"/api/download/{pdf_filename}",
                            "format": "pdf",
                            "title": title
                        }
                        print(f"✅ Sheet music generated: {pdf_filename}")
                    else:
                        print(f"❌ PDF generation failed: {pdf_message}")
                elif success:
                    sheet_music_result = {
                        "fileUrl": f"/api/download/{musicxml_filename}",
                        "format": "musicxml", 
                        "title": title
                    }
                    print(f"✅ MusicXML generated: {musicxml_filename}")
                else:
                    print(f"❌ Sheet music generation failed: {message}")
                    
            except Exception as sheet_e:
                print(f"❌ Sheet music generation error: {sheet_e}")

        # Clean up temporary wav file if it was converted
        try:
            if wav_path != audio_file_path and os.path.exists(wav_path):
                os.remove(wav_path)
        except Exception as cleanup_e:
            print(f"⚠️ Warning: Could not clean up temporary wav file: {cleanup_e}")

        # Prepare response data
        result_data = {
            "success": True,
            "notes": notes,
            "midi_file": f"/api/download/{midi_filename}",
            "musescore_available": musescore_available,
            "sheet_music": sheet_music_result,
            "debug_info": {
                "model_outputs": len(predictions),
                "notes_extracted": len(notes),
                "sheet_music_generated": sheet_music_result is not None
            }
        }

        print(f"🎉 Transcription complete: {len(notes)} notes, MIDI: ✅, Sheet: {'✅' if sheet_music_result else '❌'}")
        
        return True, result_data, None

    except Exception as e:
        print(f"❌ Error in transcription: {e}")
        import traceback
        traceback.print_exc()
        return False, None, str(e)

def get_file_extension(filename):
    """Extract file extension from filename"""
    return '.' + filename.rsplit('.', 1)[1].lower() if '.' in filename else ''

def save_file_locally(file, filename):
    """Save uploaded file to local directory temporarily"""
    local_path = os.path.join(UPLOAD_FOLDER, filename)
    file.save(local_path)
    return local_path

def upload_file_to_s3(local_path, s3_path, content_type):
    """Upload file from local path to S3"""
    s3_client.upload_file(
        local_path,
        "flutter-audio-uploads",
        s3_path,
        ExtraArgs={'ContentType': content_type}
    )

def clean_up_local_file(local_path):
    """Remove temporary local file"""
    try:
        os.remove(local_path)
    except:
        pass

def save_metadata_to_s3(metadata, s3_path):
    """Save metadata JSON to S3"""
    import tempfile
    
    # Create temporary file with metadata
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json') as temp_file:
        json.dump(metadata, temp_file, indent=2)
        temp_file_path = temp_file.name
    
    # Upload to S3
    s3_client.upload_file(
        temp_file_path,
        "flutter-audio-uploads",
        s3_path,
        ExtraArgs={'ContentType': 'application/json'}
    )
    
    # Clean up
    os.remove(temp_file_path)


def check_musescore_with_display():
    """
    Check MuseScore with proper display setup for your container
    """
    # Your Dockerfile sets up virtual display, so we need to start it
    try:
        # Start virtual display if not already running
        if not os.environ.get('DISPLAY'):
            os.environ['DISPLAY'] = ':99'
        
        # Try to start Xvfb if needed (your Dockerfile includes it)
        try:
            subprocess.run(['Xvfb', ':99', '-screen', '0', '1024x768x24'], 
                          stdout=subprocess.DEVNULL, 
                          stderr=subprocess.DEVNULL, 
                          timeout=2)
        except:
            pass  # Xvfb might already be running or not needed
        
        # Test MuseScore3 (what your Dockerfile installs)
        commands_to_test = ['musescore3', 'musescore', 'mscore3', 'mscore']
        
        for cmd in commands_to_test:
            try:
                result = subprocess.run([cmd, '--version'], 
                                      capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    print(f"✅ {cmd} is available: {result.stdout.strip()}")
                    return True, cmd, result.stdout.strip()
            except Exception as e:
                print(f"   {cmd}: {e}")
                continue
        
        return False, None, "MuseScore not responding"
        
    except Exception as e:
        print(f"❌ Display setup error: {e}")
        return False, None, str(e)

def check_musescore_installation():
    """Updated function that works with your Dockerfile setup"""
    return check_musescore_with_display()[:2]  # Return (available, version_info)


def pitch_to_note_name(pitch):
    """Convert MIDI pitch number to note name."""
    note_names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    octave = (pitch // 12) - 1
    note = note_names[pitch % 12]
    return f"{note}{octave}"


# Post-processing to clean up notes
def clean_up_notes(notes_list, min_duration=0.05, merge_gap=0.08, confidence_threshold=0.4):
    """
    Filter and merge notes to improve MIDI quality:
    - Remove very short notes
    - Merge notes of same pitch that are close together
    - Remove low confidence notes
    """
    # Step 1: Remove very short notes and low confidence notes
    filtered_notes = []
    for note in notes_list:
        # Skip notes that are too short or have low velocity
        if note["duration"] >= min_duration and note["velocity"] >= confidence_threshold:
            filtered_notes.append(note)

    # Step 2: Sort by pitch and time for merging
    filtered_notes.sort(key=lambda x: (x["pitch"], x["time"]))

    # Step 3: Merge notes of the same pitch that are close together
    merged_notes = []
    i = 0
    while i < len(filtered_notes):
        current_note = filtered_notes[i]

        # Look ahead for notes of same pitch to potentially merge
        j = i + 1
        while j < len(filtered_notes) and filtered_notes[j]["pitch"] == current_note["pitch"]:
            next_note = filtered_notes[j]

            # If notes are close enough, merge them
            gap = next_note["time"] - (current_note["time"] + current_note["duration"])
            if gap <= merge_gap:
                # Create a merged note
                current_note["duration"] = (next_note["time"] + next_note["duration"]) - current_note["time"]
                # Take the max velocity of the two notes
                current_note["velocity"] = max(current_note["velocity"], next_note["velocity"])
                current_note["velocity_midi"] = max(current_note["velocity_midi"], next_note["velocity_midi"])

                # Skip the merged note in future iterations
                j += 1
            else:
                # Notes are too far apart to merge
                break

        # Add the current note (possibly merged) to the result
        merged_notes.append(current_note)
        # Move to the next unprocessed note
        i = j

    return merged_notes


def extract_notes_from_predictions(predictions):
    """
    Enhanced note extraction using sophisticated postprocessing
    """
    print("🎼 Extracting notes with enhanced postprocessing...")

    # Create postprocessor with optimized settings for piano music
    postprocessor = MusicTranscriptionPostprocessor(
        onset_threshold=0.3,  # Confidence threshold for note starts
        frame_threshold=0.3,  # Confidence threshold for note continuation
        min_note_duration=0.05,  # 50ms minimum (removes very short artifacts)
        max_note_duration=8.0,  # 8 seconds maximum (realistic for piano)
        merge_gap_threshold=0.05,  # Merge notes closer than 50ms
        time_resolution=0.032  # 32ms per frame (match your model)
    )

    # Process predictions and get refined notes
    refined_notes = postprocessor.process_predictions(predictions)

    return refined_notes


def _calculate_note_duration(onset_frame, pitch_idx, frames, offsets, 
                           time_resolution, frame_threshold, offset_threshold):
    """
    Calculate note duration using available information.
    """
    # Method 1: Use offset predictions if available
    if offsets is not None:
        offset_frames = np.where((offsets[onset_frame:, pitch_idx] > offset_threshold))[0]
        if len(offset_frames) > 0:
            offset_frame = offset_frames[0] + onset_frame
            duration = (offset_frame - onset_frame) * time_resolution
            return max(0.05, duration)  # Minimum 50ms duration

    # Method 2: Use frame activations to estimate duration
    if frames is not None:
        active_frames = np.where(frames[onset_frame:, pitch_idx] > frame_threshold)[0]
        
        if len(active_frames) > 0:
            # Find the first gap in active frames or use the last active frame
            for i in range(len(active_frames) - 1):
                if active_frames[i + 1] - active_frames[i] > 2:  # Gap found (2+ frames)
                    duration = (active_frames[i] + onset_frame - onset_frame + 1) * time_resolution
                    return max(0.05, duration)
            
            # No gap found, use the last active frame
            duration = (active_frames[-1] + onset_frame - onset_frame + 1) * time_resolution
            return max(0.05, duration)

    # Method 3: Default duration if no other information available
    return 0.5  # 500ms default note duration


def print_detailed_notes(notes):
    """Print detailed information about detected notes for debugging"""
    print("\n===== DETECTED NOTES (BACKEND) =====")
    print(f"Total notes detected: {len(notes)}")

    if len(notes) > 0:
        # Print summary of note ranges
        pitches = [note['pitch'] for note in notes]
        times = [note['time'] for note in notes]
        durations = [note['duration'] for note in notes]
        velocities = [note['velocity'] for note in notes]

        print(f"Pitch range: {min(pitches)} to {max(pitches)}")
        print(f"Time range: {min(times):.2f}s to {max(times):.2f}s")
        print(f"Duration range: {min(durations):.2f}s to {max(durations):.2f}s")
        print(f"Velocity range: {min(velocities):.2f} to {max(velocities):.2f}")

        # Print details of each note
        for i, note in enumerate(notes):
            print(f"Note {i + 1}: name={note['note_name']}, time={note['time']:.3f}s, "
                  f"duration={note['duration']:.3f}s, velocity={note['velocity']:.2f}, "
                  f"pitch={note['pitch']}")

    print("===== END OF NOTES =====\n")


def create_midi_from_notes(notes, output_path):
    """Create a MIDI file from the detected notes"""
    print(f"Creating MIDI file with {len(notes)} notes")

    # Check for any obvious issues in the first few notes
    for i, note in enumerate(notes[:5]):
        print(f"Note {i}: time={note.get('time', 'N/A')}, "
              f"duration={note.get('duration', 'N/A')}, "
              f"pitch={note.get('pitch', 'N/A')}, "
              f"velocity={note.get('velocity_midi', 'N/A')}")

    mid = mido.MidiFile()
    track = mido.MidiTrack()
    mid.tracks.append(track)

    # Set tempo (500000 microseconds per beat = 120 BPM)
    track.append(mido.MetaMessage('set_tempo', tempo=500000, time=0))

    # Convert time to ticks (assuming default 480 ticks per beat)
    ticks_per_beat = 480
    tempo = 500000  # microseconds per beat
    ticks_per_second = ticks_per_beat / (tempo / 1000000)

    # Sort notes by start time
    notes = sorted(notes, key=lambda x: x['time'])

    # Create a list of all MIDI events with absolute times
    events = []

    for note in notes:
        # Skip notes with negative times or durations
        if note['time'] < 0 or note['duration'] <= 0:
            print(f"Skipping invalid note: time={note['time']}, duration={note['duration']}")
            continue

        # Calculate absolute times in ticks
        onset_time_ticks = int(max(0, note['time'] * ticks_per_second))
        offset_time_ticks = onset_time_ticks + int(max(1, note['duration'] * ticks_per_second))

        # -----
        # # Ensure MIDI velocity is within valid range (0-127)
        # velocity = max(0, min(127, note['velocity_midi']))

        # If velocity is greater than 5, set it to 100
        velocity_raw = note['velocity_midi']
        if velocity_raw > 5:
            velocity_raw = 100

        # Ensure MIDI velocity is within valid range (0-127)
        velocity = max(0, min(127, velocity_raw))
        # -----

        # Add note_on and note_off events with absolute times
        events.append((onset_time_ticks, 'note_on', note['pitch'], velocity))
        events.append((offset_time_ticks, 'note_off', note['pitch'], 0))

    # Sort all events by absolute time
    events.sort()

    # Convert absolute times to delta times
    last_time = 0
    for abs_time, msg_type, pitch, velocity in events:
        # Ensure delta time is never negative
        delta_time = max(0, abs_time - last_time)

        # Create and add the MIDI message
        if msg_type == 'note_on':
            track.append(mido.Message('note_on', note=pitch, velocity=velocity, time=delta_time))
        else:  # note_off
            track.append(mido.Message('note_off', note=pitch, velocity=velocity, time=delta_time))

        # Update last_time for next event
        last_time = abs_time

    # Save MIDI file
    mid.save(output_path)
    return output_path


def extract_mel_spectrogram(audio_path, sr=16000, n_mels=229, hop_length=512, n_fft=2048):
    y, _ = librosa.load(audio_path, sr=sr)
    mel_spec = librosa.feature.melspectrogram(
        y=y, sr=sr, n_mels=n_mels, hop_length=hop_length, n_fft=n_fft
    )
    log_mel_spec = librosa.power_to_db(mel_spec, ref=np.max)
    return log_mel_spec


def convert_audio_to_wav(input_path, output_path, sample_rate=16000):
    """
    Simple function to convert audio files to WAV format.
    Args:
        input_path: Path to the input audio file
        output_path: Path where the WAV file will be saved
        sample_rate: Sample rate for the output WAV file
    Returns:
        True if successful, False otherwise
    """
    try:
        # Load the audio file
        audio = AudioSegment.from_file(input_path)

        # Set sample rate
        audio = audio.set_frame_rate(sample_rate)

        # Convert to mono if stereo
        if audio.channels > 1:
            audio = audio.set_channels(1)

        # Export as WAV
        audio.export(output_path, format="wav")
        print(f"Converted {input_path} to {output_path}")
        return True

    except Exception as e:
        print(f"Error converting audio: {e}")
        return False


def convert_m4a_to_wav(input_path, output_path, sample_rate=16000):
    """
    Convert specifically M4A to WAV format.
    Args:
        input_path: Path to the input M4A file
        output_path: Path where the WAV file will be saved
        sample_rate: Sample rate for the output WAV file
    Returns:
        True if successful, False otherwise
    """
    try:
        # Load the M4A file
        audio = AudioSegment.from_file(input_path, format="m4a")

        # Set sample rate
        audio = audio.set_frame_rate(sample_rate)

        # Convert to mono if stereo
        if audio.channels > 1:
            audio = audio.set_channels(1)

        # Export as WAV
        audio.export(output_path, format="wav")
        print(f"Converted {input_path} to {output_path}")
        return True

    except Exception as e:
        print(f"Error converting audio: {e}")
        return False


def convert_midi_to_musicxml(midi_path, output_path):
    """Convert MIDI to MusicXML using your container's MuseScore"""
    try:
        # Ensure display is set up
        if not os.environ.get('DISPLAY'):
            os.environ['DISPLAY'] = ':99'
        
        # Use musescore3 (what your Dockerfile installs)
        cmd = ['musescore3', '-o', output_path, midi_path]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0 and os.path.exists(output_path):
            return True, "Conversion successful"
        else:
            return False, f"MuseScore error: {result.stderr or 'Unknown error'}"
            
    except subprocess.TimeoutExpired:
        return False, "MuseScore conversion timed out"
    except Exception as e:
        return False, f"Conversion error: {str(e)}"

def convert_musicxml_to_pdf(musicxml_path, pdf_path):
    """Convert MusicXML to PDF using your container's MuseScore"""
    try:
        # Ensure display is set up
        if not os.environ.get('DISPLAY'):
            os.environ['DISPLAY'] = ':99'
        
        # Use musescore3 (what your Dockerfile installs)
        cmd = ['musescore3', '-o', pdf_path, musicxml_path]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0 and os.path.exists(pdf_path):
            return True, "PDF conversion successful"
        else:
            return False, f"PDF conversion error: {result.stderr or 'Unknown error'}"
            
    except Exception as e:
        return False, f"PDF conversion error: {str(e)}"


print("🎼 Checking MuseScore in containerized environment...")
try:
    musescore_available, musescore_cmd, musescore_version = check_musescore_with_display()
    
    if musescore_available:
        print(f"✅ MuseScore ready: {musescore_cmd}")
        print(f"   Version: {musescore_version}")
        print(f"   Display: {os.environ.get('DISPLAY', 'Not set')}")
    else:
        print(f"❌ MuseScore issue: {musescore_version}")
        print("   Check container setup and virtual display")
        
except Exception as e:
    print(f"❌ MuseScore check failed: {e}")


def process_spectrogram_for_model(mel_spec):
    """Process the spectrogram to fit model input requirements"""
    expected_height = 229
    expected_width = 626

    # Adjust frequency dimension if needed
    if mel_spec.shape[0] != expected_height:
        mel_spec = tf.image.resize(
            tf.expand_dims(mel_spec, 0),
            [expected_height, mel_spec.shape[1]]
        )[0]

    # Adjust time dimension if needed
    if mel_spec.shape[1] < expected_width:
        padding = expected_width - mel_spec.shape[1]
        mel_spec = np.pad(mel_spec, ((0, 0), (0, padding)), mode='constant')
    elif mel_spec.shape[1] > expected_width:
        mel_spec = mel_spec[:, :expected_width]

    # Prepare for model input
    mel_spec = tf.transpose(mel_spec)
    mel_spec = tf.expand_dims(mel_spec, axis=0)  # Add batch dimension
    mel_spec = tf.expand_dims(mel_spec, axis=-1)  # Add channel dimension

    return mel_spec


@app.route('/hello', methods=['GET'])
def hello():
    return jsonify({"message": "Hello, World!"}), 200


@app.route('/api/musescore-status', methods=['GET'])
def check_musescore_status():
    """Check if MuseScore is available for sheet music generation"""
    try:
        is_available, version_info = check_musescore_installation()
        return jsonify({
            "available": is_available,
            "version": version_info,
            "features": ["pdf", "musicxml"] if is_available else []
        })
    except Exception as e:
        return jsonify({
            "available": False,
            "error": str(e),
            "features": []
        })


@app.route('/upload', methods=['POST'])
def upload_recording_with_files():
    """Enhanced upload endpoint that handles multiple file types"""
    try:
        print("📤 Enhanced upload request received")
        
        # Validate required fields
        if 'userId' not in request.form:
            return jsonify({"error": "User ID is required"}), 400

        user_id = request.form['userId']
        title = request.form.get('title', 'Untitled Recording')
        description = request.form.get('description', '')
        
        # Check for audio file (required)
        if 'audio_file' not in request.files:
            return jsonify({"error": "Audio file is required"}), 400

        audio_file = request.files['audio_file']
        if audio_file.filename == '':
            return jsonify({"error": "No audio file selected"}), 400

        # Get optional files
        image_file = request.files.get('image_file')  # Optional recording image
        pdf_file = request.files.get('pdf_file')      # Optional sheet music PDF
        midi_file = request.files.get('midi_file')    # Optional MIDI file

        print(f"📋 Upload details:")
        print(f"   User: {user_id}")
        print(f"   Title: {title}")
        print(f"   Audio: {audio_file.filename}")
        print(f"   Image: {image_file.filename if image_file else 'None'}")
        print(f"   PDF: {pdf_file.filename if pdf_file else 'None'}")
        print(f"   MIDI: {midi_file.filename if midi_file else 'None'}")

        # Generate unique recording ID
        recording_id = str(uuid.uuid4())
        timestamp = datetime.now()
        
        # Create S3 folder path for this recording
        recording_folder = f"users/{user_id}/recordings/{recording_id}"
        
        # Prepare metadata
        metadata = {
            'recording_id': recording_id,
            'user_id': user_id,  # Store user_id in metadata
            'title': title,
            'description': description,
            'upload_date': timestamp.isoformat(),
            'created_date': timestamp.strftime('%Y-%m-%d'),
            'files': {}  # Will store info about each uploaded file
        }

        uploaded_files = {}

        # Process audio file (required)
        audio_extension = get_file_extension(audio_file.filename)
        audio_s3_path = f"{recording_folder}/audio{audio_extension}"
        local_audio_path = save_file_locally(audio_file, f"audio_{recording_id}{audio_extension}")
        
        upload_file_to_s3(local_audio_path, audio_s3_path, audio_file.content_type)
        metadata['files']['audio'] = {
            'filename': f"audio{audio_extension}",
            'original_name': audio_file.filename,
            'content_type': audio_file.content_type,
            's3_path': audio_s3_path,
            'url': f"https://flutter-audio-uploads.s3.amazonaws.com/{audio_s3_path}"
        }
        uploaded_files['audio'] = metadata['files']['audio']['url']
        clean_up_local_file(local_audio_path)

        # Process image file (optional)
        if image_file and image_file.filename:
            image_extension = get_file_extension(image_file.filename)
            image_s3_path = f"{recording_folder}/image{image_extension}"
            local_image_path = save_file_locally(image_file, f"image_{recording_id}{image_extension}")
            
            upload_file_to_s3(local_image_path, image_s3_path, image_file.content_type)
            metadata['files']['image'] = {
                'filename': f"image{image_extension}",
                'original_name': image_file.filename,
                'content_type': image_file.content_type,
                's3_path': image_s3_path,
                'url': f"https://flutter-audio-uploads.s3.amazonaws.com/{image_s3_path}"
            }
            uploaded_files['image'] = metadata['files']['image']['url']
            clean_up_local_file(local_image_path)

        # Process PDF file (optional)
        if pdf_file and pdf_file.filename:
            pdf_s3_path = f"{recording_folder}/sheet_music.pdf"
            local_pdf_path = save_file_locally(pdf_file, f"pdf_{recording_id}.pdf")
            
            upload_file_to_s3(local_pdf_path, pdf_s3_path, 'application/pdf')
            metadata['files']['pdf'] = {
                'filename': 'sheet_music.pdf',
                'original_name': pdf_file.filename,
                'content_type': 'application/pdf',
                's3_path': pdf_s3_path,
                'url': f"https://flutter-audio-uploads.s3.amazonaws.com/{pdf_s3_path}"
            }
            uploaded_files['pdf'] = metadata['files']['pdf']['url']
            clean_up_local_file(local_pdf_path)

        # Process MIDI file (optional)
        if midi_file and midi_file.filename:
            midi_s3_path = f"{recording_folder}/transcription.mid"
            local_midi_path = save_file_locally(midi_file, f"midi_{recording_id}.mid")
            
            upload_file_to_s3(local_midi_path, midi_s3_path, 'audio/midi')
            metadata['files']['midi'] = {
                'filename': 'transcription.mid',
                'original_name': midi_file.filename,
                'content_type': 'audio/midi',
                's3_path': midi_s3_path,
                'url': f"https://flutter-audio-uploads.s3.amazonaws.com/{midi_s3_path}"
            }
            uploaded_files['midi'] = metadata['files']['midi']['url']
            clean_up_local_file(local_midi_path)

        # Save metadata.json to S3
        metadata_s3_path = f"{recording_folder}/metadata.json"
        save_metadata_to_s3(metadata, metadata_s3_path)

        print(f"✅ Upload successful for recording {recording_id}")

        return jsonify({
            "success": True,
            "message": f"Recording '{title}' uploaded successfully",
            "recording_id": recording_id,
            "files": uploaded_files,
            "metadata": metadata
        }), 200

    except Exception as e:
        print(f"❌ Upload error: {e}")
        import traceback
        traceback.print_exc()
        
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


@app.route('/recordings/<user_id>', methods=['GET'])
def get_user_recordings_enhanced(user_id):
    """Enhanced endpoint to get all recordings with their files"""
    try:
        print(f"📋 Getting recordings for user: {user_id}")
        
        # Load model on first recordings request
        if not model_loader.is_model_ready():
            print("Loading model on recordings endpoint request...")
            model_loader.load_model()
            print("Model loaded successfully!")

        # List all recording folders for this user
        user_recordings_prefix = f"users/{user_id}/recordings/"
        
        # Get all objects in user's recordings folder
        response = s3_client.list_objects_v2(
            Bucket="flutter-audio-uploads",
            Prefix=user_recordings_prefix,
            Delimiter='/'
        )

        recordings = []
        
        # Get recording folders (each CommonPrefix is a recording folder)
        if 'CommonPrefixes' in response:
            for prefix in response['CommonPrefixes']:
                recording_folder = prefix['Prefix']
                recording_id = recording_folder.split('/')[-2]  # Extract recording ID from path
                
                # Try to get metadata for this recording
                try:
                    metadata_key = f"{recording_folder}metadata.json"
                    metadata_response = s3_client.get_object(
                        Bucket="flutter-audio-uploads",
                        Key=metadata_key
                    )
                    metadata = json.loads(metadata_response['Body'].read().decode('utf-8'))
                    
                    # Add the complete recording info
                    recordings.append({
                        'recording_id': recording_id,
                        'metadata': metadata,
                        'files': metadata.get('files', {}),
                        'title': metadata.get('title', 'Untitled'),
                        'upload_date': metadata.get('upload_date'),
                        'description': metadata.get('description', ''),
                        'user_id': metadata.get('user_id', user_id),  # Ensure user_id is available
                        # For backward compatibility with existing UI
                        'url': metadata.get('files', {}).get('audio', {}).get('url', ''),
                        'has_image': 'image' in metadata.get('files', {}),
                        'has_pdf': 'pdf' in metadata.get('files', {}),
                        'has_midi': 'midi' in metadata.get('files', {})
                    })
                    
                except Exception as e:
                    print(f"❌ Error reading metadata for recording {recording_id}: {e}")
                    # If metadata is missing, try to create basic info from folder contents
                    continue

        # Sort recordings by upload date (newest first)
        recordings.sort(key=lambda x: x.get('upload_date', ''), reverse=True)
        
        print(f"🎵 Found {len(recordings)} recordings for user {user_id}")
        
        return jsonify({
            "success": True,
            "userId": user_id,
            "recordings": recordings,
            "model_ready": model_loader.is_model_ready(),
            "total_recordings": len(recordings)
        }), 200

    except Exception as e:
        print(f"❌ Error in enhanced recordings endpoint: {e}")
        import traceback
        traceback.print_exc()


@app.route('/recordings/<recording_id>', methods=['PUT'])
def update_recording_metadata(recording_id):
    """Update recording metadata and optionally replace image"""
    try:
        print(f"📝 Updating recording {recording_id}")
        
        # Validate required fields
        if 'userId' not in request.form:
            return jsonify({"error": "User ID is required"}), 400

        user_id = request.form['userId']
        title = request.form.get('title', 'Untitled Recording')
        description = request.form.get('description', '')
        
        print(f"👤 User: {user_id}")
        print(f"🏷️ New title: {title}")
        print(f"📝 New description: {description}")

        # Construct recording folder path
        recording_folder = f"users/{user_id}/recordings/{recording_id}"
        metadata_key = f"{recording_folder}/metadata.json"
        
        # Get existing metadata
        try:
            metadata_response = s3_client.get_object(
                Bucket="flutter-audio-uploads",
                Key=metadata_key
            )
            metadata = json.loads(metadata_response['Body'].read().decode('utf-8'))
            print("📋 Loaded existing metadata")
        except Exception as e:
            print(f"❌ Could not load existing metadata: {e}")
            return jsonify({"error": "Recording not found or access denied"}), 404

        # Update metadata fields
        metadata['title'] = title
        metadata['description'] = description
        metadata['last_modified'] = datetime.now().isoformat()

        # Handle new image file if provided
        image_file = request.files.get('image_file')
        if image_file and image_file.filename:
            print(f"🖼️ Processing new image: {image_file.filename}")
            
            # Save image locally first
            image_extension = get_file_extension(image_file.filename)
            local_image_path = save_file_locally(image_file, f"image_update_{recording_id}{image_extension}")
            
            # Upload new image to S3 (replacing old one)
            image_s3_path = f"{recording_folder}/image{image_extension}"
            upload_file_to_s3(local_image_path, image_s3_path, image_file.content_type)
            
            # Update metadata with new image info
            metadata['files']['image'] = {
                'filename': f"image{image_extension}",
                'original_name': image_file.filename,
                'content_type': image_file.content_type,
                's3_path': image_s3_path,
                'url': f"https://flutter-audio-uploads.s3.amazonaws.com/{image_s3_path}"
            }
            
            clean_up_local_file(local_image_path)
            print("✅ Image updated successfully")

        # Save updated metadata back to S3
        save_metadata_to_s3(metadata, metadata_key)
        print("✅ Metadata updated successfully")

        return jsonify({
            "success": True,
            "message": f"Recording '{title}' updated successfully",
            "recording_id": recording_id,
            "metadata": metadata
        }), 200

    except Exception as e:
        print(f"❌ Update error: {e}")
        import traceback
        traceback.print_exc()
        
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


@app.route('/recordings/<user_id>/<recording_id>/transcribe', methods=['POST'])
def generate_transcription_for_recording(user_id, recording_id):
    """Generate AI transcription for an existing recording and save files to S3"""
    try:
        print(f"🤖 Generating transcription for recording {recording_id}")
        
        # Get request data
        data = request.get_json() or {}
        title = data.get('title', 'Piano Transcription')
        sheet_format = data.get('sheet_format', 'pdf')
        tempo = int(data.get('tempo', 120))
        
        # Get the recording's metadata and audio file from S3
        recording_folder = f"users/{user_id}/recordings/{recording_id}"
        metadata_key = f"{recording_folder}/metadata.json"
        
        try:
            metadata_response = s3_client.get_object(
                Bucket="flutter-audio-uploads",
                Key=metadata_key
            )
            metadata = json.loads(metadata_response['Body'].read().decode('utf-8'))
            print("📋 Loaded recording metadata")
        except Exception as e:
            print(f"❌ Could not load recording metadata: {e}")
            return jsonify({"error": "Recording not found"}), 404

        # Get audio file info
        audio_info = metadata.get('files', {}).get('audio')
        if not audio_info:
            return jsonify({"error": "Audio file not found in recording"}), 404

        audio_s3_path = audio_info['s3_path']
        print(f"📥 Audio file S3 path: {audio_s3_path}")
        
        # Download audio file from S3 to temp location
        import tempfile
        temp_audio_path = None
        
        try:
            # Create temp file with proper extension
            audio_extension = audio_info.get('filename', 'audio.m4a').split('.')[-1]
            with tempfile.NamedTemporaryFile(delete=False, suffix=f'.{audio_extension}') as temp_audio:
                temp_audio_path = temp_audio.name
                
            # Download from S3
            s3_client.download_file(
                "flutter-audio-uploads",
                audio_s3_path,
                temp_audio_path
            )
            
            print(f"📥 Downloaded audio file for transcription: {temp_audio_path}")
            
            # Use the same transcription logic as the regular endpoint
            success, result_data, error_message = perform_transcription(
                temp_audio_path, title, sheet_format, tempo
            )
            
            if success:
                # Add recording-specific info to result
                result_data['recording_id'] = recording_id
                result_data['user_id'] = user_id
                
                # Save generated files to S3 and get updated URLs
                updated_result_data = save_generated_files_to_s3(user_id, recording_id, result_data)
                
                print(f"✅ Transcription completed for recording {recording_id}")
                print(f"🔗 Updated URLs:")
                if 'midi_file' in updated_result_data:
                    print(f"   MIDI: {updated_result_data['midi_file']}")
                if 'sheet_music' in updated_result_data and updated_result_data['sheet_music']:
                    print(f"   PDF: {updated_result_data['sheet_music'].get('fileUrl', 'None')}")
                
                return jsonify(updated_result_data), 200
            else:
                print(f"❌ Transcription failed: {error_message}")
                return jsonify({"error": error_message}), 500
                
        finally:
            # Clean up temp file
            if temp_audio_path and os.path.exists(temp_audio_path):
                try:
                    os.unlink(temp_audio_path)
                    print("🧹 Cleaned up temporary audio file")
                except Exception as cleanup_e:
                    print(f"⚠️ Warning: Could not clean up temp file: {cleanup_e}")

    except Exception as e:
        print(f"❌ Transcription error: {e}")
        import traceback
        traceback.print_exc()
        
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500



@app.route('/api/health', methods=['GET'])
def health_check():
    """Simple health check endpoint"""
    return jsonify({
        "status": "ok",
        "model_loaded": model_loader.is_model_ready(),
        "timestamp": datetime.now().isoformat(),
        "message": "Model loads on first recordings endpoint request"
    })


@app.route('/api/transcribe', methods=['POST'])
def transcribe_audio_with_sheet_music():
    """Enhanced transcribe endpoint that includes sheet music generation"""
    if 'audio' not in request.files:
        return jsonify({"error": "No audio file provided"}), 400

    file = request.files['audio']
    if file.filename == '':
        return jsonify({"error": "Empty filename"}), 400

    try:
        # Get optional parameters for sheet music
        sheet_format = request.form.get('sheet_format', 'pdf')
        title = request.form.get('title', 'Piano Transcription')
        tempo = int(request.form.get('tempo', '120'))

        # Generate a unique filename to prevent collisions
        original_filename = secure_filename(file.filename)
        filename = f"{uuid.uuid4()}_{original_filename}"
        audio_path = os.path.join(UPLOAD_FOLDER, filename)
        file.save(audio_path)

        print(f"🎵 Processing uploaded audio file: {filename}")

        # Use the shared transcription function
        success, result_data, error_message = perform_transcription(
            audio_path, title, sheet_format, tempo
        )

        # Clean up uploaded file
        try:
            if os.path.exists(audio_path):
                os.remove(audio_path)
        except Exception as cleanup_e:
            print(f"⚠️ Warning: Could not clean up uploaded file: {cleanup_e}")

        if success:
            return jsonify(result_data)
        else:
            return jsonify({"error": error_message}), 500

    except Exception as e:
        print(f"❌ Error in transcription endpoint: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route('/api/convert-midi-to-sheet', methods=['POST'])
def convert_midi_to_sheet():
    """Convert an existing MIDI file to sheet music"""
    if 'midi' not in request.files:
        return jsonify({"error": "No MIDI file provided"}), 400

    file = request.files['midi']
    if file.filename == '':
        return jsonify({"error": "Empty filename"}), 400

    try:
        # Get parameters
        format_type = request.form.get('format', 'pdf')
        title = request.form.get('title', 'Piano Sheet Music')

        # Check MuseScore availability
        musescore_available, musescore_info = check_musescore_installation()
        
        if not musescore_available:
            return jsonify({
                "error": "MuseScore is not available for sheet music generation",
                "musescore_info": musescore_info
            }), 400

        # Save uploaded MIDI file
        original_filename = secure_filename(file.filename)
        filename = f"{uuid.uuid4()}_{original_filename}"
        midi_path = os.path.join(UPLOAD_FOLDER, filename)
        file.save(midi_path)

        # Generate sheet music
        if format_type.lower() == 'pdf':
            # First convert to MusicXML, then to PDF
            musicxml_filename = f"{os.path.splitext(filename)[0]}.musicxml"
            musicxml_path = os.path.join(OUTPUT_FOLDER, musicxml_filename)
            
            pdf_filename = f"{os.path.splitext(filename)[0]}.pdf"
            pdf_path = os.path.join(OUTPUT_FOLDER, pdf_filename)
            
            # Convert MIDI to MusicXML
            success, message = convert_midi_to_musicxml(midi_path, musicxml_path)
            
            if success:
                # Convert MusicXML to PDF
                pdf_success, pdf_message = convert_musicxml_to_pdf(musicxml_path, pdf_path)
                
                if pdf_success:
                    sheet_music_result = {
                        "fileUrl": f"/api/download/{pdf_filename}",
                        "format": "pdf",
                        "title": title
                    }
                else:
                    return jsonify({"error": f"PDF conversion failed: {pdf_message}"}), 500
            else:
                return jsonify({"error": f"MusicXML conversion failed: {message}"}), 500
        else:
            # Direct MusicXML conversion
            musicxml_filename = f"{os.path.splitext(filename)[0]}.musicxml"
            musicxml_path = os.path.join(OUTPUT_FOLDER, musicxml_filename)
            
            success, message = convert_midi_to_musicxml(midi_path, musicxml_path)
            
            if success:
                sheet_music_result = {
                    "fileUrl": f"/api/download/{musicxml_filename}",
                    "format": "musicxml",
                    "title": title
                }
            else:
                return jsonify({"error": f"MusicXML conversion failed: {message}"}), 500

        # Clean up uploaded MIDI file
        try:
            if os.path.exists(midi_path):
                os.remove(midi_path)
        except Exception as cleanup_e:
            print(f"Warning: Could not clean up MIDI file: {cleanup_e}")

        return jsonify({
            "success": True,
            "sheet_music": sheet_music_result,
            "musescore_available": True
        })

    except Exception as e:
        print(f"Error in MIDI to sheet conversion: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/api/download/<filename>', methods=['GET'])
def download_midi(filename):
    """Download the generated MIDI file"""
    try:
        file_path = os.path.join(OUTPUT_FOLDER, secure_filename(filename))
        if not os.path.exists(file_path):
            return jsonify({"error": "File not found"}), 404
        return send_file(file_path, as_attachment=True)
    except Exception as e:
        print(f"Error downloading file {filename}: {e}")
        return jsonify({"error": str(e)}), 404


@app.route('/process-audio', methods=['POST'])
def process_audio():
    """Process uploaded audio file and return detected notes"""
    if 'file' not in request.files:
        print("No file part in the request.")
        return jsonify({"error": "No file part in the request"}), 400

    file = request.files['file']
    if file.filename == '':
        print("No selected file.")
        return jsonify({"error": "No selected file"}), 400

    try:
        # Save the uploaded audio file locally
        file_ext = os.path.splitext(file.filename)[1].lower()
        unique_filename = f"{uuid.uuid4()}_{secure_filename(file.filename)}"
        audio_path = os.path.join(UPLOAD_FOLDER, unique_filename)
        file.save(audio_path)
        print(f"File saved at: {audio_path}")

        # Convert to WAV if needed
        wav_file_path = os.path.splitext(audio_path)[0] + ".wav"
        if file_ext != '.wav':
            print(f"Converting {file_ext} to WAV...")
            if file_ext == '.m4a':
                success = convert_m4a_to_wav(audio_path, wav_file_path)
            else:
                success = convert_audio_to_wav(audio_path, wav_file_path)

            if not success:
                return jsonify({"error": "Failed to convert audio file"}), 500
        else:
            wav_file_path = audio_path

        # Extract features from audio
        mel_spec = extract_mel_spectrogram(wav_file_path)
        expected_height = 229
        expected_width = 625

        print(f"Original spectrogram shape: {mel_spec.shape}")

        # Adjust frequency dimension if needed
        if mel_spec.shape[0] != expected_height:
            print(f"Resizing frequency dimension from {mel_spec.shape[0]} to {expected_height}")
            mel_spec = tf.image.resize(
                tf.expand_dims(mel_spec, 0),  # Add batch dimension for resize
                [expected_height, mel_spec.shape[1]]
            )[0]  # Remove batch dimension

        # Adjust time dimension if needed
        if mel_spec.shape[1] < expected_width:
            padding = expected_width - mel_spec.shape[1]
            mel_spec = np.pad(mel_spec, ((0, 0), (0, padding)), mode='constant')
            print(f"Padded time dimension to {mel_spec.shape}")
        elif mel_spec.shape[1] > expected_width:
            mel_spec = mel_spec[:, :expected_width]
            print(f"Trimmed time dimension to {mel_spec.shape}")

        # Prepare for model input
        mel_spec = tf.transpose(mel_spec)
        mel_spec = tf.expand_dims(mel_spec, axis=0)  # Batch dimension
        mel_spec = tf.expand_dims(mel_spec, axis=-1)  # Channel dimension
        print(f"Spectrogram shape for model input: {mel_spec.shape}")

        # Run model prediction using ModelLoader
        try:
            current_model = model_loader.get_model()
            print("Model loaded successfully for processing")
            print("Running model prediction...")
            predictions = current_model.predict(mel_spec)
            print("Model prediction completed")
            notes = extract_notes_from_predictions(predictions)
            print(f"Extracted {len(notes)} notes")

        except Exception as model_error:
            # Fallback to test notes if model fails
            print(f"Model failed: {model_error}, generating test notes...")
            print("Creating test notes (C major scale)...")
            notes = []
            for i, pitch in enumerate([60, 62, 64, 65, 67, 69, 71, 72]):  # C4 to C5
                notes.append({
                    "note_name": pitch_to_note_name(pitch),
                    "time": float(i * 0.5),
                    "duration": 0.4,
                    "velocity": 0.8,
                    "velocity_midi": 100,
                    "pitch": pitch,
                    "frequency": librosa.midi_to_hz(pitch)
                })

        # Detailed logging to debug note detection
        print("\n===== EXTRACTED NOTES SUMMARY =====")
        print(f"Total notes extracted: {len(notes)}")
        if len(notes) > 0:
            print(f"Time range: {notes[0]['time']:.2f}s to {notes[-1]['time']:.2f}s")
            print(f"Pitch range: {min([n['pitch'] for n in notes])} to {max([n['pitch'] for n in notes])}")

        # Generate MIDI file from the notes
        midi_filename = f"{os.path.splitext(unique_filename)[0]}.mid"
        midi_output_path = os.path.join(OUTPUT_FOLDER, midi_filename)
        create_midi_from_notes(notes, midi_output_path)
        print(f"MIDI file created at: {midi_output_path}")

        # Clean up temporary files
        try:
            if os.path.exists(audio_path):
                os.remove(audio_path)
            if os.path.exists(wav_file_path) and wav_file_path != audio_path:
                os.remove(wav_file_path)
        except Exception as cleanup_e:
            print(f"Warning: Could not clean up temporary files: {cleanup_e}")

        # Return the detected notes to the frontend
        return jsonify({
            "success": True,
            "notes": notes,
            "midi_file": f"/api/download/{midi_filename}"
        }), 200

    except Exception as e:
        print(f"Error processing audio: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route('/api/recording/<user_id>/<recording_id>', methods=['GET'])
def get_recording_detail(user_id, recording_id):
    """Get detailed information about a specific recording"""
    try:
        metadata = get_recording_metadata(user_id, recording_id)
        
        if not metadata:
            return jsonify({"error": "Recording not found"}), 404
        
        # Return detailed recording information
        return jsonify({
            "success": True,
            "recording": metadata
        })
        
    except Exception as e:
        print(f"Error getting recording detail: {e}")
        return jsonify({"error": str(e)}), 500

        
@app.route('/api/recording/<user_id>/<recording_id>', methods=['PUT'])
def update_user_recording_metadata(user_id, recording_id):
    """Update recording metadata (title, description, etc.)"""
    try:
        data = request.get_json()
        
        metadata = get_recording_metadata(user_id, recording_id)
        if not metadata:
            return jsonify({"error": "Recording not found"}), 404
        
        # Update allowed fields
        if 'title' in data:
            metadata['title'] = data['title']
        if 'description' in data:
            metadata['description'] = data['description']
        
        metadata['updated_at'] = datetime.now().isoformat()
        
        # Save updated metadata
        save_recording_metadata(user_id, recording_id, metadata)
        
        return jsonify({
            "success": True,
            "message": "Recording updated successfully",
            "recording": metadata
        })
        
    except Exception as e:
        print(f"Error updating recording: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/test', methods=['GET'])
def simple_test():
    """Simple test to check if server is working"""
    return jsonify({
        "success": True,
        "message": "Server is working!",
        "timestamp": datetime.now().isoformat()
    })

@app.route('/test-json', methods=['GET'])
def test_json():
    """Test JSON response"""
    try:
        test_data = {
            "test": "working",
            "bucket": "flutter-audio-uploads",
            "model_ready": model_loader.is_model_ready() if 'model_loader' in globals() else False
        }
        return jsonify(test_data)
    except Exception as e:
        return jsonify({"error": str(e), "type": type(e).__name__})

if __name__ == '__main__':
    # For Hugging Face Spaces, we need to use the PORT environment variable
    port = int(os.environ.get('PORT', 7860))
    app.run(host='0.0.0.0', port=port, debug=False)