// lib/services/platform_audio_service.dart (Main File)
import 'dart:async';
import 'package:flutter/foundation.dart';

// Conditional imports - this is the correct syntax!
import 'platform_audio_service_mobile.dart' if (dart.library.html) 'platform_audio_service_web.dart' as audio_impl;

typedef TimeUpdateCallback = void Function(double currentTime);

/// A cross-platform audio service that handles audio playback
/// differently for web and mobile to avoid CORS and compatibility issues
class PlatformAudioService {
  late final audio_impl.PlatformAudioServiceImpl _impl;

  // Stream controllers for cross-platform events
  StreamController<Duration>? _positionController;
  StreamController<Duration>? _durationController;
  StreamController<CrossPlatformPlayerState>? _stateController;

  // Getters for streams
  Stream<Duration> get onPositionChanged => 
      _positionController?.stream ?? Stream.empty();
  Stream<Duration> get onDurationChanged => 
      _durationController?.stream ?? Stream.empty();
  Stream<CrossPlatformPlayerState> get onPlayerStateChanged => 
      _stateController?.stream ?? Stream.empty();
  
  // Getters for current state
  bool get isPlaying => _impl.isPlaying;
  Duration get position => _impl.position;
  Duration get duration => _impl.duration;
  bool get isInitialized => _impl.isInitialized;

  PlatformAudioService() {
    _initializeStreams();
    _impl = audio_impl.PlatformAudioServiceImpl();
    _setupStreamForwarding();
  }

  void _initializeStreams() {
    _positionController = StreamController<Duration>.broadcast();
    _durationController = StreamController<Duration>.broadcast();
    _stateController = StreamController<CrossPlatformPlayerState>.broadcast();
  }

  void _setupStreamForwarding() {
    // Forward events from implementation to main streams
    _impl.onPositionChanged.listen((position) {
      _positionController?.add(position);
    });
    
    _impl.onDurationChanged.listen((duration) {
      _durationController?.add(duration);
    });
    
    _impl.onPlayerStateChanged.listen((state) {
      _stateController?.add(state);
    });
  }

  /// Initialize audio player with URL
  Future<bool> initialize(String audioUrl) async {
    print('🎵 Initializing cross-platform audio for: ${kIsWeb ? 'Web' : 'Mobile'}');
    return await _impl.initialize(audioUrl);
  }

  /// Start audio playback
  Future<bool> play() async {
    return await _impl.play();
  }

  /// Pause audio playback
  Future<bool> pause() async {
    return await _impl.pause();
  }

  /// Stop audio playback
  Future<bool> stop() async {
    return await _impl.stop();
  }

  /// Seek to a specific position
  Future<bool> seek(Duration position) async {
    return await _impl.seek(position);
  }

  /// Set volume (0.0 to 1.0)
  Future<bool> setVolume(double volume) async {
    return await _impl.setVolume(volume);
  }

  /// Get current audio URL
  String? get currentUrl => _impl.currentUrl;

  /// Check if audio is ready to play
  bool get canPlay => _impl.canPlay;

  /// Dispose of the audio player
  Future<void> dispose() async {
    await _impl.dispose();
  }

  /// Close streams
  Future<void> closeStreams() async {
    await _positionController?.close();
    await _durationController?.close();
    await _stateController?.close();
    _positionController = null;
    _durationController = null;
    _stateController = null;
    
    await _impl.closeStreams();
  }
}

/// Custom audio player states to avoid conflicts with AudioPlayers package
enum CrossPlatformPlayerState {
  stopped,
  playing,
  paused,
  completed,
}

/// Note: We don't use PlayerState alias to avoid conflicts with audioplayers package