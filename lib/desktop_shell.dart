import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'neumorphic.dart';

class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _maximized = false;
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager
        .isMaximized()
        .catchError((Object _) => false)
        .then((value) {
          if (mounted && value != _maximized) setState(() => _maximized = value);
        });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullScreen = false);
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized().catchError((Object _) => false)) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    return ColoredBox(
      color: palette.base,
      child: Column(
        children: [
          if (!_fullScreen)
            _Caption(
              title: widget.title,
              maximized: _maximized,
              onToggleMaximize: _toggleMaximize,
            ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.title,
    required this.maximized,
    required this.onToggleMaximize,
  });

  final String title;
  final bool maximized;
  final Future<void> Function() onToggleMaximize;

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: onToggleMaximize,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.play_circle_fill_rounded,
                        size: 16,
                        color: palette.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .6,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _WindowButton(
            icon: Icons.remove_rounded,
            tip: '最小化',
            onPressed: windowManager.minimize,
          ),
          _WindowButton(
            icon: maximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            tip: maximized ? '还原' : '最大化',
            size: maximized ? 12 : 13,
            onPressed: onToggleMaximize,
          ),
          _WindowButton(
            icon: Icons.close_rounded,
            tip: '关闭',
            danger: true,
            onPressed: windowManager.close,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tip,
    required this.onPressed,
    this.danger = false,
    this.size = 16,
  });

  final IconData icon;
  final String tip;
  final VoidCallback onPressed;
  final bool danger;
  final double size;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    final background = widget.danger
        ? const Color(0xFFC4553F)
        : palette.surfaceHigh;
    return Tooltip(
      message: widget.tip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: 32,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: _hovered ? background : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: _hovered && widget.danger ? Colors.white : palette.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopNavItem {
  const DesktopNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class DesktopNavRail extends StatelessWidget {
  const DesktopNavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
    this.footer,
  });

  final List<DesktopNavItem> items;
  final int index;
  final ValueChanged<int> onSelected;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    return Container(
      width: 100,
      decoration: BoxDecoration(
        color: palette.base,
        border: Border(right: BorderSide(color: palette.separator)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          NeuSurface(
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Icon(
              Icons.play_circle_fill_rounded,
              size: 24,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < items.length; i++) ...[
            _NavItem(
              item: items[i],
              selected: i == index,
              onTap: () => onSelected(i),
            ),
            const SizedBox(height: 10),
          ],
          const Spacer(),
          if (footer != null) ...[
            footer!,
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final DesktopNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = NeuTheme.of(context);
    final active = widget.selected || _hovered;
    final color = widget.selected
        ? palette.accent
        : _hovered
        ? palette.text
        : palette.muted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: widget.selected ? palette.well : palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected ? palette.focusLine : palette.outline,
            ),
            boxShadow: widget.selected
                ? null
                : [
                    BoxShadow(
                      color: palette.shadowDark,
                      offset: const Offset(3, 3),
                      blurRadius: 9,
                    ),
                    BoxShadow(
                      color: palette.shadowLight,
                      offset: const Offset(-3, -3),
                      blurRadius: 9,
                    ),
                  ],
          ),
          child: Column(
            children: [
              Icon(
                widget.selected ? widget.item.selectedIcon : widget.item.icon,
                size: 22,
                color: active ? color : palette.muted,
              ),
              const SizedBox(height: 7),
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: widget.selected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
