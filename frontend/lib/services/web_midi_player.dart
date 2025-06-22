// SOLUTION 2: Client-Side MIDI Player using JavaScript libraries
// This creates a web-specific MIDI player implementation

// lib/services/web_midi_player.dart (NEW FILE)
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:async';
import 'package:flutter/foundation.dart';

class WebMidiPlayer {
  html.DivElement? _playerContainer;
  StreamController<Duration>? _positionController;
  StreamController<bool>? _playStateController;
  
  bool _isInitialized = false;
  bool _isPlaying = false;
  
  Stream<Duration> get onPositionChanged => 
      _positionController?.stream ?? Stream.empty();
  Stream<bool> get onPlayStateChanged => 
      _playStateController?.stream ?? Stream.empty();
  
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;

  WebMidiPlayer() {
    _positionController = StreamController<Duration>.broadcast();
    _playStateController = StreamController<bool>.broadcast();
  }

  /// Initialize the web MIDI player with HTML MIDI Player library
  Future<bool> initialize(String midiUrl) async {
    if (!kIsWeb) return false;
    
    try {
      print('🎹 Initializing web MIDI player');
      
      // Create container for MIDI player
      _playerContainer = html.DivElement();
      _playerContainer!.style.display = 'none'; // Hidden from UI
      html.document.body!.append(_playerContainer!);
      
      // Load MIDI.js or html-midi-player library dynamically
      await _loadMidiLibrary();
      
      // Create MIDI player element
      final midiPlayer = html.Element.tag('midi-player');
      midiPlayer.setAttribute('src', midiUrl);
      midiPlayer.setAttribute('sound-font', '');
      midiPlayer.setAttribute('visualizer', '#piano');
      
      _playerContainer!.append(midiPlayer);
      
      // Set up event listeners
      midiPlayer.addEventListener('start', (event) {
        _isPlaying = true;
        _playStateController?.add(true);
      });
      
      midiPlayer.addEventListener('stop', (event) {
        _isPlaying = false;
        _playStateController?.add(false);
      });
      
      // Position updates (if supported by library)
      _startPositionUpdates(midiPlayer);
      
      _isInitialized = true;
      print('✅ Web MIDI player initialized');
      return true;
      
    } catch (e) {
      print('❌ Error initializing web MIDI player: $e');
      return false;
    }
  }

  /// Load MIDI library dynamically
  Future<void> _loadMidiLibrary() async {
    // Check if library is already loaded
    if (js.context.hasProperty('MIDIPlayer')) {
      return;
    }
    
    print('📦 Loading MIDI library...');
    
    // Load html-midi-player library
    final script = html.ScriptElement();
    script.src = 'https://cdn.jsdelivr.net/npm/html-midi-player@1.5.0/dist/midi-player.min.js';
    script.type = 'module';
    
    final completer = Completer<void>();
    
    script.onLoad.listen((_) {
      print('✅ MIDI library loaded');
      completer.complete();
    });
    
    script.onError.listen((error) {
      print('❌ Error loading MIDI library: $error');
      completer.completeError(error);
    });
    
    html.document.head!.append(script);
    
    await completer.future;
  }

  /// Start position updates
  void _startPositionUpdates(html.Element midiPlayer) {
    Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (!_isPlaying) return;
      
      try {
        // Try to get current time from player (depends on library)
        final currentTime = js.context.callMethod('getCurrentTime', [midiPlayer]);
        if (currentTime != null) {
          final duration = Duration(milliseconds: (currentTime * 1000).round());
          _positionController?.add(duration);
        }
      } catch (e) {
        // Ignore errors - library might not support this
      }
    });
  }

  /// Play MIDI
  Future<bool> play() async {
    if (!_isInitialized || _playerContainer == null) return false;
    
    try {
      final midiPlayer = _playerContainer!.querySelector('midi-player');
      if (midiPlayer != null) {
        js.context.callMethod('playMidi', [midiPlayer]);
        return true;
      }
    } catch (e) {
      print('❌ Error playing MIDI: $e');
    }
    return false;
  }

  /// Pause MIDI
  Future<bool> pause() async {
    if (!_isInitialized || _playerContainer == null) return false;
    
    try {
      final midiPlayer = _playerContainer!.querySelector('midi-player');
      if (midiPlayer != null) {
        js.context.callMethod('pauseMidi', [midiPlayer]);
        return true;
      }
    } catch (e) {
      print('❌ Error pausing MIDI: $e');
    }
    return false;
  }

  /// Stop MIDI
  Future<bool> stop() async {
    if (!_isInitialized || _playerContainer == null) return false;
    
    try {
      final midiPlayer = _playerContainer!.querySelector('midi-player');
      if (midiPlayer != null) {
        js.context.callMethod('stopMidi', [midiPlayer]);
        return true;
      }
    } catch (e) {
      print('❌ Error stopping MIDI: $e');
    }
    return false;
  }

  /// Dispose player
  Future<void> dispose() async {
    _playerContainer?.remove();
    _playerContainer = null;
    _isInitialized = false;
    _isPlaying = false;
  }

  /// Close streams
  Future<void> closeStreams() async {
    await _positionController?.close();
    await _playStateController?.close();
    _positionController = null;
    _playStateController = null;
  }
}