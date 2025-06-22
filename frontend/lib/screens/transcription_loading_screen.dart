import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/aws_service.dart';
import 'result_screen.dart';
import '../config/app_theme.dart';

class TranscriptionLoadingScreen extends StatefulWidget {
  final Map<String, dynamic> recordingData;
  final String title;
  final ApiService apiService;
  final AwsService awsService;

  const TranscriptionLoadingScreen({
    Key? key,
    required this.recordingData,
    required this.title,
    required this.apiService,
    required this.awsService,
  }) : super(key: key);

  @override
  _TranscriptionLoadingScreenState createState() => _TranscriptionLoadingScreenState();
}

class _TranscriptionLoadingScreenState extends State<TranscriptionLoadingScreen> {
  String _status = 'Loading transcription...';
  int _processingSeconds = 0;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startTranscriptionLoading();
  }

  Future<void> _startTranscriptionLoading() async {
    // Start the status timer
    final statusTimer = Stream.periodic(Duration(seconds: 1), (i) => i).listen((seconds) {
      setState(() {
        _processingSeconds = seconds;
        if (seconds < 3) {
          _status = 'Loading transcription data...';
        } else if (seconds < 8) {
          _status = 'Preparing visualization...';
        } else if (seconds < 15) {
          _status = 'Processing notes...';
        } else if (seconds < 30) {
          _status = 'Nearly finished...';
        } else {
          _status = 'Loading (taking longer than usual)...';
        }
      });
    });

    try {
      // Check if transcription data is available
      final hasMidi = widget.awsService.hasFileType(widget.recordingData, 'midi');
      final hasPdf = widget.awsService.hasFileType(widget.recordingData, 'pdf');
      
      if (!hasMidi && !hasPdf) {
        throw Exception('No transcription data available');
      }

      // Get recording information
      final recordingId = widget.recordingData['recording_id'] ?? 
                         widget.recordingData['metadata']?['recording_id'] ??
                         widget.recordingData['id'];
      
      final userId = widget.recordingData['metadata']?['user_id'] ?? 
                    widget.recordingData['metadata']?['userId'] ??
                    widget.recordingData['user_id'] ??
                    widget.recordingData['userId'];
      
      if (recordingId == null || userId == null) {
        throw Exception('Recording information incomplete');
      }

      // Load the transcription
      final result = await widget.apiService.transcribeExistingRecording(
        userId: userId,
        recordingId: recordingId,
        title: widget.title,
      );

      statusTimer.cancel();

      if (result != null) {
        // Navigate to ResultScreen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ResultScreen(result: result),
          ),
        );
      } else {
        throw Exception('Could not load transcription data');
      }

    } catch (e) {
      statusTimer.cancel();
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _status = 'Error loading transcription';
      });
      print('❌ Transcription loading error: $e');
    }
  }

  void _goBack() {
    Navigator.of(context).pop();
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _status = 'Loading transcription...';
      _processingSeconds = 0;
    });
    _startTranscriptionLoading();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Loading Transcription',
          style: TextStyle(color: AppTheme.textColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.textColor),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: _goBack,
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
                if (_hasError)
                  Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      SizedBox(height: 20),
                      Text(
                        _errorMessage ?? 'An error occurred',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: Icon(Icons.refresh),
                            label: Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _retry,
                          ),
                          SizedBox(width: 16),
                          OutlinedButton.icon(
                            icon: Icon(Icons.arrow_back),
                            label: Text('Go Back'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textColor,
                              side: BorderSide(color: AppTheme.textColor),
                              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _goBack,
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Please wait while we load your transcription.\nThis usually takes a few seconds.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textColor),
                      ),
                      if (_processingSeconds > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            '${_processingSeconds}s',
                            style: TextStyle(
                              color: AppTheme.textColor.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
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