import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'audio_recorder.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool showPlayer = false;
  String? audioPath;
  List<dynamic> notes = [];

  void navigateToNotesDisplay(List<dynamic> detectedNotes) {
    setState(() {
      notes = detectedNotes;
    });

    navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (context) => NotesDisplay(notes: notes),
      ),
    );
  }

  @override
  void initState() {
    showPlayer = false;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: Center(
          child: showPlayer
              ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Text('Audio Player Placeholder'),
          )
              : Recorder(
            onStop: (path) {
              if (kDebugMode) print('Recorded file path: $path');
              setState(() {
                audioPath = path;
                showPlayer = true;
              });
            },
            onNavigateToNotes: navigateToNotesDisplay,
          ),
        ),
      ),
    );
  }
}
