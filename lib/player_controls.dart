import 'dart:async';

import 'package:flutter/material.dart';

import 'player_interactions.dart';
import 'remote_widgets.dart';
import 'widgets.dart';
import 'lan_screen.dart';
import 'playback_player.dart';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.interactions,
    required this.enabled,
    required this.fullscreen,
    required this.onFullscreen,
    required this.onPrevious,
    required this.onNext,
    required this.title,
    required this.onTogglePlayback,
    required this.onEpisodes,
    required this.onSettings,
    required this.onSpeed,
    required this.onQuality,
    required this.speed,
    required this.qualityLabel,
    required this.onFocusSurface,
    this.swipeEnabled = false,
    this.panelOpen = false,
    this.seamless = false,
    this.showProgress = true,
    this.onSeek,
    this.onPush,
  });

  final PlaybackPlayer player;
  final PlayerInteractions interactions;
  final bool enabled;
  final bool fullscreen;
  final VoidCallback onFullscreen;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String title;
  final VoidCallback onTogglePlayback;
  final Future<void> Function() onEpisodes;
  final Future<void> Function() onSettings;
  final Future<void> Function() onSpeed;
  final Future<void> Function() onQuality;
  final double speed;
  final String qualityLabel;
  final VoidCallback onFocusSurface;
  final bool swipeEnabled;
  final bool panelOpen;
  final bool seamless;
  final bool showProgress;
  final Future<void> Function(Duration)? onSeek;
  final Future<void> Function()? onPush;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _hideTimer;
  bool _visible = true;
  double? _seekValue;

  @override
  void initState() {
    super.initState();
    if (widget.seamless) _visible = false;
    for (final stream in [
      widget.player.stream.position,
      widget.player.stream.duration,
      widget.player.stream.buffer,
      widget.player.stream.playing,
      widget.player.stream.buffering,
      widget.player.stream.volume,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          if (mounted) setState(() {});
        }),
      );
    }
    _subscriptions.add(widget.player.stream.playing.listen((_) => _show()));
    widget.interactions.addListener(_interactionChanged);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seamless && !oldWidget.seamless) {
      _seekValue = null;
      _visible = false;
    }
    if (!widget.seamless &&
        (widget.enabled != oldWidget.enabled ||
            widget.panelOpen != oldWidget.panelOpen ||
            widget.fullscreen != oldWidget.fullscreen)) {
      _seekValue = null;
      _visible = true;
      _scheduleHide();
    }
  }

  void _interactionChanged() {
    if (mounted && widget.interactions.feedback.isNotEmpty) _show(user: true);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.enabled ||
        widget.panelOpen ||
        !widget.player.state.playing ||
        _seekValue != null) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          widget.enabled &&
          !widget.panelOpen &&
          widget.player.state.playing &&
          !widget.player.state.buffering &&
          !widget.interactions.boosting &&
          _seekValue == null) {
        setState(() => _visible = false);
      }
    });
  }

  void _show({bool user = false}) {
    if (!mounted) return;
    if (widget.seamless && !user) return;
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _tap() {
    if (widget.interactions.suppressTap) return;
    widget.onFocusSurface();
    if (widget.swipeEnabled &&
        MediaQuery.orientationOf(context) == Orientation.portrait &&
        widget.enabled) {
      widget.onTogglePlayback();
      _show(user: true);
    } else {
      setState(() => _visible = !_visible);
      _scheduleHide();
    }
  }

  Future<void> _panel(Future<void> Function() open) async {
    _hideTimer?.cancel();
    widget.interactions.cancel();
    await open();
    _show(user: true);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.interactions.removeListener(_interactionChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.player.state;
    final duration = state.duration.inMilliseconds / 1000;
    final position = state.position.inMilliseconds / 1000;
    final buffered = state.buffer.inMilliseconds / 1000;
    final visible =
        _visible ||
        (!widget.seamless && (!state.playing || state.buffering)) ||
        widget.panelOpen;
    return MouseRegion(
      onHover: (_) => _show(user: true),
      cursor: visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              key: const ValueKey('player-gesture-surface'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                widget.onFocusSurface();
                widget.interactions.pointerDown(
                  event,
                  swipeEnabled: widget.swipeEnabled,
                  height: constraints.maxHeight,
                );
              },
              onPointerMove: widget.interactions.pointerMove,
              onPointerUp: widget.interactions.pointerUp,
              onPointerCancel: widget.interactions.pointerCancel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _tap,
                onDoubleTap: () {
                  if (!widget.enabled || widget.interactions.suppressTap) {
                    return;
                  }
                  widget.onTogglePlayback();
                  _show(user: true);
                },
              ),
            ),
            if (state.buffering && widget.enabled && !widget.seamless)
              const IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            IgnorePointer(
              ignoring: !visible,
              child: ExcludeFocus(
                excluding: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x99000000),
                                Colors.transparent,
                                Color(0xDD000000),
                              ],
                              stops: [0, .45, 1],
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        top: widget.fullscreen,
                        bottom: widget.fullscreen,
                        minimum: const EdgeInsets.symmetric(horizontal: 8),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: Row(
                                children: [
                                  if (widget.fullscreen)
                                    IconButton(
                                      tooltip: '退出全屏',
                                      onPressed: widget.onFullscreen,
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (widget.fullscreen &&
                                      widget.onPush != null)
                                    LanPushButton(
                                      key: const ValueKey(
                                        'fullscreen-lan-push',
                                      ),
                                      onPressed: widget.enabled
                                          ? () => _panel(widget.onPush!)
                                          : null,
                                    ),
                                  IconButton(
                                    key: const ValueKey('player-settings'),
                                    tooltip: '播放设置',
                                    onPressed: () => _panel(widget.onSettings),
                                    icon: const Icon(Icons.tune_rounded),
                                  ),
                                ],
                              ),
                            ),
                            if (!widget.fullscreen &&
                                !state.buffering &&
                                widget.enabled &&
                                constraints.maxHeight >= 300)
                              Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '上一集',
                                      onPressed: widget.onPrevious,
                                      icon: const Icon(
                                        Icons.skip_previous_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton.filledTonal(
                                      tooltip: state.playing ? '暂停' : '播放',
                                      iconSize: 38,
                                      onPressed: () {
                                        widget.onTogglePlayback();
                                        _show(user: true);
                                      },
                                      icon: Icon(
                                        state.playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      tooltip: '下一集',
                                      onPressed: widget.onNext,
                                      icon: const Icon(Icons.skip_next_rounded),
                                    ),
                                  ],
                                ),
                              ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.fullscreen &&
                                      constraints.maxHeight >= 240)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                RemoteButton(
                                                  key: const ValueKey(
                                                    'player-previous',
                                                  ),
                                                  dense: true,
                                                  label: '上一集',
                                                  icon: Icons
                                                      .skip_previous_rounded,
                                                  onPressed: widget.onPrevious,
                                                ),
                                                RemoteButton(
                                                  key: const ValueKey(
                                                    'player-play-pause',
                                                  ),
                                                  dense: true,
                                                  label: state.playing
                                                      ? '暂停'
                                                      : '播放',
                                                  icon: state.playing
                                                      ? Icons.pause_rounded
                                                      : Icons
                                                            .play_arrow_rounded,
                                                  onPressed: widget.enabled
                                                      ? widget.onTogglePlayback
                                                      : null,
                                                ),
                                                RemoteButton(
                                                  key: const ValueKey(
                                                    'player-next',
                                                  ),
                                                  dense: true,
                                                  label: '下一集',
                                                  icon: Icons.skip_next_rounded,
                                                  onPressed: widget.onNext,
                                                ),
                                                RemoteButton(
                                                  key: const ValueKey(
                                                    'player-episodes',
                                                  ),
                                                  dense: true,
                                                  label: '选集',
                                                  icon: Icons.grid_view_rounded,
                                                  onPressed: () =>
                                                      _panel(widget.onEpisodes),
                                                ),
                                                RemoteButton(
                                                  key: const ValueKey(
                                                    'player-speed',
                                                  ),
                                                  dense: true,
                                                  label: '${widget.speed}x',
                                                  icon: Icons.speed_rounded,
                                                  onPressed: () =>
                                                      _panel(widget.onSpeed),
                                                ),
                                                RemoteButton(
                                                  key: const ValueKey(
                                                    'player-quality',
                                                  ),
                                                  dense: true,
                                                  label: widget.qualityLabel,
                                                  icon: Icons.hd_rounded,
                                                  onPressed: () =>
                                                      _panel(widget.onQuality),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '${formatPosition(_seekValue ?? position)} / ${formatPosition(duration)}',
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                        if (!widget.swipeEnabled)
                                          IconButton(
                                            tooltip: state.volume == 0
                                                ? '取消静音'
                                                : '静音',
                                            visualDensity:
                                                VisualDensity.compact,
                                            iconSize: 20,
                                            onPressed: widget.enabled
                                                ? widget.interactions.toggleMute
                                                : null,
                                            icon: Icon(
                                              state.volume == 0
                                                  ? Icons.volume_off_rounded
                                                  : Icons.volume_up_rounded,
                                            ),
                                          ),
                                        IconButton(
                                          tooltip: widget.fullscreen
                                              ? '退出全屏'
                                              : '旋转与全屏',
                                          visualDensity: VisualDensity.compact,
                                          iconSize: 20,
                                          onPressed: widget.onFullscreen,
                                          icon: Icon(
                                            widget.fullscreen
                                                ? Icons.fullscreen_exit_rounded
                                                : Icons.fullscreen_rounded,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Row(
                                      children: [
                                        if (constraints.maxHeight < 300)
                                          IconButton(
                                            tooltip: state.playing
                                                ? '暂停'
                                                : '播放',
                                            onPressed: widget.enabled
                                                ? widget.onTogglePlayback
                                                : null,
                                            icon: Icon(
                                              state.playing
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            '${formatPosition(_seekValue ?? position)} / ${formatPosition(duration)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        if (!widget.swipeEnabled)
                                          IconButton(
                                            tooltip: state.volume == 0
                                                ? '取消静音'
                                                : '静音',
                                            onPressed: widget.enabled
                                                ? widget.interactions.toggleMute
                                                : null,
                                            icon: Icon(
                                              state.volume == 0
                                                  ? Icons.volume_off_rounded
                                                  : Icons.volume_up_rounded,
                                            ),
                                          ),
                                        IconButton(
                                          tooltip: widget.fullscreen
                                              ? '退出全屏'
                                              : '旋转与全屏',
                                          onPressed: widget.onFullscreen,
                                          icon: Icon(
                                            widget.fullscreen
                                                ? Icons.fullscreen_exit_rounded
                                                : Icons.fullscreen_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (widget.showProgress)
                                    _ProgressTrack(
                                      key: const ValueKey('player-progress'),
                                      position: _seekValue ?? position,
                                      buffered: buffered,
                                      duration: duration,
                                      enabled: widget.enabled,
                                      onScrub: (value) {
                                        widget.interactions.cancel();
                                        _hideTimer?.cancel();
                                        setState(() => _seekValue = value);
                                      },
                                      onCommit: (value) {
                                        if (duration > 0) {
                                          (widget.onSeek ?? widget.player.seek)(
                                            Duration(
                                              milliseconds: (value * 1000)
                                                  .round(),
                                            ),
                                          );
                                        }
                                        setState(() => _seekValue = null);
                                        _show(user: true);
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: widget.interactions,
              builder: (context, _) {
                final feedback = widget.interactions.feedback;
                if (feedback.isEmpty) return const SizedBox.shrink();
                return IgnorePointer(
                  child: Align(
                    alignment: const Alignment(0, -.5),
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(feedback, textAlign: TextAlign.center),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressTrack extends StatefulWidget {
  const _ProgressTrack({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.enabled,
    required this.onScrub,
    required this.onCommit,
  });

  final double position;
  final double buffered;
  final double duration;
  final bool enabled;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onCommit;

  @override
  State<_ProgressTrack> createState() => _ProgressTrackState();
}

class _ProgressTrackState extends State<_ProgressTrack> {
  double? _drag;
  double _last = 0;

  double get _limit => widget.duration > 0 ? widget.duration : 1;

  void _update(Offset local, double width) {
    if (!widget.enabled || widget.duration <= 0 || width <= 0) return;
    final value = (local.dx / width).clamp(0.0, 1.0) * _limit;
    _last = value;
    setState(() => _drag = value);
    widget.onScrub(value);
  }

  void _commit() {
    if (_drag != null) widget.onCommit(_last);
    if (mounted) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final value = (_drag ?? widget.position).clamp(0.0, _limit) / _limit;
      final buffered = widget.buffered.clamp(0.0, _limit) / _limit;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _update(details.localPosition, width),
        onTapUp: (_) => _commit(),
        onTapCancel: _commit,
        onHorizontalDragStart: (details) =>
            _update(details.localPosition, width),
        onHorizontalDragUpdate: (details) =>
            _update(details.localPosition, width),
        onHorizontalDragEnd: (_) => _commit(),
        onHorizontalDragCancel: _commit,
        child: SizedBox(
          height: 18,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.white24),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: buffered,
                    child: const ColoredBox(color: Colors.white38),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
