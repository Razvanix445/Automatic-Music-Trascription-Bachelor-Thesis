import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audioplayers/audioplayers.dart' as audio_players;
import 'dart:math' as math;

class MidiTestScreen extends StatefulWidget {
  final String midiFilePath;

  MidiTestScreen({required this.midiFilePath});

  @override
  _MidiTestScreenState createState() => _MidiTestScreenState();
}

class _MidiTestScreenState extends State<MidiTestScreen> {
  final AudioPlayer _justAudioPlayer = AudioPlayer();
  final audio_players.AudioPlayer _audioPlayersLib = audio_players.AudioPlayer();

  bool _justAudioPlaying = false;
  bool _audioPlayersPlaying = false;
  String _status = "Ready to test";
  String _fileInfo = "Checking file...";

  @override
  void initState() {
    super.initState();
    _checkFile();
  }

  Future<void> _checkFile() async {
    try {
      final file = File(widget.midiFilePath);
      if (await file.exists()) {
        final size = await file.length();
        final lastModified = await file.lastModified();

        setState(() {
          _fileInfo = "File exists: ${widget.midiFilePath}\n"
              "Size: ${size} bytes\n"
              "Last modified: ${lastModified}";
        });

        try {
          await _justAudioPlayer.setFilePath(widget.midiFilePath);
          await _justAudioPlayer.load();
          setState(() {
            _status += "\nJustAudio loaded the file successfully";
          });
        } catch (e) {
          setState(() {
            _status += "\nJustAudio failed to load: $e";
          });
        }

        try {
          await _audioPlayersLib.setSource(audio_players.DeviceFileSource(widget.midiFilePath));
          setState(() {
            _status += "\nAudioPlayers loaded the file successfully";
          });
        } catch (e) {
          setState(() {
            _status += "\nAudioPlayers failed to load: $e";
          });
        }
      } else {
        setState(() {
          _fileInfo = "File does not exist at path: ${widget.midiFilePath}";
        });
      }
    } catch (e) {
      setState(() {
        _fileInfo = "Error checking file: $e";
      });
    }
  }

  @override
  void dispose() {
    _justAudioPlayer.dispose();
    _audioPlayersLib.dispose();
    super.dispose();
  }

  Future<void> _playWithJustAudio() async {
    try {
      if (_justAudioPlaying) {
        await _justAudioPlayer.stop();
        setState(() {
          _justAudioPlaying = false;
          _status = "JustAudio: Stopped playback";
        });
      } else {
        await _justAudioPlayer.setVolume(1.0);
        await _justAudioPlayer.seek(Duration.zero);
        await _justAudioPlayer.play();
        setState(() {
          _justAudioPlaying = true;
          _status = "JustAudio: Attempted to play";
        });

        Future.delayed(Duration(seconds: 1), () {
          setState(() {
            _status = "JustAudio state: ${_justAudioPlayer.playing ? 'PLAYING' : 'NOT PLAYING'}, "
                "Volume: ${_justAudioPlayer.volume}";
          });
        });
      }
    } catch (e) {
      setState(() {
        _status = "JustAudio error: $e";
      });
    }
  }

  Future<void> _playWithAudioPlayers() async {
    try {
      if (_audioPlayersPlaying) {
        await _audioPlayersLib.stop();
        setState(() {
          _audioPlayersPlaying = false;
          _status = "AudioPlayers: Stopped playback";
        });
      } else {
        await _audioPlayersLib.setVolume(1.0);
        await _audioPlayersLib.seek(Duration.zero);
        await _audioPlayersLib.resume();
        setState(() {
          _audioPlayersPlaying = true;
          _status = "AudioPlayers: Attempted to play";
        });
      }
    } catch (e) {
      setState(() {
        _status = "AudioPlayers error: $e";
      });
    }
  }

  Future<void> _loadFileAsData() async {
    try {
      final file = File(widget.midiFilePath);
      final bytes = await file.openRead(0, 50).toList();
      final flatBytes = bytes.expand((e) => e).toList();

      String hexString = '';
      for (int i = 0; i < math.min(flatBytes.length, 50); i++) {
        hexString += flatBytes[i].toRadixString(16).padLeft(2, '0') + ' ';
      }

      setState(() {
        _status = "File header (first 50 bytes):\n$hexString";
      });

      bool isMidiSignature = false;
      if (flatBytes.length >= 4) {
        final signature = String.fromCharCodes(flatBytes.sublist(0, 4));
        isMidiSignature = signature == 'MThd';
      }

      setState(() {
        _status += "\nMIDI signature present: $isMidiSignature";
      });
    } catch (e) {
      setState(() {
        _status = "Error reading file data: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MIDI Playback Test'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MIDI File Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_fileInfo),
            ),
            SizedBox(height: 24),

            Text('Status',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_status),
            ),
            SizedBox(height: 24),

            Text('Test Players',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _playWithJustAudio,
              icon: Icon(_justAudioPlaying ? Icons.stop : Icons.play_arrow),
              label: Text(_justAudioPlaying ? 'Stop JustAudio' : 'Play with JustAudio'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                minimumSize: Size(double.infinity, 50),
              ),
            ),
            SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _playWithAudioPlayers,
              icon: Icon(_audioPlayersPlaying ? Icons.stop : Icons.play_arrow),
              label: Text(_audioPlayersPlaying ? 'Stop AudioPlayers' : 'Play with AudioPlayers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                minimumSize: Size(double.infinity, 50),
              ),
            ),
            SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _loadFileAsData,
              icon: Icon(Icons.search),
              label: Text('Analyze File Contents'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                minimumSize: Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}