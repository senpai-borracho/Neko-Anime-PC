/// Referencia persistente: conserva los IDs originales del addon.
class StremioRef {
  final String manifest, type, id, name;
  const StremioRef(this.manifest, this.type, this.id, this.name);

  String get url => Uri(
    scheme: 'neko-stremio',
    host: 'item',
    queryParameters: {
      'manifest': manifest,
      'type': type,
      'id': id,
      'name': name,
    },
  ).toString();

  static StremioRef? parse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'neko-stremio') return null;
    final q = uri.queryParameters;
    if (q['manifest'] == null || q['type'] == null || q['id'] == null) {
      return null;
    }
    return StremioRef(
      q['manifest']!,
      q['type']!,
      q['id']!,
      q['name'] ?? 'Stremio',
    );
  }
}
