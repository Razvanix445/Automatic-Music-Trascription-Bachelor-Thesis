import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'recording_player_screen.dart';
import 'upload_recording_screen.dart';
import '../services/recording_service.dart';
import '../services/aws_service.dart';
import 'transcription_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AwsService _awsService = AwsService();
  final AuthService _authService = AuthService();
  final RecordingService _recordingService = RecordingService();

  @override
  Widget build(BuildContext context) {
    final currentUser = _authService.currentUser;
    final displayName = currentUser?.displayName ?? 'Musician';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Piano Notes',
          style: TextStyle(color: AppTheme.textColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.music_note, color: AppTheme.textColor),
            tooltip: 'Transcription',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => TranscriptionScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: AppTheme.textColor),
            onPressed: () async {
              await _authService.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => LoginScreen()),
                    (route) => false,
              );
            },
          ),
        ],
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
            // Welcome section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 30,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome,',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppTheme.textColor.withOpacity(0.7),
                          ),
                        ),
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Piano transcription card
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => TranscriptionScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.piano,
                            color: AppTheme.accentColor,
                            size: 32,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Piano Transcription',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textColor,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Convert audio piano recordings into musical notes and MIDI files',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textColor.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: AppTheme.accentColor,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Recordings list header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your recordings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {});
                    },
                    icon: Icon(
                      Icons.refresh,
                      color: AppTheme.primaryColor,
                    ),
                    label: Text(
                      'Refresh',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Enhanced recordings list
            Expanded(
              child: _buildEnhancedRecordingsList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => UploadRecordingScreen(),
            ),
          ).then((_) {
            setState(() {});
          });
        },
        icon: Icon(Icons.add),
        label: Text('Add recording'),
        backgroundColor: AppTheme.accentColor,
      ),
    );
  }

  Widget _buildEnhancedRecordingsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _awsService.getUserRecordings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppTheme.errorColor,
                ),
                SizedBox(height: 16),
                Text(
                  'Error loading recordings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textColor.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: Text('Try Again'),
                ),
              ],
            ),
          );
        }

        final recordings = snapshot.data ?? [];

        if (recordings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_note,
                  size: 70,
                  color: AppTheme.primaryColor.withOpacity(0.5),
                ),
                SizedBox(height: 16),
                Text(
                  'No recordings yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppTheme.textColor,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Press the + button to add your first recording',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textColor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: recordings.length,
          itemBuilder: (context, index) {
            final recording = recordings[index];
            return _buildEnhancedRecordingCard(recording);
          },
        );
      },
    );
  }

  Widget _buildEnhancedRecordingCard(Map<String, dynamic> recording) {
    final metadata = recording['metadata'] ?? {};
    final title = recording['title'] ?? metadata['title'] ?? 'Unnamed Recording';
    final description = recording['description'] ?? metadata['description'] ?? '';
    
    // Parse upload date
    final uploadDateStr = recording['upload_date'] ?? metadata['upload_date'];
    DateTime? uploadDate;
    if (uploadDateStr != null) {
      try {
        uploadDate = DateTime.parse(uploadDateStr);
      } catch (e) {
        uploadDate = DateTime.now();
      }
    }
    final formattedDate = uploadDate != null 
        ? "${uploadDate.day}/${uploadDate.month}/${uploadDate.year}"
        : 'Unknown date';

    // Check which file types are available
    final hasImage = _awsService.hasFileType(recording, 'image');
    final hasPdf = _awsService.hasFileType(recording, 'pdf');
    final hasMidi = _awsService.hasFileType(recording, 'midi');
    final hasTranscription = hasMidi || hasPdf;

    return Card(
      elevation: 2,
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RecordingPlayerScreen(
                recordingUrl: _awsService.getFileUrl(recording, 'audio'),
                recordingData: recording,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main recording info row
              Row(
                children: [
                  // Cover image or default icon with AI badge
                  Stack(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          image: hasImage ? DecorationImage(
                            image: NetworkImage(_awsService.getFileUrl(recording, 'image')),
                            fit: BoxFit.cover,
                          ) : null,
                        ),
                        child: hasImage ? null : Icon(
                          Icons.music_note,
                          color: AppTheme.primaryColor,
                          size: 32,
                        ),
                      ),
                      
                      // AI generated badge
                      if (hasTranscription)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            padding: EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(width: 16),
                  
                  // Recording details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textColor,
                                ),
                              ),
                            ),
                            if (hasTranscription)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                                ),
                                child: Text(
                                  'AI',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          SizedBox(height: 2),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textColor.withOpacity(0.6),
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textColor.withOpacity(0.7),
                              ),
                            ),
                            if (hasTranscription) ...[
                              SizedBox(width: 8),
                              Icon(
                                Icons.check_circle,
                                size: 12,
                                color: Colors.green,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'Transcribed',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Play button
                  IconButton(
                    icon: Icon(
                      Icons.play_circle_filled,
                      color: AppTheme.accentColor,
                      size: 36,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => RecordingPlayerScreen(
                            recordingUrl: _awsService.getFileUrl(recording, 'audio'),
                            recordingData: recording,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              
              // Enhanced file type indicators and quick actions
              if (hasImage || hasPdf || hasMidi) ...[
                SizedBox(height: 12),
                Divider(height: 1),
                SizedBox(height: 8),
                
                Row(
                  children: [
                    Text(
                      'Available:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textColor.withOpacity(0.8),
                      ),
                    ),
                    SizedBox(width: 8),
                    
                    // Enhanced file type chips
                    Expanded(
                      child: Row(
                        children: [
                          if (hasImage) _buildQuickFileChip(
                            'Photo',
                            Icons.image,
                            AppTheme.accentColor,
                            () => _openFile(_awsService.getFileUrl(recording, 'image')),
                          ),
                          if (hasPdf) _buildQuickFileChip(
                            'PDF',
                            Icons.picture_as_pdf,
                            Colors.red,
                            () => _openFile(_awsService.getFileUrl(recording, 'pdf')),
                          ),
                          if (hasMidi) _buildQuickFileChip(
                            'MIDI',
                            Icons.piano,
                            Colors.purple,
                            () => _openFile(_awsService.getFileUrl(recording, 'midi')),
                          ),
                        ],
                      ),
                    ),
                    
                    // Quick access to transcription view
                    if (hasTranscription)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => RecordingPlayerScreen(
                                recordingUrl: _awsService.getFileUrl(recording, 'audio'),
                                recordingData: recording,
                              ),
                            ),
                          );
                        },
                        icon: Icon(Icons.visibility, size: 14),
                        label: Text(
                          'View',
                          style: TextStyle(fontSize: 11),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size(0, 0),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFileChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: color),
              SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: color,
            ),
            SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(String url) async {
    try {
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File URL not available'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch file');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening file: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }
}



// import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import '../config/app_theme.dart';
// import '../services/auth_service.dart';
// import 'login_screen.dart';
// import 'recording_player_screen.dart';
// import 'upload_recording_screen.dart';
// import '../services/recording_service.dart';
// import '../services/aws_service.dart';
// import 'transcription_screen.dart';

// class HomeScreen extends StatefulWidget {
//   @override
//   _HomeScreenState createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> {
//   final AwsService _awsService = AwsService();
//   final AuthService _authService = AuthService();
//   final RecordingService _recordingService = RecordingService();

//   @override
//   Widget build(BuildContext context) {
//     final currentUser = _authService.currentUser;
//     final displayName = currentUser?.displayName ?? 'Musician';

//     return Scaffold(
//       appBar: AppBar(
//         title: Text(
//           'Piano Notes',
//           style: TextStyle(color: AppTheme.textColor),
//         ),
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         actions: [
//           IconButton(
//             icon: Icon(Icons.music_note, color: AppTheme.textColor),
//             tooltip: 'Transcription',
//             onPressed: () {
//               Navigator.of(context).push(
//                 MaterialPageRoute(
//                   builder: (context) => TranscriptionScreen(),
//                 ),
//               );
//             },
//           ),
//           IconButton(
//             icon: Icon(Icons.logout, color: AppTheme.textColor),
//             onPressed: () async {
//               await _authService.signOut();
//               Navigator.of(context).pushAndRemoveUntil(
//                 MaterialPageRoute(builder: (context) => LoginScreen()),
//                     (route) => false,
//               );
//             },
//           ),
//         ],
//       ),
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
//         child: Column(
//           children: [
//             // Secțiunea de bun venit
//             Padding(
//               padding: const EdgeInsets.all(16.0),
//               child: Row(
//                 children: [
//                   CircleAvatar(
//                     radius: 30,
//                     backgroundColor: Colors.white,
//                     child: Icon(
//                       Icons.person,
//                       size: 30,
//                       color: AppTheme.primaryColor,
//                     ),
//                   ),
//                   SizedBox(width: 16),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           'Welcome,',
//                           style: TextStyle(
//                             fontSize: 16,
//                             color: AppTheme.textColor.withOpacity(0.7),
//                           ),
//                         ),
//                         Text(
//                           displayName,
//                           style: TextStyle(
//                             fontSize: 22,
//                             fontWeight: FontWeight.bold,
//                             color: AppTheme.textColor,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
//               child: Card(
//                 elevation: 3,
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(16),
//                 ),
//                 child: InkWell(
//                   onTap: () {
//                     Navigator.of(context).push(
//                       MaterialPageRoute(
//                         builder: (context) => TranscriptionScreen(),
//                       ),
//                     );
//                   },
//                   borderRadius: BorderRadius.circular(16),
//                   child: Padding(
//                     padding: const EdgeInsets.all(16.0),
//                     child: Row(
//                       children: [
//                         Container(
//                           width: 60,
//                           height: 60,
//                           decoration: BoxDecoration(
//                             color: AppTheme.accentColor.withOpacity(0.2),
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           child: Icon(
//                             Icons.piano,
//                             color: AppTheme.accentColor,
//                             size: 32,
//                           ),
//                         ),
//                         SizedBox(width: 16),
//                         Expanded(
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Text(
//                                 'Piano Transcription',
//                                 style: TextStyle(
//                                   fontSize: 18,
//                                   fontWeight: FontWeight.bold,
//                                   color: AppTheme.textColor,
//                                 ),
//                               ),
//                               SizedBox(height: 4),
//                               Text(
//                                 'Convert audio piano recordings into musical notes and MIDI files',
//                                 style: TextStyle(
//                                   fontSize: 12,
//                                   color: AppTheme.textColor.withOpacity(0.7),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                         Icon(
//                           Icons.arrow_forward_ios,
//                           color: AppTheme.accentColor,
//                           size: 20,
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//               ),
//             ),

//             // Titlu pentru lista de înregistrări
//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     'Your recordings',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: AppTheme.textColor,
//                     ),
//                   ),
//                   TextButton.icon(
//                     onPressed: () {
//                       // Actualizează lista dacă e nevoie
//                       setState(() {});
//                     },
//                     icon: Icon(
//                       Icons.refresh,
//                       color: AppTheme.primaryColor,
//                     ),
//                     label: Text(
//                       'Refresh',
//                       style: TextStyle(
//                         color: AppTheme.primaryColor,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // Lista de înregistrări
//             Expanded(
//               child: _buildRecordingsList(),
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton.extended(
//         onPressed: () {
//           Navigator.of(context).push(
//             MaterialPageRoute(
//               builder: (context) => UploadRecordingScreen(),
//             ),
//           ).then((_) {
//             // Actualizează lista după upload
//             setState(() {});
//           });
//         },
//         icon: Icon(Icons.add),
//         label: Text('Add recording'),
//         backgroundColor: AppTheme.accentColor,
//       ),
//     );
//   }

//   Widget _buildRecordingsList() {
//     return FutureBuilder<List<Map<String, dynamic>>>(
//       future: _awsService.getUserRecordings(),
//       builder: (context, snapshot) {
//         if (snapshot.connectionState == ConnectionState.waiting) {
//           return Center(
//             child: CircularProgressIndicator(
//               valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
//             ),
//           );
//         }

//         if (snapshot.hasError) {
//           return Center(
//             child: Text('Encountered an error: ${snapshot.error}'),
//           );
//         }

//         final recordings = snapshot.data ?? [];

//         if (recordings.isEmpty) {
//           return Center(
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(
//                   Icons.music_note,
//                   size: 70,
//                   color: AppTheme.primaryColor.withOpacity(0.5),
//                 ),
//                 SizedBox(height: 16),
//                 Text(
//                   'You do not have recordings yet',
//                   style: TextStyle(
//                     fontSize: 18,
//                     color: AppTheme.textColor,
//                   ),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   'Press + button to add a recording',
//                   style: TextStyle(
//                     fontSize: 14,
//                     color: AppTheme.textColor.withOpacity(0.7),
//                   ),
//                 ),
//               ],
//             ),
//           );
//         }

//         return ListView.builder(
//           padding: EdgeInsets.all(16),
//           itemCount: recordings.length,
//           itemBuilder: (context, index) {
//             final recording = recordings[index];
//             final metadata = recording['metadata'] ?? {};

//             final title = metadata['title'] ?? 'Unnamed Recording';
//             final uploadDate = DateTime.parse(
//                 metadata['uploadDate'] ?? DateTime.now().toIso8601String());
//             final formattedDate = "${uploadDate.day}/${uploadDate
//                 .month}/${uploadDate.year}";

//             // Folosește durata reală dacă există, altfel estimează
//             final duration = metadata['duration'] ?? '00:00';

//             return Card(
//               elevation: 2,
//               margin: EdgeInsets.only(bottom: 16),
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(16),
//               ),
//               child: InkWell(
//                 onTap: () {
//                   Navigator.of(context).push(
//                     MaterialPageRoute(
//                       builder: (context) =>
//                           RecordingPlayerScreen(
//                             recordingUrl: recording['url'],
//                             recordingData: recording,
//                           ),
//                     ),
//                   );
//                 },
//                 borderRadius: BorderRadius.circular(16),
//                 child: Padding(
//                   padding: const EdgeInsets.all(16.0),
//                   child: Row(
//                     children: [
//                       Container(
//                         width: 60,
//                         height: 60,
//                         decoration: BoxDecoration(
//                           color: AppTheme.primaryColor.withOpacity(0.2),
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                         child: Icon(
//                           Icons.music_note,
//                           color: AppTheme.primaryColor,
//                           size: 32,
//                         ),
//                       ),
//                       SizedBox(width: 16),
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               title,
//                               style: TextStyle(
//                                 fontSize: 16,
//                                 fontWeight: FontWeight.bold,
//                                 color: AppTheme.textColor,
//                               ),
//                             ),
//                             SizedBox(height: 4),
//                             Text(
//                               'Duration: $duration • $formattedDate',
//                               style: TextStyle(
//                                 fontSize: 12,
//                                 color: AppTheme.textColor.withOpacity(0.7),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       IconButton(
//                         icon: Icon(
//                           Icons.play_circle_filled,
//                           color: AppTheme.accentColor,
//                           size: 36,
//                         ),
//                         onPressed: () {
//                           Navigator.of(context).push(
//                             MaterialPageRoute(
//                               builder: (context) =>
//                                   RecordingPlayerScreen(
//                                     recordingUrl: recording['url'],
//                                     recordingData: recording,
//                                   ),
//                             ),
//                           );
//                         },
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
// }