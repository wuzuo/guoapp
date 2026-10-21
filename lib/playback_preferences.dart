import 'package:flutter/material.dart';

import 'player_keys.dart';

const playbackSpeeds = [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0];

enum VideoFrameMode {
  contain,
  cover,
  fill;

  String get label => switch (this) {
    contain => '完整画面',
    cover => '等比铺满',
    fill => '拉伸铺满',
  };

  String get hint => switch (this) {
    contain => '保留比例与全部内容，可能有黑边',
    cover => '填满画面，会裁掉部分画面与字幕',
    fill => '填满画面，画面比例会改变',
  };

  BoxFit get fit => switch (this) {
    contain => BoxFit.contain,
    cover => BoxFit.cover,
    fill => BoxFit.fill,
  };

  static VideoFrameMode of(Object? value) =>
      values.where((mode) => mode.name == value).firstOrNull ?? contain;
}

class PlaybackPreferences {
  const PlaybackPreferences({
    this.speed = 1,
    this.quality = 0,
    this.autoAdvance = true,
    this.danmaku = true,
    this.preload = true,
    this.frameMode = VideoFrameMode.contain,
    this.hardwareDecoding = true,
    this.keyMap = const PlayerKeyMap(),
  });

  final double speed;
  final int quality;
  final bool autoAdvance;
  final bool danmaku;
  final bool preload;
  final VideoFrameMode frameMode;
  final bool hardwareDecoding;
  final PlayerKeyMap keyMap;

  PlaybackPreferences copyWith({
    double? speed,
    int? quality,
    bool? autoAdvance,
    bool? danmaku,
    bool? preload,
    VideoFrameMode? frameMode,
    bool? hardwareDecoding,
    PlayerKeyMap? keyMap,
  }) => PlaybackPreferences(
    speed: speed ?? this.speed,
    quality: quality ?? this.quality,
    autoAdvance: autoAdvance ?? this.autoAdvance,
    danmaku: danmaku ?? this.danmaku,
    preload: preload ?? this.preload,
    frameMode: frameMode ?? this.frameMode,
    hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
    keyMap: keyMap ?? this.keyMap,
  );

  Map<String, dynamic> toJson() => {
    'speed': speed,
    'quality': quality,
    'autoAdvance': autoAdvance,
    'danmaku': danmaku,
    'preload': preload,
    'frameMode': frameMode.name,
    'hardwareDecoding': hardwareDecoding,
    'keyBindings': keyMap.toJson(),
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> value) {
    final speed = (value['speed'] as num? ?? 1).toDouble();
    final quality = value['quality'] as int? ?? 0;
    final autoAdvance = value['autoAdvance'] as bool? ?? true;
    final danmaku = value['danmaku'] as bool? ?? true;
    final preload = value['preload'] as bool? ?? true;
    if (!playbackSpeeds.contains(speed) || quality < 0 || quality > 4320) {
      throw const FormatException('播放偏好无效');
    }
    return PlaybackPreferences(
      speed: speed,
      quality: quality,
      autoAdvance: autoAdvance,
      danmaku: danmaku,
      preload: preload,
      frameMode: VideoFrameMode.of(value['frameMode']),
      hardwareDecoding: value['hardwareDecoding'] as bool? ?? true,
      keyMap: PlayerKeyMap.fromJson(value['keyBindings']),
    );
  }
}
