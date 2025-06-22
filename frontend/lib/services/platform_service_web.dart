// lib/services/platform_service_web.dart (Web Implementation)
import 'dart:html' as html;
import 'dart:typed_data';
import 'platform_service.dart'; // Import main file for shared types

/// Web-specific implementation of platform services
/// This file is used when running in web browsers

const String _webDownloadMessage = 'File downloaded to your browser\'s download folder';

/// Get a directory path for storing files on web (dummy path)
Future<String> getStorageDirectory() async {
  return '/web_temp'; // Dummy path since web can't save to file system
}

/// Download file on web (triggers browser download)
Future<PlatformFile?> downloadFile({
  required Uint8List fileBytes,
  required String fileName,
  required String mimeType,
}) async {
  try {
    // Create a blob and download it using browser APIs
    final blob = html.Blob([fileBytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    // Create a temporary anchor element to trigger download
    final anchor = html.AnchorElement(href: url)
      ..target = 'blank'
      ..download = fileName;
    
    // Add to document, click, then remove
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    
    // Clean up the URL
    html.Url.revokeObjectUrl(url);
    
    print('✅ Web download triggered: $fileName');
    
    // Return the shared PlatformFile type from main file
    return PlatformFile(
      path: 'web_download',
      name: fileName,
      size: fileBytes.length,
      downloadMessage: _webDownloadMessage,
    );
  } catch (e) {
    print('❌ Web download error: $e');
    return null;
  }
}

/// Check if a file exists on web (always false)
Future<bool> fileExists(String filePath) async {
  return false; // Files don't persist on web
}

/// Get file size on web (always 0)
Future<int> getFileSize(String filePath) async {
  return 0;
}

/// Open file externally on web
Future<bool> openFile(String filePath) async {
  try {
    // On web, files are downloaded, so just show a message
    return true;
  } catch (e) {
    print('Error opening file: $e');
    return false;
  }
}