import 'package:flutter/material.dart';

import 'local_store.dart';
import 'webdav_client.dart';
import 'webdav_sync.dart';

class WebdavScreen extends StatefulWidget {
  const WebdavScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<WebdavScreen> createState() => _WebdavScreenState();
}

class _WebdavScreenState extends State<WebdavScreen> {
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  bool _autoSync = false;
  bool _obscure = true;
  bool _busy = false;
  bool _failed = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final config = widget.store.webdavConfig;
    _url = TextEditingController(text: config.url);
    _username = TextEditingController(text: config.username);
    _password = TextEditingController(text: config.password);
    _autoSync = config.autoSync;
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  WebdavConfig get _config => WebdavConfig(
    url: _url.text.trim(),
    username: _username.text.trim(),
    password: _password.text,
    autoSync: _autoSync,
  );

  Future<void> _run(String working, Future<String> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failed = false;
      _status = working;
    });
    try {
      await widget.store.setWebdavConfig(_config);
      final message = await action();
      if (!mounted) return;
      setState(() {
        _status = message;
        _failed = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString();
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() => _run('正在连接…', () async {
    final client = WebdavClient(_config);
    try {
      await client.check();
      return '连接成功，目录可用';
    } finally {
      client.close();
    }
  });

  Future<void> _sync() => _run('正在同步…', () async {
    final result = await WebdavSyncService.instance.run(widget.store);
    return '同步完成：${result.label}';
  });

  Future<void> _setAutoSync(bool value) async {
    setState(() => _autoSync = value);
    try {
      await widget.store.setWebdavConfig(_config);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString();
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _HintCard(),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('webdav-url'),
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'WebDAV 地址',
                  hintText: 'https://dav.jianguoyun.com/dav/guoapp',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _username,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '密码 / 应用密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _test,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text('测试连接'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('立即同步'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autoSync,
                onChanged: _busy ? null : _setAutoSync,
                title: const Text('自动同步'),
                subtitle: const Text('启动、回到前台或记录变化后自动合并各设备记录'),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _status!,
                    style: TextStyle(
                      color: _failed
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                '说明：每台设备填同一个 WebDAV 目录即可同步追剧、观看记录与'
                '追剧状态（未追剧的剧集也会按观看进度同步）。播放偏好（画质/'
                '倍速/主题等）保持本机。密码只保存在'
                '本机配置中，不会写入导出的备份文件。',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '填一个专用目录（例如 https://dav.jianguoyun.com/dav/guoapp）。'
              '目录不存在时会自动创建；多台设备使用完全相同的地址。',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
