// lib/services/platform_service.dart (Main File)
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// Conditional imports - this is the correct syntax!
import 'platform_service_mobile.dart' if (dart.library.html) 'platform_service_web.dart' as platform_impl;

/// A service that handles platform-specific operations
/// Works on both mobile (iOS/Android) and web
class PlatformService {
  static const String _webDownloadMessage = 'File downloaded to your browser\'s download folder';
  
  /// Check if we're running on web
  static bool get isWeb => kIsWeb;
  
  /// Get a directory path for storing files
  /// On mobile: returns app documents directory
  /// On web: returns a temporary path (files won't actually be saved)
  static Future<String> getStorageDirectory() async {
    return await platform_impl.getStorageDirectory();
  }
  
  /// Download a file with platform-appropriate method
  /// On mobile: saves to app documents directory
  /// On web: triggers browser download
  static Future<PlatformFile?> downloadFile({
    required Uint8List fileBytes,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      return await platform_impl.downloadFile(
        fileBytes: fileBytes,
        fileName: fileName,
        mimeType: mimeType,
      );
    } catch (e) {
      print('❌ Error downloading file: $e');
      return null;
    }
  }
  
  /// Check if a file exists (mobile only, always false on web)
  static Future<bool> fileExists(String filePath) async {
    return await platform_impl.fileExists(filePath);
  }
  
  /// Get file size (mobile only, 0 on web)
  static Future<int> getFileSize(String filePath) async {
    return await platform_impl.getFileSize(filePath);
  }
  
  /// Open file externally (platform specific)
  static Future<bool> openFile(String filePath) async {
    return await platform_impl.openFile(filePath);
  }
}

/// A cross-platform file representation
class PlatformFile {
  final String path;
  final String name;
  final int size;
  final String? downloadMessage;
  
  const PlatformFile({
    required this.path,
    required this.name,
    required this.size,
    this.downloadMessage,
  });
  
  /// Check if this is a web download (no actual file saved)
  bool get isWebDownload => downloadMessage != null;
  
  /// Get file size (for compatibility)
  int get length => size;
  
  /// Check if file exists (for mobile compatibility)
  Future<bool> exists() async {
    return PlatformService.fileExists(path);
  }
}