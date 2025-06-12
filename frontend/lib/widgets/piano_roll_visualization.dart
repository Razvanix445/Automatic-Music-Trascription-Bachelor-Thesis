import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/transcription_result.dart';
import '../config/app_theme.dart';

// Add a callback type for time updates
typedef TimeUpdateCallback = void Function(double currentTime);

class PianoRollVisualization extends StatefulWidget {
  final List<Note> notes;
  final double duration;
  final String? midiFilePath;
  // Add the callback
  final TimeUpdateCallback? onTimeUpdate;

  PianoRollVisualization({
    Key? key,
    required this.notes,
    required this.duration,
    this.midiFilePath,
    this.onTimeUpdate,
  }) : super(key: key);

  @override
  _PianoRollVisualizationState createState() => _PianoRollVisualizationState();
}

class _PianoRollVisualizationState extends State<PianoRollVisualization> with TickerProviderStateMixin {
  // ONLY use AudioPlayer for MIDI playback - no individual notes
  final AudioPlayer _midiPlayer = AudioPlayer();

  // Animation controller for visualization
  late AnimationController _animationController;

  // Playback state
  double _currentTime = 0.0;
  bool _isPlaying = false;
  bool _hasStarted = false;
  bool _midiLoaded = false;

  // Active notes tracking for visualization only
  final Set<int> _activeNotes = {};

  // Piano constants
  final int _lowestNote = 21; // A0
  final int _highestNote = 108; // C8

  @override
  void initState() {
    super.initState();

    // Set up animation controller for visualization
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.duration * 1000).round()),
    );

    _animationController.addListener(_onAnimationUpdate);

    // Load MIDI file if available
    if (widget.midiFilePath != null) {
      _loadMidiFile();
    }
  }

  @override
  void didUpdateWidget(PianoRollVisualization oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the MIDI file path changed, reload it
    if (widget.midiFilePath != oldWidget.midiFilePath && widget.midiFilePath != null) {
      _loadMidiFile();
    }
  }

  Future<void> _loadMidiFile() async {
    try {
      if (widget.midiFilePath != null) {
        print("🎵 Loading MIDI file: ${widget.midiFilePath}");

        final file = File(widget.midiFilePath!);
        if (await file.exists()) {
          try {
            // For testing purposes, print some info about the file
            final size = await file.length();
            print("📊 MIDI file size: $size bytes");

            // Set the source to the device file
            await _midiPlayer.setSource(DeviceFileSource(widget.midiFilePath!));
            await _midiPlayer.setVolume(1.0);

            setState(() {
              _midiLoaded = true;
            });

            print("✅ MIDI file loaded successfully!");

          } catch (e) {
            print("❌ Error loading MIDI file: $e");
          }
        } else {
          print("❌ MIDI file not found: ${widget.midiFilePath}");
        }
      }
    } catch (e) {
      print("❌ Error in MIDI loading process: $e");
    }
  }

  void _onAnimationUpdate() {
    // Update current time for visualization
    _currentTime = _animationController.value * widget.duration;

    // Update active notes for visualization
    _updateActiveNotes();

    // Call the time update callback if provided
    widget.onTimeUpdate?.call(_currentTime);

    // Update the UI
    setState(() {});
  }

  void _updateActiveNotes() {
    // Clear previous active notes
    _activeNotes.clear();

    // Find currently active notes based on current time
    for (final note in widget.notes) {
      if (note.time <= _currentTime && note.time + note.duration > _currentTime) {
        _activeNotes.add(note.pitch);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _midiPlayer.dispose();
    print("🧹 Resources disposed");
    super.dispose();
  }

  // Method to start playback (can be called from parent)
  void startPlayback() async {
    if (_hasStarted) {
      // If already started, just resume the animation
      _animationController.forward();
    } else {
      _hasStarted = true;
      _animationController.forward(from: 0);
    }

    setState(() {
      _isPlaying = true;
    });
  }

  // Method to stop playback (can be called from parent)
  void stopPlayback() {
    // Stop animation
    _animationController.stop();

    setState(() {
      _isPlaying = false;
    });
  }

  // Method to reset playback (can be called from parent)
  void resetPlayback() {
    // Stop playback
    _animationController.stop();

    // Reset animation
    _animationController.reset();

    setState(() {
      _currentTime = 0.0;
      _isPlaying = false;
      _hasStarted = false;
      _activeNotes.clear();
    });

    // Call the time update callback
    widget.onTimeUpdate?.call(0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Stack(
        children: [
          // Only draw falling notes if playback has started
          if (_hasStarted)
            CustomPaint(
              size: Size.infinite,
              painter: NotePainter(
                notes: widget.notes,
                currentTime: _currentTime,
                lowestNote: _lowestNote,
                highestNote: _highestNote,
                activeNotes: _activeNotes,
              ),
            ),

          // Piano keyboard at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 60,
            child: CustomPaint(
              size: Size.infinite,
              painter: PianoKeyboardPainter(
                lowestNote: _lowestNote,
                highestNote: _highestNote,
                activeNotes: _activeNotes,
              ),
            ),
          ),

          // Play indicator line
          Positioned(
            bottom: 60, // Just above keyboard
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              color: Colors.red,
            ),
          ),

          // Starting instructions or status
          if (!_hasStarted)
            Center(
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_circle_filled,
                      color: Colors.white,
                      size: 48,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Use the controller above to start playback',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '${widget.notes.length} notes detected',
                      style: TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(double seconds) {
    final int minutes = (seconds / 60).floor();
    final int remainingSeconds = (seconds % 60).floor();
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

// Custom painter for piano keyboard
class PianoKeyboardPainter extends CustomPainter {
  final int lowestNote;
  final int highestNote;
  final Set<int> activeNotes;

  PianoKeyboardPainter({
    required this.lowestNote,
    required this.highestNote,
    required this.activeNotes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double keyWidth = size.width / (highestNote - lowestNote + 1);

    // Draw white keys first
    for (int pitch = lowestNote; pitch <= highestNote; pitch++) {
      final bool isBlackKey = [1, 3, 6, 8, 10].contains(pitch % 12);
      if (!isBlackKey) {
        final Rect keyRect = Rect.fromLTWH(
          (pitch - lowestNote) * keyWidth,
          0,
          keyWidth,
          size.height,
        );

        final bool isActive = activeNotes.contains(pitch);
        final Paint paint = Paint()
          ..color = isActive ? Colors.lightBlue : Colors.white
          ..style = PaintingStyle.fill;

        canvas.drawRect(keyRect, paint);

        // Draw key border
        canvas.drawRect(
          keyRect,
          Paint()
            ..color = Colors.black45
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );

        // Draw C note labels
        if (pitch % 12 == 0) {
          TextPainter textPainter = TextPainter(
            text: TextSpan(
              text: 'C${(pitch ~/ 12) - 1}',
              style: TextStyle(fontSize: 8, color: Colors.grey[700]),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(
              (pitch - lowestNote) * keyWidth + keyWidth / 2 - textPainter.width / 2,
              size.height - textPainter.height - 2,
            ),
          );
        }
      }
    }

    // Draw black keys on top
    for (int pitch = lowestNote; pitch <= highestNote; pitch++) {
      final bool isBlackKey = [1, 3, 6, 8, 10].contains(pitch % 12);
      if (isBlackKey) {
        final Rect keyRect = Rect.fromLTWH(
          (pitch - lowestNote) * keyWidth - keyWidth * 0.3,
          0,
          keyWidth * 0.6,
          size.height * 0.6,
        );

        final bool isActive = activeNotes.contains(pitch);
        final Paint paint = Paint()
          ..color = isActive ? Colors.blue : Colors.black
          ..style = PaintingStyle.fill;

        canvas.drawRect(keyRect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(PianoKeyboardPainter oldDelegate) {
    return activeNotes != oldDelegate.activeNotes;
  }
}

// Custom painter for piano roll notes
class NotePainter extends CustomPainter {
  final List<Note> notes;
  final double currentTime;
  final int lowestNote;
  final int highestNote;
  final Set<int> activeNotes;

  NotePainter({
    required this.notes,
    required this.currentTime,
    required this.lowestNote,
    required this.highestNote,
    required this.activeNotes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double keyWidth = size.width / (highestNote - lowestNote + 1);
    final double viewportHeight = size.height - 60; // Exclude keyboard height
    final double pixelsPerSecond = viewportHeight / 3.0; // 3 seconds visible

    // Draw only notes that are visible in the current time window
    for (final note in notes) {
      // Skip notes that are not visible
      if (note.time + note.duration < currentTime - 1.0 || note.time > currentTime + 3.0) {
        continue;
      }

      // Calculate note position
      final double timeDiff = note.time - currentTime;
      final int noteIndex = note.pitch - lowestNote;

      // Notes that haven't reached the bottom yet
      if (timeDiff > 0) {
        final double noteTop = viewportHeight - (viewportHeight * (timeDiff / 3.0));
        final double noteHeight = pixelsPerSecond * note.duration;

        final Rect noteRect = Rect.fromLTWH(
          noteIndex * keyWidth,
          noteTop - noteHeight,
          keyWidth,
          noteHeight,
        );

        // Draw note
        final Paint paint = Paint()
          ..color = _getNoteColor(note.pitch).withOpacity(0.8)
          ..style = PaintingStyle.fill;

        canvas.drawRRect(
          RRect.fromRectAndRadius(noteRect, Radius.circular(3)),
          paint,
        );

        // Draw border
        canvas.drawRRect(
          RRect.fromRectAndRadius(noteRect, Radius.circular(3)),
          Paint()
            ..color = Colors.white.withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      // Notes that have already reached the bottom but are still playing
      else if (note.time <= currentTime && note.time + note.duration > currentTime) {
        final double remainingDuration = note.time + note.duration - currentTime;
        final double noteHeight = pixelsPerSecond * remainingDuration;

        final Rect noteRect = Rect.fromLTWH(
          noteIndex * keyWidth,
          viewportHeight - noteHeight,
          keyWidth,
          noteHeight,
        );

        // Draw note
        final Paint paint = Paint()
          ..color = _getNoteColor(note.pitch).withOpacity(0.8)
          ..style = PaintingStyle.fill;

        canvas.drawRRect(
          RRect.fromRectAndRadius(noteRect, Radius.circular(3)),
          paint,
        );

        // Draw border
        canvas.drawRRect(
          RRect.fromRectAndRadius(noteRect, Radius.circular(3)),
          Paint()
            ..color = Colors.white.withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  Color _getNoteColor(int pitch) {
    // Simple color scheme
    final List<Color> colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.lightGreen,
      Colors.green,
      Colors.teal,
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.pink,
      Colors.deepPurple,
      Colors.amber,
    ];

    return colors[pitch % 12];
  }

  @override
  bool shouldRepaint(NotePainter oldDelegate) {
    return currentTime != oldDelegate.currentTime ||
        activeNotes != oldDelegate.activeNotes;
  }
}