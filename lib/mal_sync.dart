// Sincronización automática con MyAnimeList: cuando pasas del 80% de un
// episodio, Neko lo marca como visto en tu lista de MAL.
//
// Reglas de seguridad:
//  - solo actúa si hay una cuenta de MAL conectada y el interruptor está activo;
//  - nunca baja el contador ni toca un anime que ya tienes como "Completado";
//  - si no está seguro de qué anime es en MAL, no marca nada.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'anilist_client.dart';
import 'catalog.dart';
import 'mal_client.dart';

/// Instancia activa (la crea la página de inicio). El reproductor la consulta.
MalSync? malSync;

class MalSync {
  MalSync(this.mal, this.anilist);
  final MalClient mal;
  final AniListClient anilist;

  /// Para avisar en pantalla ("episodio 5 marcado en MAL").
  void Function(String message)? onMessage;

  // URL del anime en la fuente → ID en MAL (se guarda en disco).
  final Map<String, int> _ids = {};
  bool _loaded = false;
  final Set<String> _done = {}, _busy = {}, _noMatch = {};
  final Map<String, DateTime> _retryAt = {};
  bool _warnedWrite = false;

  File get _file {
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
    return File('$base/NekoPlayerPC/mal_map.json');
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!await _file.exists()) return;
      final data = jsonDecode(await _file.readAsString());
      if (data is Map) {
        for (final e in data.entries) {
          final id = e.value;
          if (id is num) _ids['${e.key}'] = id.toInt();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveMap() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(_ids));
    } catch (_) {}
  }

  static String _key(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  static bool _similar(String a, String b) {
    final x = _key(a), y = _key(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    final shorter = x.length < y.length ? x.length : y.length;
    final longer = x.length < y.length ? y.length : x.length;
    return shorter >= 6 && shorter / longer >= .75 && (x.contains(y) || y.contains(x));
  }

  /// Lo llama el reproductor cada pocos segundos con el avance actual.
  void onProgress(
    Anime anime,
    Episode episode,
    Duration position,
    Duration duration,
  ) {
    if (!mal.configured || !mal.connected || !mal.autoSync) return;
    if (duration.inSeconds < 60 || position.inSeconds < duration.inSeconds * .8) {
      return;
    }
    final id = episode.url;
    if (_done.contains(id) || _busy.contains(id)) return;
    final retry = _retryAt[id];
    if (retry != null && DateTime.now().isBefore(retry)) return;
    _busy.add(id);
    _sync(anime, episode)
        .then((decided) {
          if (decided) {
            _done.add(id);
          } else {
            _retryAt[id] = DateTime.now().add(const Duration(seconds: 60));
          }
        })
        .catchError((Object _) {
          _retryAt[id] = DateTime.now().add(const Duration(seconds: 60));
        })
        .whenComplete(() => _busy.remove(id));
  }

  /// Devuelve true si ya se decidió (marcado u omitido) y false si conviene
  /// reintentar más tarde (error de red, por ejemplo).
  Future<bool> _sync(Anime anime, Episode episode) async {
    // Solo episodios con número entero ("5", "Episodio 5"); especiales (12.5) no.
    final match = RegExp(r'^\D*(\d+)\D*$').firstMatch(episode.number.trim());
    if (match == null) return true;
    final n = int.parse(match[1]!);
    if (n <= 0) return true;
    try {
      final malId = await _malIdFor(anime);
      if (malId == null) return true;
      final current = await mal.myStatus(malId);
      if (current.status == 'completed') return true;
      if (n <= current.watched) return true;
      if (current.total > 0 && n > current.total) {
        onMessage?.call(
          'MAL: "${anime.title}" tiene ${current.total} episodios en MAL y este es el $n '
          '(numeración distinta), no lo marqué.',
        );
        return true;
      }
      final status = current.total > 0 && n >= current.total ? 'completed' : 'watching';
      try {
        await mal.setProgress(malId, n, status);
      } on HttpException catch (e) {
        if (!_warnedWrite) {
          _warnedWrite = true;
          onMessage?.call(
            'No pude actualizar MAL (${e.message}). Prueba desconectar y volver a conectar tu cuenta.',
          );
        }
        return true;
      }
      onMessage?.call(
        status == 'completed'
            ? 'MAL: "${anime.title}" marcado como completado.'
            : 'MAL: episodio $n de "${anime.title}" marcado como visto.',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int?> _malIdFor(Anime anime) async {
    await _load();
    final cached = _ids[anime.url];
    if (cached != null) return cached;
    if (_noMatch.contains(anime.url)) return null;

    final names = <String>[
      anime.title,
      ...anime.alternatives.where((a) => a.trim().isNotEmpty).take(2),
    ];
    int? found;
    // 1) AniList, que ya trae el ID de MAL; se acepta solo si el título coincide.
    for (final name in names) {
      try {
        final info = await anilist.lookup(name);
        if (info?.malId != null &&
            names.any(
              (n) => _similar(n, info!.title) || _similar(n, info.titleEnglish),
            )) {
          found = info!.malId;
          break;
        }
      } catch (_) {}
    }
    // 2) Búsqueda en MAL con coincidencia exacta de algún título conocido.
    if (found == null) {
      final wanted = names.map(_key).where((k) => k.isNotEmpty).toSet();
      for (final name in names.take(2)) {
        try {
          for (final result in await mal.search(name)) {
            if (result.titles.any((t) => wanted.contains(_key(t)))) {
              found = result.id;
              break;
            }
          }
        } catch (_) {}
        if (found != null) break;
      }
    }
    if (found == null || found == 0) {
      _noMatch.add(anime.url);
      onMessage?.call(
        'MAL: no encontré "${anime.title}" en MyAnimeList, así que no se sincroniza.',
      );
      return null;
    }
    _ids[anime.url] = found;
    await _saveMap();
    return found;
  }
}
