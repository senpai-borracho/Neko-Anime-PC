class MediaSource {
  final String name, url;
  final Map<String, String> headers;
  final List<Map<String, dynamic>> subtitles;
  const MediaSource(
    this.name,
    this.url,
    this.headers, [
    this.subtitles = const [],
  ]);
  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'headers': headers,
    'subtitles': subtitles,
  };
  factory MediaSource.fromJson(Map json) => MediaSource(
    '${json['name']}',
    '${json['url']}',
    Map<String, String>.from(json['headers'] as Map? ?? {}),
    [
      for (final s in (json['subtitles'] as List? ?? []))
        Map<String, dynamic>.from(s as Map),
    ],
  );
}
