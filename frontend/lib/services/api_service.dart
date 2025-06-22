// lib/services/api_service.dart (Updated Version)
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/transcription_result.dart';
import 'platform_service.dart';

class ApiService {
  final Dio _dio = Dio();
  final String baseUrl;
  String get baseUrlPublic => baseUrl;

  ApiService({required this.baseUrl}) {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(minutes: 4);
    _dio.options.receiveTimeout = const Duration(minutes: 5);
    _dio.options.sendTimeout = const Duration(minutes: 4);

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('🚀 API Request: ${options.method} ${options.path}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print('✅ API Response: ${response.statusCode} from ${response.requestOptions.path}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        print('❌ API Error: ${e.message}');
        return handler.next(e);
      },
    ));
  }

  Future<bool> checkServerStatus() async {
    try {
      print('🔍 Checking server health...');
      final response = await _dio.get('/api/health');
      final isHealthy = response.data['status'] == 'ok';
      print('💚 Server status: ${isHealthy ? "OK" : "NOT OK"}');
      return isHealthy;
    } catch (e) {
      print('❌ Server health check failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> checkMuseScoreStatus() async {
    try {
      print('🎼 Checking MuseScore availability...');
      final response = await _dio.get('/api/musescore-status');
      if (response.statusCode == 200) {
        final data = response.data;
        print('🎵 MuseScore available: ${data['available']}');
        return data;
      }
      return null;
    } catch (e) {
      print('❌ MuseScore status check failed: $e');
      return null;
    }
  }

  Future<TranscriptionResult?> transcribeExistingRecording({
    required String userId,
    required String recordingId,
    String title = 'Piano Transcription',
  }) async {
    try {
      print('🤖 Starting transcription for existing recording...');
      print('👤 User ID: $userId');
      print('🆔 Recording ID: $recordingId');
      
      final response = await _dio.post(
        '/recordings/$userId/$recordingId/transcribe',
        data: {
          'title': title,
        },
        options: Options(
          contentType: 'application/json',
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 2),
        ),
      );

      if (response.statusCode == 200) {
        print('✅ Transcription completed successfully');
        
        final data = response.data;
        print('📊 Transcription result:');
        print('  - Success: ${data['success']}');
        print('  - Notes count: ${data['notes']?.length ?? 0}');
        print('  - MIDI file: ${data['midi_file'] ?? 'None'}');
        print('  - Sheet music: ${data['sheet_music'] != null ? 'Available' : 'None'}');
        
        return TranscriptionResult.fromJson(data);
      } else {
        print('❌ Transcription failed: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ Network error during transcription: ${e.type}');
      print('❌ Error message: ${e.message}');
      return null;
    } catch (e) {
      print('❌ Unexpected error during transcription: $e');
      return null;
    }
  }

  Future<TranscriptionResult?> transcribeAudio(String audioFilePath, {
    String sheetFormat = 'pdf',
    String title = 'Piano Transcription',
    int tempo = 120,
    int retryCount = 0,
  }) async {
    try {
      print('🎵 Starting transcription process...');
      print('📂 Audio file: $audioFilePath');
      
      // Your existing transcription code here...
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audioFilePath,
          filename: basename(audioFilePath),
        ),
        'sheet_format': sheetFormat,
        'title': title,
        'tempo': tempo.toString(),
      });

      print('🚀 Sending audio to backend for complete processing...');
      
      final response = await _dio.post(
        '/api/transcribe',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 5),
        ),
      );

      if (response.statusCode == 200) {
        print('✅ Backend processing completed successfully');
        final data = response.data;
        return TranscriptionResult.fromJson(data);
      } else {
        throw Exception('Backend returned error: ${response.statusCode}');
      }
      
    } on DioException catch (e) {
      print('❌ Network error during transcription: ${e.type}');
      print('❌ Error message: ${e.message}');
      
      // If we get a server error that might indicate corruption
      if ((e.response?.statusCode == 500 || e.message?.contains('format') == true) && retryCount < 2) {
        print('🔄 Attempting to reset server state and retry...');
        await _resetServerState();
        
        // Wait a bit then retry
        await Future.delayed(Duration(seconds: 3));
        return transcribeAudio(audioFilePath, 
            sheetFormat: sheetFormat, 
            title: title, 
            tempo: tempo, 
            retryCount: retryCount + 1);
      }
      
      return null;
    } catch (e) {
      print('❌ Unexpected error during transcription: $e');
      return null;
    }
  }

  Future<void> _resetServerState() async {
    try {
      print('🔄 Requesting server state reset...');
      await _dio.post('/api/reset-server-state');
      print('✅ Server state reset successfully');
    } catch (e) {
      print('⚠️ Could not reset server state: $e');
    }
  }

  /// Download MIDI file - works on both web and mobile
  Future<PlatformFile?> downloadMidiFile(String midiUrl, String filename) async {
    try {
      final completeUrl = midiUrl.startsWith('http') ? midiUrl : '$baseUrl$midiUrl';
      
      print('📥 Downloading MIDI from: $completeUrl');
      
      // Download the file bytes
      final response = await _dio.get(
        completeUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 3),
        ),
      );

      if (response.statusCode == 200) {
        final Uint8List fileBytes = Uint8List.fromList(response.data);
        
        // Use platform service to handle the download
        final result = await PlatformService.downloadFile(
          fileBytes: fileBytes,
          fileName: filename,
          mimeType: 'audio/midi',
        );

        if (result != null) {
          print('✅ MIDI file downloaded: ${result.name}');
          if (result.isWebDownload) {
            print('📱 ${result.downloadMessage}');
          }
        }

        return result;
      } else {
        print('❌ Failed to download MIDI: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error downloading MIDI: $e');
      return null;
    }
  }

  /// Convert MIDI to audio for web playback (ADD THIS METHOD)
  Future<String?> convertMidiToAudio({
    required String midiUrl,
    String format = 'mp3',
    int sampleRate = 44100,
    String quality = 'high',
  }) async {
    try {
      print('🎵 Converting MIDI to audio for web playback...');
      
      final response = await _dio.post(
        '/api/convert-midi-audio',
        data: {
          'midi_url': midiUrl,
          'format': format, // mp3, wav, ogg
          'sample_rate': sampleRate,
          'quality': quality, // high, medium, low
        },
        options: Options(
          contentType: 'application/json',
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        print('✅ MIDI to audio conversion completed');
        print('🎵 Audio URL: ${data['audio_url']}');
        print('📊 File size: ${data['file_size']} bytes');
        
        return data['audio_url']; // Returns the converted audio URL
      } else {
        print('❌ MIDI conversion failed: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      print('❌ Network error during MIDI conversion: ${e.type}');
      print('❌ Error message: ${e.message}');
      return null;
    } catch (e) {
      print('❌ Unexpected error during MIDI conversion: $e');
      return null;
    }
  }

  Future<bool> checkMidiConversionSupport() async {
    try {
      final response = await _dio.get('/api/midi-conversion-status');
      if (response.statusCode == 200) {
        final data = response.data;
        print('🔍 MIDI conversion support: ${data['supported']}');
        if (data['supported']) {
          print('🎵 Supported formats: ${data['supported_formats']}');
          print('🔊 Sample rates: ${data['sample_rates']}');
        }
        return data['supported'] == true;
      }
      return false;
    } catch (e) {
      print('⚠️ Could not check MIDI conversion support: $e');
      return false;
    }
  }

  /// Download any file - works on both web and mobile
  Future<PlatformFile?> downloadFile(String fileUrl, String filename) async {
    try {
      final completeUrl = fileUrl.startsWith('http') ? fileUrl : '$baseUrl$fileUrl';
      
      print('📥 Downloading file from: $completeUrl');
      
      // Download the file bytes
      final response = await _dio.get(
        completeUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 3),
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            print('📥 Download progress: $progress%');
          }
        },
      );

      if (response.statusCode == 200) {
        final Uint8List fileBytes = Uint8List.fromList(response.data);
        
        // Determine MIME type from filename
        String mimeType = _getMimeTypeFromFilename(filename);
        
        // Use platform service to handle the download
        final result = await PlatformService.downloadFile(
          fileBytes: fileBytes,
          fileName: filename,
          mimeType: mimeType,
        );

        if (result != null) {
          print('✅ File downloaded: ${result.name}');
          if (result.isWebDownload) {
            print('📱 ${result.downloadMessage}');
          }
        }

        return result;
      } else {
        print('❌ Failed to download file: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error downloading file: $e');
      return null;
    }
  }

  /// Download sheet music - works on both web and mobile
  Future<PlatformFile?> downloadSheetMusic(String fileUrl, String fileName) async {
    try {
      final completeUrl = fileUrl.startsWith('http') ? fileUrl : '$baseUrl$fileUrl';
      
      print('📄 Downloading sheet music from: $completeUrl');
      
      final response = await _dio.get(
        completeUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 3),
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            print('📄 Download progress: $progress%');
          }
        },
      );

      if (response.statusCode == 200) {
        final Uint8List fileBytes = Uint8List.fromList(response.data);
        
        // Use platform service to handle the download
        final result = await PlatformService.downloadFile(
          fileBytes: fileBytes,
          fileName: fileName,
          mimeType: 'application/pdf',
        );

        if (result != null) {
          print('✅ Sheet music downloaded: ${result.name}');
          if (result.isWebDownload) {
            print('📱 ${result.downloadMessage}');
          } else {
            print('📱 Saved to: ${result.path}');
          }
        }

        return result;
      } else {
        print('❌ Failed to download sheet music: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error downloading sheet music: $e');
      rethrow;
    }
  }

  /// Get MIME type from filename extension
  String _getMimeTypeFromFilename(String filename) {
    final extension = filename.toLowerCase().split('.').last;
    
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'mid':
      case 'midi':
        return 'audio/midi';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Future<Map<String, dynamic>?> convertMidiToSheet({
    required String midiFilePath,
    String format = 'pdf',
    String title = 'Piano Sheet Music',
  }) async {
    try {
      print('🎼 Converting MIDI to sheet music...');
      
      final formData = FormData.fromMap({
        'midi': await MultipartFile.fromFile(
          midiFilePath,
          filename: basename(midiFilePath),
        ),
        'format': format,
        'title': title,
      });

      final response = await _dio.post(
        '/api/convert-midi-to-sheet',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      if (response.statusCode == 200) {
        print('✅ MIDI to sheet conversion completed');
        return response.data;
      } else {
        print('❌ Conversion failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error converting MIDI to sheet: $e');
      return null;
    }
  }
}

// import 'dart:io';
// import 'package:dio/dio.dart';
// import 'package:path/path.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';
// import '../models/transcription_result.dart';

// class ApiService {
//   final Dio _dio = Dio();
//   final String baseUrl;

//   ApiService({required this.baseUrl}) {
//     _dio.options.baseUrl = baseUrl;
//     _dio.options.connectTimeout = const Duration(minutes: 4);
//     _dio.options.receiveTimeout = const Duration(minutes: 5);
//     _dio.options.sendTimeout = const Duration(minutes: 4);

//     _dio.interceptors.add(InterceptorsWrapper(
//       onRequest: (options, handler) {
//         print('🚀 API Request: ${options.method} ${options.path}');
//         return handler.next(options);
//       },
//       onResponse: (response, handler) {
//         print('✅ API Response: ${response.statusCode} from ${response.requestOptions.path}');
//         return handler.next(response);
//       },
//       onError: (DioException e, handler) {
//         print('❌ API Error: ${e.message}');
//         return handler.next(e);
//       },
//     ));
//   }

//   Future<bool> checkServerStatus() async {
//     try {
//       print('🔍 Checking server health...');
//       final response = await _dio.get('/api/health');
//       final isHealthy = response.data['status'] == 'ok';
//       print('💚 Server status: ${isHealthy ? "OK" : "NOT OK"}');
//       return isHealthy;
//     } catch (e) {
//       print('❌ Server health check failed: $e');
//       return false;
//     }
//   }

//   Future<Map<String, dynamic>?> checkMuseScoreStatus() async {
//     try {
//       print('🎼 Checking MuseScore availability...');
//       final response = await _dio.get('/api/musescore-status');
//       if (response.statusCode == 200) {
//         final data = response.data;
//         print('🎵 MuseScore available: ${data['available']}');
//         return data;
//       }
//       return null;
//     } catch (e) {
//       print('❌ MuseScore status check failed: $e');
//       return null;
//     }
//   }

//   Future<TranscriptionResult?> transcribeExistingRecording({
//     required String userId,
//     required String recordingId,
//     String title = 'Piano Transcription',
//   }) async {
//     try {
//       print('🤖 Starting transcription for existing recording...');
//       print('👤 User ID: $userId');
//       print('🆔 Recording ID: $recordingId');
      
//       final response = await _dio.post(
//         '/recordings/$userId/$recordingId/transcribe',
//         data: {
//           'title': title,
//         },
//         options: Options(
//           contentType: 'application/json',
//           receiveTimeout: const Duration(minutes: 10),
//           sendTimeout: const Duration(minutes: 2),
//         ),
//       );

//       if (response.statusCode == 200) {
//         print('✅ Transcription completed successfully');
        
//         final data = response.data;
//         print('📊 Transcription result:');
//         print('  - Success: ${data['success']}');
//         print('  - Notes count: ${data['notes']?.length ?? 0}');
//         print('  - MIDI file: ${data['midi_file'] ?? 'None'}');
//         print('  - Sheet music: ${data['sheet_music'] != null ? 'Available' : 'None'}');
        
//         return TranscriptionResult.fromJson(data);
//       } else {
//         print('❌ Transcription failed: ${response.statusCode}');
//         return null;
//       }
//     } on DioException catch (e) {
//       print('❌ Network error during transcription: ${e.type}');
//       print('❌ Error message: ${e.message}');
//       return null;
//     } catch (e) {
//       print('❌ Unexpected error during transcription: $e');
//       return null;
//     }
//   }

//   Future<TranscriptionResult?> transcribeAudio(String audioFilePath, {
//     String sheetFormat = 'pdf',
//     String title = 'Piano Transcription',
//     int tempo = 120,
//   }) async {
//     try {
//       print('🎵 Starting transcription process...');
//       print('📂 Audio file: $audioFilePath');
      
//       final file = File(audioFilePath);
//       if (!await file.exists()) {
//         print('❌ Audio file does not exist');
//         return null;
//       }
      
//       final fileSize = await file.length();
//       print('📊 File size: ${fileSize} bytes');
      
//       final formData = FormData.fromMap({
//         'audio': await MultipartFile.fromFile(
//           audioFilePath,
//           filename: basename(audioFilePath),
//         ),
//         'sheet_format': sheetFormat,
//         'title': title,
//         'tempo': tempo.toString(),
//       });

//       print('🚀 Sending audio to backend for complete processing...');
      
//       // Send to backend:
//       // 1. Load audio
//       // 2. Extract features  
//       // 3. Run AI model prediction
//       // 4. Extract notes from predictions
//       // 5. Generate MIDI file
//       // 6. Generate sheet music (if MuseScore available)
//       // 7. Return complete results
//       final response = await _dio.post(
//         '/api/transcribe',
//         data: formData,
//         options: Options(
//           contentType: 'multipart/form-data',
//           receiveTimeout: const Duration(minutes: 10),
//           sendTimeout: const Duration(minutes: 5),
//         ),
//       );

//       if (response.statusCode == 200) {
//         print('✅ Backend processing completed successfully');
        
//         final data = response.data;
//         print('📊 Received from backend:');
//         print('  - Success: ${data['success']}');
//         print('  - Notes count: ${data['notes']?.length ?? 0}');
//         print('  - MIDI file: ${data['midi_file'] ?? 'None'}');
//         print('  - Sheet music: ${data['sheet_music'] != null ? 'Included' : 'None'}');
//         print('  - MuseScore available: ${data['musescore_available'] ?? false}');
        
//         return TranscriptionResult.fromJson(data);
//       } else {
//         print('❌ Backend returned error: ${response.statusCode}');
//         print('❌ Error details: ${response.data}');
//         return null;
//       }
//     } on DioException catch (e) {
//       print('❌ Network error during transcription: ${e.type}');
//       print('❌ Error message: ${e.message}');
//       if (e.response != null) {
//         print('❌ Response status: ${e.response?.statusCode}');
//         print('❌ Response data: ${e.response?.data}');
//       }
//       return null;
//     } catch (e) {
//       print('❌ Unexpected error during transcription: $e');
//       return null;
//     }
//   }

//   Future<File?> downloadMidiFile(String midiUrl, String filename) async {
//     try {
//       final completeUrl = midiUrl.startsWith('http') ? midiUrl : '$baseUrl$midiUrl';
      
//       print('📥 Downloading MIDI from: $completeUrl');
      
//       final directory = await getApplicationDocumentsDirectory();
//       final filePath = '${directory.path}/$filename';

//       await _dio.download(completeUrl, filePath);

//       print('✅ MIDI file saved: $filePath');
//       return File(filePath);
//     } catch (e) {
//       print('❌ Error downloading MIDI: $e');
//       return null;
//     }
//   }

//   Future<File?> downloadFile(String fileUrl, String filename) async {
//     try {
//       final completeUrl = fileUrl.startsWith('http') ? fileUrl : '$baseUrl$fileUrl';
      
//       print('📥 Downloading file from: $completeUrl');
      
//       final directory = await getApplicationDocumentsDirectory();
//       final filePath = '${directory.path}/$filename';

//       await _dio.download(
//         completeUrl, 
//         filePath,
//         onReceiveProgress: (received, total) {
//           if (total != -1) {
//             final progress = (received / total * 100).toStringAsFixed(0);
//             print('📥 Download progress: $progress%');
//           }
//         },
//       );

//       print('✅ File saved: $filePath');
//       return File(filePath);
//     } catch (e) {
//       print('❌ Error downloading file: $e');
//       return null;
//     }
//   }

//   Future<File?> downloadSheetMusic(String fileUrl, String fileName) async {
//     try {
//       final completeUrl = fileUrl.startsWith('http') ? fileUrl : '$baseUrl$fileUrl';
      
//       print('📄 Downloading sheet music from: $completeUrl');
      
//       final directory = await getApplicationDocumentsDirectory();
//       final filePath = '${directory.path}/$fileName';
      
//       print('📄 Saving to app directory: $filePath');
      
//       await _dio.download(
//         completeUrl,
//         filePath,
//         options: Options(
//           receiveTimeout: const Duration(minutes: 3),
//         ),
//         onReceiveProgress: (received, total) {
//           if (total != -1) {
//             final progress = (received / total * 100).toStringAsFixed(0);
//             print('📄 Download progress: $progress%');
//           }
//         },
//       );

//       final file = File(filePath);
//       if (await file.exists()) {
//         final fileSize = await file.length();
//         print('✅ Sheet music downloaded to app storage: $fileSize bytes');
//         return file;
//       } else {
//         throw Exception('Downloaded file does not exist');
//       }
//     } catch (e) {
//       print('❌ Error downloading sheet music: $e');
//       rethrow;
//     }
//   }

//   Future<Map<String, dynamic>?> convertMidiToSheet({
//     required String midiFilePath,
//     String format = 'pdf',
//     String title = 'Piano Sheet Music',
//   }) async {
//     try {
//       print('🎼 Converting MIDI to sheet music...');
      
//       final formData = FormData.fromMap({
//         'midi': await MultipartFile.fromFile(
//           midiFilePath,
//           filename: basename(midiFilePath),
//         ),
//         'format': format,
//         'title': title,
//       });

//       final response = await _dio.post(
//         '/api/convert-midi-to-sheet',
//         data: formData,
//         options: Options(
//           contentType: 'multipart/form-data',
//           receiveTimeout: const Duration(minutes: 5),
//         ),
//       );

//       if (response.statusCode == 200) {
//         print('✅ MIDI to sheet conversion completed');
//         return response.data;
//       } else {
//         print('❌ Conversion failed: ${response.statusCode}');
//         return null;
//       }
//     } catch (e) {
//       print('❌ Error converting MIDI to sheet: $e');
//       return null;
//     }
//   }
// }