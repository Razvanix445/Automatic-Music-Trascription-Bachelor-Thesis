import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_projects/screens/transcription_loading_screen.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../services/aws_service.dart';
import '../services/api_service.dart';
import '../services/platform_service.dart';
import '../services/platform_audio_service.dart';
import '../models/transcription_result.dart';
import 'result_screen.dart';

typedef PlayerState = CrossPlatformPlayerState;

class RecordingPlayerScreen extends StatefulWidget {
  final String recordingUrl;
  final Map<String, dynamic> recordingData;

  RecordingPlayerScreen({
    required this.recordingUrl,
    required this.recordingData,
  });

  @override
  _RecordingPlayerScreenState createState() => _RecordingPlayerScreenState();
}

class _RecordingPlayerScreenState extends State<RecordingPlayerScreen>
    with TickerProviderStateMixin {
  final AwsService _awsService = AwsService();
  final ApiService _apiService = ApiService(
    baseUrl: 'https://razvanix-wave2notes.hf.space',
  );

  // Replace AudioPlayer with PlatformAudioService
  final PlatformAudioService _audioService = PlatformAudioService();
  
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isEditing = false;
  bool _isGeneratingTranscription = false;
  bool _isSavingChanges = false;
  bool _audioInitialized = false;
  
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  File? _newImageFile;
  String? _newImagePath;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
    _setupAudioPlayer();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();
  }

  void _initializeData() {
    final metadata = widget.recordingData['metadata'] ?? {};
    _titleController.text = widget.recordingData['title'] ?? metadata['title'] ?? 'Untitled Recording';
    _descriptionController.text = widget.recordingData['description'] ?? metadata['description'] ?? '';
  }

  void _setupAudioPlayer() async {
    try {
      print('🎵 Setting up cross-platform audio for: ${widget.recordingUrl}');
      
      // Initialize the platform audio service
      final success = await _audioService.initialize(widget.recordingUrl);
      
      if (success) {
        // Listen to duration changes
        _audioService.onDurationChanged.listen((duration) {
          if (mounted) {
            setState(() => _duration = duration);
          }
        });

        // Listen to position changes
        _audioService.onPositionChanged.listen((position) {
          if (mounted) {
            setState(() => _position = position);
          }
        });

        // Listen to player state changes
        _audioService.onPlayerStateChanged.listen((state) {
          if (mounted) {
            setState(() {
              _isPlaying = state == PlayerState.playing;
              if (state == PlayerState.completed) {
                _position = Duration.zero;
              }
            });
          }
        });
        
        setState(() => _audioInitialized = true);
        print('✅ Cross-platform audio setup complete');
      } else {
        print('❌ Failed to initialize audio player');
        _showPlatformAwareMessage(
          'Failed to load audio. This may be due to browser security restrictions.',
          isError: true
        );
      }
    } catch (e) {
      print('Error setting up audio player: $e');
      _showPlatformAwareMessage(
        'Audio setup error: $e',
        isError: true
      );
    }
  }

  @override
  void dispose() {
    _audioService.dispose();
    _audioService.closeStreams();
    _titleController.dispose();
    _descriptionController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (!_audioInitialized) {
      _showPlatformAwareMessage('Audio not ready. Please wait for initialization.', isError: true);
      return;
    }

    try {
      if (_isPlaying) {
        await _audioService.pause();
      } else {
        await _audioService.play();
      }
    } catch (e) {
      print('Error toggling playback: $e');
      _showPlatformAwareMessage('Playback error: $e', isError: true);
    }
  }

  Future<void> _seekTo(double value) async {
    if (!_audioInitialized) return;
    
    final position = Duration(milliseconds: (value * _duration.inMilliseconds).round());
    await _audioService.seek(position);
  }

  Future<void> _pickNewImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        if (PlatformService.isWeb) {
          // On web, we get bytes instead of a file path
          setState(() {
            _newImagePath = result.files.first.name; // Just the name for display
            // Note: For web, you'd need to handle bytes differently
            // This is a simplified version
          });
        } else {
          // On mobile, we get a real file path
          setState(() {
            _newImageFile = File(result.files.first.path!);
            _newImagePath = result.files.first.path!;
          });
        }
      }
    } catch (e) {
      _showPlatformAwareMessage('Error selecting image: $e', isError: true);
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingChanges = true);

    try {
      print('🔍 Save changes - Recording data structure:');
      print('📋 Keys: ${widget.recordingData.keys.toList()}');
      
      final recordingId = widget.recordingData['recording_id'] ?? 
                         widget.recordingData['metadata']?['recording_id'] ??
                         widget.recordingData['id'];
      
      print('🆔 Found recording ID for update: $recordingId');
      
      if (recordingId == null) {
        throw Exception('Recording ID not found - cannot update');
      }

      final result = await _awsService.updateRecordingMetadata(
        recordingId: recordingId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        newImageFile: _newImageFile,
      );

      setState(() => _isSavingChanges = false);
      _showPlatformAwareMessage('Recording updated successfully!');
      setState(() {
        _isEditing = false;
        _newImageFile = null;
        _newImagePath = null;
      });

      widget.recordingData['title'] = _titleController.text.trim();
      widget.recordingData['description'] = _descriptionController.text.trim();
      if (widget.recordingData['metadata'] != null) {
        widget.recordingData['metadata']['title'] = _titleController.text.trim();
        widget.recordingData['metadata']['description'] = _descriptionController.text.trim();
      }

    } catch (e) {
      setState(() => _isSavingChanges = false);
      _showPlatformAwareMessage('Error saving changes: $e', isError: true);
      
      print('❌ Save changes error details: $e');
      print('📋 Available recording data keys: ${widget.recordingData.keys.toList()}');
    }
  }

  Future<void> _generateTranscription({bool forceRegenerate = false}) async {
    setState(() => _isGeneratingTranscription = true);

    try {
      _showPlatformAwareMessage('Preparing transcription...');
      
      print('🔍 Recording data structure:');
      print('📋 Keys: ${widget.recordingData.keys.toList()}');
      print('📋 Full data: ${widget.recordingData}');
      
      final recordingId = widget.recordingData['recording_id'] ?? 
                         widget.recordingData['metadata']?['recording_id'] ??
                         widget.recordingData['id'];
      
      final userId = widget.recordingData['metadata']?['user_id'] ?? 
                    widget.recordingData['metadata']?['userId'] ??
                    widget.recordingData['user_id'] ??
                    widget.recordingData['userId'];
      
      print('🆔 Found recording ID: $recordingId');
      print('👤 Found user ID: $userId');
      
      if (recordingId == null) {
        throw Exception('Recording ID not found in recording data');
      }
      
      if (userId == null) {
        throw Exception('User ID not found in recording data');
      }

      if (!forceRegenerate) {
        final hasMidi = _awsService.hasFileType(widget.recordingData, 'midi');
        final hasPdf = _awsService.hasFileType(widget.recordingData, 'pdf');
        
        if (hasMidi && hasPdf) {
          setState(() => _isGeneratingTranscription = false);
          _showPlatformAwareMessage('Files already exist. Use "View Transcription" to see them.');
          return;
        }
      }

      _showPlatformAwareMessage('Generating AI transcription...');

      final result = await _apiService.transcribeExistingRecording(
        userId: userId,
        recordingId: recordingId,
        title: _titleController.text.trim(),
      );

      setState(() => _isGeneratingTranscription = false);

      if (result != null) {
        _showPlatformAwareMessage('Transcription generated successfully!');
        
        await _refreshRecordingDataSimple(userId, recordingId);
        
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ResultScreen(result: result),
          ),
        );
      } else {
        _showPlatformAwareMessage('Failed to generate transcription', isError: true);
      }

    } catch (e) {
      setState(() => _isGeneratingTranscription = false);
      _showPlatformAwareMessage('Error generating transcription: $e', isError: true);
      
      print('❌ Transcription error details: $e');
      print('📋 Available recording data keys: ${widget.recordingData.keys.toList()}');
      if (widget.recordingData['metadata'] != null) {
        print('📋 Available metadata keys: ${widget.recordingData['metadata'].keys.toList()}');
      }
    }
  }

  Future<void> _refreshRecordingDataSimple(String userId, String recordingId) async {
    try {
      print('🔄 Refreshing recording data to show new files...');
      
      final recordings = await _awsService.getUserRecordings();
      
      final updatedRecording = recordings.firstWhere(
        (r) => r['recording_id'] == recordingId,
        orElse: () => {},
      );
      
      if (updatedRecording.isNotEmpty) {
        widget.recordingData.clear();
        widget.recordingData.addAll(updatedRecording);
        
        setState(() {});
        
        print('✅ Recording data refreshed - new files should now be visible');
      }
    } catch (e) {
      print('⚠️ Could not refresh recording data: $e');
    }
  }

  // Platform-aware message showing
  void _showPlatformAwareMessage(String message, {bool isError = false}) {
    String platformNote = '';
    
    if (PlatformService.isWeb) {
      if (message.contains('download') || message.contains('file')) {
        platformNote = '\n\nOn web: Files are downloaded to your browser\'s download folder.';
      }
      if (isError && (message.contains('audio') || message.contains('CORS'))) {
        platformNote = '\n\nWeb browsers may block audio from external sources due to security restrictions.';
      }
    } else {
      if (message.contains('download') || message.contains('file')) {
        platformNote = '\n\nOn mobile: Files are saved to app storage.';
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message + platformNote),
        backgroundColor: isError ? AppTheme.errorColor : 
                        message.contains('success') ? Colors.green : AppTheme.primaryColor,
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  Future<void> _openFile(String url, String type) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showPlatformAwareMessage('Could not open $type file', isError: true);
      }
    } catch (e) {
      _showPlatformAwareMessage('Error opening $type file: $e', isError: true);
    }
  }

  // Updated download function using new cross-platform approach
  Future<void> _downloadFile(String url, String fileName) async {
    try {
      _showPlatformAwareMessage('Downloading $fileName...');
      
      String cleanFileName = fileName.replaceAll(RegExp(r'[^\w\s-.]'), '').trim();
      if (!cleanFileName.contains('.')) {
        if (fileName.toLowerCase().contains('pdf')) {
          cleanFileName += '.pdf';
        } else if (fileName.toLowerCase().contains('midi')) {
          cleanFileName += '.mid';
        } else if (fileName.toLowerCase().contains('image')) {
          cleanFileName += '.jpg';
        }
      }
      
      // Use the new cross-platform download method
      final platformFile = await _apiService.downloadFile(url, cleanFileName);
      
      if (platformFile != null) {
        if (platformFile.isWebDownload) {
          // Web download - show browser download message
          _showPlatformAwareMessage(platformFile.downloadMessage!);
        } else {
          // Mobile download - file saved to device
          _showPlatformAwareMessage('$fileName downloaded successfully!');
        }
      } else {
        _showPlatformAwareMessage('Failed to download $fileName', isError: true);
      }
    } catch (e) {
      _showPlatformAwareMessage('Error downloading $fileName: $e', isError: true);
    }
  }

  // Updated MIDI playback for cross-platform compatibility
  Future<void> _playMidiFile() async {
    try {
      final midiUrl = _awsService.getFileUrl(widget.recordingData, 'midi');
      if (midiUrl.isEmpty) {
        _showPlatformAwareMessage('MIDI file not available', isError: true);
        return;
      }

      _showPlatformAwareMessage('Loading MIDI file...');
      
      if (PlatformService.isWeb) {
        // On web, try to stream MIDI directly (if CORS allows)
        try {
          await _audioService.dispose(); // Stop current audio
          final success = await _audioService.initialize(midiUrl);
          if (success) {
            await _audioService.play();
            _showPlatformAwareMessage('Playing MIDI file...');
          } else {
            _showPlatformAwareMessage(
              'Cannot play MIDI directly on web due to browser restrictions. Try downloading the file.',
              isError: true
            );
          }
        } catch (e) {
          _showPlatformAwareMessage(
            'MIDI playback not supported on web. Download the file to play it locally.',
            isError: true
          );
        }
      } else {
        // On mobile, download and play the MIDI file
        final midiFile = await _apiService.downloadMidiFile(midiUrl, 'temp_playback.mid');
        
        if (midiFile != null && !midiFile.isWebDownload) {
          try {
            await _audioService.dispose(); // Stop current audio
            final success = await _audioService.initialize('file://${midiFile.path}');
            if (success) {
              await _audioService.play();
              _showPlatformAwareMessage('Playing MIDI file...');
            } else {
              _showPlatformAwareMessage('Could not play MIDI file', isError: true);
            }
          } catch (e) {
            _showPlatformAwareMessage('Error playing MIDI: $e', isError: true);
          }
        } else {
          _showPlatformAwareMessage('Could not load MIDI file', isError: true);
        }
      }
    } catch (e) {
      _showPlatformAwareMessage('Error with MIDI playback: $e', isError: true);
    }
  }

  Future<void> _showTranscriptionVisualization() async {
    try {
      final hasMidi = _awsService.hasFileType(widget.recordingData, 'midi');
      final hasPdf = _awsService.hasFileType(widget.recordingData, 'pdf');
      
      if (!hasMidi && !hasPdf) {
        _showPlatformAwareMessage('No transcription data available', isError: true);
        return;
      }

      // Navigate to the loading screen instead of loading here
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TranscriptionLoadingScreen(
            recordingData: widget.recordingData,
            title: _titleController.text.trim(),
            apiService: _apiService,
            awsService: _awsService,
          ),
        ),
      );

    } catch (e) {
      _showPlatformAwareMessage('Error: $e', isError: true);
      print('❌ Error navigating to transcription: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildAudioPlayer(),
                        SizedBox(height: 24),
                        _buildRecordingDetails(),
                        SizedBox(height: 24),
                        _buildAvailableFiles(),
                        SizedBox(height: 24),
                        _buildAIActions(),
                        SizedBox(height: 100), // Space for FAB
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final hasImage = _awsService.hasFileType(widget.recordingData, 'image');
    final imageUrl = hasImage ? _awsService.getFileUrl(widget.recordingData, 'image') : null;

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: AppTheme.primaryColor,
      iconTheme: IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null || _newImagePath != null)
              Image.network(
                _newImagePath ?? imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildDefaultBackground(),
              )
            else
              _buildDefaultBackground(),
            
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleController.text,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  if (_descriptionController.text.isNotEmpty)
                    Text(
                      _descriptionController.text,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(_isEditing ? Icons.close : Icons.edit, color: Colors.white),
          onPressed: () => setState(() => _isEditing = !_isEditing),
        ),
      ],
    );
  }

  Widget _buildDefaultBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.accentColor,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 100,
          color: Colors.white.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildAudioPlayer() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.grey[50]!],
          ),
        ),
        child: Column(
          children: [
            // Platform indicator
            if (PlatformService.isWeb)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.web, size: 14, color: AppTheme.primaryColor),
                    SizedBox(width: 6),
                    Text(
                      'Web Audio Player',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: _duration.inMilliseconds > 0 
                    ? _position.inMilliseconds / _duration.inMilliseconds 
                    : 0.0,
                onChanged: _audioInitialized ? _seekTo : null,
                activeColor: AppTheme.primaryColor,
                inactiveColor: Colors.grey[300],
              ),
            ),
            
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 16),
            
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: _audioInitialized ? _togglePlayPause : null,
                backgroundColor: _audioInitialized ? AppTheme.primaryColor : Colors.grey,
                child: _audioInitialized
                    ? Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      )
                    : SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                heroTag: "audio_player",
              ),
            ),
            
            if (!_audioInitialized)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Initializing audio...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingDetails() {
    if (!_isEditing) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Recording Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              
              _buildDetailRow('Title', _titleController.text),
              if (_descriptionController.text.isNotEmpty) ...[
                SizedBox(height: 12),
                _buildDetailRow('Description', _descriptionController.text),
              ],
              
              SizedBox(height: 12),
              _buildDetailRow('Upload Date', _getFormattedDate()),
              
              SizedBox(height: 12),
              _buildDetailRow('Platform', PlatformService.isWeb ? 'Web Browser' : 'Mobile App'),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.edit, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Edit Recording',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),

              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.music_note),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) => value?.trim().isEmpty ?? true ? 'Title is required' : null,
              ),
              
              SizedBox(height: 16),
              
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              
              SizedBox(height: 20),
              
              _buildImageSelection(),
              
              SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _isEditing = false),
                      child: Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSavingChanges ? null : _saveChanges,
                      child: _isSavingChanges 
                          ? SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('Save Changes'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSelection() {
    final hasImage = _awsService.hasFileType(widget.recordingData, 'image');
    final currentImageUrl = hasImage ? _awsService.getFileUrl(widget.recordingData, 'image') : null;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: _pickNewImage,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
                ),
                child: _newImagePath != null
                    ? (PlatformService.isWeb
                        ? Container(
                            child: Icon(Icons.image, color: Colors.grey[400], size: 30),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.green.withOpacity(0.1),
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(_newImagePath!), fit: BoxFit.cover),
                          ))
                    : currentImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(currentImageUrl, fit: BoxFit.cover),
                          )
                        : Icon(Icons.image, color: Colors.grey[400], size: 30),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cover Image',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _newImagePath != null
                          ? 'New image selected'
                          : hasImage 
                              ? 'Tap to change image'
                              : 'Tap to add cover image',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit, color: AppTheme.primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: AppTheme.textColor),
          ),
        ),
      ],
    );
  }

  Widget _buildAvailableFiles() {
    final hasImage = _awsService.hasFileType(widget.recordingData, 'image');
    final hasPdf = _awsService.hasFileType(widget.recordingData, 'pdf');
    final hasMidi = _awsService.hasFileType(widget.recordingData, 'midi');

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Text(
                  'Available Files',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                ),
                Spacer(),
                if (hasMidi || hasPdf)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'AI Generated',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: 16),
            
            if (!hasImage && !hasPdf && !hasMidi)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[400], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No additional files yet. Generate AI transcription to create MIDI and PDF files.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (hasImage) _buildEnhancedFileChip(
                        'Cover Image',
                        Icons.image,
                        AppTheme.accentColor,
                        () => _openFile(_awsService.getFileUrl(widget.recordingData, 'image'), 'image'),
                        canDownload: true,
                        downloadUrl: _awsService.getFileUrl(widget.recordingData, 'image'),
                      ),
                      if (hasPdf) _buildEnhancedFileChip(
                        'Sheet Music (PDF)',
                        Icons.picture_as_pdf,
                        Colors.red,
                        () => _openFile(_awsService.getFileUrl(widget.recordingData, 'pdf'), 'PDF'),
                        canDownload: true,
                        downloadUrl: _awsService.getFileUrl(widget.recordingData, 'pdf'),
                      ),
                      if (hasMidi) _buildEnhancedFileChip(
                        'MIDI File',
                        Icons.piano,
                        Colors.purple,
                        () => _playMidiFile(),
                        canDownload: true,
                        downloadUrl: _awsService.getFileUrl(widget.recordingData, 'midi'),
                        isPlayable: true,
                      ),
                    ],
                  ),
                  
                  if (hasMidi) ...[
                    SizedBox(height: 16),
                    _buildMidiPlayerSection(),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedFileChip(
    String label, 
    IconData icon, 
    Color color, 
    VoidCallback onTap, 
    {
      bool canDownload = false,
      String? downloadUrl,
      bool isPlayable = false,
    }
  ) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: color),
                  SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if (isPlayable) ...[
                    SizedBox(width: 8),
                    Icon(Icons.play_arrow, size: 16, color: color),
                  ],
                ],
              ),
            ),
          ),
          
          if (canDownload && downloadUrl != null)
            Container(
              width: double.infinity,
              height: 1,
              color: color.withOpacity(0.2),
            ),
          if (canDownload && downloadUrl != null)
            InkWell(
              onTap: () => _downloadFile(downloadUrl, label),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download, size: 14, color: color.withOpacity(0.7)),
                    SizedBox(width: 4),
                    Text(
                      PlatformService.isWeb ? 'Download' : 'Save',
                      style: TextStyle(
                        color: color.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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

  Widget _buildMidiPlayerSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.piano, color: Colors.purple, size: 20),
              SizedBox(width: 8),
              Text(
                'MIDI Playback',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                  fontSize: 14,
                ),
              ),
              Spacer(),
              Text(
                'Generated by AI',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.purple.withOpacity(0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          
          if (PlatformService.isWeb)
            Container(
              padding: EdgeInsets.all(8),
              margin: EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'MIDI playback may be limited on web browsers',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _playMidiFile,
                icon: Icon(Icons.play_arrow, size: 18),
                label: Text('Play MIDI'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _showTranscriptionVisualization(),
                icon: Icon(Icons.visibility, size: 18),
                label: Text('View Notes'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purple,
                  side: BorderSide(color: Colors.purple),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAIActions() {
    final hasImage = _awsService.hasFileType(widget.recordingData, 'image');
    final hasPdf = _awsService.hasFileType(widget.recordingData, 'pdf');
    final hasMidi = _awsService.hasFileType(widget.recordingData, 'midi');
    final hasTranscription = hasMidi || hasPdf;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Text(
                  'AI Transcription',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                ),
                Spacer(),
                if (hasTranscription)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'Generated',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: 12),
            
            Text(
              hasTranscription 
                ? 'AI transcription complete! MIDI and sheet music files are ready.'
                : 'Generate MIDI file and sheet music using artificial intelligence',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isGeneratingTranscription ? null : () {
                      if (hasTranscription) {
                        _showTranscriptionVisualization();
                      } else {
                        _generateTranscription();
                      }
                    },
                    icon: _isGeneratingTranscription 
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(hasTranscription ? Icons.visibility : Icons.auto_awesome),
                    label: Text(_isGeneratingTranscription 
                        ? 'Generating...' 
                        : hasTranscription 
                            ? 'View Transcription'
                            : 'Generate AI Transcription'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasTranscription ? Colors.green : AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                
                if (hasTranscription) ...[
                  SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: _isGeneratingTranscription ? null : () {
                        _showRegenerateDialog();
                      },
                      icon: Icon(Icons.refresh, size: 18),
                      label: Text('Regenerate'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accentColor,
                        side: BorderSide(color: AppTheme.accentColor),
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRegenerateDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Regenerate Transcription'),
          content: Text(
            'This will replace the existing MIDI and PDF files with new ones. This action cannot be undone. Continue?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _generateTranscription(forceRegenerate: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
              ),
              child: Text('Regenerate'),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _getFormattedDate() {
    final uploadDateStr = widget.recordingData['upload_date'] ?? 
                         widget.recordingData['metadata']?['upload_date'];
    if (uploadDateStr != null) {
      try {
        final date = DateTime.parse(uploadDateStr);
        return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        return 'Unknown date';
      }
    }
    return 'Unknown date';
  }
}

// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:audioplayers/audioplayers.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter_projects/screens/transcription_loading_screen.dart';
// import 'package:path/path.dart' as path;
// import 'package:url_launcher/url_launcher.dart';
// import '../config/app_theme.dart';
// import '../services/aws_service.dart';
// import '../services/api_service.dart';
// import '../models/transcription_result.dart';
// import 'result_screen.dart';

// class RecordingPlayerScreen extends StatefulWidget {
//   final String recordingUrl;
//   final Map<String, dynamic> recordingData;

//   RecordingPlayerScreen({
//     required this.recordingUrl,
//     required this.recordingData,
//   });

//   @override
//   _RecordingPlayerScreenState createState() => _RecordingPlayerScreenState();
// }

// class _RecordingPlayerScreenState extends State<RecordingPlayerScreen>
//     with TickerProviderStateMixin {
//   final AwsService _awsService = AwsService();
//   final ApiService _apiService = ApiService(
//     baseUrl: 'https://razvanix-wave2notes.hf.space',
//   );

//   final AudioPlayer _audioPlayer = AudioPlayer();
  
//   final _titleController = TextEditingController();
//   final _descriptionController = TextEditingController();
//   final _formKey = GlobalKey<FormState>();

//   bool _isPlaying = false;
//   bool _isLoading = false;
//   bool _isEditing = false;
//   bool _isGeneratingTranscription = false;
//   bool _isSavingChanges = false;
  
//   Duration _duration = Duration.zero;
//   Duration _position = Duration.zero;

//   late AnimationController _fadeController;
//   late AnimationController _slideController;
//   late Animation<double> _fadeAnimation;
//   late Animation<Offset> _slideAnimation;

//   File? _newImageFile;
//   String? _newImagePath;

//   @override
//   void initState() {
//     super.initState();
//     _setupAnimations();
//     _initializeData();
//     _setupAudioPlayer();
//   }

//   void _setupAnimations() {
//     _fadeController = AnimationController(
//       duration: Duration(milliseconds: 600),
//       vsync: this,
//     );
//     _slideController = AnimationController(
//       duration: Duration(milliseconds: 500),
//       vsync: this,
//     );
    
//     _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
//         .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
//     _slideAnimation = Tween<Offset>(begin: Offset(0, 0.1), end: Offset.zero)
//         .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

//     _fadeController.forward();
//     _slideController.forward();
//   }

//   void _initializeData() {
//     final metadata = widget.recordingData['metadata'] ?? {};
//     _titleController.text = widget.recordingData['title'] ?? metadata['title'] ?? 'Untitled Recording';
//     _descriptionController.text = widget.recordingData['description'] ?? metadata['description'] ?? '';
//   }

//   void _setupAudioPlayer() async {
//     try {
//       await _audioPlayer.setSource(UrlSource(widget.recordingUrl));
      
//       _audioPlayer.onDurationChanged.listen((duration) {
//         setState(() => _duration = duration);
//       });

//       _audioPlayer.onPositionChanged.listen((position) {
//         setState(() => _position = position);
//       });

//       _audioPlayer.onPlayerComplete.listen((_) {
//         setState(() {
//           _isPlaying = false;
//           _position = Duration.zero;
//         });
//       });

//     } catch (e) {
//       print('Error setting up audio player: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _audioPlayer.dispose();
//     _titleController.dispose();
//     _descriptionController.dispose();
//     _fadeController.dispose();
//     _slideController.dispose();
//     super.dispose();
//   }

//   Future<void> _togglePlayPause() async {
//     try {
//       if (_isPlaying) {
//         await _audioPlayer.pause();
//       } else {
//         await _audioPlayer.resume();
//       }
//       setState(() => _isPlaying = !_isPlaying);
//     } catch (e) {
//       print('Error toggling playback: $e');
//     }
//   }

//   Future<void> _seekTo(double value) async {
//     final position = Duration(milliseconds: (value * _duration.inMilliseconds).round());
//     await _audioPlayer.seek(position);
//   }

//   Future<void> _pickNewImage() async {
//     try {
//       FilePickerResult? result = await FilePicker.platform.pickFiles(
//         type: FileType.image,
//         allowMultiple: false,
//       );

//       if (result != null && result.files.isNotEmpty) {
//         setState(() {
//           _newImageFile = File(result.files.first.path!);
//           _newImagePath = result.files.first.path!;
//         });
//       }
//     } catch (e) {
//       _showErrorMessage('Error selecting image: $e');
//     }
//   }

//   Future<void> _saveChanges() async {
//     if (!_formKey.currentState!.validate()) return;

//     setState(() => _isSavingChanges = true);

//     try {
//       print('🔍 Save changes - Recording data structure:');
//       print('📋 Keys: ${widget.recordingData.keys.toList()}');
      
//       final recordingId = widget.recordingData['recording_id'] ?? 
//                          widget.recordingData['metadata']?['recording_id'] ??
//                          widget.recordingData['id'];
      
//       print('🆔 Found recording ID for update: $recordingId');
      
//       if (recordingId == null) {
//         throw Exception('Recording ID not found - cannot update');
//       }

//       final result = await _awsService.updateRecordingMetadata(
//         recordingId: recordingId,
//         title: _titleController.text.trim(),
//         description: _descriptionController.text.trim(),
//         newImageFile: _newImageFile,
//       );

//       setState(() => _isSavingChanges = false);
//       _showSuccessMessage('Recording updated successfully!');
//       setState(() {
//         _isEditing = false;
//         _newImageFile = null;
//         _newImagePath = null;
//       });

//       widget.recordingData['title'] = _titleController.text.trim();
//       widget.recordingData['description'] = _descriptionController.text.trim();
//       if (widget.recordingData['metadata'] != null) {
//         widget.recordingData['metadata']['title'] = _titleController.text.trim();
//         widget.recordingData['metadata']['description'] = _descriptionController.text.trim();
//       }

//     } catch (e) {
//       setState(() => _isSavingChanges = false);
//       _showErrorMessage('Error saving changes: $e');
      
//       print('❌ Save changes error details: $e');
//       print('📋 Available recording data keys: ${widget.recordingData.keys.toList()}');
//     }
//   }

//   Future<void> _generateTranscription({bool forceRegenerate = false}) async {
//     setState(() => _isGeneratingTranscription = true);

//     try {
//       _showInfoMessage('Preparing transcription...');
      
//       print('🔍 Recording data structure:');
//       print('📋 Keys: ${widget.recordingData.keys.toList()}');
//       print('📋 Full data: ${widget.recordingData}');
      
//       final recordingId = widget.recordingData['recording_id'] ?? 
//                          widget.recordingData['metadata']?['recording_id'] ??
//                          widget.recordingData['id'];
      
//       final userId = widget.recordingData['metadata']?['user_id'] ?? 
//                     widget.recordingData['metadata']?['userId'] ??
//                     widget.recordingData['user_id'] ??
//                     widget.recordingData['userId'];
      
//       print('🆔 Found recording ID: $recordingId');
//       print('👤 Found user ID: $userId');
      
//       if (recordingId == null) {
//         throw Exception('Recording ID not found in recording data');
//       }
      
//       if (userId == null) {
//         throw Exception('User ID not found in recording data');
//       }

//       if (!forceRegenerate) {
//         final hasMidi = _awsService.hasFileType(widget.recordingData, 'midi');
//         final hasPdf = _awsService.hasFileType(widget.recordingData, 'pdf');
        
//         if (hasMidi && hasPdf) {
//           setState(() => _isGeneratingTranscription = false);
//           _showInfoMessage('Files already exist. Use "View Transcription" to see them.');
//           return;
//         }
//       }

//       _showInfoMessage('Generating AI transcription...');

//       final result = await _apiService.transcribeExistingRecording(
//         userId: userId,
//         recordingId: recordingId,
//         title: _titleController.text.trim(),
//       );

//       setState(() => _isGeneratingTranscription = false);

//       if (result != null) {
//         _showSuccessMessage('Transcription generated successfully!');
        
//         await _refreshRecordingDataSimple(userId, recordingId);
        
//         Navigator.of(context).push(
//           MaterialPageRoute(
//             builder: (context) => ResultScreen(result: result),
//           ),
//         );
//       } else {
//         _showErrorMessage('Failed to generate transcription');
//       }

//     } catch (e) {
//       setState(() => _isGeneratingTranscription = false);
//       _showErrorMessage('Error generating transcription: $e');
      
//       print('❌ Transcription error details: $e');
//       print('📋 Available recording data keys: ${widget.recordingData.keys.toList()}');
//       if (widget.recordingData['metadata'] != null) {
//         print('📋 Available metadata keys: ${widget.recordingData['metadata'].keys.toList()}');
//       }
//     }
//   }

//   Future<void> _refreshRecordingDataSimple(String userId, String recordingId) async {
//     try {
//       print('🔄 Refreshing recording data to show new files...');
      
//       final recordings = await _awsService.getUserRecordings();
      
//       final updatedRecording = recordings.firstWhere(
//         (r) => r['recording_id'] == recordingId,
//         orElse: () => {},
//       );
      
//       if (updatedRecording.isNotEmpty) {
//         widget.recordingData.clear();
//         widget.recordingData.addAll(updatedRecording);
        
//         setState(() {});
        
//         print('✅ Recording data refreshed - new files should now be visible');
//       }
//     } catch (e) {
//       print('⚠️ Could not refresh recording data: $e');
//     }
//   }

//   Future<void> _refreshRecordingData(String userId) async {
//     try {
//       print('🔄 Refreshing recording data...');
      
//       final recordings = await _awsService.getUserRecordings();
      
//       final recordingId = widget.recordingData['recording_id'] ?? 
//                          widget.recordingData['metadata']?['recording_id'];
      
//       if (recordingId != null) {
//         final updatedRecording = recordings.firstWhere(
//           (r) => r['recording_id'] == recordingId,
//           orElse: () => {},
//         );
        
//         if (updatedRecording.isNotEmpty) {
//           widget.recordingData.addAll(updatedRecording);
          
//           setState(() {});
          
//           print('✅ Recording data refreshed');
//         }
//       }
//     } catch (e) {
//       print('⚠️ Could not refresh recording data: $e');
//     }
//   }

//   void _showSuccessMessage(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(message), backgroundColor: Colors.green),
//     );
//   }

//   void _showErrorMessage(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(message), backgroundColor: AppTheme.errorColor),
//     );
//   }

//   void _showInfoMessage(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(message), backgroundColor: AppTheme.primaryColor),
//     );
//   }

//   Future<void> _openFile(String url, String type) async {
//     try {
//       final uri = Uri.parse(url);
//       if (await canLaunchUrl(uri)) {
//         await launchUrl(uri, mode: LaunchMode.externalApplication);
//       } else {
//         _showErrorMessage('Could not open $type file');
//       }
//     } catch (e) {
//       _showErrorMessage('Error opening $type file: $e');
//     }
//   }

//   Future<void> _downloadFile(String url, String fileName) async {
//     try {
//       _showInfoMessage('Downloading $fileName...');
      
//       String cleanFileName = fileName.replaceAll(RegExp(r'[^\w\s-.]'), '').trim();
//       if (!cleanFileName.contains('.')) {
//         if (fileName.toLowerCase().contains('pdf')) {
//           cleanFileName += '.pdf';
//         } else if (fileName.toLowerCase().contains('midi')) {
//           cleanFileName += '.mid';
//         } else if (fileName.toLowerCase().contains('image')) {
//           cleanFileName += '.jpg';
//         }
//       }
      
//       final file = await _apiService.downloadFile(url, cleanFileName);
      
//       if (file != null) {
//         _showSuccessMessage('$fileName downloaded successfully!');
//       } else {
//         _showErrorMessage('Failed to download $fileName');
//       }
//     } catch (e) {
//       _showErrorMessage('Error downloading $fileName: $e');
//     }
//   }

//   Future<void> _playMidiFile() async {
//     try {
//       final midiUrl = _awsService.getFileUrl(widget.recordingData, 'midi');
//       if (midiUrl.isEmpty) {
//         _showErrorMessage('MIDI file not available');
//         return;
//       }

//       _showInfoMessage('Loading MIDI file...');
      
//       final midiFile = await _apiService.downloadFile(midiUrl, 'temp_playback.mid');
      
//       if (midiFile != null) {
//         await _audioPlayer.stop();
//         await _audioPlayer.setSource(DeviceFileSource(midiFile.path));
//         await _audioPlayer.resume();
        
//         _showSuccessMessage('Playing MIDI file...');
//       } else {
//         _showErrorMessage('Could not load MIDI file');
//       }
//     } catch (e) {
//       _showErrorMessage('Error playing MIDI: $e');
//     }
//   }

//   Future<void> _showTranscriptionVisualization() async {
//   try {
//     final hasMidi = _awsService.hasFileType(widget.recordingData, 'midi');
//     final hasPdf = _awsService.hasFileType(widget.recordingData, 'pdf');
    
//     if (!hasMidi && !hasPdf) {
//       _showErrorMessage('No transcription data available');
//       return;
//     }

//     // Navigate to the loading screen instead of loading here
//     Navigator.of(context).push(
//       MaterialPageRoute(
//         builder: (context) => TranscriptionLoadingScreen(
//           recordingData: widget.recordingData,
//           title: _titleController.text.trim(),
//           apiService: _apiService,
//           awsService: _awsService,
//         ),
//       ),
//     );

//   } catch (e) {
//     _showErrorMessage('Error: $e');
//     print('❌ Error navigating to transcription: $e');
//   }
// }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Container(
//         decoration: BoxDecoration(
//           gradient: LinearGradient(
//             begin: Alignment.topCenter,
//             end: Alignment.bottomCenter,
//             colors: [
//               AppTheme.backgroundColor,
//               Color(0xFFE8F4F2),
//             ],
//           ),
//         ),
//         child: FadeTransition(
//           opacity: _fadeAnimation,
//           child: SlideTransition(
//             position: _slideAnimation,
//             child: CustomScrollView(
//               slivers: [
//                 _buildSliverAppBar(),
//                 SliverToBoxAdapter(
//                   child: Padding(
//                     padding: EdgeInsets.all(16),
//                     child: Column(
//                       children: [
//                         _buildAudioPlayer(),
//                         SizedBox(height: 24),
//                         _buildRecordingDetails(),
//                         SizedBox(height: 24),
//                         _buildAvailableFiles(),
//                         SizedBox(height: 24),
//                         _buildAIActions(),
//                         SizedBox(height: 100), // Space for FAB
//                       ],
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildSliverAppBar() {
//     final hasImage = _awsService.hasFileType(widget.recordingData, 'image');
//     final imageUrl = hasImage ? _awsService.getFileUrl(widget.recordingData, 'image') : null;

//     return SliverAppBar(
//       expandedHeight: 300,
//       pinned: true,
//       backgroundColor: AppTheme.primaryColor,
//       iconTheme: IconThemeData(color: Colors.white),
//       flexibleSpace: FlexibleSpaceBar(
//         background: Stack(
//           fit: StackFit.expand,
//           children: [
//             if (imageUrl != null || _newImagePath != null)
//               Image.network(
//                 _newImagePath ?? imageUrl!,
//                 fit: BoxFit.cover,
//                 errorBuilder: (context, error, stackTrace) => _buildDefaultBackground(),
//               )
//             else
//               _buildDefaultBackground(),
            
//             Container(
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   begin: Alignment.topCenter,
//                   end: Alignment.bottomCenter,
//                   colors: [
//                     Colors.transparent,
//                     Colors.black.withOpacity(0.7),
//                   ],
//                 ),
//               ),
//             ),
            
//             Positioned(
//               bottom: 16,
//               left: 16,
//               right: 16,
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     _titleController.text,
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 28,
//                       fontWeight: FontWeight.bold,
//                     ),
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                   SizedBox(height: 4),
//                   if (_descriptionController.text.isNotEmpty)
//                     Text(
//                       _descriptionController.text,
//                       style: TextStyle(
//                         color: Colors.white.withOpacity(0.9),
//                         fontSize: 16,
//                       ),
//                       maxLines: 2,
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//       actions: [
//         IconButton(
//           icon: Icon(_isEditing ? Icons.close : Icons.edit, color: Colors.white),
//           onPressed: () => setState(() => _isEditing = !_isEditing),
//         ),
//       ],
//     );
//   }

//   Widget _buildDefaultBackground() {
//     return Container(
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//           colors: [
//             AppTheme.primaryColor,
//             AppTheme.accentColor,
//           ],
//         ),
//       ),
//       child: Center(
//         child: Icon(
//           Icons.music_note,
//           size: 100,
//           color: Colors.white.withOpacity(0.3),
//         ),
//       ),
//     );
//   }

//   Widget _buildAudioPlayer() {
//     return Card(
//       elevation: 8,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//       child: Container(
//         padding: EdgeInsets.all(24),
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(20),
//           gradient: LinearGradient(
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//             colors: [Colors.white, Colors.grey[50]!],
//           ),
//         ),
//         child: Column(
//           children: [
//             SliderTheme(
//               data: SliderTheme.of(context).copyWith(
//                 thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
//                 overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
//               ),
//               child: Slider(
//                 value: _duration.inMilliseconds > 0 
//                     ? _position.inMilliseconds / _duration.inMilliseconds 
//                     : 0.0,
//                 onChanged: _seekTo,
//                 activeColor: AppTheme.primaryColor,
//                 inactiveColor: Colors.grey[300],
//               ),
//             ),
            
//             Padding(
//               padding: EdgeInsets.symmetric(horizontal: 16),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     _formatDuration(_position),
//                     style: TextStyle(color: Colors.grey[600]),
//                   ),
//                   Text(
//                     _formatDuration(_duration),
//                     style: TextStyle(color: Colors.grey[600]),
//                   ),
//                 ],
//               ),
//             ),
            
//             SizedBox(height: 16),
            
//             Container(
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 boxShadow: [
//                   BoxShadow(
//                     color: AppTheme.primaryColor.withOpacity(0.3),
//                     blurRadius: 20,
//                     spreadRadius: 5,
//                   ),
//                 ],
//               ),
//               child: FloatingActionButton(
//                 onPressed: _togglePlayPause,
//                 backgroundColor: AppTheme.primaryColor,
//                 child: Icon(
//                   _isPlaying ? Icons.pause : Icons.play_arrow,
//                   color: Colors.white,
//                   size: 32,
//                 ),
//                 heroTag: "audio_player",
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildRecordingDetails() {
//     if (!_isEditing) {
//       return Card(
//         elevation: 4,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         child: Padding(
//           padding: EdgeInsets.all(20),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Icon(Icons.info_outline, color: AppTheme.primaryColor),
//                   SizedBox(width: 8),
//                   Text(
//                     'Recording Details',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: AppTheme.textColor,
//                     ),
//                   ),
//                 ],
//               ),
//               SizedBox(height: 16),
              
//               _buildDetailRow('Title', _titleController.text),
//               if (_descriptionController.text.isNotEmpty) ...[
//                 SizedBox(height: 12),
//                 _buildDetailRow('Description', _descriptionController.text),
//               ],
              
//               SizedBox(height: 12),
//               _buildDetailRow('Upload Date', _getFormattedDate()),
//             ],
//           ),
//         ),
//       );
//     }

//     return Card(
//       elevation: 4,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       child: Padding(
//         padding: EdgeInsets.all(20),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Icon(Icons.edit, color: AppTheme.primaryColor),
//                   SizedBox(width: 8),
//                   Text(
//                     'Edit Recording',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: AppTheme.textColor,
//                     ),
//                   ),
//                 ],
//               ),
//               SizedBox(height: 20),

//               TextFormField(
//                 controller: _titleController,
//                 decoration: InputDecoration(
//                   labelText: 'Title',
//                   prefixIcon: Icon(Icons.music_note),
//                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
//                 ),
//                 validator: (value) => value?.trim().isEmpty ?? true ? 'Title is required' : null,
//               ),
              
//               SizedBox(height: 16),
              
//               TextFormField(
//                 controller: _descriptionController,
//                 maxLines: 3,
//                 decoration: InputDecoration(
//                   labelText: 'Description',
//                   prefixIcon: Icon(Icons.description),
//                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
//                 ),
//               ),
              
//               SizedBox(height: 20),
              
//               _buildImageSelection(),
              
//               SizedBox(height: 20),
              
//               Row(
//                 children: [
//                   Expanded(
//                     child: OutlinedButton(
//                       onPressed: () => setState(() => _isEditing = false),
//                       child: Text('Cancel'),
//                       style: OutlinedButton.styleFrom(
//                         padding: EdgeInsets.symmetric(vertical: 12),
//                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                       ),
//                     ),
//                   ),
//                   SizedBox(width: 12),
//                   Expanded(
//                     child: ElevatedButton(
//                       onPressed: _isSavingChanges ? null : _saveChanges,
//                       child: _isSavingChanges 
//                           ? SizedBox(
//                               width: 20, 
//                               height: 20, 
//                               child: CircularProgressIndicator(strokeWidth: 2),
//                             )
//                           : Text('Save Changes'),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: AppTheme.primaryColor,
//                         foregroundColor: Colors.white,
//                         padding: EdgeInsets.symmetric(vertical: 12),
//                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildImageSelection() {
//     final hasImage = _awsService.hasFileType(widget.recordingData, 'image');
//     final currentImageUrl = hasImage ? _awsService.getFileUrl(widget.recordingData, 'image') : null;

//     return Container(
//       decoration: BoxDecoration(
//         border: Border.all(color: Colors.grey[300]!),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: InkWell(
//         onTap: _pickNewImage,
//         borderRadius: BorderRadius.circular(12),
//         child: Padding(
//           padding: EdgeInsets.all(16),
//           child: Row(
//             children: [
//               Container(
//                 width: 60,
//                 height: 60,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(8),
//                   color: Colors.grey[200],
//                 ),
//                 child: _newImagePath != null
//                     ? ClipRRect(
//                         borderRadius: BorderRadius.circular(8),
//                         child: Image.file(File(_newImagePath!), fit: BoxFit.cover),
//                       )
//                     : currentImageUrl != null
//                         ? ClipRRect(
//                             borderRadius: BorderRadius.circular(8),
//                             child: Image.network(currentImageUrl, fit: BoxFit.cover),
//                           )
//                         : Icon(Icons.image, color: Colors.grey[400], size: 30),
//               ),
//               SizedBox(width: 16),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Cover Image',
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     Text(
//                       _newImagePath != null
//                           ? 'New image selected'
//                           : hasImage 
//                               ? 'Tap to change image'
//                               : 'Tap to add cover image',
//                       style: TextStyle(color: Colors.grey[600], fontSize: 12),
//                     ),
//                   ],
//                 ),
//               ),
//               Icon(Icons.edit, color: AppTheme.primaryColor),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildDetailRow(String label, String value) {
//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         SizedBox(
//           width: 100,
//           child: Text(
//             label,
//             style: TextStyle(
//               fontWeight: FontWeight.w500,
//               color: Colors.grey[600],
//             ),
//           ),
//         ),
//         Expanded(
//           child: Text(
//             value,
//             style: TextStyle(color: AppTheme.textColor),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildAvailableFiles() {
//     final hasImage = _awsService.hasFileType(widget.recordingData, 'image');
//     final hasPdf = _awsService.hasFileType(widget.recordingData, 'pdf');
//     final hasMidi = _awsService.hasFileType(widget.recordingData, 'midi');

//     return Card(
//       elevation: 4,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       child: Padding(
//         padding: EdgeInsets.all(20),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Icon(Icons.folder_open, color: AppTheme.primaryColor),
//                 SizedBox(width: 8),
//                 Text(
//                   'Available Files',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     color: AppTheme.textColor,
//                   ),
//                 ),
//                 Spacer(),
//                 if (hasMidi || hasPdf)
//                   Container(
//                     padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                     decoration: BoxDecoration(
//                       color: Colors.green.withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(12),
//                       border: Border.all(color: Colors.green.withOpacity(0.3)),
//                     ),
//                     child: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         Icon(Icons.check_circle, size: 14, color: Colors.green),
//                         SizedBox(width: 4),
//                         Text(
//                           'AI Generated',
//                           style: TextStyle(
//                             fontSize: 11,
//                             fontWeight: FontWeight.w500,
//                             color: Colors.green,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//               ],
//             ),
//             SizedBox(height: 16),
            
//             if (!hasImage && !hasPdf && !hasMidi)
//               Container(
//                 padding: EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   color: Colors.grey[50],
//                   borderRadius: BorderRadius.circular(8),
//                   border: Border.all(color: Colors.grey[200]!),
//                 ),
//                 child: Row(
//                   children: [
//                     Icon(Icons.info_outline, color: Colors.grey[400], size: 20),
//                     SizedBox(width: 8),
//                     Text(
//                       'No additional files yet. Generate AI transcription to create MIDI and PDF files.',
//                       style: TextStyle(
//                         color: Colors.grey[600],
//                         fontSize: 12,
//                       ),
//                     ),
//                   ],
//                 ),
//               )
//             else
//               Column(
//                 children: [
//                   Wrap(
//                     spacing: 12,
//                     runSpacing: 12,
//                     children: [
//                       if (hasImage) _buildEnhancedFileChip(
//                         'Cover Image',
//                         Icons.image,
//                         AppTheme.accentColor,
//                         () => _openFile(_awsService.getFileUrl(widget.recordingData, 'image'), 'image'),
//                         canDownload: true,
//                         downloadUrl: _awsService.getFileUrl(widget.recordingData, 'image'),
//                       ),
//                       if (hasPdf) _buildEnhancedFileChip(
//                         'Sheet Music (PDF)',
//                         Icons.picture_as_pdf,
//                         Colors.red,
//                         () => _openFile(_awsService.getFileUrl(widget.recordingData, 'pdf'), 'PDF'),
//                         canDownload: true,
//                         downloadUrl: _awsService.getFileUrl(widget.recordingData, 'pdf'),
//                       ),
//                       if (hasMidi) _buildEnhancedFileChip(
//                         'MIDI File',
//                         Icons.piano,
//                         Colors.purple,
//                         () => _playMidiFile(),
//                         canDownload: true,
//                         downloadUrl: _awsService.getFileUrl(widget.recordingData, 'midi'),
//                         isPlayable: true,
//                       ),
//                     ],
//                   ),
                  
//                   if (hasMidi) ...[
//                     SizedBox(height: 16),
//                     _buildMidiPlayerSection(),
//                   ],
//                 ],
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildEnhancedFileChip(
//     String label, 
//     IconData icon, 
//     Color color, 
//     VoidCallback onTap, 
//     {
//       bool canDownload = false,
//       String? downloadUrl,
//       bool isPlayable = false,
//     }
//   ) {
//     return Container(
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.1),
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: color.withOpacity(0.3)),
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           InkWell(
//             onTap: onTap,
//             borderRadius: BorderRadius.circular(12),
//             child: Padding(
//               padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//               child: Row(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Icon(icon, size: 18, color: color),
//                   SizedBox(width: 8),
//                   Text(
//                     label,
//                     style: TextStyle(
//                       color: color,
//                       fontWeight: FontWeight.w500,
//                       fontSize: 13,
//                     ),
//                   ),
//                   if (isPlayable) ...[
//                     SizedBox(width: 8),
//                     Icon(Icons.play_arrow, size: 16, color: color),
//                   ],
//                 ],
//               ),
//             ),
//           ),
          
//           if (canDownload && downloadUrl != null)
//             Container(
//               width: double.infinity,
//               height: 1,
//               color: color.withOpacity(0.2),
//             ),
//           if (canDownload && downloadUrl != null)
//             InkWell(
//               onTap: () => _downloadFile(downloadUrl, label),
//               borderRadius: BorderRadius.only(
//                 bottomLeft: Radius.circular(12),
//                 bottomRight: Radius.circular(12),
//               ),
//               child: Padding(
//                 padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Icon(Icons.download, size: 14, color: color.withOpacity(0.7)),
//                     SizedBox(width: 4),
//                     Text(
//                       'Download',
//                       style: TextStyle(
//                         color: color.withOpacity(0.7),
//                         fontSize: 11,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildMidiPlayerSection() {
//     return Container(
//       padding: EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.purple.withOpacity(0.05),
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: Colors.purple.withOpacity(0.2)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Icon(Icons.piano, color: Colors.purple, size: 20),
//               SizedBox(width: 8),
//               Text(
//                 'MIDI Playback',
//                 style: TextStyle(
//                   fontWeight: FontWeight.bold,
//                   color: Colors.purple,
//                   fontSize: 14,
//                 ),
//               ),
//               Spacer(),
//               Text(
//                 'Generated by AI',
//                 style: TextStyle(
//                   fontSize: 11,
//                   color: Colors.purple.withOpacity(0.7),
//                   fontStyle: FontStyle.italic,
//                 ),
//               ),
//             ],
//           ),
//           SizedBox(height: 12),
//           Row(
//             children: [
//               ElevatedButton.icon(
//                 onPressed: _playMidiFile,
//                 icon: Icon(Icons.play_arrow, size: 18),
//                 label: Text('Play MIDI'),
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.purple,
//                   foregroundColor: Colors.white,
//                   padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                 ),
//               ),
//               SizedBox(width: 12),
//               OutlinedButton.icon(
//                 onPressed: () => _showTranscriptionVisualization(),
//                 icon: Icon(Icons.visibility, size: 18),
//                 label: Text('View Notes'),
//                 style: OutlinedButton.styleFrom(
//                   foregroundColor: Colors.purple,
//                   side: BorderSide(color: Colors.purple),
//                   padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildFileChip(String label, IconData icon, Color color, VoidCallback onTap) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(25),
//       child: Container(
//         padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//         decoration: BoxDecoration(
//           color: color.withOpacity(0.1),
//           borderRadius: BorderRadius.circular(25),
//           border: Border.all(color: color.withOpacity(0.3)),
//         ),
//         child: Row(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(icon, size: 18, color: color),
//             SizedBox(width: 8),
//             Text(
//               label,
//               style: TextStyle(
//                 color: color,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildAIActions() {
//     final hasImage = _awsService.hasFileType(widget.recordingData, 'image');
//     final hasPdf = _awsService.hasFileType(widget.recordingData, 'pdf');
//     final hasMidi = _awsService.hasFileType(widget.recordingData, 'midi');
//     final hasTranscription = hasMidi || hasPdf;

//     return Card(
//       elevation: 4,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       child: Padding(
//         padding: EdgeInsets.all(20),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Icon(Icons.smart_toy, color: AppTheme.primaryColor),
//                 SizedBox(width: 8),
//                 Text(
//                   'AI Transcription',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     color: AppTheme.textColor,
//                   ),
//                 ),
//                 Spacer(),
//                 if (hasTranscription)
//                   Container(
//                     padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                     decoration: BoxDecoration(
//                       color: Colors.green.withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(12),
//                       border: Border.all(color: Colors.green.withOpacity(0.3)),
//                     ),
//                     child: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         Icon(Icons.check_circle, size: 14, color: Colors.green),
//                         SizedBox(width: 4),
//                         Text(
//                           'Generated',
//                           style: TextStyle(
//                             fontSize: 11,
//                             fontWeight: FontWeight.w500,
//                             color: Colors.green,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//               ],
//             ),
//             SizedBox(height: 12),
            
//             Text(
//               hasTranscription 
//                 ? 'AI transcription complete! MIDI and sheet music files are ready.'
//                 : 'Generate MIDI file and sheet music using artificial intelligence',
//               style: TextStyle(
//                 color: Colors.grey[600],
//                 fontSize: 14,
//               ),
//             ),
//             SizedBox(height: 20),
            
//             Row(
//               children: [
//                 Expanded(
//                   flex: 2,
//                   child: ElevatedButton.icon(
//                     onPressed: _isGeneratingTranscription ? null : () {
//                       if (hasTranscription) {
//                         _showTranscriptionVisualization();
//                       } else {
//                         _generateTranscription();
//                       }
//                     },
//                     icon: _isGeneratingTranscription 
//                         ? SizedBox(
//                             width: 20,
//                             height: 20,
//                             child: CircularProgressIndicator(
//                               strokeWidth: 2,
//                               valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//                             ),
//                           )
//                         : Icon(hasTranscription ? Icons.visibility : Icons.auto_awesome),
//                     label: Text(_isGeneratingTranscription 
//                         ? 'Generating...' 
//                         : hasTranscription 
//                             ? 'View Transcription'
//                             : 'Generate AI Transcription'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: hasTranscription ? Colors.green : AppTheme.accentColor,
//                       foregroundColor: Colors.white,
//                       padding: EdgeInsets.symmetric(vertical: 16),
//                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                     ),
//                   ),
//                 ),
                
//                 if (hasTranscription) ...[
//                   SizedBox(width: 12),
//                   Expanded(
//                     flex: 1,
//                     child: OutlinedButton.icon(
//                       onPressed: _isGeneratingTranscription ? null : () {
//                         _showRegenerateDialog();
//                       },
//                       icon: Icon(Icons.refresh, size: 18),
//                       label: Text('Regenerate'),
//                       style: OutlinedButton.styleFrom(
//                         foregroundColor: AppTheme.accentColor,
//                         side: BorderSide(color: AppTheme.accentColor),
//                         padding: EdgeInsets.symmetric(vertical: 16),
//                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                       ),
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   void _showRegenerateDialog() {
//     showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return AlertDialog(
//           title: Text('Regenerate Transcription'),
//           content: Text(
//             'This will replace the existing MIDI and PDF files with new ones. This action cannot be undone. Continue?'
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.of(context).pop(),
//               child: Text('Cancel'),
//             ),
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.of(context).pop();
//                 _generateTranscription(forceRegenerate: true);
//               },
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: AppTheme.accentColor,
//                 foregroundColor: Colors.white,
//               ),
//               child: Text('Regenerate'),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   Widget _buildFloatingActionButton() {
//     if (_isEditing) return SizedBox.shrink();
    
//     return FloatingActionButton.extended(
//       onPressed: () => setState(() => _isEditing = true),
//       backgroundColor: AppTheme.primaryColor,
//       foregroundColor: Colors.white,
//       icon: Icon(Icons.edit),
//       label: Text('Edit Recording'),
//       heroTag: "edit_recording",
//     );
//   }

//   String _formatDuration(Duration duration) {
//     String twoDigits(int n) => n.toString().padLeft(2, '0');
//     final minutes = twoDigits(duration.inMinutes.remainder(60));
//     final seconds = twoDigits(duration.inSeconds.remainder(60));
//     return '$minutes:$seconds';
//   }

//   String _getFormattedDate() {
//     final uploadDateStr = widget.recordingData['upload_date'] ?? 
//                          widget.recordingData['metadata']?['upload_date'];
//     if (uploadDateStr != null) {
//       try {
//         final date = DateTime.parse(uploadDateStr);
//         return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
//       } catch (e) {
//         return 'Unknown date';
//       }
//     }
//     return 'Unknown date';
//   }
// }