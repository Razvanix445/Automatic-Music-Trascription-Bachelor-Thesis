import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/app_theme.dart';

class MidiPlayerButton extends StatefulWidget {
  final String midiFilePath;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onReset;
  final double currentTime;
  final double totalDuration;

  MidiPlayerButton({
    required this.midiFilePath,
    required this.onPlay,
    required this.onPause,
    required this.onReset,
    required this.currentTime,
    required this.totalDuration,
  });

  @override
  _MidiPlayerButtonState createState() => _MidiPlayerButtonState();
}

class _MidiPlayerButtonState extends State<MidiPlayerButton> {
  late AudioPlayer _midiPlayer;
  bool _isPlaying = false;
  bool _isInitialized = false;
  String _statusMessage = "Initializing...";

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _midiPlayer.dispose();
    super.dispose();
  }

  // Initialize the MIDI player
  Future<void> _initializePlayer() async {
    try {
      _midiPlayer = AudioPlayer();

      final file = File(widget.midiFilePath);
      final exists = await file.exists();

      if (!exists) {
        setState(() {
          _statusMessage = "File missing";
        });
        return;
      }

      await _midiPlayer.setVolume(1.0);
      await _midiPlayer.setSource(DeviceFileSource(widget.midiFilePath));

      setState(() {
        _isInitialized = true;
        _statusMessage = "Ready";
      });

      _midiPlayer.onPlayerComplete.listen((event) {
        setState(() {
          _isPlaying = false;
        });
        widget.onReset();
      });

    } catch (e) {
      print("❌ Error initializing MIDI player: $e");
      setState(() {
        _statusMessage = "Error";
      });
    }
  }

  // Play MIDI with proper error handling
  Future<void> _playMidi() async {
    if (!_isInitialized) {
      await _initializePlayer();
      if (!_isInitialized) return;
    }

    try {
      setState(() {
        _statusMessage = "Loading...";
      });

      await _midiPlayer.stop();
      await _midiPlayer.setSource(DeviceFileSource(widget.midiFilePath));
      await _midiPlayer.setVolume(1.0);

      if (widget.currentTime > 0) {
        await _midiPlayer.seek(Duration(milliseconds: (widget.currentTime * 1000).round()));
      }

      await _midiPlayer.resume();

      setState(() {
        _isPlaying = true;
        _statusMessage = "Playing";
      });

      widget.onPlay();

    } catch (e) {
      print("❌ Error playing MIDI: $e");
      _reinitializePlayer();
    }
  }

  // Pause playback
  Future<void> _pauseMidi() async {
    try {
      await _midiPlayer.pause();

      setState(() {
        _isPlaying = false;
        _statusMessage = "Paused";
      });

      widget.onPause();
    } catch (e) {
      print("❌ Error pausing MIDI: $e");
    }
  }

  // Toggle play/pause
  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _pauseMidi();
    } else {
      await _playMidi();
    }
  }

  // Reset playback
  Future<void> _resetPlayback() async {
    try {
      await _midiPlayer.stop();

      setState(() {
        _isPlaying = false;
        _statusMessage = "Reset";
      });

      await _reinitializePlayer();
      widget.onReset();
    } catch (e) {
      print("❌ Error resetting MIDI: $e");
    }
  }

  // Reinitialize player
  Future<void> _reinitializePlayer() async {
    await _midiPlayer.dispose();

    setState(() {
      _isInitialized = false;
    });

    _midiPlayer = AudioPlayer();

    try {
      await _midiPlayer.setVolume(1.0);
      await _midiPlayer.setSource(DeviceFileSource(widget.midiFilePath));

      _midiPlayer.onPlayerComplete.listen((event) {
        setState(() {
          _isPlaying = false;
        });
        widget.onReset();
      });

      setState(() {
        _isInitialized = true;
        _statusMessage = "Ready";
      });

    } catch (e) {
      print("❌ Error reinitializing player: $e");
    }
  }

  // Format time as mm:ss
  String _formatTime(double seconds) {
    final int mins = (seconds / 60).floor();
    final int secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // More compact layout
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Controls on the left
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Play/Pause button
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _isInitialized ? _togglePlayback : null,
                  color: _isPlaying ? Colors.orange : Colors.green,
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),

                // Reset button
                IconButton(
                  icon: Icon(Icons.replay),
                  onPressed: _isInitialized ? _resetPlayback : null,
                  color: Colors.blue,
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),

            SizedBox(width: 8),

            // Time display in the middle
            Expanded(
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: "${_formatTime(widget.currentTime)} / ${_formatTime(widget.totalDuration)}",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: " • $_statusMessage",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}