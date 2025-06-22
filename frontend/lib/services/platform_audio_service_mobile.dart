// lib/services/platform_audio_service_mobile.dart (Mobile Implementation)
import 'dart:async';
import 'package:audioplayers/audioplayers.dart' as audioplayers;
import 'platform_audio_service.dart'; // Import main file for shared types

/// Mobile-specific implementation of audio services
/// This file is used when running on iOS/Android

class PlatformAudioServiceImpl {
  audioplayers.AudioPlayer? _mobilePlayer;
  
  StreamController<Duration>? _positionController;
  StreamController<Duration>? _durationController;
  StreamController<CrossPlatformPlayerState>? _stateController;
  
  bool _isInitialized = false;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String? _currentUrl;
  
  // Getters for streams
  Stream<Duration> get onPositionChanged => 
      _positionController?.stream ?? Stream.empty();
  Stream<Duration> get onDurationChanged => 
      _durationController?.stream ?? Stream.empty();
  Stream<CrossPlatformPlayerState> get onPlayerStateChanged => 
      _stateController?.stream ?? Stream.empty();
  
  // Getters for current state
  bool get isPlaying => _isPlaying;
  Duration get position => _currentPosition;
  Duration get duration => _totalDuration;
  bool get isInitialized => _isInitialized;

  PlatformAudioServiceImpl() {
    _initializeStreams();
  }

  void _initializeStreams() {
    _positionController = StreamController<Duration>.broadcast();
    _durationController = StreamController<Duration>.broadcast();
    _stateController = StreamController<CrossPlatformPlayerState>.broadcast();
  }

  /// Initialize mobile player using AudioPlayers
  Future<bool> initialize(String audioUrl) async {
    try {
      print('🎵 Initializing mobile audio player');
      print('🔗 Audio URL: $audioUrl');
      
      await dispose(); // Clean up any existing player
      _currentUrl = audioUrl;
      
      _mobilePlayer = audioplayers.AudioPlayer();
      
      // Set up event listeners
      _mobilePlayer!.onDurationChanged.listen((duration) {
        _totalDuration = duration;
        _durationController?.add(_totalDuration);
      });
      
      _mobilePlayer!.onPositionChanged.listen((position) {
        _currentPosition = position;
        _positionController?.add(_currentPosition);
      });
      
      _mobilePlayer!.onPlayerStateChanged.listen((state) {
        // Use explicit audioplayers.PlayerState to avoid conflicts
        _isPlaying = state == audioplayers.PlayerState.playing;
        
        // Convert AudioPlayers PlayerState to our custom state
        CrossPlatformPlayerState customState;
        switch (state) {
          case audioplayers.PlayerState.playing:
            customState = CrossPlatformPlayerState.playing;
            break;
          case audioplayers.PlayerState.paused:
            customState = CrossPlatformPlayerState.paused;
            break;
          case audioplayers.PlayerState.stopped:
            customState = CrossPlatformPlayerState.stopped;
            break;
          case audioplayers.PlayerState.completed:
            customState = CrossPlatformPlayerState.completed;
            break;
          default:
            customState = CrossPlatformPlayerState.stopped;
        }
        _stateController?.add(customState);
      });
      
      _mobilePlayer!.onPlayerComplete.listen((_) {
        _isPlaying = false;
        _currentPosition = Duration.zero;
        _positionController?.add(_currentPosition);
      });
      
      // Set the source using AudioPlayers UrlSource
      await _mobilePlayer!.setSource(audioplayers.UrlSource(audioUrl));
      
      _isInitialized = true;
      print('✅ Mobile player initialized');
      return true;
    } catch (e) {
      print('❌ Mobile player initialization failed: $e');
      return false;
    }
  }

  /// Start audio playback
  Future<bool> play() async {
    if (!_isInitialized) {
      print('⚠️ Audio not initialized');
      return false;
    }
    
    try {
      if (_mobilePlayer != null) {
        await _mobilePlayer!.resume();
        print('▶️ Mobile audio playing');
      }
      return true;
    } catch (e) {
      print('❌ Error playing audio: $e');
      return false;
    }
  }

  /// Pause audio playback
  Future<bool> pause() async {
    if (!_isInitialized) return false;
    
    try {
      if (_mobilePlayer != null) {
        await _mobilePlayer!.pause();
        print('⏸️ Mobile audio paused');
      }
      return true;
    } catch (e) {
      print('❌ Error pausing audio: $e');
      return false;
    }
  }

  /// Stop audio playback
  Future<bool> stop() async {
    if (!_isInitialized) return false;
    
    try {
      if (_mobilePlayer != null) {
        await _mobilePlayer!.stop();
        print('⏹️ Mobile audio stopped');
      }
      
      _currentPosition = Duration.zero;
      _positionController?.add(_currentPosition);
      return true;
    } catch (e) {
      print('❌ Error stopping audio: $e');
      return false;
    }
  }

  /// Seek to a specific position
  Future<bool> seek(Duration position) async {
    if (!_isInitialized) return false;
    
    try {
      if (_mobilePlayer != null) {
        await _mobilePlayer!.seek(position);
        print('🔍 Mobile audio seek: ${_formatDuration(position)}');
      }
      return true;
    } catch (e) {
      print('❌ Error seeking audio: $e');
      return false;
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<bool> setVolume(double volume) async {
    if (!_isInitialized) return false;
    
    try {
      volume = volume.clamp(0.0, 1.0);
      
      if (_mobilePlayer != null) {
        await _mobilePlayer!.setVolume(volume);
      }
      
      print('🔊 Volume set to: ${(volume * 100).toInt()}%');
      return true;
    } catch (e) {
      print('❌ Error setting volume: $e');
      return false;
    }
  }

  /// Format duration for logging
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get current audio URL
  String? get currentUrl => _currentUrl;

  /// Check if audio is ready to play
  bool get canPlay => _isInitialized && _mobilePlayer != null;

  /// Dispose of the audio player
  Future<void> dispose() async {
    if (_mobilePlayer != null) {
      await _mobilePlayer!.dispose();
      _mobilePlayer = null;
    }
    
    _isInitialized = false;
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _currentUrl = null;
    
    print('🧹 Mobile audio player disposed');
  }

  /// Close streams
  Future<void> closeStreams() async {
    await _positionController?.close();
    await _durationController?.close();
    await _stateController?.close();
    _positionController = null;
    _durationController = null;
    _stateController = null;
  }
}