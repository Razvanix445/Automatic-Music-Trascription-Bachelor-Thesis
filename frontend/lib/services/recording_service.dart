import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'auth_service.dart';

class RecordingService {
  final AuthService _authService = AuthService();
  final String _storageKey = 'local_recordings';

  // Adaugă o înregistrare simulată folosind SharedPreferences
  Future<bool> mockAddRecording(File audioFile, String title) async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        throw Exception('Nu ești autentificat');
      }

      final prefs = await SharedPreferences.getInstance();
      final recordingsJson = prefs.getStringList(_storageKey) ?? [];

      final recordingId = 'mock_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(audioFile.path)}';

      // URL fictiv - va fi înlocuit cu AWS S3 URL în viitor
      final mockUrl = 'https://mock-url-to-be-replaced-with-aws-s3/${userId}/${fileName}';

      // Calculează durata simulată bazată pe dimensiunea fișierului
      final fileSize = await audioFile.length();
      final mockDuration = Duration(seconds: (fileSize / 50000).round());
      final formattedDuration = _formatDuration(mockDuration);

      // Creează înregistrarea simulată
      final recordingData = {
        'id': recordingId,
        'userId': userId,
        'title': title,
        'fileName': fileName,
        'storageUrl': mockUrl,
        'createdAt': DateTime.now().toIso8601String(),
        'duration': formattedDuration,
        'notes': [],
        'analyzed': false,
        'isMock': true,
        'originalFilePath': audioFile.path,
      };

      // Adaugă la lista existentă
      recordingsJson.add(jsonEncode(recordingData));
      await prefs.setStringList(_storageKey, recordingsJson);

      return true;
    } catch (e) {
      print('Error adding mock recording: $e');
      return false;
    }
  }

  // Generează o durată formatată pentru afișare
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // Obține înregistrările utilizatorului din SharedPreferences
  Future<List<Map<String, dynamic>>> getUserRecordings() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      return [];
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final recordingsJson = prefs.getStringList(_storageKey) ?? [];

      List<Map<String, dynamic>> recordings = [];

      for (var recordingJson in recordingsJson) {
        Map<String, dynamic> recording =
        jsonDecode(recordingJson) as Map<String, dynamic>;

        if (recording['userId'] == userId) {
          recordings.add(recording);
        }
      }

      // Sortează după data creării (descendent)
      recordings.sort((a, b) {
        DateTime dateA = DateTime.parse(a['createdAt']);
        DateTime dateB = DateTime.parse(b['createdAt']);
        return dateB.compareTo(dateA);
      });

      return recordings;
    } catch (e) {
      print('Error getting recordings: $e');
      return [];
    }
  }
}