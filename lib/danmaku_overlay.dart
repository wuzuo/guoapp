import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'danmaku_controller.dart';
import 'danmaku_models.dart';

// 红果弹幕表情代码 -> Unicode emoji（对齐 hgtv-tv 的 DanmakuLayer.EMOJI_MAP）。
const Map<String, String> _danmakuEmojiMap = {
  '[微笑]': '😊',
  '[偷笑]': '🤭',
  '[笑]': '😄',
  '[什么]': '😳',
  '[害羞]': '🥰',
  '[爱慕]': '😍',
  '[飞吻]': '😘',
  '[奸笑]': '😏',
  '[尬笑]': '😅',
  '[思考]': '🤔',
  '[撇嘴]': '😒',
  '[做鬼脸]': '🤪',
  '[酷]': '😎',
  '[翻白眼]': '🙄',
  '[惊呆]': '😲',
  '[震惊]': '😱',
  '[送心]': '💕',
  '[委屈]': '🥺',
  '[快哭了]': '😢',
  '[笑哭]': '😂',
  '[哭]': '😭',
  '[大笑]': '🤣',
  '[舔屏]': '🤤',
  '[怒]': '😡',
  '[捂脸]': '🤦',
  '[吐]': '🤮',
  '[恐惧]': '😨',
  '[抓狂]': '🤯',
  '[敬礼]': '🫡',
  '[石化]': '🗿',
  '[OK]': '👌',
  '[赞]': '👍',
  '[爱心]': '❤️',
  '[伤心]': '💔',
  '[KISS]': '💋',
  '[懂了]': '👀',
  '[探究]': '🧐',
  '[重拳出击]': '👊',
  '[吃瓜]': '🍉',
  '[盯]': '👁️',
  '[你细品]': '🫣',
  '[赶稿中]': '✍️',
  '[注意]': '⚠️',
  '[饱了]': '🫃',
  '[码住]': '📌',
  '[学会了]': '✅',
  '[顶帖]': '🔝',
  '[求爆更]': '🔥',
  '[求关注]': '🙏',
  '[爽]': '😆',
  '[鼓掌]': '👏',
  '[没看够]': '🥹',
  '[送花]': '🌹',
};

final RegExp _danmakuEmojiPattern = RegExp(r'\[[^\]]+\]');

/// 把 `[表情]` 代码替换为 Unicode emoji，未知代码保持原样；返回分段列表。
List<(String, bool)> danmakuSegments(String source) {
  final segments = <(String, bool)>[];
  var last = 0;
  for (final match in _danmakuEmojiPattern.allMatches(source)) {
    final emoji = _danmakuEmojiMap[match.group(0)];
    if (emoji == null) continue;
    if (match.start > last) {
      segments.add((source.substring(last, match.start), false));
    }
    segments.add((emoji, true));
    last = match.end;
  }
  if (last < source.length) {
    segments.add((source.substring(last), false));
  }
  if (segments.isEmpty) segments.add((source, false));
  return segments;
}

List<DanmakuFlight> planDanmaku(
  List<DanmakuItem> items, {
  required double width,
  required int rows,
  required double Function(String) measure,
}) {
  if (!width.isFinite || width <= 0 || rows < 1) return const [];
  // 与 hgtv-tv 一致：屏幕上方两行，放不下则丢弃，优先保证不重叠。
  final lanes = List<DanmakuFlight?>.filled(rows.clamp(1, 2), null);
  final sorted = items.toList()..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final seen = <String>{};
  final flights = <DanmakuFlight>[];
  for (final item in sorted) {
    if (item.id.isEmpty ||
        item.text.trim().isEmpty ||
        item.timeMs < 0 ||
        !seen.add(item.id)) {
      continue;
    }
    if (flights.reversed
            .takeWhile(
              (flight) => item.timeMs - flight.item.timeMs < danmakuLifetimeMs,
            )
            .length >=
        24) {
      continue;
    }
    final rawRunes = item.text.runes;
    final raw =
        String.fromCharCodes(rawRunes.take(100)) +
        (rawRunes.length > 100 ? '…' : '');
    // 用表情替换后的显示文本测量宽度，避免 [微笑] 与 emoji 宽度不一致。
    final display = danmakuSegments(raw).map((segment) => segment.$1).join('');
    final size = measure(display).ceilToDouble() + 8;
    final lane = lanes.indexWhere((previous) {
      if (previous == null) return true;
      final gap = item.timeMs - previous.item.timeMs;
      if (gap >= danmakuLifetimeMs) return true;
      return (width + previous.width) * gap / danmakuLifetimeMs -
                  previous.width >=
              24 &&
          width -
                  (width + size) *
                      (danmakuLifetimeMs - gap) /
                      danmakuLifetimeMs >=
              24;
    });
    if (lane < 0) continue;
    final flight = DanmakuFlight(item, raw, lane, size);
    lanes[lane] = flight;
    flights.add(flight);
  }
  return flights;
}

class DanmakuFlight {
  const DanmakuFlight(this.item, this.text, this.lane, this.width);
  final DanmakuItem item;
  final String text;
  final int lane;
  final double width;
}

class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    required this.aspectRatio,
  });
  final DanmakuController controller;
  final double aspectRatio;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  Object? _layout;
  List<DanmakuFlight> _schedule = const [];

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final aspect = widget.aspectRatio.isFinite && widget.aspectRatio > 0
              ? widget.aspectRatio
              : 16 / 9;
          final width = math.min(
            constraints.maxWidth,
            constraints.maxHeight * aspect,
          );
          final height = math.min(
            constraints.maxHeight,
            constraints.maxWidth / aspect,
          );
          // 与 hgtv-tv 一致：字号约 18dp（窄屏 16），仅屏幕上方两行。
          final fontSize = width < 480 ? 16.0 : 18.0;
          final scaler = MediaQuery.textScalerOf(context);
          final rowHeight = scaler.scale(fontSize) * 1.5;
          final rows = ((height - 8) / rowHeight).floor().clamp(0, 2);
          final style = TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.2,
          );
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final controller = widget.controller;
                    if (!controller.visible || rows == 0) {
                      return const SizedBox.shrink();
                    }
                    final layout = (
                      controller,
                      controller.dataRevision,
                      width,
                      rows,
                      fontSize,
                      scaler,
                    );
                    if (_layout != layout) {
                      _layout = layout;
                      _schedule = planDanmaku(
                        controller.items,
                        width: width,
                        rows: rows,
                        measure: (text) {
                          final painter = TextPainter(
                            text: TextSpan(text: text, style: style),
                            textDirection: TextDirection.ltr,
                            textScaler: scaler,
                            maxLines: 1,
                          )..layout();
                          final measured = painter.width;
                          painter.dispose();
                          return measured;
                        },
                      );
                    }
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final flight in _schedule)
                          if (controller.positionMs >= flight.item.timeMs &&
                              controller.positionMs <
                                  flight.item.timeMs + danmakuLifetimeMs)
                            Positioned(
                              key: ValueKey('danmaku-item-${flight.item.id}'),
                              left: 0,
                              top: 8 + flight.lane * rowHeight,
                              width: flight.width,
                              height: rowHeight,
                              child: _DanmakuMotion(
                                flight: flight,
                                width: width,
                                positionMs: controller.positionMs,
                                moving: controller.moving,
                                rate: controller.rate,
                                revision: controller.motionRevision,
                                style: style,
                                scaler: scaler,
                              ),
                            ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _DanmakuMotion extends StatefulWidget {
  const _DanmakuMotion({
    required this.flight,
    required this.width,
    required this.positionMs,
    required this.moving,
    required this.rate,
    required this.revision,
    required this.style,
    required this.scaler,
  });
  final DanmakuFlight flight;
  final double width;
  final int positionMs;
  final bool moving;
  final double rate;
  final int revision;
  final TextStyle style;
  final TextScaler scaler;

  @override
  State<_DanmakuMotion> createState() => _DanmakuMotionState();
}

class _DanmakuMotionState extends State<_DanmakuMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_DanmakuMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.width != widget.width ||
        oldWidget.flight.width != widget.flight.width ||
        oldWidget.flight.item.timeMs != widget.flight.item.timeMs) {
      _sync();
    }
  }

  void _sync() {
    _motion.stop();
    final elapsed = (widget.positionMs - widget.flight.item.timeMs).clamp(
      0,
      danmakuLifetimeMs,
    );
    _motion.value = elapsed / danmakuLifetimeMs;
    if (widget.moving && elapsed < danmakuLifetimeMs) {
      _motion.animateTo(
        1,
        duration: Duration(
          microseconds: ((danmakuLifetimeMs - elapsed) * 1000 / widget.rate)
              .round()
              .clamp(1, 86400000000),
        ),
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: RepaintBoundary(
      child: Text.rich(
        TextSpan(
          children: _danmakuSpans(
            widget.flight.text,
            widget.style,
            widget.scaler,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: widget.scaler,
        maxLines: 1,
        softWrap: false,
      ),
    ),
    builder: (context, child) => Transform.translate(
      key: ValueKey('danmaku-motion-${widget.flight.item.id}'),
      offset: Offset(
        widget.width - (widget.width + widget.flight.width) * _motion.value,
        0,
      ),
      child: child,
    ),
  );
}

/// 把弹幕拆成内联片段：文字段用黑描边 + 白填充，表情段用原生彩色 emoji 不加描边。
List<InlineSpan> _danmakuSpans(
  String text,
  TextStyle style,
  TextScaler scaler,
) {
  final segments = danmakuSegments(text);
  return [
    for (final (content, isEmoji) in segments)
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: isEmoji
            ? Text(
                content,
                style: style,
                textScaler: scaler,
                textDirection: TextDirection.ltr,
              )
            : _DanmakuStrokeText(content, style, scaler),
      ),
  ];
}

/// 白字 + 黑描边两层（对齐 hgtv-tv 的 textPaint 描边绘制）。
class _DanmakuStrokeText extends StatelessWidget {
  const _DanmakuStrokeText(this.text, this.style, this.scaler);
  final String text;
  final TextStyle style;
  final TextScaler scaler;

  @override
  Widget build(BuildContext context) {
    final strokeWidth = math.max(2.0, (style.fontSize ?? 18) * 0.16);
    return Stack(
      children: [
        Text(
          text,
          textScaler: scaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          softWrap: false,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = Colors.black,
          ),
        ),
        Text(
          text,
          style: style,
          textScaler: scaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          softWrap: false,
        ),
      ],
    );
  }
}
