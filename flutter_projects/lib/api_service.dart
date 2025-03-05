import 'dart:io';
import 'package:dio/dio.dart';

// Base URL for your API
class ApiService {
  final Dio _dio = Dio(BaseOptions(baseUrl: 'http://192.168.100.36:5000')); // Replace with your server IP

  Future<Map<String, dynamic>> registerUser(Map<String, dynamic> userData) async {
    try {
      final response = await _dio.post('/register', data: userData);
      return {'ok': true, 'data': response.data};
    } on DioError catch (e) {
      return {'ok': false, 'error': e.response?.data['error'] ?? e.message};
    }
  }

  Future<Map<String, dynamic>> loginUser(Map<String, dynamic> userData) async {
    try {
      final response = await _dio.post('/login', data: userData);
      return {'ok': true, 'data': response.data};
    } on DioError catch (e) {
      return {'ok': false, 'error': e.response?.data['error'] ?? e.message};
    }
  }

  Future<String> chatWithBot(String message) async {
    try {
      final response = await _dio.post('/chat', data: {'message': message});
      return response.data['response'] as String;
    } on DioError catch (e) {
      print('Error communicating with chatbot: ${e.message}');
      return "Sorry, I'm having trouble responding at the moment.";
    }
  }

  Future<String> transcribeAudio(File audioFile) async {
    try {
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audioFile.path,
          filename: 'recording.m4a', // Match your backend's expected format
        ),
      });

      final response = await _dio.post('/transcribe', data: formData);
      return response.data['transcription'] as String;
    } on DioError catch (e) {
      print('Error transcribing audio: ${e.message}');
      rethrow; // Throw error for the caller to handle
    }
  }
}
