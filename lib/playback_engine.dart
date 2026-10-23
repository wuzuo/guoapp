import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_exo.dart';
import 'playback_media_kit.dart';
import 'playback_player.dart';

PlaybackPlayer createPlaybackPlayer({required bool television}) {
  if (defaultTargetPlatform == TargetPlatform.android && television) {
    return ExoPlaybackPlayer();
  }
  return MediaKitPlaybackPlayer(
    Player(
      configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
    ),
  );
}
