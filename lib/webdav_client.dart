import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WebdavConfig {
  const WebdavConfig({
    this.url = '',
    this.username = '',
    this.password = '',
    this.autoSync = false,
  });

  final String url;
  final String username;
  final String password;
  final bool autoSync;

  bool get configured => url.trim().isNotEmpty;

  WebdavConfig copyWith({
    String? url,
    String? username,
    String? password,
    bool? autoSync,
  }) => WebdavConfig(
    url: url ?? this.url,
    username: username ?? this.username,
    password: password ?? this.password,
    autoSync: autoSync ?? this.autoSync,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'password': password,
    'autoSync': autoSync,
  };

  factory WebdavConfig.fromJson(Map<String, dynamic> json) => WebdavConfig(
    url: (json['url'] ?? '').toString(),
    username: (json['username'] ?? '').toString(),
    password: (json['password'] ?? '').toString(),
    autoSync: json['autoSync'] == true,
  );
}

class WebdavException implements Exception {
  WebdavException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

class _WebdavResponse {
  _WebdavResponse(this.statusCode, this.body);

  final int statusCode;
  final List<int> body;
}

class WebdavClient {
  WebdavClient(this.config) {
    if (!config.configured) {
      throw WebdavException('请先填写 WebDAV 地址');
    }
    final parsed = Uri.tryParse(_normalize(config.url));
    if (parsed == null ||
        !(parsed.isScheme('http') || parsed.isScheme('https')) ||
        parsed.host.isEmpty) {
      throw WebdavException('WebDAV 地址无效，需要 http(s)://…');
    }
    base = parsed.replace(
      path: parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/',
    );
  }

  final WebdavConfig config;
  late final Uri base;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  static String _normalize(String raw) {
    final value = raw.trim();
    if (value.isEmpty ||
        value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }
    return 'https://$value';
  }

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/>'
      '<d:getcontentlength/></d:prop></d:propfind>';

  String get _authorization =>
      'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';

  void close() => _http.close(force: true);

  Future<_WebdavResponse> _send(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
    Map<String, String>? headers,
  }) async {
    var target = uri;
    for (var hop = 0; hop < 6; hop++) {
      final request = await _http.openUrl(method, target);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, _authorization);
      request.headers.set(HttpHeaders.userAgentHeader, 'duanju-app');
      if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      headers?.forEach((key, value) => request.headers.set(key, value));
      if (body != null) {
        request.headers.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw WebdavException('连接超时，请检查地址与网络'),
      );
      final buffer = <int>[];
      await for (final chunk in response) {
        buffer.addAll(chunk);
        if (buffer.length > 8 * 1024 * 1024) {
          throw WebdavException('响应内容过大');
        }
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (const {301, 302, 307, 308}.contains(response.statusCode) &&
          location != null &&
          location.isNotEmpty) {
        target = target.resolve(location);
        continue;
      }
      return _WebdavResponse(response.statusCode, buffer);
    }
    throw WebdavException('重定向次数过多');
  }

  Never _fail(int status) {
    if (status == 401 || status == 403) {
      throw WebdavException('用户名或密码错误，或没有权限', status: status);
    }
    if (status == 404) {
      throw WebdavException('目录不存在，请检查路径', status: status);
    }
    if (status == 409) {
      throw WebdavException('上级目录不存在，请换一个可写路径', status: status);
    }
    if (status == 423) {
      throw WebdavException('目录被锁定，请稍后重试', status: status);
    }
    if (status == 507) {
      throw WebdavException('WebDAV 空间不足', status: status);
    }
    throw WebdavException('WebDAV 返回 HTTP $status', status: status);
  }

  void _check(int status, {Set<int> allow = const {200, 201, 204, 207}}) {
    if (!allow.contains(status)) _fail(status);
  }

  Future<bool> exists(Uri uri) async {
    final response = await _send(
      'PROPFIND',
      uri,
      body: utf8.encode(_propfindBody),
      contentType: 'application/xml; charset=utf-8',
      headers: const {'Depth': '0'},
    );
    if (response.statusCode == 404) return false;
    _check(response.statusCode);
    return true;
  }

  Future<void> ensureDirectory(Uri uri) async {
    if (await exists(uri)) return;
    final response = await _send('MKCOL', uri);
    if (response.statusCode == 201 || response.statusCode == 200) return;
    if (response.statusCode == 405) return;
    _fail(response.statusCode);
  }

  Future<void> check() async {
    final response = await _send(
      'PROPFIND',
      base,
      body: utf8.encode(_propfindBody),
      contentType: 'application/xml; charset=utf-8',
      headers: const {'Depth': '0'},
    );
    _check(response.statusCode);
  }

  Future<List<Uri>> listDirectory(Uri directory) async {
    final response = await _send(
      'PROPFIND',
      directory,
      body: utf8.encode(_propfindBody),
      contentType: 'application/xml; charset=utf-8',
      headers: const {'Depth': '1'},
    );
    _check(response.statusCode);
    return _children(
      utf8.decode(response.body, allowMalformed: true),
      directory,
    );
  }

  Future<List<int>?> read(Uri uri) async {
    final response = await _send('GET', uri);
    if (response.statusCode == 404) return null;
    _check(response.statusCode);
    return response.body;
  }

  Future<void> write(Uri uri, List<int> bytes) async {
    final response = await _send(
      'PUT',
      uri,
      body: bytes,
      contentType: 'application/json; charset=utf-8',
    );
    _check(response.statusCode, allow: const {200, 201, 204});
  }

  List<Uri> _children(String xml, Uri directory) {
    final pattern = RegExp(
      r'<(?:[A-Za-z0-9]+:)?href[^>]*>(.*?)</(?:[A-Za-z0-9]+:)?href>',
      caseSensitive: false,
      dotAll: true,
    );
    final children = <Uri>[];
    final seen = <String>{};
    for (final match in pattern.allMatches(xml)) {
      final raw = _unescape(match.group(1)?.trim() ?? '');
      if (raw.isEmpty) continue;
      final uri = directory.resolve(raw);
      if (uri.path == directory.path) continue;
      if (!seen.add(uri.path)) continue;
      children.add(uri);
    }
    return children;
  }

  String _unescape(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
