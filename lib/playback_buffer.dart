import 'package:flutter/material.dart';

import 'playback_player.dart';

String _clock(double seconds) {
  final value = seconds.floor().clamp(0, 864000);
  return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
}

class PlaybackBufferStatus extends StatelessWidget {
  const PlaybackBufferStatus({
    super.key,
    required this.player,
    this.enabled = true,
  });

  final PlaybackPlayer player;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final state = player.state;
    final position = state.position.inMilliseconds / 1000;
    final buffered = position + state.buffer.inMilliseconds / 1000;
    return Text(
      !enabled
          ? ''
          : state.buffer <= Duration.zero
          ? '正在等待缓冲'
          : '已缓冲至 ${_clock(buffered)}',
      key: const ValueKey('playback-buffer-status'),
      style: const TextStyle(fontSize: 12, color: Colors.white70),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
