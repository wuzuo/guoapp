import 'package:flutter/material.dart';

@immutable
class NeuPalette {
  const NeuPalette({
    required this.id,
    required this.name,
    required this.base,
    required this.light,
    required this.dark,
    required this.lit,
    required this.onLit,
    required this.ink,
    required this.accent,
    required this.tips,
    required this.isDark,
  });

  static const deepDark = NeuPalette(
    id: 'deep-dark',
    name: '深邃暗调',
    base: Color(0xFF2E3238),
    light: Color(0xFF383D44),
    dark: Color(0xFF24272C),
    lit: Color(0xFFF0EAE0),
    onLit: Color(0xFF1A1612),
    ink: Color(0xFFF4F3F1),
    accent: Color(0xFFDFB77C),
    tips: Color(0xFFFFC24B),
    isDark: true,
  );

  static const softGray = NeuPalette(
    id: 'soft-gray',
    name: '经典浅灰',
    base: Color(0xFFE0E5EC),
    light: Color(0xFFFFFFFF),
    dark: Color(0xFFA3B1C6),
    lit: Color(0xFFFFFFFF),
    onLit: Color(0xFF2B3444),
    ink: Color(0xFF39435A),
    accent: Color(0xFF5F6E8C),
    tips: Color(0xFFC8871F),
    isDark: false,
  );

  final String id;
  final String name;
  final Color base;
  final Color light;
  final Color dark;
  final Color lit;
  final Color onLit;
  final Color ink;
  final Color accent;
  final Color tips;
  final bool isDark;

  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  Color get surface => Color.lerp(base, light, .45)!;
  Color get surfaceHigh => Color.lerp(base, light, .72)!;
  Color get well => Color.lerp(base, dark, .45)!;
  Color get wellDeep => Color.lerp(base, dark, .72)!;

  Color get shadowLight => light.withValues(alpha: isDark ? .62 : .72);
  Color get shadowDark => dark.withValues(alpha: isDark ? .62 : .72);
  Color get glow => lit.withValues(alpha: isDark ? .2 : .35);

  Color get text => ink;
  Color get textStrong => ink.withValues(alpha: .84);
  Color get textDim => ink.withValues(alpha: .7);
  Color get muted => ink.withValues(alpha: .62);
  Color get outline => ink.withValues(alpha: .1);
  Color get separator => ink.withValues(alpha: .08);
  Color get focusLine => ink.withValues(alpha: .45);

  static NeuPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? deepDark : softGray;
}

class NeuTheme extends InheritedWidget {
  const NeuTheme({super.key, required this.palette, required super.child});

  final NeuPalette palette;

  static NeuPalette? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NeuTheme>()?.palette;

  static NeuPalette of(BuildContext context) =>
      maybeOf(context) ??
      NeuPalette.forBrightness(Theme.of(context).brightness);

  @override
  bool updateShouldNotify(NeuTheme oldWidget) =>
      palette.id != oldWidget.palette.id;
}

class NeuSurface extends StatelessWidget {
  const NeuSurface({
    super.key,
    this.child,
    this.radius = 18,
    this.inset = false,
    this.padding,
    this.color,
    this.lift = 0,
    this.border = true,
    this.clip = false,
  });

  final Widget? child;
  final double radius;
  final bool inset;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double lift;
  final bool border;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    final radiusValue = BorderRadius.circular(radius);
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    if (inset) {
      return CustomPaint(
        painter: _NeuInsetPainter(
          palette: palette,
          radius: radius,
          color: color ?? palette.well,
        ),
        child: Padding(padding: EdgeInsets.zero, child: content),
      );
    }
    final offset = 3 + lift;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: radiusValue,
        border: border ? Border.all(color: palette.outline) : null,
        boxShadow: [
          BoxShadow(
            color: palette.shadowDark,
            offset: Offset(offset, offset),
            blurRadius: 10 + lift * 2,
          ),
          BoxShadow(
            color: palette.shadowLight,
            offset: Offset(-offset, -offset),
            blurRadius: 10 + lift * 2,
          ),
        ],
      ),
      child: clip
          ? ClipRRect(borderRadius: radiusValue, child: content)
          : content,
    );
  }
}

class NeuHover extends StatefulWidget {
  const NeuHover({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 18,
    this.padding,
    this.enabled = true,
    this.selected = false,
    this.tooltip,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool enabled;
  final bool selected;
  final String? tooltip;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  @override
  State<NeuHover> createState() => _NeuHoverState();
}

class _NeuHoverState extends State<NeuHover> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    final active = widget.enabled && (_hovered || _focused);
    final target = active ? 1.0 : 0.0;
    Widget surface = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      builder: (context, value, _) => NeuSurface(
        radius: widget.radius,
        lift: value,
        color: Color.lerp(palette.surface, palette.surfaceHigh, value),
        padding: widget.padding ?? const EdgeInsets.all(10),
        child: widget.child,
      ),
    );
    if (widget.selected) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: palette.accent, width: 1.5),
        ),
        child: surface,
      );
    }
    surface = MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FocusableActionDetector(
        enabled: widget.enabled,
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          onLongPress: widget.enabled ? widget.onLongPress : null,
          onSecondaryTap: widget.enabled ? widget.onSecondaryTap : null,
          child: surface,
        ),
      ),
    );
    if (widget.tooltip == null) return surface;
    return Tooltip(message: widget.tooltip!, child: surface);
  }
}

class NeuChip extends StatelessWidget {
  const NeuChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSelected,
        child: NeuSurface(
          inset: selected,
          radius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: selected ? palette.well : palette.surface,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? palette.accent : palette.textDim,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? palette.accent : palette.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NeuSectionLabel extends StatelessWidget {
  const NeuSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                color: palette.textStrong,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _NeuInsetPainter extends CustomPainter {
  _NeuInsetPainter({
    required this.palette,
    required this.radius,
    required this.color,
  });

  final NeuPalette palette;
  final double radius;
  final Color color;

  static const _depth = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = color);
    canvas.save();
    canvas.clipRRect(rrect);
    void inner(Color shade, Offset shift) {
      canvas.drawRRect(
        rrect.shift(shift),
        Paint()
          ..color = shade
          ..style = PaintingStyle.stroke
          ..strokeWidth = _depth * 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _depth),
      );
    }

    inner(palette.shadowDark, const Offset(_depth, _depth));
    inner(palette.shadowLight, const Offset(-_depth, -_depth));
    canvas.restore();
    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..color = palette.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _NeuInsetPainter oldDelegate) =>
      oldDelegate.palette.id != palette.id ||
      oldDelegate.radius != radius ||
      oldDelegate.color != color;
}
