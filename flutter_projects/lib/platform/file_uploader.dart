import 'dart:io';
import 'package:dio/dio.dart';

class FileUploader {
  final Dio _dio = Dio(BaseOptions(baseUrl: 'http://192.168.100.36:5000'));

  Future<void> uploadFile(String filePath) async {
    try {
      final file = File(filePath);
      final fileName = filePath.split('/').last;

      // Check if the file exists
      if (!await file.exists()) {
        print('File does not exist: $filePath');
        return;
      }

      // Read the file as binary
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      // Send the file to the server
      final response = await _dio.post('/upload', data: formData);
      print('Server response: ${response.data}');
    } catch (e) {
      print('Error uploading file: $e');
    }
  }
}
