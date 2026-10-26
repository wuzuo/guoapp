import 'dart:async';

import 'package:flutter/material.dart';

class PlaybackVideoSize {
  const PlaybackVideoSize(this.width, this.height);

  final int width;
  final int height;

  double get aspectRatio => width > 0 && height > 0 ? width / height : 16 / 9;
}

class PlaybackState {
  const PlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.rate = 1,
    this.volume = 100,
    this.video,
    this.mediaUri = '',
    this.decoder = '',
    this.dropped = 0,
  });

  final Duration position;
  final Duration duration;
  final Duration buffer;
  final bool playing;
  final bool buffering;
  final bool completed;
  final double rate;
  final double volume;
  final PlaybackVideoSize? video;
  final String mediaUri;
  final String decoder;
  final int dropped;

  int? get width => video?.width;

  int? get height => video?.height;

  PlaybackState copyWith({
    Duration? position,
    Duration? duration,
    Duration? buffer,
    bool? playing,
    bool? buffering,
    bool? completed,
    double? rate,
    double? volume,
    PlaybackVideoSize? video,
    String? mediaUri,
    String? decoder,
    int? dropped,
  }) => PlaybackState(
    position: position ?? this.position,
    duration: duration ?? this.duration,
    buffer: buffer ?? this.buffer,
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    completed: completed ?? this.completed,
    rate: rate ?? this.rate,
    volume: volume ?? this.volume,
    video: video ?? this.video,
    mediaUri: mediaUri ?? this.mediaUri,
    decoder: decoder ?? this.decoder,
    dropped: dropped ?? this.dropped,
  );
}

class PlaybackStream {
  PlaybackStream({
    required this.position,
    required this.duration,
    required this.buffer,
    required this.playing,
    required this.buffering,
    required this.completed,
    required this.rate,
    required this.volume,
    required this.error,
    required this.video,
  });

  final Stream<Duration> position;
  final Stream<Duration> duration;
  final Stream<Duration> buffer;
  final Stream<bool> playing;
  final Stream<bool> buffering;
  final Stream<bool> completed;
  final Stream<double> rate;
  final Stream<double> volume;
  final Stream<String> error;
  final Stream<PlaybackVideoSize> video;
}

abstract class PlaybackPlayer {
  PlaybackState get state;

  PlaybackStream get stream;

  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    Duration? start,
    bool play = true,
    String decryptionKey = '',
    bool local = false,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> playOrPause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setRate(double rate);

  Future<void> setVolume(double volume);

  Future<void> configureMpv(Map<String, String> options);

  Widget buildVideo({required Widget overlay, required BoxFit fit});

  Future<void> dispose();
}
