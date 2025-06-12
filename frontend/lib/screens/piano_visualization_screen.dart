import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class PianoVisualizationScreen extends StatefulWidget {
  final String recordingUrl;
  final Map<String, dynamic> recordingData;

  PianoVisualizationScreen({
    required this.recordingUrl,
    required this.recordingData,
  });

  @override
  _PianoVisualizationScreenState createState() => _PianoVisualizationScreenState();
}

class _PianoVisualizationScreenState extends State<PianoVisualizationScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isPlaying = false;

  // Date simulate pentru note (vor fi înlocuite cu datele reale din AI)
  final List<Map<String, dynamic>> _mockNotes = [
    {'note': 'C4', 'startTime': 0.5, 'duration': 0.5, 'velocity': 80},
    {'note': 'E4', 'startTime': 1.0, 'duration': 0.5, 'velocity': 70},
    {'note': 'G4', 'startTime': 1.5, 'duration': 1.0, 'velocity': 90},
    {'note': 'C5', 'startTime': 2.5, 'duration': 1.5, 'velocity': 85},
    {'note': 'D4', 'startTime': 4.0, 'duration': 0.5, 'velocity': 75},
    {'note': 'F4', 'startTime': 4.5, 'duration': 0.5, 'velocity': 80},
    {'note': 'A4', 'startTime': 5.0, 'duration': 1.0, 'velocity': 85},
    {'note': 'B4', 'startTime': 6.0, 'duration': 2.0, 'velocity': 90},
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 10), // Durată simulată pentru animație
    );

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isPlaying = false;
        });
        _animationController.reset();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _animationController.forward();
      } else {
        _animationController.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMock = widget.recordingData['isMock'] ?? false;
    final title = widget.recordingData['title'] ?? 'Unnamed Recording';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'Notes Visualization',
              style: TextStyle(color: AppTheme.textColor),
            ),
            if (isMock)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Simulated Notes',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ),
              ),
          ],
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
        child: Column(
          children: [
            // Informații despre înregistrare
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textColor,
                ),
              ),
            ),

            // Zona de vizualizare Synthesia
            Expanded(
              child: Stack(
                children: [
                  // Fundal negru pentru vizualizare
                  Container(
                    color: Colors.black87,
                  ),

                  // Animația notelor care cad
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: Size.infinite,
                        painter: PianoRollPainter(
                          notes: _mockNotes,
                          progress: _animationController.value,
                        ),
                      );
                    },
                  ),

                  // Claviatura de pian în partea de jos
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 100,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: PianoKeyboardPainter(),
                    ),
                  ),
                ],
              ),
            ),

            // Controale pentru redare
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Buton Play/Pause
                  FloatingActionButton(
                    onPressed: _togglePlayPause,
                    backgroundColor: AppTheme.accentColor,
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 24),

                  // Buton Reset
                  FloatingActionButton(
                    onPressed: () {
                      setState(() {
                        _isPlaying = false;
                        _animationController.reset();
                      });
                    },
                    backgroundColor: AppTheme.primaryColor,
                    child: Icon(
                      Icons.replay,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// CustomPainter pentru nota care cade
class PianoRollPainter extends CustomPainter {
  final List<Map<String, dynamic>> notes;
  final double progress;

  PianoRollPainter({
    required this.notes,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalDuration = 10.0; // Durată totală în secunde
    final secondsElapsed = progress * totalDuration;
    final viewportHeight = size.height - 100; // Height minus keyboard

    // Dimensiunile pentru note
    final whiteKeyWidth = size.width / 52; // Lățimea unei clape albe (7 octave * 7 note + 3 note)

    // Notele și pozițiile lor pe claviatură
    final notePositions = {
      'C4': 28, 'C#4': 28.5, 'D4': 29, 'D#4': 29.5, 'E4': 30, 'F4': 31, 'F#4': 31.5,
      'G4': 32, 'G#4': 32.5, 'A4': 33, 'A#4': 33.5, 'B4': 34,
      'C5': 35, 'C#5': 35.5, 'D5': 36, 'D#5': 36.5, 'E5': 37, 'F5': 38, 'F#5': 38.5,
      'G5': 39, 'G#5': 39.5, 'A5': 40, 'A#5': 40.5, 'B5': 41,
    };

    // Culori pentru note
    final colors = <String, Color>{
      'C': Colors.red[400]!,
      'D': Colors.orange[400]!,
      'E': Colors.yellow[400]!,
      'F': Colors.green[400]!,
      'G': Colors.blue[400]!,
      'A': Colors.indigo[400]!,
      'B': Colors.purple[400]!,
    };

    // Desenează fiecare notă
    for (var note in notes) {
      final noteName = note['note'] as String;
      final startTime = note['startTime'] as double;
      final duration = note['duration'] as double;
      final velocity = note['velocity'] as int;

      // Verifică dacă nota este vizibilă în viewport
      if (startTime > secondsElapsed + 5) {
        continue; // Nota este prea departe în viitor
      }
      if (startTime + duration < secondsElapsed - 1) {
        continue; // Nota a trecut deja
      }

      // Calcul poziție notă
      final keyPosition = notePositions[noteName] ?? 0;
      final baseColor = colors[noteName[0]] ?? Colors.grey;
      final opacity = 0.5 + (velocity / 127) * 0.5; // Intensitate bazată pe velocitate

      // Calculează poziția notei pe ecran
      final xPos = keyPosition * whiteKeyWidth;
      final yStart = (startTime - secondsElapsed) * viewportHeight / 5 + viewportHeight;
      final noteHeight = duration * viewportHeight / 5;

      // Definește dreptunghiul notei
      final noteRect = Rect.fromLTWH(
        xPos - whiteKeyWidth / 2,
        yStart - noteHeight,
        whiteKeyWidth,
        noteHeight,
      );

      // Desenează nota
      final paint = Paint()
        ..color = baseColor.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);

      // Adaugă umbră
      canvas.drawRRect(
        RRect.fromRectAndRadius(noteRect.translate(2, 2), Radius.circular(4)),
        shadowPaint,
      );

      // Desenează nota cu margini rotunjite
      canvas.drawRRect(
        RRect.fromRectAndRadius(noteRect, Radius.circular(4)),
        paint,
      );

      // Adaugă un contur
      final borderPaint = Paint()
        ..color = baseColor.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawRRect(
        RRect.fromRectAndRadius(noteRect, Radius.circular(4)),
        borderPaint,
      );
    }

    // Desenează linia de timp (punctul de declanșare a notelor)
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(0, viewportHeight),
      Offset(size.width, viewportHeight),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant PianoRollPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// CustomPainter pentru claviatura de pian
class PianoKeyboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final numWhiteKeys = 52; // 7 octave * 7 white keys per octave + 3 extra keys
    final whiteKeyWidth = size.width / numWhiteKeys;
    final whiteKeyHeight = size.height;
    final blackKeyWidth = whiteKeyWidth * 0.6;
    final blackKeyHeight = whiteKeyHeight * 0.6;

    // Creare pensule
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final blackPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Desenează clapele albe
    for (int i = 0; i < numWhiteKeys; i++) {
      final keyRect = Rect.fromLTWH(
        i * whiteKeyWidth,
        0,
        whiteKeyWidth,
        whiteKeyHeight,
      );

      canvas.drawRect(keyRect, whitePaint);
      canvas.drawRect(keyRect, borderPaint);
    }

    // Desenează clapele negre
    // Pattern pentru clape negre: după clapele albe 0, 1, 3, 4, 5 în fiecare octavă
    for (int octave = 0; octave < 7; octave++) {
      final blackKeyPositions = [0, 1, 3, 4, 5];

      for (int pos in blackKeyPositions) {
        final i = octave * 7 + pos;
        final xPos = i * whiteKeyWidth + whiteKeyWidth * 0.7;

        final keyRect = Rect.fromLTWH(
          xPos,
          0,
          blackKeyWidth,
          blackKeyHeight,
        );

        canvas.drawRect(keyRect, blackPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}