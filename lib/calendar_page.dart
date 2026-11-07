// Calendario semanal de estrenos (lunes a domingo) con datos de AniList.
// Reutiliza AniListClient. Guarda una caché local y solo consulta AniList cuando
// cambia la semana (primer arranque de cada lunes) o cuando se pulsa Actualizar.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'anilist_client.dart';
import 'main.dart' show Cover, accent, border, elevated, ink, muted, surface;

/// Un episodio programado en AniList.
class AiringItem {
  final int mediaId, episode;
  final String title, titleEnglish, titleNative, cover;
  final DateTime airingAt; // hora local

  const AiringItem({
    required this.mediaId,
    required this.episode,
    required this.title,
    required this.airingAt,
    this.titleEnglish = '',
    this.titleNative = '',
    this.cover = '',
  });

  /// "Próximo estreno" si la hora de emisión aún no llegó; "Emitido" si ya pasó.
  /// Nunca se afirma "Disponible": eso solo lo confirman las fuentes.
  String statusAt(DateTime now) => airingAt.isAfter(now) ? 'Próximo estreno' : 'Emitido';

  /// Datos mínimos para abrir la ficha con la búsqueda existente en las fuentes.
  AniListInfo toInfo() =>
      AniListInfo(id: mediaId, title: title, titleEnglish: titleEnglish, cover: cover);

  Map<String, dynamic> toJson() => {
    'id': mediaId,
    'ep': episode,
    'title': title,
    'en': titleEnglish,
    'native': titleNative,
    'cover': cover,
    'at': airingAt.millisecondsSinceEpoch ~/ 1000,
  };

  static AiringItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], ep = raw['ep'], at = raw['at'];
    if (id is! num || ep is! num || at is! num) return null;
    String s(String k) => raw[k] is String ? raw[k] as String : '';
    return AiringItem(
      mediaId: id.toInt(),
      episode: ep.toInt(),
      title: s('title'),
      titleEnglish: s('en'),
      titleNative: s('native'),
      cover: s('cover'),
      airingAt: DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000),
    );
  }

  /// Interpreta un elemento de `airingSchedules`; null si no sirve u es +18.
  static AiringItem? fromAniList(Map raw) {
    final media = raw['media'];
    final at = raw['airingAt'], ep = raw['episode'];
    if (media is! Map || at is! num || ep is! num) return null;
    if (media['isAdult'] == true) return null;
    final id = media['id'];
    if (id is! num) return null;
    final names = media['title'];
    String name(String k) =>
        names is Map && names[k] is String ? (names[k] as String).trim() : '';
    final cover = media['coverImage'];
    String image() {
      if (cover is! Map) return '';
      final big = cover['extraLarge'], small = cover['large'];
      return small is String && small.isNotEmpty
          ? small
          : big is String
          ? big
          : '';
    }

    final romaji = name('romaji'), english = name('english');
    if (romaji.isEmpty && english.isEmpty) return null;
    return AiringItem(
      mediaId: id.toInt(),
      episode: ep.toInt(),
      title: romaji.isNotEmpty ? romaji : english,
      titleEnglish: english,
      titleNative: name('native'),
      cover: image(),
      airingAt: DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000),
    );
  }
}

/// Carga, guarda en caché y expone los estrenos de la semana actual.
class CalendarController extends ChangeNotifier {
  CalendarController(this.client, {File? cacheFile, DateTime Function()? clock})
    : _cacheFile = cacheFile,
      _clock = clock ?? DateTime.now;

  final AniListClient client;
  final File? _cacheFile;
  final DateTime Function() _clock;

  List<AiringItem> items = [];
  DateTime? weekStart; // lunes 00:00 (local) de la semana de la caché
  DateTime? fetchedAt;
  bool loading = false;
  String? error;
  bool _cacheRead = false, _disposed = false;

  DateTime now() => _clock();

  /// Lunes 00:00 local de la semana de [d].
  static DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  DateTime get currentMonday => mondayOf(now());

  /// Estrenos de la semana en curso (lunes a domingo), ordenados por hora.
  List<AiringItem> get thisWeek {
    final start = currentMonday;
    final end = DateTime(start.year, start.month, start.day + 7);
    return [
      for (final item in items)
        if (!item.airingAt.isBefore(start) && item.airingAt.isBefore(end)) item,
    ]..sort((a, b) => a.airingAt.compareTo(b.airingAt));
  }

  File get _file {
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
    return _cacheFile ?? File('$base/NekoPlayerPC/calendar_cache.json');
  }

  Future<void> _readCache() async {
    if (_cacheRead) return;
    _cacheRead = true;
    try {
      final file = _file;
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      final week = data['weekStart'], at = data['fetchedAt'], list = data['items'];
      if (week is! String || list is! List) return;
      weekStart = DateTime.tryParse(week);
      fetchedAt = at is String ? DateTime.tryParse(at) : null;
      items = [
        for (final raw in list)
          if (AiringItem.fromJson(raw) case final item?) item,
      ];
    } catch (_) {
      // Caché ilegible: se ignora y se vuelve a pedir.
    }
  }

  Future<void> _writeCache() async {
    try {
      final file = _file;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'weekStart': weekStart!.toIso8601String(),
          'fetchedAt': fetchedAt!.toIso8601String(),
          'items': [for (final i in items) i.toJson()],
        }),
      );
    } catch (_) {}
  }

  /// Lee la caché y solo consulta AniList si es de otra semana (o no existe).
  /// Con [force] (botón Actualizar) consulta siempre.
  Future<void> ensureFresh({bool force = false}) async {
    if (loading) return;
    await _readCache();
    final monday = currentMonday;
    final fresh = weekStart == monday && fetchedAt != null;
    if (!force && fresh) {
      _notify();
      return;
    }
    loading = true;
    error = null;
    _notify();
    try {
      final end = DateTime(monday.year, monday.month, monday.day + 7);
      final raw = await client.airingSchedules(
        monday.millisecondsSinceEpoch ~/ 1000 - 1,
        end.millisecondsSinceEpoch ~/ 1000,
      );
      final seen = <String>{};
      final parsed = <AiringItem>[];
      for (final entry in raw) {
        final item = AiringItem.fromAniList(entry);
        if (item != null && seen.add('${item.mediaId}:${item.episode}')) parsed.add(item);
      }
      items = parsed;
      weekStart = monday;
      fetchedAt = now();
      await _writeCache();
    } catch (e) {
      error = e.toString().replaceFirst(
        RegExp(r'^(Exception|FormatException|HttpException|SocketException|TimeoutException):\s*'),
        '',
      );
    } finally {
      loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _key(String t) => t.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// ¿Este estreno corresponde a algo de mi biblioteca? [followed] son los
/// títulos (y alternativos) de la biblioteca ya normalizados con [calendarKey].
bool isFollowedAiring(AiringItem item, Set<String> followed) {
  if (followed.isEmpty) return false;
  final mine = {
    _key(item.title),
    _key(item.titleEnglish),
    _key(item.titleNative),
  }..remove('');
  for (final k in mine) {
    if (followed.contains(k)) return true;
  }
  for (final k in mine) {
    for (final f in followed) {
      final shorter = k.length < f.length ? k.length : f.length;
      final longer = k.length < f.length ? f.length : k.length;
      if (shorter >= 6 && shorter / longer >= .75 && (k.contains(f) || f.contains(k))) {
        return true;
      }
    }
  }
  return false;
}

String calendarKey(String title) => _key(title);

const _dayNames = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const _monthNames = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Vista de la sección «Calendario».
class CalendarView extends StatefulWidget {
  final CalendarController controller;

  /// Títulos de mi biblioteca, ya normalizados con [calendarKey].
  final Set<String> followed;
  final ValueChanged<AiringItem> onOpen;
  final ScrollController? scroll;
  const CalendarView({
    super.key,
    required this.controller,
    required this.followed,
    required this.onOpen,
    this.scroll,
  });
  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  String filter = 'Todos';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final now = c.now();
      final monday = c.currentMonday;
      final week = c.thisWeek;
      final mine = {for (final i in week) if (isFollowedAiring(i, widget.followed)) i};
      final shown = filter == 'Mis animes' ? [for (final i in week) if (mine.contains(i)) i] : week;
      return SingleChildScrollView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Calendario', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'Estrenos de la semana según AniList, con tu horario local. Se actualiza solo el primer día que abres Neko cada lunes.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final name in const ['Todos', 'Mis animes'])
                  ChoiceChip(
                    label: Text(name == 'Mis animes' ? '$name (${mine.length})' : '$name (${week.length})'),
                    selected: filter == name,
                    onSelected: (_) => setState(() => filter = name),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: c.loading ? null : () => c.ensureFresh(force: true),
                  icon: c.loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(c.loading ? 'Actualizando…' : 'Actualizar ahora'),
                ),
                if (c.fetchedAt != null)
                  Text(
                    'Última actualización: ${c.fetchedAt!.day} ${_monthNames[c.fetchedAt!.month - 1]} ${_hhmm(c.fetchedAt!)}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
              ],
            ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'No se pudo actualizar: ${c.error}${week.isEmpty ? '' : ' Se conserva el último listado guardado.'}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 18),
            if (week.isEmpty && !c.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Todavía no hay estrenos guardados para esta semana. Pulsa «Actualizar ahora».',
                  style: TextStyle(color: muted),
                ),
              )
            else if (filter == 'Mis animes' && shown.isEmpty && !c.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Ninguna serie de tu biblioteca tiene estreno esta semana. Guarda animes en «Mi lista» para verlos aquí.',
                  style: TextStyle(color: muted),
                ),
              )
            else
              for (var d = 0; d < 7; d++)
                _day(
                  DateTime(monday.year, monday.month, monday.day + d),
                  d,
                  now,
                  [for (final i in shown) if (i.airingAt.weekday == d + 1) i],
                  mine,
                ),
          ],
        ),
      );
    },
  );

  Widget _day(DateTime date, int index, DateTime now, List<AiringItem> list, Set<AiringItem> mine) {
    final today = date.year == now.year && date.month == now.month && date.day == now.day;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_dayNames[index]} ${date.day} ${_monthNames[date.month - 1]}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: today ? accent : ink,
                ),
              ),
              if (today) ...[const SizedBox(width: 8), _chip('HOY', accent)],
              const SizedBox(width: 8),
              Text('${list.length}', style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          if (list.isEmpty)
            const Text('Sin estrenos.', style: TextStyle(color: muted, fontSize: 12))
          else
            LayoutBuilder(
              builder: (_, c) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisExtent: 112,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 10,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => _card(list[i], now, mine.contains(list[i])),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xcc191328),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700),
    ),
  );

  Widget _card(AiringItem item, DateTime now, bool followed) {
    final status = item.statusAt(now);
    final aired = status == 'Emitido';
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onOpen(item),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: followed ? elevated : null,
            border: Border.all(
              color: followed ? accent.withValues(alpha: .75) : border,
              width: followed ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 56, height: 80, child: Cover(item.cover, thumbnail: true)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Episodio ${item.episode} · ${_hhmm(item.airingAt)}',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _chip(status, aired ? muted : accent),
                        if (followed) _chip('EN TU LISTA', accent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
