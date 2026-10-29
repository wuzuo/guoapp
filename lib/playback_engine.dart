import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_exo.dart';
import 'playback_media_kit.dart';
import 'playback_player.dart';

PlaybackPlayer createPlaybackPlayer({
  required bool television,
  bool systemPlayer = true,
  bool platformView = true,
}) {
  if (defaultTargetPlatform == TargetPlatform.android &&
      television &&
      systemPlayer) {
    return ExoPlaybackPlayer(platformView: platformView);
  }
  return MediaKitPlaybackPlayer(
    Player(
      configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
    ),
  );
}
