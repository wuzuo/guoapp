import 'dart:async';
import 'dart:convert';

import 'lan_sync_models.dart';
import 'local_store.dart';
import 'webdav_client.dart';

class WebdavSyncResult {
  const WebdavSyncResult({
    this.total = 0,
    this.updated = 0,
    this.conflicts = 0,
    this.skipped = 0,
    this.uploaded = false,
  });

  final int total;
  final int updated;
  final int conflicts;
  final int skipped;
  final bool uploaded;

  String get label {
    final parts = [
      '共 $total 条',
      if (updated > 0) '更新 $updated 条',
      if (conflicts > 0) '冲突 $conflicts',
      if (skipped > 0) '跳过 $skipped 个分片',
      if (updated == 0) '已是最新',
    ];
    return parts.join(' · ');
  }
}

class WebdavSyncService {
  WebdavSyncService._();

  static final instance = WebdavSyncService._();

  Future<WebdavSyncResult>? _running;
  final _watched = Expando<bool>('webdav-watched');
  final _syncedRevision = Expando<int>('webdav-revision');
  Timer? _debounce;

  Future<void> autoSync(LocalStore store) async {
    if (store.locked) return;
    final config = store.webdavConfig;
    if (!config.configured) return;
    attach(store);
    if (!config.autoSync) return;
    try {
      await run(store);
    } catch (_) {}
  }

  void attach(LocalStore store) {
    if (_watched[store] == true) return;
    _watched[store] = true;
    _syncedRevision[store] = store.lanRevision;
    store.addListener(() {
      bool enabled;
      try {
        if (store.lanRevision == _syncedRevision[store]) return;
        enabled = store.webdavConfig.autoSync;
      } catch (_) {
        return;
      }
      if (!enabled) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 12), () {
        _debounce = null;
        _syncedRevision[store] = store.lanRevision;
        unawaited(autoSync(store));
      });
    });
  }

  Future<WebdavSyncResult> run(LocalStore store) {
    final current = _running;
    if (current != null) return current;
    final future = _execute(store);
    _running = future;
    future.whenComplete(() {
      if (identical(_running, future)) _running = null;
    }).ignore();
    return future;
  }

  Future<WebdavSyncResult> _execute(LocalStore store) async {
    if (store.locked) {
      throw WebdavException('请先解锁本机配置');
    }
    final config = store.webdavConfig;
    if (!config.configured) {
      throw WebdavException('请先配置 WebDAV');
    }
    final client = WebdavClient(config);
    try {
      await client.ensureDirectory(client.base);
      final devices = client.base.resolve('devices/');
      await client.ensureDirectory(devices);

      await store.ensureLanRecords();
      final document = store.lanDocument;
      final self = devices.resolve('${document.replica}.json');
      final children = await client.listDirectory(devices);

      final local = Map<String, LanRecord>.of(document.records);
      final merged = Map<String, LanRecord>.of(local);
      var skipped = 0;
      for (final child in children) {
        if (child.path == self.path) continue;
        if (!child.path.endsWith('.json')) continue;
        try {
          final bytes = await client.read(child);
          if (bytes == null) continue;
          final remote = LanDocument.fromJson(jsonDecode(utf8.decode(bytes)));
          for (final record in remote.records.values) {
            if (!store.allowsSource(record.drama.source)) continue;
            final current = merged[record.id];
            merged[record.id] = current == null
                ? record
                : current.merge(record);
          }
        } catch (_) {
          skipped++;
        }
      }

      final allowed = merged.values
          .where((record) => store.allowsSource(record.drama.source))
          .toList();
      var updated = 0;
      for (final record in allowed) {
        if (local[record.id]?.hash != record.hash) updated++;
      }
      final sources = allowed.map((record) => record.drama.source).toSet();
      if (sources.isNotEmpty) {
        await store.applyLanRecords(
          operation: lanID(),
          base: store.lanDocument.hashFor(sources),
          sources: sources,
          records: allowed,
          epoch: store.profileEpoch,
        );
      }

      final payload = utf8.encode(jsonEncode(store.lanDocument.toJson()));
      await client.write(self, payload);

      final conflicts = store.lanDocument.records.values.fold<int>(
        0,
        (sum, record) => sum + record.conflicts,
      );
      return WebdavSyncResult(
        total: store.lanDocument.records.length,
        updated: updated,
        conflicts: conflicts,
        skipped: skipped,
        uploaded: true,
      );
    } finally {
      client.close();
    }
  }
}
