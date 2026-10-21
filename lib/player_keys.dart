import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PlayerKey { up, down, left, right, ok, menu }

enum PlayerKeyAction {
  playPause,
  seekForward,
  seekBackward,
  volumeUp,
  volumeDown,
  previousEpisode,
  nextEpisode,
  toggleFullscreen,
  toggleMute,
  openSettings,
  none;

  String get label => switch (this) {
    playPause => '播放 / 暂停',
    seekForward => '快进 5 秒（长按 3 倍速）',
    seekBackward => '后退 5 秒',
    volumeUp => '音量 +5%',
    volumeDown => '音量 -5%',
    previousEpisode => '上一集',
    nextEpisode => '下一集',
    toggleFullscreen => '全屏 / 退出全屏',
    toggleMute => '静音',
    openSettings => '打开播放设置',
    none => '不响应',
  };
}

extension PlayerKeyLabel on PlayerKey {
  String get label => switch (this) {
    PlayerKey.up => '上',
    PlayerKey.down => '下',
    PlayerKey.left => '左',
    PlayerKey.right => '右',
    PlayerKey.ok => '确定',
    PlayerKey.menu => '菜单',
  };
}

class PlayerKeyMap {
  const PlayerKeyMap([this._bindings = const {}]);

  final Map<PlayerKey, PlayerKeyAction> _bindings;

  static const defaults = <PlayerKey, PlayerKeyAction>{
    PlayerKey.up: PlayerKeyAction.volumeUp,
    PlayerKey.down: PlayerKeyAction.volumeDown,
    PlayerKey.left: PlayerKeyAction.seekBackward,
    PlayerKey.right: PlayerKeyAction.seekForward,
    PlayerKey.ok: PlayerKeyAction.playPause,
    PlayerKey.menu: PlayerKeyAction.openSettings,
  };

  PlayerKeyAction operator [](PlayerKey key) =>
      _bindings[key] ?? defaults[key] ?? PlayerKeyAction.none;

  PlayerKeyMap withBinding(PlayerKey key, PlayerKeyAction action) =>
      PlayerKeyMap({..._bindings, key: action});

  bool get isDefault => customized == 0;

  int get customized =>
      PlayerKey.values.where((key) => this[key] != defaults[key]).length;

  Map<String, String> toJson() => {
    for (final key in PlayerKey.values) key.name: this[key].name,
  };

  factory PlayerKeyMap.fromJson(Object? value) {
    if (value is! Map) return const PlayerKeyMap();
    final bindings = <PlayerKey, PlayerKeyAction>{};
    for (final key in PlayerKey.values) {
      final raw = value[key.name];
      if (raw is! String) continue;
      final action = PlayerKeyAction.values
          .where((entry) => entry.name == raw)
          .firstOrNull;
      if (action != null) bindings[key] = action;
    }
    return PlayerKeyMap(bindings);
  }

  static PlayerKey? keyOf(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowUp => PlayerKey.up,
    LogicalKeyboardKey.arrowDown => PlayerKey.down,
    LogicalKeyboardKey.arrowLeft => PlayerKey.left,
    LogicalKeyboardKey.arrowRight => PlayerKey.right,
    LogicalKeyboardKey.enter ||
    LogicalKeyboardKey.numpadEnter ||
    LogicalKeyboardKey.select ||
    LogicalKeyboardKey.gameButtonA => PlayerKey.ok,
    LogicalKeyboardKey.contextMenu => PlayerKey.menu,
    _ => null,
  };
}

Future<PlayerKeyMap?> showPlayerKeyMapDialog(
  BuildContext context, {
  required PlayerKeyMap initial,
  required bool hardwareKeyboard,
}) => showDialog<PlayerKeyMap>(
  context: context,
  builder: (_) =>
      _PlayerKeyMapDialog(initial: initial, hardwareKeyboard: hardwareKeyboard),
);

class _PlayerKeyMapDialog extends StatefulWidget {
  const _PlayerKeyMapDialog({
    required this.initial,
    required this.hardwareKeyboard,
  });

  final PlayerKeyMap initial;
  final bool hardwareKeyboard;

  @override
  State<_PlayerKeyMapDialog> createState() => _PlayerKeyMapDialogState();
}

class _PlayerKeyMapDialogState extends State<_PlayerKeyMapDialog> {
  late PlayerKeyMap _map = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('播放按键'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '播放画面获得焦点时生效；方向键、确定键与菜单键可分别设置，空格、M、F 与 F11 保持固定。',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          for (final key in PlayerKey.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      key.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: DropdownButton<PlayerKeyAction>(
                      key: ValueKey('player-key-${key.name}'),
                      isExpanded: true,
                      value: _map[key],
                      items: [
                        for (final action in PlayerKeyAction.values)
                          DropdownMenuItem(
                            value: action,
                            child: Text(
                              action.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (action) {
                        if (action == null) return;
                        setState(() => _map = _map.withBinding(key, action));
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('player-keys-reset'),
        onPressed: () => setState(() => _map = const PlayerKeyMap()),
        child: const Text('恢复默认'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('player-keys-save'),
        onPressed: () => Navigator.pop(context, _map),
        child: const Text('保存'),
      ),
    ],
  );
}
