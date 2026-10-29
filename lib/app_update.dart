import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_layout.dart';

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.title,
    required this.notes,
    required this.assetName,
    required this.assetUrl,
    required this.size,
  });

  final String version;
  final String title;
  final String notes;
  final String assetName;
  final String assetUrl;
  final int size;

  String get sizeLabel =>
      size <= 0 ? '' : '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
}

class AppUpdateService {
  AppUpdateService._();

  static const _repo = 'wuzuo/guoapp';
  static const _channel = MethodChannel('duanju/update');
  static const _userAgent = 'guoapp-updater';

  static Future<AppUpdate?> check() async {
    final device = await AppDevice.detect();
    final local = _Version.parse(device.version);
    final abi = device.abi.isNotEmpty ? device.abi : 'arm64-v8a';
    final suffix = Platform.isWindows ? '-windows-x64.zip' : '-$abi.apk';
    final path = '/repos/$_repo/releases?per_page=20';
    String raw;
    try {
      raw = await _getText(Uri.parse('https://api.github.com$path'));
    } catch (_) {
      raw = await _getText(
        Uri.parse('https://ghproxy.net/https://api.github.com$path'),
      );
    }
    final list = jsonDecode(raw);
    if (list is! List) return null;
    AppUpdate? best;
    _Version? bestVersion;
    for (final entry in list) {
      if (entry is! Map) continue;
      final tag = (entry['tag_name'] as String? ?? '').trim();
      if (!tag.startsWith('app-v')) continue;
      final version = _Version.parse(tag.substring(5).replaceFirst('-', '+'));
      if (version == null) continue;
      if (local != null && version.compareTo(local) <= 0) continue;
      if (bestVersion != null && version.compareTo(bestVersion) <= 0) continue;
      final assets = entry['assets'];
      if (assets is! List) continue;
      Map? matched;
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'] as String? ?? '';
        if (!name.startsWith('$appSlug-') || !name.endsWith(suffix)) continue;
        matched = asset;
        break;
      }
      if (matched == null) continue;
      final title = (entry['name'] as String? ?? '').trim();
      bestVersion = version;
      best = AppUpdate(
        version: version.label,
        title: title.isEmpty ? '红果鉴 ${version.label}' : title,
        notes: (entry['body'] as String? ?? '').trim(),
        assetName: matched['name'] as String,
        assetUrl: matched['browser_download_url'] as String,
        size: (matched['size'] as num?)?.toInt() ?? 0,
      );
    }
    return best;
  }

  static Future<File> download(
    AppUpdate update, {
    required void Function(int received, int total) onProgress,
  }) async {
    final root = await getTemporaryDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}updates');
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${update.assetName}',
    );
    if (await file.exists()) await file.delete();
    Object? lastError;
    for (final url in [
      update.assetUrl,
      'https://ghproxy.net/${update.assetUrl}',
    ]) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('User-Agent', _userAgent);
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('下载失败 HTTP ${response.statusCode}');
        }
        final total = response.contentLength > 0
            ? response.contentLength
            : update.size;
        var received = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
            onProgress(received, total);
          }
        } finally {
          await sink.close();
        }
        if (await file.length() <= 0) throw const HttpException('下载内容为空');
        return file;
      } catch (error) {
        lastError = error;
        if (await file.exists()) await file.delete();
      } finally {
        client.close(force: true);
      }
    }
    throw HttpException(lastError?.toString() ?? '下载失败');
  }

  static Future<bool> install(File file) async {
    if (Platform.isAndroid) {
      final installed = await _channel.invokeMethod<bool>('installApk', {
        'path': file.path,
      });
      return installed ?? false;
    }
    if (Platform.isWindows) {
      final result = await Process.run('explorer', ['/select,${file.path}']);
      return result.exitCode == 0;
    }
    return false;
  }

  static Future<String> _getText(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', _userAgent);
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('更新服务 HTTP ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

class _Version implements Comparable<_Version> {
  const _Version(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final int build;

  String get label => '$major.$minor.$patch';

  static _Version? parse(String raw) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:[+-](\d+))?',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    return _Version(
      int.tryParse(match.group(1) ?? '') ?? 0,
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
      int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }

  @override
  int compareTo(_Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }
}
