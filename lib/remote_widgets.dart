import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RemoteTarget extends StatefulWidget {
  const RemoteTarget({
    super.key,
    required this.child,
    required this.onPressed,
    this.focusNode,
    this.onFocus,
    this.autofocus = false,
    this.selected = false,
    this.label,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final bool autofocus;
  final bool selected;
  final String? label;

  @override
  State<RemoteTarget> createState() => _RemoteTargetState();
}

class _RemoteTargetState extends State<RemoteTarget> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
    enabled: widget.onPressed != null,
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onPressed?.call();
          return null;
        },
      ),
    },
    onFocusChange: (focused) {
      if (mounted) {
        setState(() => _focused = focused);
      }
      if (focused) {
        widget.onFocus?.call();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_focused) return;
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          );
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        });
      }
    },
    child: Semantics(
      button: true,
      enabled: widget.onPressed != null,
      focused: _focused,
      label: widget.label,
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _focused
                  ? Theme.of(context).colorScheme.primaryContainer
                  : widget.selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? Theme.of(context).colorScheme.primary
                    : widget.selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 3,
              ),
            ),
            child: ExcludeFocus(child: widget.child),
          ),
        ),
      ),
    ),
  );
}

class RemoteButton extends StatelessWidget {
  const RemoteButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.dense = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool dense;

  @override
  Widget build(BuildContext context) => RemoteTarget(
    onPressed: onPressed,
    selected: selected,
    autofocus: autofocus,
    focusNode: focusNode,
    label: label,
    child: Padding(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 9, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 18 : 22),
            SizedBox(width: dense ? 5 : 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 13 : 17,
              color: onPressed == null
                  ? Theme.of(context).disabledColor
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    ),
  );
}

class RemoteGrid extends StatefulWidget {
  const RemoteGrid({
    super.key,
    required this.itemKeys,
    required this.columns,
    required this.itemExtent,
    required this.itemBuilder,
    this.controller,
    this.spacing = 14,
    this.padding = const EdgeInsets.all(18),
    this.footer,
    this.initialIndex = 0,
    this.autofocus = false,
  });
  final List<String> itemKeys;
  final int columns;
  final double itemExtent;
  final double spacing;
  final EdgeInsets padding;
  final ScrollController? controller;
  final Widget? footer;
  final int initialIndex;
  final bool autofocus;
  final Widget Function(BuildContext, int, FocusNode, VoidCallback) itemBuilder;

  @override
  State<RemoteGrid> createState() => _RemoteGridState();
}

class _RemoteGridState extends State<RemoteGrid> {
  final _ownScroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  String? _focused;
  String? _target;
  int _generation = 0;
  ScrollController get _scroll => widget.controller ?? _ownScroll;

  FocusNode _node(int index) => _nodes.putIfAbsent(
    widget.itemKeys[index],
    () => FocusNode(debugLabel: 'remote-${widget.itemKeys[index]}'),
  );

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.itemKeys.isNotEmpty) {
          _focusAt(widget.initialIndex.clamp(0, widget.itemKeys.length - 1));
        }
      });
    }
  }

  void _focusAt(int index) {
    final generation = ++_generation;
    _target = widget.itemKeys[index];
    final node = _node(index);
    if (node.context != null) {
      node.requestFocus();
      _target = null;
      return;
    }
    if (_scroll.hasClients) {
      final top =
          widget.padding.top +
          (index ~/ widget.columns) * (widget.itemExtent + widget.spacing);
      final offset = top < _scroll.offset
          ? top
          : top + widget.itemExtent - _scroll.position.viewportDimension;
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation && node.context != null) {
        node.requestFocus();
        _target = null;
      }
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_focused == null || !(_nodes[_focused]?.hasFocus ?? false)) {
      return KeyEventResult.ignored;
    }
    final index = widget.itemKeys.indexOf(_target ?? _focused!);
    if (index < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final int next;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index ~/ widget.columns ==
          (widget.itemKeys.length - 1) ~/ widget.columns) {
        return KeyEventResult.ignored;
      }
      next = (index + widget.columns).clamp(0, widget.itemKeys.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = index - widget.columns;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (index % widget.columns == widget.columns - 1 ||
          index == widget.itemKeys.length - 1) {
        return KeyEventResult.handled;
      }
      next = index + 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (index % widget.columns == 0) {
        return widget.columns <= 1
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      next = index - 1;
    } else {
      return KeyEventResult.ignored;
    }
    if (next < 0 || next >= widget.itemKeys.length) {
      return KeyEventResult.ignored;
    }
    _focusAt(next);
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant RemoteGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final removed = _nodes.keys
        .where((key) => !widget.itemKeys.contains(key))
        .toList();
    final restore = removed.any((key) => _nodes[key]!.hasFocus);
    final index = oldWidget.itemKeys.indexOf(_focused ?? '');
    for (final key in removed) {
      _nodes.remove(key)?.dispose();
    }
    if (_focused != null && !widget.itemKeys.contains(_focused)) {
      _focused = null;
      _target = null;
      _generation++;
    }
    if (restore && widget.itemKeys.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.itemKeys.isNotEmpty) {
          _focusAt(index.clamp(0, widget.itemKeys.length - 1));
        }
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    for (final node in _nodes.values) {
      node.dispose();
    }
    _ownScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _key,
    child: CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: widget.padding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.columns,
              mainAxisExtent: widget.itemExtent,
              crossAxisSpacing: widget.spacing,
              mainAxisSpacing: widget.spacing,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  widget.itemBuilder(context, index, _node(index), () {
                    _focused = widget.itemKeys[index];
                  }),
              childCount: widget.itemKeys.length,
            ),
          ),
        ),
        if (widget.footer != null) SliverToBoxAdapter(child: widget.footer),
      ],
    ),
  );
}

class RemoteEpisodeButton extends StatelessWidget {
  const RemoteEpisodeButton({
    super.key,
    required this.number,
    required this.onPressed,
    this.vip = false,
    this.current = false,
    this.focusNode,
    this.onFocus,
  });
  final int number;
  final bool vip;
  final bool current;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) => RemoteTarget(
    focusNode: focusNode,
    onFocus: onFocus,
    selected: current,
    onPressed: onPressed,
    label: '第 $number 集${vip ? '，VIP 试看' : ''}',
    child: Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '$number',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20),
            ),
          ),
          if (vip) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.workspace_premium_rounded,
              color: Theme.of(context).colorScheme.tertiary,
              size: 18,
            ),
          ],
        ],
      ),
    ),
  );
}

class TelevisionSearchDialog extends StatefulWidget {
  const TelevisionSearchDialog({
    super.key,
    required this.initialValue,
    required this.title,
    this.suggestions,
    this.recentSearches = const [],
    this.onCancel,
  });
  final Future<List<String>> Function(String)? suggestions;
  final List<String> recentSearches;
  final VoidCallback? onCancel;
  final String initialValue;
  final String title;

  @override
  State<TelevisionSearchDialog> createState() => _TelevisionSearchDialogState();
}

class _TelevisionSearchDialogState extends State<TelevisionSearchDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final _field = FocusNode(debugLabel: 'tv-search-field');
  final _search = FocusNode(debugLabel: 'tv-search-submit');
  final _clear = FocusNode(debugLabel: 'tv-search-clear');
  final _cancel = FocusNode(debugLabel: 'tv-search-cancel');
  final _rows = <int, FocusNode>{};
  List<String> _items = const [];
  bool _recent = false;
  Timer? _timer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue.trim().isEmpty) {
      _recent = true;
      _items = widget.recentSearches.take(8).toList();
    } else {
      _schedule(widget.initialValue);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    for (final node in [_field, _search, _clear, _cancel]) {
      node.dispose();
    }
    for (final node in _rows.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _rowNode(int index) => _rows.putIfAbsent(
    index,
    () => FocusNode(debugLabel: 'tv-search-row-$index'),
  );

  void _showItems({required bool recent, required List<String> items}) {
    for (final index
        in _rows.keys.where((index) => index >= items.length).toList()) {
      _rows.remove(index)?.dispose();
    }
    setState(() {
      _recent = recent;
      _items = items;
    });
  }

  void _schedule(String value) {
    _timer?.cancel();
    final generation = ++_generation;
    final query = value.trim();
    if (query.isEmpty || query.length > 100 || widget.suggestions == null) {
      _showItems(recent: true, items: widget.recentSearches.take(8).toList());
      return;
    }
    _timer = Timer(const Duration(milliseconds: 300), () async {
      List<String> result;
      try {
        result = (await widget.suggestions!(
          query,
        )).where((entry) => entry.trim().isNotEmpty).toSet().take(8).toList();
      } catch (_) {
        result = const [];
      }
      if (!mounted || generation != _generation) return;
      _showItems(recent: false, items: result);
    });
  }

  void _close([String? value]) {
    if (value == null) widget.onCancel?.call();
    Navigator.pop(context, value);
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _close(query);
  }

  List<FocusNode> get _order => [
    _field,
    for (var index = 0; index < _items.length; index++) _rowNode(index),
    if (_controller.text.isNotEmpty) _clear,
    _search,
    _cancel,
  ];

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    final order = _order;
    final index = order.indexOf(focused ?? _field);
    if (index < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index >= order.length - 1) return KeyEventResult.handled;
      order[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index == 0) return KeyEventResult.handled;
      order[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (focused == _field) return KeyEventResult.ignored;
      final buttons = [
        if (_controller.text.isNotEmpty) _clear,
        _search,
        _cancel,
      ];
      final current = buttons.indexOf(focused ?? _search);
      if (current < 0) return KeyEventResult.handled;
      final next = key == LogicalKeyboardKey.arrowRight
          ? min(current + 1, buttons.length - 1)
          : max(current - 1, 0);
      buttons[next].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _key,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              focusNode: _field,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                setState(() {});
                _schedule(value);
              },
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: '输入剧名',
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_controller.text.isNotEmpty)
                      IconButton(
                        tooltip: '清空输入',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                          _schedule('');
                          _field.requestFocus();
                        },
                      ),
                    IconButton(
                      tooltip: '搜索',
                      focusNode: _search,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: () => _submit(_controller.text),
                    ),
                  ],
                ),
              ),
            ),
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _recent ? '最近搜索' : '搜索建议',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _items.length,
                  itemBuilder: (context, index) => RemoteTarget(
                    key: ValueKey('search-suggestion-$index'),
                    focusNode: _rowNode(index),
                    label: _items[index],
                    onPressed: () => _submit(_items[index]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _recent
                                ? Icons.history_rounded
                                : Icons.search_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _items[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          focusNode: _cancel,
          onPressed: _close,
          child: const Text('取消'),
        ),
        if (_controller.text.isNotEmpty)
          TextButton(
            focusNode: _clear,
            onPressed: () => _close(''),
            child: const Text('清空'),
          ),
        FilledButton(
          focusNode: _search,
          onPressed: () => _submit(_controller.text),
          child: const Text('搜索'),
        ),
      ],
    ),
  );
}
