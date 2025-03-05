import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_projects/platform/file_uploader.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import 'platform/audio_recorder_platform.dart';

export 'platform/audio_recorder_io.dart' if (dart.library.html) 'platform/audio_recorder_web.dart';

class Recorder extends StatefulWidget {
  final void Function(String path) onStop;
  final void Function(List<dynamic> notes) onNavigateToNotes;

  const Recorder({super.key, required this.onStop, required this.onNavigateToNotes});

  @override
  State<Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<Recorder> with AudioRecorderMixin {
  int _recordDuration = 0;
  Timer? _timer;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Amplitude? _amplitude;

  @override
  void initState() {
    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });

    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 300))
        .listen((amp) {
      setState(() => _amplitude = amp);
    });

    super.initState();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.aacLc;

        if (!await _isEncoderSupported(encoder)) {
          return;
        }

        final devs = await _audioRecorder.listInputDevices();
        debugPrint(devs.toString());

        const config = RecordConfig(encoder: encoder, numChannels: 1);

        // Record to file
        await recordFile(_audioRecorder, config);

        // Record to stream
        // await recordStream(_audioRecorder, config);

        _recordDuration = 0;

        _startTimer();
      }
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  // Future<void> _stopRecording() async {
  //   try {
  //     final path = await _audioRecorder.stop();
  //     if (path != null) {
  //       widget.onStop(path);
  //
  //       // Upload the file to the server
  //       final file = File(path);
  //       if (!(await file.exists())) {
  //         print("===========================File not found at path: $path===========================");
  //         return;
  //       }
  //       final bytes = await file.readAsBytes();
  //       print("===========================File read successfully, size: ${bytes.length} bytes===========================");
  //
  //       final uri = Uri.parse("http://192.168.0.157:5000/process-midi");
  //       final request = MultipartRequest('POST', uri)
  //         ..files.add(await MultipartFile.fromPath('file', file.path));
  //
  //       final response = await request.send();
  //       if (response.statusCode == 200) {
  //         final responseBody = await response.stream.bytesToString();
  //         final jsonResponse = jsonDecode(responseBody);
  //
  //         print('Response Status: ${responseBody}');
  //
  //         if (jsonResponse is Map<String, dynamic> && jsonResponse.containsKey('notes')) {
  //           final notes = jsonResponse['notes'] as List<dynamic>;
  //           widget.onNavigateToNotes(notes); // Trigger navigation
  //         } else if (jsonResponse is List<dynamic>) {
  //           // Handle the case where the response is a list directly
  //           widget.onNavigateToNotes(jsonResponse); // Assume the list is the notes
  //         } else {
  //           debugPrint('Unexpected server response: $jsonResponse');
  //         }
  //       } else {
  //         debugPrint('File upload failed with status: ${response.statusCode}');
  //       }
  //     }
  //   } catch (e) {
  //     if (kDebugMode) {
  //       print(e);
  //     }
  //   }
  // }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        widget.onStop(path);

        final file = File(path);
        if (!(await file.exists())) {
          print("File not found at path: $path");
          return;
        }

        // Upload the file to the Flask server
        final uri = Uri.parse("http://192.168.100.36:5000/process-audio");
        final request = http.MultipartRequest('POST', uri)
          ..files.add(await http.MultipartFile.fromPath('file', file.path));

        final response = await request.send().timeout(const Duration(seconds: 60), onTimeout: () {
          throw Exception("Request timed out");
        });
        final responseBody = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          final jsonResponse = json.decode(responseBody);

          if (jsonResponse['notes'] != null) {
            final notes = jsonResponse['notes'] as List<dynamic>;
            print("Transcription completed. Extracted notes: $notes");

            widget.onNavigateToNotes(notes);
          } else {
            print("No notes found in the transcription response.");
          }
        } else {
          print("File processing failed with status: ${response.statusCode}");
          print("Error: $responseBody");
        }
      }
    } catch (e) {
      print("Error during recording stop: $e");
    }
  }

  Future<void> downloadFile(String filename) async {
    try {
      final uri = Uri.parse("http://192.168.0.157:5000/download/$filename");
      final response = await dio.Dio().get(
        uri.toString(),
        options: dio.Options(
          responseType: dio.ResponseType.bytes,
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final filePath = "${directory.path}/$filename";
      final file = File(filePath);
      await file.writeAsBytes(response.data);

      print("File downloaded successfully to $filePath");
    } catch (e) {
      print("Error downloading file: $e");
    }
  }


  Future<void> _pause() => _audioRecorder.pause();

  Future<void> _resume() => _audioRecorder.resume();

  void _updateRecordState(RecordState recordState) {
    setState(() => _recordState = recordState);

    switch (recordState) {
      case RecordState.pause:
        _timer?.cancel();
        break;
      case RecordState.record:
        _startTimer();
        break;
      case RecordState.stop:
        _timer?.cancel();
        _recordDuration = 0;
        break;
    }
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(
      encoder,
    );

    if (!isSupported) {
      debugPrint('${encoder.name} is not supported on this platform.');
      debugPrint('Supported encoders are:');

      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          debugPrint('- ${e.name}');
        }
      }
    }

    return isSupported;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildRecordStopControl(),
              const SizedBox(width: 20),
              _buildPauseResumeControl(),
              const SizedBox(width: 20),
              _buildText(),
            ],
          ),
          if (_amplitude != null) ...[
            const SizedBox(height: 40),
            Text('Current: ${_amplitude?.current ?? 0.0}'),
            Text('Max: ${_amplitude?.max ?? 0.0}'),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Widget _buildRecordStopControl() {
    late Icon icon;
    late Color color;

    if (_recordState != RecordState.stop) {
      icon = const Icon(Icons.stop, color: Colors.red, size: 30);
      color = Colors.red.withOpacity(0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.mic, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withOpacity(0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            (_recordState != RecordState.stop) ? _stopRecording() : _startRecording();
          },
        ),
      ),
    );
  }

  Widget _buildPauseResumeControl() {
    if (_recordState == RecordState.stop) {
      return const SizedBox.shrink();
    }

    late Icon icon;
    late Color color;

    if (_recordState == RecordState.record) {
      icon = const Icon(Icons.pause, color: Colors.red, size: 30);
      color = Colors.red.withOpacity(0.1);
    } else {
      final theme = Theme.of(context);
      icon = const Icon(Icons.play_arrow, color: Colors.red, size: 30);
      color = theme.primaryColor.withOpacity(0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            (_recordState == RecordState.pause) ? _resume() : _pause();
          },
        ),
      ),
    );
  }

  Widget _buildText() {
    if (_recordState != RecordState.stop) {
      return _buildTimer();
    }

    return const Text("Waiting to record");
  }

  Widget _buildTimer() {
    final String minutes = _formatNumber(_recordDuration ~/ 60);
    final String seconds = _formatNumber(_recordDuration % 60);

    return Text(
      '$minutes : $seconds',
      style: const TextStyle(color: Colors.red),
    );
  }

  String _formatNumber(int number) {
    String numberStr = number.toString();
    if (number < 10) {
      numberStr = '0$numberStr';
    }

    return numberStr;
  }

  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() => _recordDuration++);
    });
  }
}

class NotesDisplay extends StatelessWidget {
  final List<dynamic> notes;

  const NotesDisplay({Key? key, required this.notes}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = WebViewController(); // Declare controller first

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadFlutterAsset('assets/vexflow.html')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            print("WebView loaded, injecting notes...");

            // Transform notes to VexFlow compatible format (e.g., D2 -> d/2)
            final List<String> noteKeys = notes.map((note) {
              final noteName = note['note_name'] ?? 'c4'; // Fallback to "c4"
              return "${noteName.substring(0, 1).toLowerCase()}${noteName.substring(1).replaceAll('#', '#')}".replaceAllMapped(
                  RegExp(r'(\D)(\d+)'), (match) => "${match[1]}/${match[2]}");
            }).cast<String>().toList();

            final jsNotes = jsonEncode(noteKeys);
            print("Sending formatted notes: $jsNotes");

            // Call the renderNotes function in the HTML file
            await controller.runJavaScript("renderNotes($jsNotes);");
          },
        ),
      );

    return Scaffold(
      appBar: AppBar(title: const Text('Music Sheet Viewer')),
      body: WebViewWidget(controller: controller),
    );
  }
}


class NotesDisplayOld extends StatelessWidget {
  final List<dynamic> notes;

  const NotesDisplayOld({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detected Notes on Sheet')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Staff Display
          CustomPaint(
            size: Size(double.infinity, 200), // Fixed size for the staff
            painter: PianoStaffPainter(notes),
          ),
          // Notes List
          Expanded(
            child: ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return ListTile(
                  title: Text('Note: ${note['note_name']}'),
                  subtitle: Text('Time: ${note['time']}s, Frequency: ${note['frequency']}Hz'),
                  trailing: Text('Velocity: ${note['velocity']}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PianoStaffPainter extends CustomPainter {
  final List<dynamic> notes;

  PianoStaffPainter(this.notes);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint staffPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0;

    final double lineHeight = size.height / 7;
    final double noteRadius = 10;
    final double noteSpacing = 30;

    // Draw staff lines
    for (int i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(0, lineHeight * (i + 1)),
        Offset(size.width, lineHeight * (i + 1)),
        staffPaint,
      );
    }

    // Draw notes
    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      final String noteName = note['note_name'];
      final double x = noteSpacing * (i + 1); // Horizontal position
      final double y = mapNoteToYPosition(noteName, lineHeight, size.height);

      // Draw the note
      canvas.drawCircle(Offset(x, y), noteRadius, Paint()..color = Colors.blue);

      // Draw the note name
      final TextSpan span = TextSpan(
        text: noteName,
        style: const TextStyle(color: Colors.black, fontSize: 12),
      );
      final TextPainter textPainter = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - 10, y + 15));
    }
  }

  // Map note name to Y position on the staff
  double mapNoteToYPosition(String noteName, double lineHeight, double staffHeight) {
    const Map<String, double> noteOffsets = {
      'C4': 5.5, 'D4': 5.0, 'E4': 4.5, 'F4': 4.0, 'G4': 3.5,
      'A4': 3.0, 'B4': 2.5, 'C5': 2.0, 'D5': 1.5, 'E5': 1.0,
      'F5': 0.5, 'G5': 0.0, 'A5': -0.5, 'B5': -1.0, 'C6': -1.5,
    };

    final double offset = noteOffsets[noteName] ?? 3.0; // Default to middle of staff
    return staffHeight / 2 + offset * lineHeight / 2;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}


class PianoStaffPainterOld extends CustomPainter {
  final List<dynamic> notes;

  PianoStaffPainterOld(this.notes);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint staffPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;

    final double lineHeight = size.height / 7;
    final double noteRadius = 10;
    final double noteSpacing = 30;

    // Draw staff lines
    for (int i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(0, lineHeight * (i + 1)),
        Offset(size.width, lineHeight * (i + 1)),
        staffPaint,
      );
    }

    // Draw notes
    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      final String noteName = note['note_name'];
      final double x = noteSpacing * (i + 1); // Horizontal position
      final double y = mapNoteToYPosition(noteName, lineHeight, size.height);

      // Draw the note
      canvas.drawCircle(Offset(x, y), noteRadius, Paint()..color = Colors.blue);

      // Draw the note name
      final TextSpan span = TextSpan(
        text: noteName,
        style: const TextStyle(color: Colors.black, fontSize: 12),
      );
      final TextPainter textPainter = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - 10, y + 15));
    }
  }

  // Map note name to Y position on the staff
  double mapNoteToYPosition(String noteName, double lineHeight, double staffHeight) {
    const Map<String, double> noteOffsets = {
      'C2': 10, 'C#2': 9.75, 'D2': 9.5, 'D#2': 9.25, 'E2': 9, 'F2': 8.5, 'F#2': 8.25, 'G2': 8,
      'G#2': 7.75, 'A2': 7.5, 'A#2': 7.25, 'B2': 7,
      'C3': 6.5, 'C#3': 6.25, 'D3': 6, 'D#3': 5.75, 'E3': 5.5, 'F3': 5, 'F#3': 4.75, 'G3': 4.5,
      'G#3': 4.25, 'A3': 4, 'A#3': 3.75, 'B3': 3.5,
      'C4': 3, 'C#4': 2.75, 'D4': 2.5, 'D#4': 2.25, 'E4': 2, 'F4': 1.5, 'F#4': 1.25, 'G4': 1,
      'G#4': 0.75, 'A4': 0.5, 'A#4': 0.25, 'B4': 0,
      'C5': -0.5, 'C#5': -0.75, 'D5': -1, 'D#5': -1.25, 'E5': -1.5, 'F5': -2, 'F#5': -2.25, 'G5': -2.5,
      'G#5': -2.75, 'A5': -3, 'A#5': -3.25, 'B5': -3.5,
      'C6': -4, 'C#6': -4.25, 'D6': -4.5, 'D#6': -4.75, 'E6': -5, 'F6': -5.5, 'F#6': -5.75, 'G6': -6,
      'G#6': -6.25, 'A6': -6.5, 'A#6': -6.75, 'B6': -7,
    };

    // final String normalizedNote = noteName.contains('#')
    //     ? noteName.replaceAll('#', '')
    //     : noteName;

    final double offset = noteOffsets[noteName] ?? 6.5;
    return staffHeight / 2 + offset * lineHeight / 2;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}