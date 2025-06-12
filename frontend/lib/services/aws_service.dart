import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'auth_service.dart';

class AwsService {
  final String _baseUrl = 'https://razvanix-wave2notes.hf.space';
  // final String _baseUrl = 'http://192.168.100.36:5000';
  // final String _baseUrl = 'http://172.30.250.117:5000';
  final AuthService _authService = AuthService();

  // Enhanced method to upload multiple files (audio + optional image, PDF, MIDI)
  Future<Map<String, dynamic>> uploadRecordingWithFiles({
    required Map<String, File> files,  // Map of file type to file
    required String title,
    String description = '',
  }) async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated - please log in again');
      }

      // Validate that audio file is provided (required)
      if (!files.containsKey('audio') || files['audio'] == null) {
        throw Exception('Audio file is required');
      }

      print('📤 Starting enhanced upload for user: $userId');
      print('📝 Title: $title');
      print('📂 Files to upload: ${files.keys.join(', ')}');

      // Check all files exist and get their sizes
      for (String fileType in files.keys) {
        File file = files[fileType]!;
        if (!await file.exists()) {
          throw Exception('$fileType file no longer exists');
        }
        
        final fileSize = await file.length();
        print('📊 $fileType file size: $fileSize bytes');
        
        if (fileSize == 0) {
          throw Exception('$fileType file is empty');
        }
      }

      // Create multipart request
      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'));

      // Add form fields
      request.fields['userId'] = userId;
      request.fields['title'] = title;
      request.fields['description'] = description;

      // Add all files to the request
      for (String fileType in files.keys) {
        File file = files[fileType]!;
        String fileName = file.path.split('/').last;
        var fileStream = http.ByteStream(file.openRead());
        final fileSize = await file.length();

        var multipartFile = http.MultipartFile(
          '${fileType}_file',  // Field name: audio_file, image_file, pdf_file, midi_file
          fileStream,
          fileSize,
          filename: fileName,
          contentType: MediaType(_getMainMimeType(fileType), _getSubMimeType(fileName, fileType)),
        );

        request.files.add(multipartFile);
        print('📎 Added $fileType file: $fileName');
      }

      print('🚀 Sending enhanced upload request...');

      // Send request with extended timeout for multiple files
      var response = await request.send().timeout(
        Duration(minutes: 10),  // Longer timeout for multiple files
        onTimeout: () {
          throw Exception('Upload timeout - files may be too large');
        },
      );

      var responseData = await response.stream.bytesToString();
      
      print('📡 Upload response status: ${response.statusCode}');
      print('📄 Upload response data: $responseData');

      if (response.statusCode == 200) {
        final result = json.decode(responseData);
        print('✅ Enhanced upload successful');
        print('🆔 Recording ID: ${result['recording_id']}');
        print('📁 Uploaded files: ${result['files']?.keys?.join(', ')}');
        return result;
      } else {
        final error = json.decode(responseData);
        final errorMessage = error['error'] ?? 'Upload failed';
        print('❌ Upload error: $errorMessage');
        throw Exception('Upload failed: $errorMessage');
      }
    } catch (e) {
      print('❌ Error uploading recording with files: $e');
      rethrow;
    }
  }

  // Backward compatibility: Keep the old single-file upload method
  Future<Map<String, dynamic>> uploadRecording(File file, String title, {String description = ''}) async {
    return uploadRecordingWithFiles(
      files: {'audio': file},
      title: title,
      description: description,
    );
  }

  // Enhanced method to get recordings with all their files
  Future<List<Map<String, dynamic>>> getUserRecordings() async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated - please log in again');
      }

      print('🔍 Fetching enhanced recordings for user: $userId');
      print('🌐 Using base URL: $_baseUrl');

      final response = await http.get(
        Uri.parse('$_baseUrl/recordings/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout - server took too long to respond');
        },
      );

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseBody = response.body;
        print('📝 Response body length: ${responseBody.length}');
        
        if (responseBody.isEmpty) {
          print('⚠️ Empty response body');
          return [];
        }

        final result = json.decode(responseBody);
        print('✅ Decoded JSON successfully');
        
        if (result['recordings'] != null) {
          final recordings = List<Map<String, dynamic>>.from(result['recordings']);
          print('🎵 Found ${recordings.length} enhanced recordings');
          
          // Log sample recording structure for debugging
          if (recordings.isNotEmpty) {
            final sample = recordings[0];
            print('📋 Sample recording structure:');
            print('   - ID: ${sample['recording_id']}');
            print('   - Title: ${sample['title']}');
            print('   - Has Image: ${sample['has_image']}');
            print('   - Has PDF: ${sample['has_pdf']}');
            print('   - Has MIDI: ${sample['has_midi']}');
            print('   - Files: ${sample['files']?.keys?.join(', ')}');
          }
          
          return recordings;
        } else {
          print('⚠️ No recordings field in response');
          return [];
        }
      } else if (response.statusCode == 404) {
        print('👤 User has no recordings yet');
        return [];
      } else {
        final error = json.decode(response.body);
        final errorMessage = error['error'] ?? 'Unknown server error';
        print('❌ Server error: $errorMessage');
        throw Exception('Server error (${response.statusCode}): $errorMessage');
      }
    } on http.ClientException catch (e) {
      print('❌ Network error: $e');
      throw Exception('Network error: Please check your internet connection');
    } on FormatException catch (e) {
      print('❌ JSON parsing error: $e');
      throw Exception('Invalid server response format');
    } on Exception catch (e) {
      print('❌ Error getting recordings: $e');
      rethrow;
    } catch (e) {
      print('❌ Unexpected error: $e');
      throw Exception('Unexpected error: $e');
    }
  }

  // Get URL for a specific file type of a recording
  String getFileUrl(Map<String, dynamic> recording, String fileType) {
    try {
      final files = recording['files'] as Map<String, dynamic>?;
      if (files != null && files.containsKey(fileType)) {
        final fileInfo = files[fileType] as Map<String, dynamic>?;
        return fileInfo?['url'] ?? '';
      }
      return '';
    } catch (e) {
      print('❌ Error getting $fileType URL: $e');
      return '';
    }
  }

  // Check if a recording has a specific file type
  bool hasFileType(Map<String, dynamic> recording, String fileType) {
    return recording['has_$fileType'] == true || 
           getFileUrl(recording, fileType).isNotEmpty;
  }

  // Update recording metadata only (without re-uploading audio file)
  Future<Map<String, dynamic>> updateRecordingMetadata({
    required String recordingId,
    required String title,
    String description = '',
    File? newImageFile,
  }) async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated - please log in again');
      }

      print('📝 Updating recording metadata for: $recordingId');
      print('🏷️ New title: $title');

      // Create multipart request for metadata update
      var request = http.MultipartRequest('PUT', Uri.parse('$_baseUrl/recordings/$recordingId'));

      // Add form fields
      request.fields['userId'] = userId;
      request.fields['title'] = title;
      request.fields['description'] = description;

      // Add new image file if provided
      if (newImageFile != null) {
        String fileName = newImageFile.path.split('/').last;
        var fileStream = http.ByteStream(newImageFile.openRead());
        final fileSize = await newImageFile.length();

        var multipartFile = http.MultipartFile(
          'image_file',
          fileStream,
          fileSize,
          filename: fileName,
          contentType: MediaType('image', _getSubMimeType(fileName, 'image')),
        );

        request.files.add(multipartFile);
        print('🖼️ Adding new image file: $fileName');
      }

      print('🚀 Sending metadata update request...');

      // Send request with timeout
      var response = await request.send().timeout(
        Duration(minutes: 3),
        onTimeout: () {
          throw Exception('Update timeout - server took too long to respond');
        },
      );

      var responseData = await response.stream.bytesToString();
      
      print('📡 Update response status: ${response.statusCode}');
      print('📄 Update response data: $responseData');

      if (response.statusCode == 200) {
        final result = json.decode(responseData);
        print('✅ Recording metadata updated successfully');
        return result;
      } else {
        final error = json.decode(responseData);
        final errorMessage = error['error'] ?? 'Update failed';
        print('❌ Update error: $errorMessage');
        throw Exception('Update failed: $errorMessage');
      }
    } catch (e) {
      print('❌ Error updating recording metadata: $e');
      rethrow;
    }
  }

  // Get streaming URL for audio playback (backward compatibility)
  String getStreamUrl(String recordingKey) {
    return '$_baseUrl/stream/$recordingKey';
  }

  // Helper method to determine main MIME type based on file type
  String _getMainMimeType(String fileType) {
    switch (fileType) {
      case 'audio':
        return 'audio';
      case 'image':
        return 'image';
      case 'pdf':
        return 'application';
      case 'midi':
        return 'audio';
      default:
        return 'application';
    }
  }

  // Helper method to determine sub MIME type based on file extension and type
  String _getSubMimeType(String fileName, String fileType) {
    final extension = fileName.toLowerCase().split('.').last;
    
    switch (fileType) {
      case 'audio':
        return _getAudioMimeType(fileName);
      case 'image':
        switch (extension) {
          case 'jpg':
          case 'jpeg':
            return 'jpeg';
          case 'png':
            return 'png';
          case 'gif':
            return 'gif';
          case 'webp':
            return 'webp';
          default:
            return 'jpeg';
        }
      case 'pdf':
        return 'pdf';
      case 'midi':
        return 'midi';
      default:
        return 'octet-stream';
    }
  }

  // Original audio MIME type helper (maintained for compatibility)
  String _getAudioMimeType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'mp3':
        return 'mpeg';
      case 'wav':
        return 'wav';
      case 'm4a':
        return 'mp4';
      case 'aac':
        return 'aac';
      case 'ogg':
        return 'ogg';
      case 'flac':
        return 'flac';
      default:
        return 'mpeg'; // Default fallback
    }
  }
}



// import 'dart:io';
// import 'package:http/http.dart' as http;
// import 'package:http_parser/http_parser.dart';
// import 'dart:convert';
// import 'auth_service.dart';

// class AwsService {
//   final String _baseUrl = 'https://razvanix-wave2notes.hf.space';
//   // final String _baseUrl = 'http://192.168.100.36:5000';
//   // final String _baseUrl = 'http://172.30.250.117:5000';
//   final AuthService _authService = AuthService();

//   // Enhanced method to upload multiple files (audio + optional image, PDF, MIDI)
//   Future<Map<String, dynamic>> uploadRecordingWithFiles({
//     required Map<String, File> files,  // Map of file type to file
//     required String title,
//     String description = '',
//   }) async {
//     try {
//       final userId = _authService.currentUser?.uid;
//       if (userId == null) {
//         throw Exception('User not authenticated - please log in again');
//       }

//       // Validate that audio file is provided (required)
//       if (!files.containsKey('audio') || files['audio'] == null) {
//         throw Exception('Audio file is required');
//       }

//       print('📤 Starting enhanced upload for user: $userId');
//       print('📝 Title: $title');
//       print('📂 Files to upload: ${files.keys.join(', ')}');

//       // Check all files exist and get their sizes
//       for (String fileType in files.keys) {
//         File file = files[fileType]!;
//         if (!await file.exists()) {
//           throw Exception('$fileType file no longer exists');
//         }
        
//         final fileSize = await file.length();
//         print('📊 $fileType file size: $fileSize bytes');
        
//         if (fileSize == 0) {
//           throw Exception('$fileType file is empty');
//         }
//       }

//       // Create multipart request
//       var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'));

//       // Add form fields
//       request.fields['userId'] = userId;
//       request.fields['title'] = title;
//       request.fields['description'] = description;

//       // Add all files to the request
//       for (String fileType in files.keys) {
//         File file = files[fileType]!;
//         String fileName = file.path.split('/').last;
//         var fileStream = http.ByteStream(file.openRead());
//         final fileSize = await file.length();

//         var multipartFile = http.MultipartFile(
//           '${fileType}_file',  // Field name: audio_file, image_file, pdf_file, midi_file
//           fileStream,
//           fileSize,
//           filename: fileName,
//           contentType: MediaType(_getMainMimeType(fileType), _getSubMimeType(fileName, fileType)),
//         );

//         request.files.add(multipartFile);
//         print('📎 Added $fileType file: $fileName');
//       }

//       print('🚀 Sending enhanced upload request...');

//       // Send request with extended timeout for multiple files
//       var response = await request.send().timeout(
//         Duration(minutes: 10),  // Longer timeout for multiple files
//         onTimeout: () {
//           throw Exception('Upload timeout - files may be too large');
//         },
//       );

//       var responseData = await response.stream.bytesToString();
      
//       print('📡 Upload response status: ${response.statusCode}');
//       print('📄 Upload response data: $responseData');

//       if (response.statusCode == 200) {
//         final result = json.decode(responseData);
//         print('✅ Enhanced upload successful');
//         print('🆔 Recording ID: ${result['recording_id']}');
//         print('📁 Uploaded files: ${result['files']?.keys?.join(', ')}');
//         return result;
//       } else {
//         final error = json.decode(responseData);
//         final errorMessage = error['error'] ?? 'Upload failed';
//         print('❌ Upload error: $errorMessage');
//         throw Exception('Upload failed: $errorMessage');
//       }
//     } catch (e) {
//       print('❌ Error uploading recording with files: $e');
//       rethrow;
//     }
//   }

//   // Backward compatibility: Keep the old single-file upload method
//   Future<Map<String, dynamic>> uploadRecording(File file, String title, {String description = ''}) async {
//     return uploadRecordingWithFiles(
//       files: {'audio': file},
//       title: title,
//       description: description,
//     );
//   }

//   // Enhanced method to get recordings with all their files
//   Future<List<Map<String, dynamic>>> getUserRecordings() async {
//     try {
//       final userId = _authService.currentUser?.uid;
//       if (userId == null) {
//         throw Exception('User not authenticated - please log in again');
//       }

//       print('🔍 Fetching enhanced recordings for user: $userId');
//       print('🌐 Using base URL: $_baseUrl');

//       final response = await http.get(
//         Uri.parse('$_baseUrl/recordings/$userId'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Accept': 'application/json',
//         },
//       ).timeout(
//         Duration(seconds: 30),
//         onTimeout: () {
//           throw Exception('Request timeout - server took too long to respond');
//         },
//       );

//       print('📡 Response status: ${response.statusCode}');

//       if (response.statusCode == 200) {
//         final responseBody = response.body;
//         print('📝 Response body length: ${responseBody.length}');
        
//         if (responseBody.isEmpty) {
//           print('⚠️ Empty response body');
//           return [];
//         }

//         final result = json.decode(responseBody);
//         print('✅ Decoded JSON successfully');
        
//         if (result['recordings'] != null) {
//           final recordings = List<Map<String, dynamic>>.from(result['recordings']);
//           print('🎵 Found ${recordings.length} enhanced recordings');
          
//           // Log sample recording structure for debugging
//           if (recordings.isNotEmpty) {
//             final sample = recordings[0];
//             print('📋 Sample recording structure:');
//             print('   - ID: ${sample['recording_id']}');
//             print('   - Title: ${sample['title']}');
//             print('   - Has Image: ${sample['has_image']}');
//             print('   - Has PDF: ${sample['has_pdf']}');
//             print('   - Has MIDI: ${sample['has_midi']}');
//             print('   - Files: ${sample['files']?.keys?.join(', ')}');
//           }
          
//           return recordings;
//         } else {
//           print('⚠️ No recordings field in response');
//           return [];
//         }
//       } else if (response.statusCode == 404) {
//         print('👤 User has no recordings yet');
//         return [];
//       } else {
//         final error = json.decode(response.body);
//         final errorMessage = error['error'] ?? 'Unknown server error';
//         print('❌ Server error: $errorMessage');
//         throw Exception('Server error (${response.statusCode}): $errorMessage');
//       }
//     } on http.ClientException catch (e) {
//       print('❌ Network error: $e');
//       throw Exception('Network error: Please check your internet connection');
//     } on FormatException catch (e) {
//       print('❌ JSON parsing error: $e');
//       throw Exception('Invalid server response format');
//     } on Exception catch (e) {
//       print('❌ Error getting recordings: $e');
//       rethrow;
//     } catch (e) {
//       print('❌ Unexpected error: $e');
//       throw Exception('Unexpected error: $e');
//     }
//   }

//   // Get URL for a specific file type of a recording
//   String getFileUrl(Map<String, dynamic> recording, String fileType) {
//     try {
//       final files = recording['files'] as Map<String, dynamic>?;
//       if (files != null && files.containsKey(fileType)) {
//         final fileInfo = files[fileType] as Map<String, dynamic>?;
//         return fileInfo?['url'] ?? '';
//       }
//       return '';
//     } catch (e) {
//       print('❌ Error getting $fileType URL: $e');
//       return '';
//     }
//   }

//   // Check if a recording has a specific file type
//   bool hasFileType(Map<String, dynamic> recording, String fileType) {
//     return recording['has_$fileType'] == true || 
//            getFileUrl(recording, fileType).isNotEmpty;
//   }

//   // Get streaming URL for audio playback (backward compatibility)
//   String getStreamUrl(String recordingKey) {
//     return '$_baseUrl/stream/$recordingKey';
//   }

//   // Helper method to determine main MIME type based on file type
//   String _getMainMimeType(String fileType) {
//     switch (fileType) {
//       case 'audio':
//         return 'audio';
//       case 'image':
//         return 'image';
//       case 'pdf':
//         return 'application';
//       case 'midi':
//         return 'audio';
//       default:
//         return 'application';
//     }
//   }

//   // Helper method to determine sub MIME type based on file extension and type
//   String _getSubMimeType(String fileName, String fileType) {
//     final extension = fileName.toLowerCase().split('.').last;
    
//     switch (fileType) {
//       case 'audio':
//         return _getAudioMimeType(fileName);
//       case 'image':
//         switch (extension) {
//           case 'jpg':
//           case 'jpeg':
//             return 'jpeg';
//           case 'png':
//             return 'png';
//           case 'gif':
//             return 'gif';
//           case 'webp':
//             return 'webp';
//           default:
//             return 'jpeg';
//         }
//       case 'pdf':
//         return 'pdf';
//       case 'midi':
//         return 'midi';
//       default:
//         return 'octet-stream';
//     }
//   }

//   // Original audio MIME type helper (maintained for compatibility)
//   String _getAudioMimeType(String fileName) {
//     final extension = fileName.toLowerCase().split('.').last;
//     switch (extension) {
//       case 'mp3':
//         return 'mpeg';
//       case 'wav':
//         return 'wav';
//       case 'm4a':
//         return 'mp4';
//       case 'aac':
//         return 'aac';
//       case 'ogg':
//         return 'ogg';
//       case 'flac':
//         return 'flac';
//       default:
//         return 'mpeg'; // Default fallback
//     }
//   }
// }


// // import 'dart:io';
// // import 'package:http/http.dart' as http;
// // import 'package:http_parser/http_parser.dart';
// // import 'dart:convert';
// // import 'auth_service.dart';

// // class AwsService {
// //   final String _baseUrl = 'https://razvanix-wave2notes.hf.space';
// //   // final String _baseUrl = 'http://192.168.100.36:5000';
// //   // final String _baseUrl = 'http://172.30.250.117:5000';
// //   final AuthService _authService = AuthService();

// //   // Încarcă înregistrarea la backend, care o va stoca în AWS S3
// //   Future<Map<String, dynamic>> uploadRecording(File file, String title, {String description = ''}) async {
// //     try {
// //       final userId = _authService.currentUser?.uid;
// //       if (userId == null) {
// //         throw Exception('User not authenticated - please log in again');
// //       }

// //       print('📤 Starting upload for user: $userId');
// //       print('📂 File: ${file.path}');
// //       print('📝 Title: $title');

// //       // Check if file exists
// //       if (!await file.exists()) {
// //         throw Exception('Selected file no longer exists');
// //       }

// //       final fileSize = await file.length();
// //       print('📊 File size: ${fileSize} bytes');

// //       if (fileSize == 0) {
// //         throw Exception('File is empty');
// //       }

// //       // Create multipart request
// //       var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'));

// //       // Add file
// //       String fileName = file.path.split('/').last;
// //       var fileStream = http.ByteStream(file.openRead());

// //       var multipartFile = http.MultipartFile(
// //         'file',
// //         fileStream,
// //         fileSize,
// //         filename: fileName,
// //         contentType: MediaType('audio', _getAudioMimeType(fileName)),
// //       );

// //       // Add form fields
// //       request.files.add(multipartFile);
// //       request.fields['userId'] = userId;
// //       request.fields['title'] = title;
// //       request.fields['description'] = description;

// //       print('🚀 Sending upload request...');

// //       // Send request with timeout
// //       var response = await request.send().timeout(
// //         Duration(minutes: 5),
// //         onTimeout: () {
// //           throw Exception('Upload timeout - file may be too large');
// //         },
// //       );

// //       var responseData = await response.stream.bytesToString();
      
// //       print('📡 Upload response status: ${response.statusCode}');
// //       print('📄 Upload response data: $responseData');

// //       if (response.statusCode == 200) {
// //         final result = json.decode(responseData);
// //         print('✅ Upload successful');
// //         return result;
// //       } else {
// //         final error = json.decode(responseData);
// //         final errorMessage = error['error'] ?? 'Upload failed';
// //         print('❌ Upload error: $errorMessage');
// //         throw Exception('Upload failed: $errorMessage');
// //       }
// //     } catch (e) {
// //       print('❌ Error uploading to AWS: $e');
// //       rethrow;
// //     }
// //   }

// //   // Obține toate înregistrările unui utilizator
// //   Future<List<Map<String, dynamic>>> getUserRecordings() async {
// //     try {
// //       final userId = _authService.currentUser?.uid;
// //       if (userId == null) {
// //         throw Exception('User not authenticated - please log in again');
// //       }

// //       print('🔍 Fetching recordings for user: $userId');
// //       print('🌐 Using base URL: $_baseUrl');

// //       final response = await http.get(
// //         Uri.parse('$_baseUrl/recordings/$userId'),
// //         headers: {
// //           'Content-Type': 'application/json',
// //           'Accept': 'application/json',
// //         },
// //       ).timeout(
// //         Duration(seconds: 30),
// //         onTimeout: () {
// //           throw Exception('Request timeout - server took too long to respond');
// //         },
// //       );

// //       print('📡 Response status: ${response.statusCode}');
// //       print('📄 Response headers: ${response.headers}');

// //       if (response.statusCode == 200) {
// //         final responseBody = response.body;
// //         print('📝 Response body length: ${responseBody.length}');
        
// //         if (responseBody.isEmpty) {
// //           print('⚠️ Empty response body');
// //           return [];
// //         }

// //         final result = json.decode(responseBody);
// //         print('✅ Decoded JSON successfully');
// //         print('📊 Response keys: ${result.keys.toList()}');
        
// //         if (result['recordings'] != null) {
// //           final recordings = List<Map<String, dynamic>>.from(result['recordings']);
// //           print('🎵 Found ${recordings.length} recordings');
          
// //           // Log first recording structure for debugging
// //           if (recordings.isNotEmpty) {
// //             print('📋 Sample recording structure: ${recordings[0].keys.toList()}');
// //           }
          
// //           return recordings;
// //         } else {
// //           print('⚠️ No recordings field in response');
// //           return [];
// //         }
// //       } else if (response.statusCode == 404) {
// //         print('👤 User has no recordings yet');
// //         return [];
// //       } else {
// //         final error = json.decode(response.body);
// //         final errorMessage = error['error'] ?? 'Unknown server error';
// //         print('❌ Server error: $errorMessage');
// //         throw Exception('Server error (${response.statusCode}): $errorMessage');
// //       }
// //     } on http.ClientException catch (e) {
// //       print('❌ Network error: $e');
// //       throw Exception('Network error: Please check your internet connection');
// //     } on FormatException catch (e) {
// //       print('❌ JSON parsing error: $e');
// //       throw Exception('Invalid server response format');
// //     } on Exception catch (e) {
// //       print('❌ Error getting recordings: $e');
// //       rethrow; // Re-throw the exception to maintain the original error message
// //     } catch (e) {
// //       print('❌ Unexpected error: $e');
// //       throw Exception('Unexpected error: $e');
// //     }
// //   }

// //   // Metoda pentru a juca o înregistrare directă din S3
// //   String getStreamUrl(String recordingKey) {
// //     return '$_baseUrl/stream/$recordingKey';
// //   }

// //   String _getAudioMimeType(String fileName) {
// //     final extension = fileName.toLowerCase().split('.').last;
// //     switch (extension) {
// //       case 'mp3':
// //         return 'mpeg';
// //       case 'wav':
// //         return 'wav';
// //       case 'm4a':
// //         return 'mp4';
// //       case 'aac':
// //         return 'aac';
// //       case 'ogg':
// //         return 'ogg';
// //       default:
// //         return 'mpeg'; // Default fallback
// //     }
// //   }
// // }