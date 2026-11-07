import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'plugin_models.dart';

String friendlyError(Object e) {
  if (e is SocketException) return 'Sin conexión o el sitio no responde.';
  if (e is TimeoutException) return 'Tardó demasiado en responder.';
  return '$e'.replaceFirst(
    RegExp(r'^(Exception|FormatException|HttpException):\s*'),
    '',
  );
}

/// El JSON importado trae rutas relativas y hace falta la URL base del repo.
class NeedBaseUrl implements Exception {
  const NeedBaseUrl();
  @override
  String toString() => 'Faltan URLs base';
}

/// Gestiona repositorios, scripts Nuvio y manifiestos remotos Stremio.
class PluginManager extends ChangeNotifier {
  final List<PluginRepo> repos = [];
  final Map<String, List<PluginInfo>> catalog = {}; // por URL de repo
  final Map<String, InstalledPlugin> installed = {}; // por PluginInfo.key
  final Map<String, String> busy = {}; // key -> 'Instalando…'
  bool refreshing = false;

  Directory? _dir;
  File? _state;
  Future<void> _saving = Future.value();
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = 'NekoMobile/0.3';

  // ------------------------------------------------------------ estado

  Future<void> load() async {
    try {
      final base = Directory(
        '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}/NekoPlayerPC',
      );
      _dir = Directory('${base.path}/plugins');
      await _dir!.create(recursive: true);
      _state = File('${_dir!.path}/state.json');
      if (await _state!.exists()) {
        final data = jsonDecode(await _state!.readAsString());
        if (data is Map) {
          for (final v in (data['repos'] as List? ?? const [])) {
            try {
              repos.add(
                PluginRepo.fromJson(Map<String, dynamic>.from(v as Map)),
              );
            } catch (_) {}
          }
          for (final v in (data['installed'] as List? ?? const [])) {
            try {
              final p = InstalledPlugin.fromJson(
                Map<String, dynamic>.from(v as Map),
              );
              installed[p.info.key] = p;
            } catch (_) {}
          }
          final cache = data['catalog'];
          if (cache is Map) {
            cache.forEach((k, v) {
              try {
                catalog['$k'] = [
                  for (final i in (v as List))
                    PluginInfo.fromJson(Map<String, dynamic>.from(i as Map)),
                ];
              } catch (_) {}
            });
          }
        }
      }
    } catch (_) {
      // Estado dañado: se arranca vacío, nunca se rompe la app.
    }
    notifyListeners();
  }

  void _save() {
    final file = _state;
    if (file == null) return;
    final body = jsonEncode({
      'repos': [for (final r in repos) r.toJson()],
      'installed': [for (final p in installed.values) p.toJson()],
      'catalog': {
        for (final e in catalog.entries)
          e.key: [for (final i in e.value) i.toJson()],
      },
    });
    _saving = _saving
        .catchError((_) {})
        .then<void>((_) async {
          await file.writeAsString(body, flush: true);
        })
        .catchError((_) {});
  }

  // ------------------------------------------------------------ consultas

  /// Todo lo mostrable: catálogo de los repos + instalados que ya no están en
  /// ningún repo. Ordenado por idioma (latino, castellano, subtitulado, otros).
  List<PluginEntry> entries() {
    final byKey = <String, PluginInfo>{};
    for (final list in catalog.values) {
      for (final i in list) {
        byKey.putIfAbsent(i.key, () => i);
      }
    }
    for (final p in installed.values) {
      byKey.putIfAbsent(p.info.key, () => p.info);
    }
    final out = <PluginEntry>[];
    for (final info in byKey.values) {
      final inst = installed[info.key];
      out.add(PluginEntry(info, inst, _newer(info, inst) ? info : null));
    }
    out.sort((a, b) {
      final g = a.info.language.group.index.compareTo(
        b.info.language.group.index,
      );
      return g != 0
          ? g
          : a.info.name.toLowerCase().compareTo(b.info.name.toLowerCase());
    });
    return out;
  }

  bool _newer(PluginInfo catalogInfo, InstalledPlugin? inst) {
    if (inst == null) return false;
    if (catalogInfo.kind == PluginKind.aniyomi) {
      return catalogInfo.code > inst.info.code;
    }
    return compareVersions(catalogInfo.version, inst.info.version) > 0;
  }

  int get installedCount => installed.length;

  // ------------------------------------------------------------ red

  Future<String> _fetch(String url, {int maxBytes = 8 * 1024 * 1024}) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw const FormatException('Solo se admiten direcciones https://');
    }
    final req = await _http.getUrl(uri).timeout(const Duration(seconds: 15));
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      await res.drain<void>().catchError((_) {});
      throw HttpException('El sitio respondió ${res.statusCode}.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(const Duration(seconds: 25))) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        throw const FormatException('El archivo es demasiado grande.');
      }
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  // ------------------------------------------------------------ repositorios

  /// Acepta la URL del manifest/index o la de la carpeta; también enlaces
  /// aniyomi://add-repo?url=...
  List<String> _candidates(String input) {
    var text = input.trim();
    if (text.startsWith('stremio://')) {
      text = text.replaceFirst('stremio://', 'https://');
    }
    final wrapped = Uri.tryParse(text);
    if (wrapped != null &&
        wrapped.queryParameters['url'] != null &&
        wrapped.scheme != 'https') {
      text = wrapped.queryParameters['url']!;
    }
    if (!text.contains('://')) text = 'https://$text';
    if (text.endsWith('/')) text = text.substring(0, text.length - 1);
    if (Uri.parse(text).path.toLowerCase().endsWith('.json')) return [text];
    return ['$text/manifest.json', '$text/index.min.json', text];
  }

  /// Lee y valida un repositorio; no lo guarda.
  Future<({String url, String name, List<PluginInfo> items})> _read(
    String candidate,
  ) async {
    final text = await _fetch(candidate);
    final dynamic json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Ese enlace no devuelve un JSON válido.');
    }
    final items = _parse(candidate, json);
    if (items.isEmpty) {
      throw const FormatException(
        'No encontré complementos válidos en ese repositorio.',
      );
    }
    var name = Uri.parse(candidate).host;
    if (json is Map &&
        json['name'] is String &&
        (json['name'] as String).trim().isNotEmpty) {
      name = (json['name'] as String).trim();
    }
    return (url: candidate, name: name, items: items);
  }

  static List<String> _langList(dynamic v) {
    if (v is List) return [for (final x in v) '$x'];
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }

  /// Reconoce Stremio, Nuvio (filename) y Aniyomi (apk/pkg).
  List<PluginInfo> _parse(String repoUrl, dynamic json) {
    // Un manifest Stremio describe un servidor, no una lista de archivos JS.
    if (json is Map &&
        json['id'] is String &&
        json['resources'] is List &&
        json['types'] is List &&
        json['name'] is String) {
      final manifestUrl = repoUrl.endsWith('/')
          ? Uri.parse(repoUrl).resolve('manifest.json').toString()
          : repoUrl;
      return [
        PluginInfo(
          kind: PluginKind.stremio,
          id: '${json['id']}:$manifestUrl',
          name: '${json['name']}',
          version: '${json['version'] ?? '1.0.0'}',
          description: '${json['description'] ?? ''}',
          logo: '${json['logo'] ?? ''}',
          repoUrl: repoUrl,
          fileUrl: manifestUrl,
        ),
      ];
    }
    dynamic list = json;
    if (json is Map) {
      list = null;
      for (final k in const [
        'scrapers',
        'providers',
        'plugins',
        'extensions',
        'sources',
        'items',
      ]) {
        if (json[k] is List) {
          list = json[k];
          break;
        }
      }
      list ??= json.values.whereType<List>().firstOrNull;
    }
    if (list is! List) return const [];
    final base = Uri.parse(repoUrl);
    final out = <PluginInfo>[];
    for (final m in list) {
      if (m is! Map) continue;
      try {
        if (m['apk'] != null && m['pkg'] != null) {
          final pkg = '${m['pkg']}';
          final sources = m['sources'] is List
              ? [
                  for (final s in (m['sources'] as List))
                    if (s is Map) '${s['name']}',
                ]
              : <String>[];
          out.add(
            PluginInfo(
              kind: PluginKind.aniyomi,
              id: pkg,
              name: '${m['name']}'.replaceFirst(
                RegExp(r'^(Aniyomi|Tachiyomi):\s*'),
                '',
              ),
              version: '${m['version'] ?? '1.0'}',
              code: (m['code'] as num?)?.toInt() ?? 0,
              langs: _langList(m['lang']),
              nsfw: m['nsfw'] == 1 || m['nsfw'] == true,
              description: sources.isEmpty
                  ? ''
                  : 'Fuentes: ${sources.take(4).join(', ')}',
              logo: base.resolve('icon/$pkg.png').toString(),
              repoUrl: repoUrl,
              fileUrl: base.resolve('apk/${m['apk']}').toString(),
            ),
          );
          continue;
        }
        final file = m['filename'] ?? m['file'] ?? m['path'] ?? m['url'];
        if (file == null || m['enabled'] == false) continue;
        final disabled = m['disabledPlatforms'];
        if (disabled is List &&
            disabled.map((e) => '$e'.toLowerCase()).contains('android')) {
          continue;
        }
        final id = '${m['id'] ?? m['name'] ?? file}';
        final logo = '${m['logo'] ?? ''}';
        out.add(
          PluginInfo(
            kind: PluginKind.nuvio,
            id: id,
            name: '${m['name'] ?? id}',
            version: '${m['version'] ?? '1.0.0'}',
            description: '${m['description'] ?? ''}',
            logo: logo.isEmpty ? '' : base.resolve(logo).toString(),
            langs: _langList(
              m['contentLanguage'] ?? m['languages'] ?? m['language'],
            ),
            repoUrl: repoUrl,
            fileUrl: base.resolve('$file').toString(),
          ),
        );
      } catch (_) {
        // Una entrada rara no invalida el resto del repositorio.
      }
    }
    return out;
  }

  Future<void> addRepo(String input) async {
    Object? last;
    for (final candidate in _candidates(input)) {
      try {
        final r = await _read(candidate);
        repos.removeWhere((x) => x.url == r.url);
        repos.add(PluginRepo(r.url, r.name));
        catalog[r.url] = r.items;
        _save();
        notifyListeners();
        return;
      } catch (e) {
        last = e;
      }
    }
    throw FormatException(
      friendlyError(last ?? 'No se pudo leer el repositorio.'),
    );
  }

  static const _placeholder = 'https://neko.invalid/';

  /// Importa un .json: o es un repositorio completo (manifest / index) o es una
  /// lista de enlaces a repositorios, que se agregan uno por uno.
  Future<({int plugins, int repos})> importJson(
    String text, {
    required String fileName,
    String baseUrl = '',
  }) async {
    final dynamic json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Ese archivo no es un JSON válido.');
    }
    var base = baseUrl.trim();
    if (base.isNotEmpty) {
      if (!base.startsWith('https://')) {
        throw const FormatException('La URL base debe empezar con https://');
      }
      if (!base.endsWith('/')) base = '$base/';
    }
    final items = _parse(base.isEmpty ? _placeholder : base, json);
    if (items.isNotEmpty) {
      if (base.isEmpty &&
          items.any(
            (i) =>
                i.kind != PluginKind.aniyomi &&
                i.fileUrl.startsWith(_placeholder),
          )) {
        throw const NeedBaseUrl();
      }
      final fixed = [
        for (final i in items)
          PluginInfo(
            kind: i.kind,
            id: i.id,
            name: i.name,
            version: i.version,
            description: i.description,
            logo: i.logo.startsWith(_placeholder) ? '' : i.logo,
            repoUrl: 'local:$fileName',
            fileUrl: i.fileUrl,
            code: i.code,
            langs: i.langs,
            nsfw: i.nsfw,
          ),
      ];
      final key = 'local:$fileName';
      repos.removeWhere((r) => r.url == key);
      repos.add(PluginRepo(key, fileName));
      catalog[key] = fixed;
      _save();
      notifyListeners();
      return (plugins: fixed.length, repos: 1);
    }
    // Sin complementos: ¿es una lista de repositorios?
    final urls = <String>[];
    void walk(dynamic v) {
      if (urls.length >= 30) return;
      if (v is String) {
        if (v.startsWith('https://') &&
            v.toLowerCase().contains('.json') &&
            !urls.contains(v)) {
          urls.add(v);
        }
      } else if (v is List) {
        v.forEach(walk);
      } else if (v is Map) {
        v.values.forEach(walk);
      }
    }

    walk(json);
    var added = 0, found = 0;
    for (final u in urls) {
      try {
        await addRepo(u);
        added++;
        found += catalog[repos.last.url]?.length ?? 0;
      } catch (_) {}
    }
    if (added == 0) {
      throw const FormatException(
        'No encontré complementos ni enlaces de repositorios en ese archivo.',
      );
    }
    return (plugins: found, repos: added);
  }

  /// Instala un complemento Nuvio desde un .js del teléfono (sin repositorio).
  Future<void> importScript(
    String code, {
    required String name,
    required String lang, // latino | castellano | subtitulado | otro
    String version = '1.0.0',
  }) async {
    final dir = _dir;
    if (dir == null) {
      throw const FormatException('Almacenamiento no disponible.');
    }
    if (!code.contains('getStreams')) {
      throw const FormatException(
        'Ese archivo no parece un complemento Nuvio (no tiene getStreams).',
      );
    }
    if (code.length > 2 * 1024 * 1024) {
      throw const FormatException('El archivo es demasiado grande.');
    }
    final clean = name.trim().isEmpty ? 'Complemento local' : name.trim();
    final info = PluginInfo(
      kind: PluginKind.nuvio,
      id: 'local-${_safe(clean.toLowerCase())}',
      name: clean,
      version: version.trim().isEmpty ? '1.0.0' : version.trim(),
      description: lang == 'subtitulado'
          ? 'Subtitulado'
          : 'Importado de un archivo',
      repoUrl: 'local',
      fileUrl: '',
      langs: switch (lang) {
        'latino' => const ['es-419'],
        'castellano' => const ['es-ES'],
        _ => const ['all'],
      },
    );
    final file = File('${dir.path}/${_safe(info.key)}.js');
    await file.writeAsString(code, flush: true);
    installed[info.key] = InstalledPlugin(
      info: info,
      enabled: true,
      file: file.path,
    );
    _save();
    notifyListeners();
  }

  Future<void> removeRepo(PluginRepo repo) async {
    repos.remove(repo);
    catalog.remove(repo.url);
    _save();
    notifyListeners();
  }

  /// Vuelve a leer todos los repositorios (cada uno por separado).
  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    notifyListeners();
    await Future.wait([
      for (final repo in List<PluginRepo>.of(repos))
        () async {
          if (repo.url.startsWith('local:')) return; // importado de archivo
          try {
            final r = await _read(repo.url);
            catalog[repo.url] = r.items;
            repo.name = r.name;
            repo.error = '';
          } catch (e) {
            repo.error = friendlyError(e);
          }
        }(),
    ]);
    refreshing = false;
    _save();
    notifyListeners();
  }

  // ------------------------------------------------------------ acciones

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  Future<void> _guard(
    String key,
    String label,
    Future<void> Function() job,
  ) async {
    if (busy.containsKey(key)) return;
    busy[key] = label;
    notifyListeners();
    try {
      await job();
    } finally {
      busy.remove(key);
      _save();
      notifyListeners();
    }
  }

  /// Instala (o actualiza) un complemento Nuvio: descarga el .js y lo guarda.
  Future<void> install(PluginInfo info) async {
    if (info.kind == PluginKind.aniyomi) {
      throw const FormatException(
        'El motor Aniyomi llega en una etapa posterior.',
      );
    }
    final dir = _dir;
    if (dir == null) {
      throw const FormatException('Almacenamiento no disponible.');
    }
    final updating = installed.containsKey(info.key);
    await _guard(
      info.key,
      updating ? 'Actualizando…' : 'Instalando…',
      () async {
        if (info.kind == PluginKind.stremio) {
          final manifest = jsonDecode(await _fetch(info.fileUrl));
          if (manifest is! Map || manifest['resources'] is! List) {
            throw const FormatException('El manifiesto Stremio no es válido.');
          }
          final prev = installed[info.key];
          installed[info.key] = InstalledPlugin(
            info: info,
            enabled: prev?.enabled ?? true,
          );
          return;
        }
        final code = await _fetch(info.fileUrl, maxBytes: 2 * 1024 * 1024);
        if (!code.contains('getStreams')) {
          throw const FormatException(
            'Ese archivo no parece un complemento Nuvio (no tiene getStreams).',
          );
        }
        final file = File('${dir.path}/${_safe(info.key)}.js');
        await file.writeAsString(code, flush: true);
        final prev = installed[info.key];
        installed[info.key] = InstalledPlugin(
          info: info,
          enabled: prev?.enabled ?? true,
          file: file.path,
        );
      },
    );
  }

  /// Guarda el último resultado de ejecutar un complemento ('' = salió bien).
  void markResult(InstalledPlugin p, String error) {
    if (p.error == error) return;
    p.error = error;
    _save();
    notifyListeners();
  }

  void setEnabled(PluginInfo info, bool on) {
    final p = installed[info.key];
    if (p == null) return;
    p.enabled = on;
    _save();
    notifyListeners();
  }

  Future<void> remove(PluginInfo info) async {
    final p = installed.remove(info.key);
    if (p != null && p.file.isNotEmpty) {
      try {
        final f = File(p.file);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _save();
    notifyListeners();
  }
}
