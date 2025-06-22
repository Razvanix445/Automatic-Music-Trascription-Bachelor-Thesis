import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../config/app_theme.dart';
import '../services/recording_service.dart';
import '../services/aws_service.dart';

class UploadRecordingScreen extends StatefulWidget {
  @override
  _UploadRecordingScreenState createState() => _UploadRecordingScreenState();
}

class _UploadRecordingScreenState extends State<UploadRecordingScreen> {
  final AwsService _awsService = AwsService();
  final RecordingService _recordingService = RecordingService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  File? _audioFile;
  File? _imageFile;
  File? _pdfFile;
  File? _midiFile;

  bool _isLoading = false;
  double _uploadProgress = 0.0;

  String _audioFileName = '';
  String _imageFileName = '';
  String _pdfFileName = '';
  String _midiFileName = '';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _audioFile = File(result.files.first.path!);
          _audioFileName = path.basename(_audioFile!.path);

          if (_titleController.text.isEmpty) {
            final nameWithoutExtension = path.basenameWithoutExtension(_audioFileName);
            _titleController.text = nameWithoutExtension;
          }
        });
      }
    } catch (e) {
      _showErrorMessage('Error selecting audio file: $e');
    }
  }

  Future<void> _pickImageFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _imageFile = File(result.files.first.path!);
          _imageFileName = path.basename(_imageFile!.path);
        });
      }
    } catch (e) {
      _showErrorMessage('Error selecting image file: $e');
    }
  }

  Future<void> _pickPdfFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pdfFile = File(result.files.first.path!);
          _pdfFileName = path.basename(_pdfFile!.path);
        });
      }
    } catch (e) {
      _showErrorMessage('Error selecting PDF file: $e');
    }
  }

  Future<void> _pickMidiFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mid', 'midi'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _midiFile = File(result.files.first.path!);
          _midiFileName = path.basename(_midiFile!.path);
        });
      }
    } catch (e) {
      _showErrorMessage('Error selecting MIDI file: $e');
    }
  }

  Future<void> _uploadRecording() async {
    if (_formKey.currentState!.validate() && _audioFile != null) {
      setState(() {
        _isLoading = true;
        _uploadProgress = 0.0;
      });

      try {
        Map<String, File> files = {
          'audio': _audioFile!,
        };

        if (_imageFile != null) files['image'] = _imageFile!;
        if (_pdfFile != null) files['pdf'] = _pdfFile!;
        if (_midiFile != null) files['midi'] = _midiFile!;

        final result = await _awsService.uploadRecordingWithFiles(
          files: files,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
        );

        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop();
      } catch (e) {
        setState(() {
          _isLoading = false;
        });

        _showErrorMessage('Error uploading recording: $e');
      }
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add Recording',
          style: TextStyle(color: AppTheme.textColor),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFileSection(
                  title: 'Audio Recording *',
                  subtitle: 'Select the main audio file',
                  icon: Icons.audiotrack,
                  selectedFile: _audioFile,
                  selectedFileName: _audioFileName,
                  onTap: _pickAudioFile,
                  isRequired: true,
                ),
                
                SizedBox(height: 16),
                
                _buildDetailsSection(),
                
                SizedBox(height: 24),
                
                Text(
                  'Optional Files',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Add extra files to enhance your recording',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textColor.withOpacity(0.7),
                  ),
                ),
                SizedBox(height: 16),
                
                _buildFileSection(
                  title: 'Cover Image',
                  subtitle: 'Add a visual representation',
                  icon: Icons.image,
                  selectedFile: _imageFile,
                  selectedFileName: _imageFileName,
                  onTap: _pickImageFile,
                  isRequired: false,
                ),
                
                SizedBox(height: 12),
                
                _buildFileSection(
                  title: 'Sheet Music (PDF)',
                  subtitle: 'Upload the musical notation',
                  icon: Icons.picture_as_pdf,
                  selectedFile: _pdfFile,
                  selectedFileName: _pdfFileName,
                  onTap: _pickPdfFile,
                  isRequired: false,
                ),
                
                SizedBox(height: 12),
                
                _buildFileSection(
                  title: 'MIDI File',
                  subtitle: 'Digital representation of the music',
                  icon: Icons.piano,
                  selectedFile: _midiFile,
                  selectedFileName: _midiFileName,
                  onTap: _pickMidiFile,
                  isRequired: false,
                ),
                
                SizedBox(height: 32),

                if (_isLoading) _buildProgressSection(),

                ElevatedButton.icon(
                  onPressed: _isLoading || _audioFile == null
                      ? null
                      : _uploadRecording,
                  icon: Icon(Icons.cloud_upload),
                  label: Text('Upload Recording'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    disabledBackgroundColor: AppTheme.accentColor.withOpacity(0.5),
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recording Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
          ),
          SizedBox(height: 16),
          
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Title *',
              hintText: 'Ex: Clair de Lune',
              prefixIcon: Icon(
                Icons.music_note,
                color: AppTheme.primaryColor,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a title';
              }
              return null;
            },
          ),
          
          SizedBox(height: 16),
          
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'Add notes about this recording...',
              prefixIcon: Icon(
                Icons.description,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required File? selectedFile,
    required String selectedFileName,
    required VoidCallback onTap,
    required bool isRequired,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isRequired && selectedFile == null
            ? Border.all(color: AppTheme.errorColor.withOpacity(0.5))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selectedFile != null
                      ? AppTheme.accentColor.withOpacity(0.2)
                      : AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  selectedFile != null ? Icons.check_circle : icon,
                  color: selectedFile != null
                      ? AppTheme.accentColor
                      : AppTheme.primaryColor,
                  size: 24,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textColor,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      selectedFile != null ? selectedFileName : subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selectedFile != null ? Icons.edit : Icons.add,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: _uploadProgress,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
        ),
        SizedBox(height: 8),
        Text(
          'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.primaryColor,
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }
}