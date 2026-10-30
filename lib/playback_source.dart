class PlaybackSource {
  const PlaybackSource({
    required this.url,
    this.headers = const {},
    this.decryptionKey = '',
    this.quality = 0,
    this.codec = '',
    this.width = 0,
    this.height = 0,
  });
  final String url;
  final Map<String, String> headers;
  final String decryptionKey;
  final int quality;
  final String codec;
  final int width;
  final int height;

  factory PlaybackSource.fromJson(Map<String, dynamic> json) => PlaybackSource(
    url: json['url'] as String? ?? '',
    headers: (json['headers'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    decryptionKey: json['decryptionKey'] as String? ?? '',
    quality: _intValue(json['quality']),
    codec: json['codec'] as String? ?? '',
    width: _intValue(json['width']),
    height: _intValue(json['height']),
  );

  static int _intValue(Object? value) => switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value) ?? 0,
    _ => 0,
  };

  Map<String, Object?> toJson() => {
    'url': url,
    'headers': headers,
    'decryptionKey': decryptionKey,
    'quality': quality,
    'codec': codec,
    'width': width,
    'height': height,
  };
}
