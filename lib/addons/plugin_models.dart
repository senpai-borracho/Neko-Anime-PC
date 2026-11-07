/// Complementos: modelos. Esta carpeta es independiente del motor de fuentes y
/// del reproductor; nada aquí modifica las fuentes que Neko ya trae.
enum PluginKind { nuvio, aniyomi, stremio }

enum LangGroup { latino, castellano, subtitulado, otros }

/// Un complemento tal como lo publica un repositorio.
class PluginInfo {
  final PluginKind kind;
  final String id, name, version, description, logo, repoUrl, fileUrl;
  final int code; // versionCode de Aniyomi (0 en Nuvio)
  final List<String> langs;
  final bool nsfw;

  const PluginInfo({
    required this.kind,
    required this.id,
    required this.name,
    required this.repoUrl,
    required this.fileUrl,
    this.version = '1.0.0',
    this.description = '',
    this.logo = '',
    this.code = 0,
    this.langs = const [],
    this.nsfw = false,
  });

  String get key => '${kind.name}:$id';

  /// Idioma priorizado: latino > castellano > subtitulado > otros.
  /// Se deduce de los metadatos y del nombre; puede equivocarse.
  ({LangGroup group, String label}) get language {
    final hint = '$name $description'.toLowerCase();
    final codes = [for (final l in langs) l.toLowerCase().replaceAll('_', '-')];
    const latinCodes = {
      'es-419',
      'es-la',
      'lat',
      'latino',
      'es-mx',
      'es-ar',
      'es-cl',
      'es-co',
    };
    if (RegExp(r'latino|\blat\b|es-419').hasMatch(hint) ||
        codes.any(latinCodes.contains)) {
      return (group: LangGroup.latino, label: 'Latino');
    }
    if (RegExp(r'castellano|espa[nñ]a').hasMatch(hint) ||
        codes.any((c) => c == 'es-es' || c == 'castellano')) {
      return (group: LangGroup.castellano, label: 'Castellano');
    }
    if (RegExp(r'subtitulad|\bsub\b|vose').hasMatch(hint)) {
      return (group: LangGroup.subtitulado, label: 'Subtitulado');
    }
    if (codes.any((c) => c == 'es' || c.startsWith('es-'))) {
      return (group: LangGroup.latino, label: 'Español');
    }
    if (codes.isEmpty || codes.contains('all') || codes.contains('multi')) {
      return (group: LangGroup.otros, label: 'Multi');
    }
    return (group: LangGroup.otros, label: codes.first.toUpperCase());
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'logo': logo,
    'repoUrl': repoUrl,
    'fileUrl': fileUrl,
    'code': code,
    'langs': langs,
    'nsfw': nsfw,
  };

  factory PluginInfo.fromJson(Map<String, dynamic> j) => PluginInfo(
    kind: PluginKind.values.firstWhere(
      (kind) => kind.name == j['kind'],
      orElse: () => PluginKind.nuvio,
    ),
    id: '${j['id']}',
    name: '${j['name']}',
    version: '${j['version'] ?? '1.0.0'}',
    description: '${j['description'] ?? ''}',
    logo: '${j['logo'] ?? ''}',
    repoUrl: '${j['repoUrl'] ?? ''}',
    fileUrl: '${j['fileUrl'] ?? ''}',
    code: (j['code'] as num?)?.toInt() ?? 0,
    langs: [for (final l in (j['langs'] as List? ?? const [])) '$l'],
    nsfw: j['nsfw'] == true,
  );
}

/// Un complemento ya descargado en el teléfono.
class InstalledPlugin {
  PluginInfo info;
  bool enabled;
  String file; // ruta del .js guardado
  String error;
  DateTime installedAt;
  InstalledPlugin({
    required this.info,
    this.enabled = true,
    this.file = '',
    this.error = '',
    DateTime? installedAt,
  }) : installedAt = installedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'info': info.toJson(),
    'enabled': enabled,
    'file': file,
    'error': error,
    'installedAt': installedAt.toIso8601String(),
  };

  factory InstalledPlugin.fromJson(Map<String, dynamic> j) => InstalledPlugin(
    info: PluginInfo.fromJson(Map<String, dynamic>.from(j['info'] as Map)),
    enabled: j['enabled'] != false,
    file: '${j['file'] ?? ''}',
    error: '${j['error'] ?? ''}',
    installedAt: DateTime.tryParse('${j['installedAt']}'),
  );
}

class PluginRepo {
  final String url;
  String name;
  String error;
  PluginRepo(this.url, this.name, {this.error = ''});

  Map<String, dynamic> toJson() => {'url': url, 'name': name};
  factory PluginRepo.fromJson(Map<String, dynamic> j) =>
      PluginRepo('${j['url']}', '${j['name'] ?? ''}');
}

/// Fila de la pantalla: lo publicado, lo instalado y la versión nueva si la hay.
class PluginEntry {
  final PluginInfo info;
  final InstalledPlugin? installed;
  final PluginInfo? update;
  const PluginEntry(this.info, this.installed, this.update);
}

int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final p in v.replaceAll(RegExp(r'[^0-9.]'), '').split('.'))
      int.tryParse(p) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final p = i < x.length ? x[i] : 0;
    final q = i < y.length ? y[i] : 0;
    if (p != q) return p.compareTo(q);
  }
  return 0;
}
