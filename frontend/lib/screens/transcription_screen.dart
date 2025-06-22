import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';
import '../models/transcription_result.dart';
import 'result_screen.dart';
import '../config/app_theme.dart';

class TranscriptionScreen extends StatefulWidget {
  @override
  _TranscriptionScreenState createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  final AudioService _audioService = AudioService();
  final ApiService _apiService = ApiService(
    baseUrl: 'https://razvanix-wave2notes.hf.space',
  );

  bool _isRecording = false;
  bool _isProcessing = false;
  String? _recordingPath;
  String _status = 'Ready to record';
  int _processingSeconds = 0;

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      setState(() => _status = 'Stopping recording...');
      final path = await _audioService.stopRecording();

      setState(() {
        _isRecording = false;
        _recordingPath = path;
        _status = path != null
            ? 'Recording saved'
            : 'Failed to save recording';
      });
    } else {
      setState(() => _status = 'Starting recording...');
      final success = await _audioService.startRecording();

      setState(() {
        _isRecording = success;
        _status = success
            ? 'Recording...'
            : 'Failed to start recording';
      });
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null) {
      setState(() {
        _recordingPath = result.files.single.path;
        _status = 'Audio file selected';
      });
    }
  }

  Future<void> _transcribe() async {
    if (_recordingPath == null) {
      setState(() => _status = 'No recording to transcribe');
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = 'Transcribing...';
      _processingSeconds = 0;
    });

    final statusTimer = Stream.periodic(Duration(seconds: 1), (i) => i).listen((seconds) {
      setState(() {
        _processingSeconds = seconds;
        if (seconds < 10) {
          _status = 'Processing audio...';
        } else if (seconds < 30) {
          _status = 'Analyzing audio models...';
        } else if (seconds < 60) {
          _status = 'Transcribing notes...';
        } else if (seconds < 120) {
          _status = 'Nearly finished...';
        } else {
          _status = 'Processing (lasts more than usual)';
        }
      });
    });

    try {
      final serverReady = await _apiService.checkServerStatus();
      if (!serverReady) {
        statusTimer.cancel();
        setState(() {
          _isProcessing = false;
          _status = 'Server is not available';
        });
        return;
      }

      final result = await _apiService.transcribeAudio(
        _recordingPath!,
        sheetFormat: 'pdf',
        title: 'Piano Transcription',
        tempo: 120,
      );
      statusTimer.cancel();

      setState(() {
        _isProcessing = false;
        _status = result != null
            ? 'Transcription complete'
            : 'Transcription failed';
      });

      if (result != null) {
      print('🎼 Transcription result:');
      print('  - Notes: ${result.notes.length}');
      print('  - MIDI: ${result.midiFileUrl}');
      print('  - Sheet Music: ${result.sheetMusic?.fileUrl ?? 'None'}');
      print('  - MuseScore: ${result.musescoreAvailable}');
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(result: result),
        ),
      );
    }
    } catch (e) {
      statusTimer.cancel();
      setState(() {
        _isProcessing = false;
        _status = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Piano Transcription',
          style: TextStyle(color: AppTheme.textColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.textColor),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.backgroundColor,
              Color(0xFFE8F4F2),
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 40),
                if (_isProcessing)
                  Column(
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Processing the recording...\nThis process can last up to a minute.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textColor),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                        label: Text(_isRecording ? 'Stop recording' : 'Start recording'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          backgroundColor: _isRecording ? Colors.red : AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _toggleRecording,
                      ),
                      SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: Icon(Icons.upload_file),
                        label: Text('Select an Audio File'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: AppTheme.primaryColor),
                          ),
                        ),
                        onPressed: _pickAudioFile,
                      ),
                      SizedBox(height: 40),
                      if (_recordingPath != null)
                        ElevatedButton.icon(
                          icon: Icon(Icons.music_note),
                          label: Text('Transcript Notes'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                            backgroundColor: AppTheme.accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _transcribe,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}