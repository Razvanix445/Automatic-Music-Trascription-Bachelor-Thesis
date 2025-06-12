import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_projects/widgets/sheet_music_viewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/transcription_result.dart';
import '../services/api_service.dart';
import '../config/app_theme.dart';
import '../widgets/piano_roll_visualization.dart'; // Use your existing piano roll
import '../screens/midi_test_screen.dart';
import '../widgets/midi_player_button.dart'; // Import our simple button widget

class ResultScreen extends StatefulWidget {
  final TranscriptionResult result;

  ResultScreen({required this.result});

  @override
  _ResultScreenState createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final ApiService _apiService = ApiService(
    baseUrl: 'https://razvanix-wave2notes.hf.space',
  );

  bool _isDownloading = false;
  File? _midiFile;

  // Reference to the piano roll visualization
  // Using a generic key instead of a specific state type
  final GlobalKey<State<PianoRollVisualization>> _pianoRollKey = GlobalKey();

  // For time display in the button
  double _currentTime = 0.0;
  double _totalDuration = 0.0;

  @override
  void initState() {
    super.initState();
    _downloadMidiFile();
    _calculateTotalDuration();
  }

  void _calculateTotalDuration() {
    _totalDuration = 0;
    if (widget.result.notes.isNotEmpty) {
      for (var note in widget.result.notes) {
        double noteEndTime = note.time + note.duration;
        if (noteEndTime > _totalDuration) {
          _totalDuration = noteEndTime;
        }
      }
      // Add a little padding to the end
      _totalDuration += 2.0;
    }
  }

  Future<void> _downloadMidiFile() async {
    setState(() => _isDownloading = true);

    try {
      final midiFilename = widget.result.midiFileUrl.split('/').last;
      print("⬇️ Attempting to download MIDI file from URL: ${widget.result.midiFileUrl}");

      final file = await _apiService.downloadMidiFile(
        widget.result.midiFileUrl,
        midiFilename,
      );

      setState(() {
        _midiFile = file;
        _isDownloading = false;
      });

      if (file != null) {
        // Print basic file info for debugging
        try {
          final size = await file.length();
          print("✅ MIDI file downloaded: ${file.path} (${size} bytes)");
        } catch (e) {
          print("⚠️ Error getting file info: $e");
        }
      } else {
        print("❌ MIDI file download returned null");
      }

    } catch (e) {
      print("❌ Error downloading MIDI file: $e");
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _shareMidiFile() async {
    if (_midiFile == null) return;

    try {
      await Share.shareXFiles(
        [XFile(_midiFile!.path)],
        text: 'My piano transcription MIDI file',
      );
    } catch (e) {
      print('Error sharing MIDI file: $e');
    }
  }

  // Called by the piano roll to update the time display
  void _updateCurrentTime(double time) {
    setState(() {
      _currentTime = time;
    });
  }

  // Button callback handlers - access methods through the widget
  void _handlePlay() {
    // Get the current widget from the key
    final pianoRollWidget = _pianoRollKey.currentWidget as PianoRollVisualization?;
    final pianoRollState = _pianoRollKey.currentState;

    // Use a safer way to access the method
    if (pianoRollState != null) {
      // Call a method that would be available on the public API
      (pianoRollState as dynamic).startPlayback();
    }
  }

  void _handlePause() {
    // Cast to dynamic to access the method
    final pianoRollState = _pianoRollKey.currentState;
    if (pianoRollState != null) {
      (pianoRollState as dynamic).stopPlayback();
    }
  }

  void _handleReset() {
    // Cast to dynamic to access the method
    final pianoRollState = _pianoRollKey.currentState;
    if (pianoRollState != null) {
      (pianoRollState as dynamic).resetPlayback();
    }

    setState(() {
      _currentTime = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Transcription Results',
            style: TextStyle(color: AppTheme.textColor),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: AppTheme.textColor),
          actions: [
            // if (widget.result.musescoreAvailable)
            //   Padding(
            //     padding: EdgeInsets.only(right: 8),
            //     child: Chip(
            //       label: Text(
            //         'Sheet Music',
            //         style: TextStyle(fontSize: 10, color: Colors.white),
            //       ),
            //       backgroundColor: Colors.green,
            //       materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            //     ),
            //   ),
            if (_midiFile != null)
              IconButton(
                icon: Icon(Icons.share, color: AppTheme.textColor),
                onPressed: _shareMidiFile,
              ),
            // if (_midiFile != null)
            //   IconButton(
            //     icon: Icon(Icons.music_note, color: AppTheme.textColor),
            //     onPressed: () {
            //       Navigator.push(
            //         context,
            //         MaterialPageRoute(
            //           builder: (context) => MidiTestScreen(midiFilePath: _midiFile!.path),
            //         ),
            //       );
            //     },
            //     tooltip: 'Test MIDI Playback',
            //   ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(icon: Icon(Icons.piano, color: AppTheme.textColor),
                  text: "Visualization"),
              Tab(icon: Icon(Icons.picture_as_pdf, color: AppTheme.textColor),
                  text: "Sheet Music"),
            ],
            labelColor: AppTheme.textColor,
            indicatorColor: AppTheme.primaryColor,
          ),
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
          child: TabBarView(
            children: [
              // Piano Roll Visualization Tab
              Column(
                children: [
                  // Add our simple MIDI player button if file is available
                  if (_midiFile != null)
                    MidiPlayerButton(
                      midiFilePath: _midiFile!.path,
                      onPlay: _handlePlay,
                      onPause: _handlePause,
                      onReset: _handleReset,
                      currentTime: _currentTime,
                      totalDuration: _totalDuration,
                    ),

                  // Use the existing PianoRollVisualization but with a key
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: PianoRollVisualization(
                          key: _pianoRollKey,
                          notes: widget.result.notes,
                          duration: _totalDuration,
                          midiFilePath: _midiFile?.path,
                          onTimeUpdate: _updateCurrentTime,
                        ),
                      ),
                    ),
                  ),
                  _buildMidiSection(),
                ],
              ),

              // Sheet Music Viewer Tab
              SheetMusicViewer(
                sheetMusic: widget.result.sheetMusic,
                title: 'Piano Transcription',
                apiService: _apiService,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesList() {
    if (widget.result.notes.isEmpty) {
      return Center(
        child: Text(
          'No notes detected. Try again with a different recording.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textColor),
        ),
      );
    }

    return ListView.builder(
      itemCount: widget.result.notes.length,
      itemBuilder: (context, index) {
        final note = widget.result.notes[index];
        return Card(
          elevation: 2,
          margin: EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getNoteColor(note.pitch),
              child: Text(
                note.noteName[0],
                style: TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              note.noteName,
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textColor),
            ),
            subtitle: Text(
              'Time: ${note.time.toStringAsFixed(2)}s, Duration: ${note.duration.toStringAsFixed(2)}s',
              style: TextStyle(color: AppTheme.textColor.withOpacity(0.7)),
            ),
            trailing: Text(
              'Velocity: ${(note.velocity * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _getVelocityColor(note.velocity),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMidiSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.music_note,
              size: 32,
              color: AppTheme.primaryColor,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MIDI File',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.textColor,
                  ),
                ),
                Text(
                  _isDownloading
                      ? 'Downloading...'
                      : _midiFile != null
                      ? 'Downloaded: ${_midiFile!.path}'
                      : 'Could not load',
                  style: TextStyle(color: AppTheme.textColor.withOpacity(0.7)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_isDownloading)
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            )
          else if (_midiFile != null)
            Icon(Icons.check_circle, color: Colors.green)
          else
            ElevatedButton(
              onPressed: _downloadMidiFile,
              child: Text('Try again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Color _getNoteColor(int pitch) {
    final List<Color> colors = [
      AppTheme.primaryColor,
      AppTheme.accentColor,
      Color(0xFF5E8B7E),
      Color(0xFF7EB5A6),
      Color(0xFFA7D7C5),
      Color(0xFF74B49B),
      Color(0xFF5C8D89),
      Color(0xFF3A6351),
      Color(0xFF344E41),
      Color(0xFF3A5A40),
      Color(0xFF588157),
      Color(0xFF2D6A4F),
    ];

    return colors[pitch % colors.length];
  }

  Color _getVelocityColor(double velocity) {
    if (velocity < 0.3) return Color(0xFF74B49B);
    if (velocity < 0.6) return Color(0xFF5E8B7E);
    if (velocity < 0.8) return Color(0xFF3A6351);
    return AppTheme.accentColor;
  }
}