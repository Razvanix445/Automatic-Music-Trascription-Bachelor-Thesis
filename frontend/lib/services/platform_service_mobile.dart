// lib/services/platform_service_mobile.dart (Mobile Implementation)
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'platform_service.dart'; // Import main file for shared types

/// Mobile-specific implementation of platform services
/// This file is used when running on iOS/Android

/// Get a directory path for storing files on mobile
Future<String> getStorageDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
}

/// Download file on mobile (saves to app directory)
Future<PlatformFile?> downloadFile({
  required Uint8List fileBytes,
  required String fileName,
  required String mimeType,
}) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    
    await file.writeAsBytes(fileBytes);
    
    print('✅ Mobile file saved: $filePath');
    
    // Return the shared PlatformFile type from main file
    return PlatformFile(
      path: filePath,
      name: fileName,
      size: fileBytes.length,
    );
  } catch (e) {
    print('❌ Mobile download error: $e');
    return null;
  }
}

/// Check if a file exists on mobile
Future<bool> fileExists(String filePath) async {
  return File(filePath).exists();
}

/// Get file size on mobile
Future<int> getFileSize(String filePath) async {
  try {
    final file = File(filePath);
    return await file.length();
  } catch (e) {
    return 0;
  }
}

/// Open file externally on mobile
Future<bool> openFile(String filePath) async {
  try {
    // On mobile, you might want to use open_file package here
    print('Opening file: $filePath');
    return true;
  } catch (e) {
    print('Error opening file: $e');
    return false;
  }
}