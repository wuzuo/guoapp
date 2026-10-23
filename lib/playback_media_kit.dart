import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'playback_player.dart';

class MediaKitPlaybackPlayer implements PlaybackPlayer {
  MediaKitPlaybackPlayer(this._player) {
    _stream = PlaybackStream(
      position: _player.stream.position,
      duration: _player.stream.duration,
      buffer: _player.stream.buffer,
      playing: _player.stream.playing,
      buffering: _player.stream.buffering,
      completed: _player.stream.completed,
      rate: _player.stream.rate,
      volume: _player.stream.volume,
      error: _player.stream.error,
      video: _player.stream.videoParams.map(_size),
    );
  }

  final Player _player;
  late final PlaybackStream _stream;
  VideoController? _video;

  static PlaybackVideoSize _size(VideoParams params) =>
      PlaybackVideoSize(params.dw ?? params.w ?? 0, params.dh ?? params.h ?? 0);

  @override
  PlaybackStream get stream => _stream;

  @override
  PlaybackState get state {
    final current = _player.state;
    final params = current.videoParams;
    return PlaybackState(
      position: current.position,
      duration: current.duration,
      buffer: current.buffer,
      playing: current.playing,
      buffering: current.buffering,
      completed: current.completed,
      rate: current.rate,
      volume: current.volume,
      video: (params.dw ?? 0) > 0
          ? _size(params)
          : (params.w ?? 0) > 0
          ? _size(params)
          : null,
      mediaUri: current.playlist.medias.firstOrNull?.uri ?? '',
    );
  }

  @override
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    Duration? start,
    bool play = true,
    String decryptionKey = '',
    bool local = false,
  }) => _player.open(
    Media(url, httpHeaders: headers, start: start),
    play: play,
  );

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> configureMpv(Map<String, String> options) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    for (final entry in options.entries) {
      await platform.setProperty(entry.key, entry.value);
    }
  }

  @override
  Widget buildVideo({required Widget overlay, required BoxFit fit}) => Video(
    controller: _video ??= VideoController(_player),
    fit: fit,
    controls: (_) => overlay,
  );

  @override
  Future<void> dispose() => _player.dispose();
}
