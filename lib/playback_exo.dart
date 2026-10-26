import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'playback_player.dart';

/// Android 端使用 Media3 ExoPlayer 解码，帧通过 SurfaceProducer 纹理交给 Flutter 合成，
/// 因此弹幕与控制层仍是 Flutter 控件，画在纹理之上。
class ExoPlaybackPlayer implements PlaybackPlayer {
  ExoPlaybackPlayer() {
    _installHandler();
    _stream = PlaybackStream(
      position: _position.stream,
      duration: _duration.stream,
      buffer: _buffer.stream,
      playing: _playing.stream,
      buffering: _buffering.stream,
      completed: _completed.stream,
      rate: _rate.stream,
      volume: _volume.stream,
      error: _error.stream,
      video: _video.stream,
    );
    unawaited(_ensure());
  }

  static const _channel = MethodChannel('duanju/playback');
  static final _players = <int, ExoPlaybackPlayer>{};
  static bool _handlerInstalled = false;

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return null;
      final arguments = call.arguments;
      if (arguments is! Map) return null;
      final id = (arguments['id'] as num?)?.toInt() ?? 0;
      _players[id]?._handle(Map<String, dynamic>.from(arguments));
      return null;
    });
  }

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _rate = StreamController<double>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _video = StreamController<PlaybackVideoSize>.broadcast();
  final _texture = ValueNotifier<int>(0);

  late final PlaybackStream _stream;
  PlaybackState _state = const PlaybackState();
  int _id = 0;
  bool _disposed = false;
  Future<void>? _creating;

  @override
  PlaybackStream get stream => _stream;

  @override
  PlaybackState get state => _state;

  Future<void> _ensure() {
    if (_id > 0) return Future.value();
    return _creating ??= _create();
  }

  Future<void> _create() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('create');
      final id = (result?['id'] as num?)?.toInt() ?? 0;
      final texture = (result?['texture'] as num?)?.toInt() ?? 0;
      if (_disposed || id <= 0) {
        if (id > 0) await _invoke('dispose', id);
        return;
      }
      _id = id;
      _players[id] = this;
      _texture.value = texture;
    } catch (_) {
      _error.add('原生播放器初始化失败');
    }
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (_disposed) return;
    await _ensure();
    if (_disposed || _id <= 0) return;
    await _channel.invokeMethod<void>(method, {
      'id': _id,
      if (arguments is Map) ...arguments,
      if (arguments is num) 'value': arguments,
    });
  }

  void _handle(Map<String, dynamic> event) {
    if (_disposed) return;
    switch (event['type']) {
      case 'state':
        final playing = event['playing'] == true;
        final buffering = event['buffering'] == true;
        final completed = event['completed'] == true;
        final volume = ((event['volume'] as num?)?.toDouble() ?? 1) * 100;
        _state = _state.copyWith(
          position: Duration(
            milliseconds: (event['position'] as num?)?.toInt() ?? 0,
          ),
          duration: Duration(
            milliseconds: (event['duration'] as num?)?.toInt() ?? 0,
          ),
          buffer: Duration(
            milliseconds: (event['buffered'] as num?)?.toInt() ?? 0,
          ),
          playing: playing,
          buffering: buffering,
          completed: completed,
          rate: (event['rate'] as num?)?.toDouble() ?? _state.rate,
          volume: volume,
          dropped: (event['dropped'] as num?)?.toInt() ?? _state.dropped,
        );
        _position.add(_state.position);
        _buffer.add(_state.buffer);
        if (playing != _playingRaw) {
          _playingRaw = playing;
          _playing.add(playing);
        }
        if (buffering != _bufferingRaw) {
          _bufferingRaw = buffering;
          _buffering.add(buffering);
        }
        if (completed != _completedRaw) {
          _completedRaw = completed;
          _completed.add(completed);
        }
        _duration.add(_state.duration);
        if (_state.volume != _volumeRaw) {
          _volumeRaw = _state.volume;
          _volume.add(_state.volume);
        }
        if (_state.rate != _rateRaw) {
          _rateRaw = _state.rate;
          _rate.add(_state.rate);
        }
      case 'duration':
        _duration.add(
          Duration(milliseconds: (event['duration'] as num?)?.toInt() ?? 0),
        );
      case 'rate':
        _state = _state.copyWith(
          rate: (event['rate'] as num?)?.toDouble() ?? 1,
        );
        _rate.add(_state.rate);
      case 'volume':
        _state = _state.copyWith(
          volume: ((event['volume'] as num?)?.toDouble() ?? 1) * 100,
        );
        _volume.add(_state.volume);
      case 'video':
        final width = (event['width'] as num?)?.toInt() ?? 0;
        final height = (event['height'] as num?)?.toInt() ?? 0;
        if (width > 0 && height > 0) {
          final size = PlaybackVideoSize(width, height);
          _state = _state.copyWith(video: size);
          _video.add(size);
        }
      case 'decoder':
        final name = (event['name'] as String? ?? '').trim();
        if (name.isNotEmpty) _state = _state.copyWith(decoder: name);
      case 'error':
        final message = (event['message'] as String? ?? '').trim();
        if (message.isNotEmpty) _error.add(message);
    }
  }

  bool _playingRaw = false;
  bool _bufferingRaw = false;
  bool _completedRaw = false;
  double _volumeRaw = 100;
  double _rateRaw = 1;

  @override
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    Duration? start,
    bool play = true,
    String decryptionKey = '',
    bool local = false,
  }) async {
    _state = _state.copyWith(
      mediaUri: url,
      completed: false,
      buffer: Duration.zero,
      position: start ?? Duration.zero,
    );
    _completedRaw = false;
    await _invoke('open', {
      'url': url,
      'headers': headers,
      'start': start?.inMilliseconds ?? 0,
      'play': play,
      'key': decryptionKey,
      'local': local,
    });
  }

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> playOrPause() async {
    if (_state.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<void> seek(Duration position) =>
      _invoke('seek', position.inMilliseconds);

  @override
  Future<void> setRate(double rate) => _invoke('rate', rate);

  @override
  Future<void> setVolume(double volume) =>
      _invoke('volume', (volume / 100).clamp(0.0, 1.0));

  @override
  Future<void> configureMpv(Map<String, String> options) async {}

  @override
  Widget buildVideo({required Widget overlay, required BoxFit fit}) =>
      ValueListenableBuilder<int>(
        valueListenable: _texture,
        builder: (context, texture, _) {
          final size = _state.video;
          final width = (size?.width ?? 16).toDouble();
          final height = (size?.height ?? 9).toDouble();
          return Stack(
            fit: StackFit.expand,
            children: [
              if (texture > 0)
                FittedBox(
                  fit: fit,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Texture(textureId: texture),
                  ),
                )
              else
                const ColoredBox(color: Colors.black),
              overlay,
            ],
          );
        },
      );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final id = _id;
    _id = 0;
    _players.remove(id);
    for (final controller in [
      _position,
      _duration,
      _buffer,
      _playing,
      _buffering,
      _completed,
      _rate,
      _volume,
      _error,
      _video,
    ]) {
      unawaited(controller.close());
    }
    _texture.dispose();
    if (id > 0) {
      try {
        await _channel.invokeMethod<void>('dispose', {'id': id});
      } catch (_) {}
    }
  }
}
