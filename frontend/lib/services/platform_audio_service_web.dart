// lib/services/platform_audio_service_web.dart (SIMPLIFIED - No JS interop issues)
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'platform_audio_service.dart';

/// Web-specific implementation - SIMPLIFIED to avoid JavaScript interop issues
class PlatformAudioServiceImpl {
  html.AudioElement? _webPlayer;
  
  StreamController<Duration>? _positionController;
  StreamController<Duration>? _durationController;
  StreamController<CrossPlatformPlayerState>? _stateController;
  
  Timer? _positionTimer;
  
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMidiFile = false;
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

  /// Initialize player with format detection
  Future<bool> initialize(String audioUrl) async {
    try {
      print('🎵 Initializing web audio player');
      print('🔗 Audio URL: $audioUrl');
      
      await dispose(); // Clean up any existing player
      _currentUrl = audioUrl;
      
      // Detect if this is a MIDI file
      _isMidiFile = _isMidiUrl(audioUrl);
      
      if (_isMidiFile) {
        print('🎹 MIDI file detected - will show conversion message');
        return await _handleMidiFile(audioUrl);
      } else {
        print('🎵 Regular audio file - using HTML5 player');
        return await _initializeHtml5Player(audioUrl);
      }
      
    } catch (e) {
      print('❌ Error initializing player: $e');
      return false;
    }
  }

  /// Check if URL is a MIDI file
  bool _isMidiUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.mid') || 
           lowerUrl.contains('.midi') || 
           lowerUrl.contains('midi') ||
           lowerUrl.contains('audio/midi');
  }

  /// Handle MIDI file - simple approach
  Future<bool> _handleMidiFile(String midiUrl) async {
    try {
      print('🎹 Handling MIDI file...');
      
      // For now, we'll just set up basic state
      // Real MIDI playback requires server-side conversion
      _totalDuration = Duration(seconds: 180); // Default 3 minutes
      _durationController?.add(_totalDuration);
      
      _isInitialized = true;
      print('⚠️ MIDI file ready (requires server conversion for playback)');
      return true;
      
    } catch (e) {
      print('❌ Error handling MIDI: $e');
      return false;
    }
  }

  /// Initialize HTML5 audio player for regular audio files
  Future<bool> _initializeHtml5Player(String audioUrl) async {
    try {
      _webPlayer = html.AudioElement(audioUrl);
      _webPlayer!.preload = 'metadata';
      _webPlayer!.crossOrigin = 'anonymous';
      
      // Set up event listeners
      _webPlayer!.onLoadedMetadata.listen((_) {
        _totalDuration = Duration(seconds: _webPlayer!.duration?.toInt() ?? 0);
        _durationController?.add(_totalDuration);
        print('🎵 HTML5 audio loaded: ${_formatDuration(_totalDuration)}');
      });
      
      _webPlayer!.onTimeUpdate.listen((_) {
        _currentPosition = Duration(seconds: _webPlayer!.currentTime?.toInt() ?? 0);
        _positionController?.add(_currentPosition);
      });
      
      _webPlayer!.onPlay.listen((_) {
        _isPlaying = true;
        _stateController?.add(CrossPlatformPlayerState.playing);
        _startPositionTimer();
      });
      
      _webPlayer!.onPause.listen((_) {
        _isPlaying = false;
        _stateController?.add(CrossPlatformPlayerState.paused);
        _stopPositionTimer();
      });
      
      _webPlayer!.onEnded.listen((_) {
        _isPlaying = false;
        _currentPosition = Duration.zero;
        _stateController?.add(CrossPlatformPlayerState.completed);
        _positionController?.add(_currentPosition);
        _stopPositionTimer();
      });
      
      _webPlayer!.onError.listen((error) {
        print('❌ HTML5 audio error: $error');
        _stateController?.add(CrossPlatformPlayerState.stopped);
      });
      
      // Load the audio
      _webPlayer!.load();
      
      _isInitialized = true;
      return true;
    } catch (e) {
      print('❌ HTML5 audio initialization failed: $e');
      return false;
    }
  }

  /// Start playback
  Future<bool> play() async {
    if (!_isInitialized) {
      print('⚠️ Player not initialized');
      return false;
    }
    
    try {
      if (_isMidiFile) {
        print('⚠️ MIDI playback requires server-side audio conversion');
        return false; // Will be handled by UI with conversion message
      } else if (_webPlayer != null) {
        await _webPlayer!.play();
        print('▶️ HTML5 audio playing');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error playing: $e');
      return false;
    }
  }

  /// Pause playback
  Future<bool> pause() async {
    if (!_isInitialized) return false;
    
    try {
      if (_isMidiFile) {
        print('⚠️ MIDI pause requires server-side conversion');
        return false;
      } else if (_webPlayer != null) {
        _webPlayer!.pause();
        print('⏸️ HTML5 audio paused');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error pausing: $e');
      return false;
    }
  }

  /// Stop playback
  Future<bool> stop() async {
    if (!_isInitialized) return false;
    
    try {
      if (_isMidiFile) {
        _isPlaying = false;
        _currentPosition = Duration.zero;
        _stateController?.add(CrossPlatformPlayerState.stopped);
        _positionController?.add(_currentPosition);
        _stopPositionTimer();
        return true;
      } else if (_webPlayer != null) {
        _webPlayer!.pause();
        _webPlayer!.currentTime = 0;
        print('⏹️ HTML5 audio stopped');
      }
      
      _currentPosition = Duration.zero;
      _positionController?.add(_currentPosition);
      return true;
    } catch (e) {
      print('❌ Error stopping: $e');
      return false;
    }
  }

  /// Seek to position
  Future<bool> seek(Duration position) async {
    if (!_isInitialized) return false;
    
    try {
      if (_isMidiFile) {
        print('🔍 MIDI seek not available without server conversion');
        return false;
      } else if (_webPlayer != null) {
        _webPlayer!.currentTime = position.inSeconds.toDouble();
        print('🔍 HTML5 audio seek: ${_formatDuration(position)}');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error seeking: $e');
      return false;
    }
  }

  /// Set volume
  Future<bool> setVolume(double volume) async {
    if (!_isInitialized) return false;
    
    try {
      volume = volume.clamp(0.0, 1.0);
      
      if (_isMidiFile) {
        print('🔊 MIDI volume control not available without server conversion');
        return false;
      } else if (_webPlayer != null) {
        _webPlayer!.volume = volume;
        print('🔊 Volume set to: ${(volume * 100).toInt()}%');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error setting volume: $e');
      return false;
    }
  }

  /// Start position timer for HTML5 audio
  void _startPositionTimer() {
    _stopPositionTimer();
    if (!_isMidiFile && _webPlayer != null) {
      _positionTimer = Timer.periodic(Duration(milliseconds: 100), (_) {
        if (_webPlayer != null && !_webPlayer!.paused) {
          _currentPosition = Duration(seconds: _webPlayer!.currentTime?.toInt() ?? 0);
          _positionController?.add(_currentPosition);
        }
      });
    }
  }

  /// Stop position timer
  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  /// Format duration
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get current URL
  String? get currentUrl => _currentUrl;

  /// Check if ready to play
  bool get canPlay => _isInitialized && (!_isMidiFile && _webPlayer != null);

  /// Dispose player
  Future<void> dispose() async {
    _stopPositionTimer();
    
    if (_webPlayer != null) {
      _webPlayer!.pause();
      _webPlayer!.src = '';
      _webPlayer = null;
    }
    
    _isInitialized = false;
    _isPlaying = false;
    _isMidiFile = false;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _currentUrl = null;
    
    print('🧹 Web audio player disposed');
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