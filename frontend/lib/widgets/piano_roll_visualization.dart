import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/transcription_result.dart';
import '../config/app_theme.dart';
import '../services/platform_service.dart';

typedef TimeUpdateCallback = void Function(double currentTime);

class PianoRollVisualization extends StatefulWidget {
  final List<Note> notes;
  final double duration;
  final PlatformFile? midiFile;
  final TimeUpdateCallback? onTimeUpdate;

  PianoRollVisualization({
    Key? key,
    required this.notes,
    required this.duration,
    this.midiFile,
    this.onTimeUpdate,
  }) : super(key: key);

  @override
  _PianoRollVisualizationState createState() => _PianoRollVisualizationState();
}

class _PianoRollVisualizationState extends State<PianoRollVisualization> with TickerProviderStateMixin {
  final AudioPlayer _midiPlayer = AudioPlayer();

  late AnimationController _animationController;

  double _currentTime = 0.0;
  bool _isPlaying = false;
  bool _hasStarted = false;
  bool _midiLoaded = false;

  final Set<int> _activeNotes = {};

  final int _lowestNote = 21;
  final int _highestNote = 108;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.duration * 1000).round()),
    );

    _animationController.addListener(_onAnimationUpdate);

    if (widget.midiFile != null) {
      _loadMidiFile();
    }
  }

  @override
  void didUpdateWidget(PianoRollVisualization oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.midiFile != oldWidget.midiFile && widget.midiFile != null) {
      _loadMidiFile();
    }
  }

  Future<void> _loadMidiFile() async {
    try {
      if (widget.midiFile != null) {
        print("🎵 Loading MIDI file: ${widget.midiFile!.name}");

        if (widget.midiFile!.isWebDownload) {
          // On web, MIDI files are downloaded to browser, not playable in app
          print("⚠️ MIDI file is web download - cannot play directly in web app");
          setState(() {
            _midiLoaded = false;
          });
          return;
        }

        // On mobile, check if file exists and load it
        final fileExists = await widget.midiFile!.exists();
        if (fileExists) {
          try {
            final size = widget.midiFile!.size;
            print("📊 MIDI file size: $size bytes");

            await _midiPlayer.setSource(DeviceFileSource(widget.midiFile!.path));
            await _midiPlayer.setVolume(1.0);

            setState(() {
              _midiLoaded = true;
            });

            print("✅ MIDI file loaded successfully!");

          } catch (e) {
            print("❌ Error loading MIDI file: $e");
          }
        } else {
          print("❌ MIDI file not found: ${widget.midiFile!.path}");
        }
      }
    } catch (e) {
      print("❌ Error in MIDI loading process: $e");
    }
  }

  void _onAnimationUpdate() {
    _currentTime = _animationController.value * widget.duration;

    _updateActiveNotes();

    widget.onTimeUpdate?.call(_currentTime);

    setState(() {});
  }

  void _updateActiveNotes() {
    _activeNotes.clear();

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

  void startPlayback() async {
    if (_hasStarted) {
      _animationController.forward();
    } else {
      _hasStarted = true;
      _animationController.forward(from: 0);
    }

    setState(() {
      _isPlaying = true;
    });
  }

  void stopPlayback() {
    _animationController.stop();

    setState(() {
      _isPlaying = false;
    });
  }

  void resetPlayback() {
    _animationController.stop();

    _animationController.reset();

    setState(() {
      _currentTime = 0.0;
      _isPlaying = false;
      _hasStarted = false;
      _activeNotes.clear();
    });

    widget.onTimeUpdate?.call(0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Stack(
        children: [
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

          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              color: Colors.red,
            ),
          ),

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
    // First: Count how many WHITE keys total
    int whiteKeyCount = 0;
    for (int pitch = lowestNote; pitch <= highestNote; pitch++) {
      final bool isBlackKey = [1, 3, 6, 8, 10].contains(pitch % 12);
      if (!isBlackKey) {
        whiteKeyCount++;
      }
    }

    // Width for each white key (no gaps)
    final double whiteKeyWidth = size.width / whiteKeyCount;

    // Track which white key we're drawing
    int whiteKeyIndex = 0;

    // Draw white keys consecutively without gaps
    for (int pitch = lowestNote; pitch <= highestNote; pitch++) {
      final bool isBlackKey = [1, 3, 6, 8, 10].contains(pitch % 12);
      if (!isBlackKey) {
        final Rect keyRect = Rect.fromLTWH(
          whiteKeyIndex * whiteKeyWidth,  // Consecutive positioning
          0,
          whiteKeyWidth,
          size.height,
        );

        final bool isActive = activeNotes.contains(pitch);
        final Paint paint = Paint()
          ..color = isActive ? Colors.lightBlue : Colors.white
          ..style = PaintingStyle.fill;

        canvas.drawRect(keyRect, paint);

        canvas.drawRect(
          keyRect,
          Paint()
            ..color = Colors.black45
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );

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
              whiteKeyIndex * whiteKeyWidth + whiteKeyWidth / 2 - textPainter.width / 2,
              size.height - textPainter.height - 2,
            ),
          );
        }

        whiteKeyIndex++;  // Move to next white key position
      }
    }

    // Second pass: Draw black keys positioned relative to white keys
    for (int pitch = lowestNote; pitch <= highestNote; pitch++) {
      final bool isBlackKey = [1, 3, 6, 8, 10].contains(pitch % 12);
      if (isBlackKey) {
        // Count how many white keys come before this black key
        int whiteKeysBeforeBlackKey = 0;
        for (int p = lowestNote; p < pitch; p++) {
          final bool isPreviousBlackKey = [1, 3, 6, 8, 10].contains(p % 12);
          if (!isPreviousBlackKey) {
            whiteKeysBeforeBlackKey++;
          }
        }

        // Position black key between this white key and the next
        final double blackKeyX = (whiteKeysBeforeBlackKey - 0.5) * whiteKeyWidth + whiteKeyWidth * 0.3 - 2;
        final double blackKeyWidth = whiteKeyWidth * 0.6;

        final Rect keyRect = Rect.fromLTWH(
          blackKeyX,
          0,
          blackKeyWidth,
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
    // Calculate white key layout (same as keyboard painter)
    int whiteKeyCount = 0;
    for (int pitch = lowestNote; pitch <= highestNote; pitch++) {
      final bool isBlackKey = [1, 3, 6, 8, 10].contains(pitch % 12);
      if (!isBlackKey) {
        whiteKeyCount++;
      }
    }
    
    final double whiteKeyWidth = size.width / whiteKeyCount;
    final double viewportHeight = size.height - 60;
    final double pixelsPerSecond = viewportHeight / 3.0;

    for (final note in notes) {
      if (note.time + note.duration < currentTime - 1.0 || note.time > currentTime + 3.0) {
        continue;
      }

      final double timeDiff = note.time - currentTime;
      
      // Calculate note position using new layout logic
      final double noteX = _getNoteXPosition(note.pitch, whiteKeyWidth);
      final double noteWidth = _getNoteWidth(note.pitch, whiteKeyWidth);

      if (timeDiff > 0) {
        final double noteTop = viewportHeight - (viewportHeight * (timeDiff / 3.0));
        final double noteHeight = pixelsPerSecond * note.duration;

        final Rect noteRect = Rect.fromLTWH(
          noteX,
          noteTop - noteHeight,
          noteWidth,
          noteHeight,
        );

        final Paint paint = Paint()
          ..color = _getNoteColor(note.pitch).withOpacity(0.8)
          ..style = PaintingStyle.fill;

        canvas.drawRRect(
          RRect.fromRectAndRadius(noteRect, Radius.circular(3)),
          paint,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(noteRect, Radius.circular(3)),
          Paint()
            ..color = Colors.white.withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      else if (note.time <= currentTime && note.time + note.duration > currentTime) {
        final double remainingDuration = note.time + note.duration - currentTime;
        final double noteHeight = pixelsPerSecond * remainingDuration;

        final Rect noteRect = Rect.fromLTWH(
          noteX,
          viewportHeight - noteHeight,
          noteWidth,
          noteHeight,
        );

        final Paint paint = Paint()
          ..color = _getNoteColor(note.pitch).withOpacity(0.8)
          ..style = PaintingStyle.fill;

        canvas.drawRRect(
          RRect.fromRectAndRadius(noteRect, Radius.circular(3)),
          paint,
        );

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

  // Calculate X position for a note (same logic as keyboard painter)
  double _getNoteXPosition(int pitch, double whiteKeyWidth) {
    final bool isBlackKey = [1, 3, 6, 8, 10].contains(pitch % 12);
    
    if (!isBlackKey) {
      // White key: count white keys before this one
      int whiteKeyIndex = 0;
      for (int p = lowestNote; p < pitch; p++) {
        final bool isPreviousBlackKey = [1, 3, 6, 8, 10].contains(p % 12);
        if (!isPreviousBlackKey) {
          whiteKeyIndex++;
        }
      }
      return whiteKeyIndex * whiteKeyWidth;
    } else {
      // Black key: position between white keys (same as keyboard painter)
      int whiteKeysBeforeBlackKey = 0;
      for (int p = lowestNote; p < pitch; p++) {
        final bool isPreviousBlackKey = [1, 3, 6, 8, 10].contains(p % 12);
        if (!isPreviousBlackKey) {
          whiteKeysBeforeBlackKey++;
        }
      }
      return (whiteKeysBeforeBlackKey - 0.5) * whiteKeyWidth + whiteKeyWidth * 0.3 - 2;
    }
  }

  // Calculate width for a note
  double _getNoteWidth(int pitch, double whiteKeyWidth) {
    final bool isBlackKey = [1, 3, 6, 8, 10].contains(pitch % 12);
    return isBlackKey ? whiteKeyWidth * 0.6 : whiteKeyWidth;
  }

  Color _getNoteColor(int pitch) {
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