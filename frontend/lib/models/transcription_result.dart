class Note {
  final String noteName;
  final double time;
  final double duration;
  final double velocity;
  final int velocityMidi;
  final int pitch;
  final double frequency;

  Note({
    required this.noteName,
    required this.time,
    required this.duration,
    required this.velocity,
    required this.velocityMidi,
    required this.pitch,
    required this.frequency,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      noteName: json['note_name'],
      time: json['time'].toDouble(),
      duration: json['duration'].toDouble(),
      velocity: json['velocity'].toDouble(),
      velocityMidi: json['velocity_midi'],
      pitch: json['pitch'],
      frequency: json['frequency'].toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'note_name': noteName,
      'time': time,
      'duration': duration,
      'velocity': velocity,
      'velocity_midi': velocityMidi,
      'pitch': pitch,
      'frequency': frequency,
    };
  }
}

class SheetMusic {
  final String fileUrl;
  final String format;
  final int size;

  SheetMusic({
    required this.fileUrl,
    required this.format,
    required this.size,
  });

  factory SheetMusic.fromJson(Map<String, dynamic> json) {
    return SheetMusic(
      fileUrl: json['fileUrl'] ?? '',
      format: json['format'] ?? 'pdf',
      size: json['size'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fileUrl': fileUrl,
      'format': format,
      'size': size,
    };
  }
}

class TranscriptionResult {
  final bool success;
  final List<Note> notes;
  final String midiFileUrl;
  final bool musescoreAvailable;
  final SheetMusic? sheetMusic;
  final String? error;

  TranscriptionResult({
    required this.success,
    required this.notes,
    required this.midiFileUrl,
    required this.musescoreAvailable,
    this.sheetMusic,
    this.error,
  });

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    List<Note> notesList = [];
    if (json['notes'] != null && json['notes'] is List) {
      notesList = (json['notes'] as List)
          .map((noteJson) => Note.fromJson(noteJson))
          .toList();
    }

    SheetMusic? sheetMusicObj;
    if (json['sheet_music'] != null && json['sheet_music'] is Map<String, dynamic>) {
      sheetMusicObj = SheetMusic.fromJson(json['sheet_music']);
    }

    return TranscriptionResult(
      success: json['success'] ?? false,
      notes: notesList,
      midiFileUrl: json['midi_file'] ?? '',
      musescoreAvailable: json['musescore_available'] ?? false,
      sheetMusic: sheetMusicObj,
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'notes': notes.map((note) => note.toJson()).toList(),
      'midi_file': midiFileUrl,
      'musescore_available': musescoreAvailable,
      'sheet_music': sheetMusic?.toJson(),
      'error': error,
    };
  }

  bool get hasNotes => notes.isNotEmpty;
  bool get hasSheetMusic => sheetMusic != null;
  bool get hasMidiFile => midiFileUrl.isNotEmpty;
  
  double get totalDuration {
    if (notes.isEmpty) return 0.0;
    
    double maxEndTime = 0.0;
    for (var note in notes) {
      double endTime = note.time + note.duration;
      if (endTime > maxEndTime) {
        maxEndTime = endTime;
      }
    }
    return maxEndTime;
  }
}