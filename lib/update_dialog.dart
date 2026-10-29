import 'dart:io';

import 'package:flutter/material.dart';

import 'app_update.dart';

Future<void> showAppUpdateDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _UpdateDialog());

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  AppUpdate? _update;
  String? _error;
  String _status = '正在检查更新…';
  double? _progress;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final update = await AppUpdateService.check();
      if (!mounted) return;
      setState(() {
        _update = update;
        _busy = false;
        _status = update == null ? '已是最新版本' : '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '检查更新失败，请确认网络可以访问 GitHub';
        _status = '';
      });
    }
  }

  Future<void> _download() async {
    final update = _update;
    if (update == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _status = '正在下载…';
    });
    try {
      final file = await AppUpdateService.download(
        update,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = (received / total).clamp(0, 1));
        },
      );
      if (!mounted) return;
      final started = await AppUpdateService.install(file);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _status = started
            ? Platform.isWindows
                  ? '已下载到 ${file.path}，解压覆盖原目录即可升级'
                  : '已开始安装，按提示确认即可'
            : '无法自动安装，请到 GitHub Release 手动下载';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _status = '';
        _error = '下载失败，请稍后重试或到 GitHub Release 手动下载';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    return AlertDialog(
      title: const Text('检查更新'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy && _progress == null)
              const LinearProgressIndicator(minHeight: 3),
            if (_busy && _progress != null) ...[
              LinearProgressIndicator(value: _progress, minHeight: 4),
              const SizedBox(height: 6),
              Text('${((_progress ?? 0) * 100).round()}%'),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_status),
            ],
            if (update != null) ...[
              const SizedBox(height: 12),
              Text(
                '新版本 ${update.version}${update.sizeLabel.isEmpty ? '' : ' · ${update.sizeLabel}'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Text(
                    update.notes.isEmpty ? '该版本没有附更新说明。' : update.notes,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (update != null && !_busy)
          FilledButton(
            onPressed: _download,
            child: Text(Platform.isWindows ? '下载更新包' : '下载并安装'),
          ),
      ],
    );
  }
}
