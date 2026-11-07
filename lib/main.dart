import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'catalog.dart';
import 'playback_health.dart';
import 'playback_config.dart';
import 'recent_episodes.dart';
import 'monoschinos_page.dart';
import 'monoschinos_client.dart';
import 'monoschinos_sources.dart';
import 'app_ui.dart';
import 'about_page.dart';
import 'sidebar_mascot.dart';
import 'startup_overlay.dart';
import 'anime_detail_panel.dart';
import 'ui_filters.dart';
import 'home_banner.dart';
import 'anilist_client.dart';
import 'anilist_account_tile.dart';
import 'calendar_page.dart';
import 'mal_client.dart';
import 'mal_sync.dart';
import 'extra_recent.dart';
import 'translator.dart';
import 'monoschinos_synopsis.dart';
import 'mal_list_dialog.dart';
import 'addons/addons_page.dart';
import 'media/source.dart';
import 'media/server_selector.dart';
import 'media/downloads_page.dart';
import 'runtime/runtime_check.dart';

const background = Color(0xff070b13),
    surface = Color(0xff101622),
    elevated = Color(0xff192033),
    border = Color(0xff222a3b),
    accent = Color(0xffa577ff),
    muted = Color(0xff8e98ad),
    ink = Color(0xfff0f1f6);
void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if(arguments.length==2 && arguments.first=='--verify-bundled-runtime') {
    try {await verifyBundledRuntime(arguments[1]);exit(0);}
    catch(e) {await File(arguments[1]).writeAsString(jsonEncode({'ok':false,'error':'$e'}));exit(1);}
  }
  MediaKit.ensureInitialized();
  runApp(const NekoApp());
}

class NekoApp extends StatelessWidget {
  final Widget? home;
  const NekoApp({super.key, this.home});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Neko Anime 0.3.1 Stable',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      fontFamily: 'Manrope',
      visualDensity: VisualDensity.compact,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 13),
        bodySmall: TextStyle(fontSize: 11),
      ),
      chipTheme: ChipThemeData(
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        labelStyle: const TextStyle(fontSize: 11),
        selectedColor: const Color(0xff6531bd),
        checkmarkColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 15,
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xff8743ed),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: elevated,
        contentTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          color: ink,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        onSurface: ink,
        secondary: accent,
      ),
      dividerColor: border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
      ),
    ),
    home: home ?? const HomePage(),
  );
}

class Library extends ChangeNotifier {
  Library({this.storageFile});
  final File? storageFile;
  static const statuses = [
    'Viendo',
    'Terminados',
    'Pendientes',
    'En pausa',
    'Abandonados',
  ];
  final Map<String, Map<String, dynamic>> tracking = {};
  final Set<String> enabledSources = {'TioAnime', 'AnimeFLV', 'AnimeAV1'};
  final Map<String, Anime> favorites = {};
  final Map<String, Map<String, dynamic>> history = {};
  // Avance de cada episodio por separado (clave: URL del episodio).
  final Map<String, Map<String, dynamic>> progress = {};
  late final File file;
  Future<void> _saving = Future.value();
  Future<void> load() async {
    final path = Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
    file = storageFile ?? File('$path/NekoPlayerPC/library.json');
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map;
        if (data['sources'] is List) {
          final valid = List<String>.from(data['sources'])
              .where(
                (s) =>
                    ['TioAnime', 'AnimeFLV', 'AnimeAV1', 'JKAnime'].contains(s),
              )
              .toSet();
          if (valid.isNotEmpty) {
            enabledSources
              ..clear()
              ..addAll(valid);
          }
        }
        // Fuentes adicionales apagadas por el usuario (solo la Library principal).
        if (storageFile == null && data['disabledMonos'] is List) {
          userDisabledMonosLabels
            ..clear()
            ..addAll(List<String>.from(data['disabledMonos']));
        }
        for (final value in (data['favorites'] as List? ?? [])) {
          final a = Anime.fromJson(Map<String, dynamic>.from(value));
          favorites[a.url] = a;
        }
        for (final value in (data['history'] as List? ?? [])) {
          final entry = Map<String, dynamic>.from(value);
          history[entry['anime']['url']] = entry;
        }
        for (final value in (data['progress'] as List? ?? [])) {
          final entry = Map<String, dynamic>.from(value);
          if (entry['episodeUrl'] is String) {
            progress[entry['episodeUrl']] = entry;
          }
        }
        for (final value in (data['tracking'] as List? ?? [])) {
          final entry = Map<String, dynamic>.from(value);
          if (statuses.contains(entry['status'])) {
            final anime = Anime.fromJson(
              Map<String, dynamic>.from(entry['anime']),
            );
            tracking[anime.url] = entry;
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  void toggle(Anime anime) {
    if (favorites.containsKey(anime.url)) {
      favorites.remove(anime.url);
    } else {
      favorites[anime.url] = anime;
    }
    save();
    notifyListeners();
  }

  String? statusFor(Anime anime) => tracking[anime.url]?['status'] as String?;

  void removeHistory(Anime anime) {
    history.remove(anime.url);
    progress.removeWhere((_, e) => e['animeUrl'] == anime.url);
    save();
    notifyListeners();
  }

  void setStatus(Anime anime, String? status) {
    if (status == null) {
      tracking.remove(anime.url);
    } else if (statuses.contains(status)) {
      tracking[anime.url] = {'anime': anime.toJson(), 'status': status};
    } else {
      return;
    }
    save();
    notifyListeners();
  }

  List<Anime> get savedAnime => {
    ...favorites,
    for (final entry in tracking.entries)
      entry.key: Anime.fromJson(
        Map<String, dynamic>.from(entry.value['anime']),
      ),
  }.values.toList();

  Future<void> get flushed => _saving;

  void record(
    Anime anime,
    Episode episode,
    Duration position,
    Duration duration, {
    bool notify = true,
  }) {
    if (position.inSeconds < 5) return;
    // Autoguardado durante la reproducción: si no cambió nada (pausa),
    // no escribe en disco ni avisa a la interfaz.
    final previous = progress[episode.url];
    if (!notify &&
        previous != null &&
        previous['seconds'] == position.inSeconds &&
        previous['duration'] == duration.inSeconds &&
        history[anime.url]?['episodeUrl'] == episode.url) {
      return;
    }
    history[anime.url] = {
      'anime': anime.toJson(),
      'episode': episode.number,
      'episodeUrl': episode.url,
      'seconds': position.inSeconds,
      'duration': duration.inSeconds,
      'updated': DateTime.now().toIso8601String(),
    };
    progress[episode.url] = {
      'animeUrl': anime.url,
      'episodeUrl': episode.url,
      'seconds': position.inSeconds,
      'duration': duration.inSeconds,
    };
    save();
    // Mientras se reproduce, el Home sigue montado bajo el reproductor:
    // notificar en cada autoguardado lo reconstruye entero junto al video.
    if (notify) notifyListeners();
  }

  int resume(Episode episode) {
    final saved = progress[episode.url];
    if (saved != null) {
      final pos = (saved['seconds'] as num).toInt(),
          total = (saved['duration'] as num).toInt();
      return total > 0 && pos > total - 40 ? 0 : pos;
    }
    for (final item in history.values) {
      if (item['episodeUrl'] == episode.url) {
        final pos = (item['seconds'] as num).toInt(),
            total = (item['duration'] as num).toInt();
        return total > 0 && pos > total - 40 ? 0 : pos;
      }
    }
    return 0;
  }

  void save() {
    final body = jsonEncode({
      'favorites': favorites.values.map((a) => a.toJson()).toList(),
      'history': history.values.toList(),
      'progress': progress.values.toList(),
      'sources': enabledSources.toList(),
      if (storageFile == null)
        'disabledMonos': userDisabledMonosLabels.toList(),
      'tracking': tracking.values.toList(),
    });
    _saving = _saving
        .catchError((_) {})
        .then((_) async {
          await file.parent.create(recursive: true);
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(body, flush: true);
          await temp.rename(file.path);
        })
        .catchError((_) {});
  }
}

class HomePage extends StatefulWidget {
  final ProviderClient? api;
  final Library? library;
  final MonosClient Function(int)? monosClientFactory;
  const HomePage({super.key, this.api, this.library, this.monosClientFactory});
  @override
  State<HomePage> createState() => _HomeState();
}

/// Dónde se encontró un anime de un ranking: en el catálogo principal
/// ([anime]) o en una de las fuentes extra ([entry] del sitio [site]).
class _RankedHit {
  final Anime? anime;
  final MonosEntry? entry;
  final int site;
  const _RankedHit.anime(Anime this.anime) : entry = null, site = -1;
  const _RankedHit.monos(MonosEntry this.entry, this.site) : anime = null;
  String get provider => anime?.provider ?? monosSites[site].label;
}

class _HomeState extends State<HomePage> {
  late final api = widget.api ?? ProviderClient();
  late final library = widget.library ?? Library();
  final search = TextEditingController();
  final scroll = ScrollController();
  late final RecentEpisodes recent = RecentEpisodes(api);
  Timer? recentTimer;
  bool refreshingRecent = false;
  // Fichas ya resueltas de los episodios recientes (para el botón Mi lista del banner).
  final Map<String, Anime> recentAnime = {};
  final AniListClient anilist = AniListClient();
  late final CalendarController calendar = CalendarController(anilist);
  final MalClient mal = MalClient();
  final Translator translator = Translator();
  // Banner del Inicio: 'recent' (episodios nuevos de las fuentes) o un ranking
  // de AniList ('trending', 'popular', 'top').
  String bannerMode = 'recent';
  // Novedades de las fuentes extra (índice en monosSites -> episodios).
  final Map<int, List<ExtraRecent>> extraRecents = {};
  final Map<String, Future<List<AniListInfo>>> rankings = {};
  final Map<int, Future<_RankedHit?>> rankedFound = {};
  final Map<int, _RankedHit> rankedHit = {};
  bool malBusy = false;
  List<Anime> cards = [];
  bool startupLoading = true;
  bool loading = true, more = false, loadingMore = false;
  String? error;
  int page = 1, section = 0, generation = 0;
  Anime? selectedAnime;
  String query = '', filter = 'Todas';
  String listStatus = 'Todos', sortOrder = 'Original';
  // MonosChinos integrado al catálogo principal.
  MonosClient? monosClient;
  List<MonosEntry> monosCards = [];
  MonosEntry? selectedMonos;
  bool monosBusy = false;
  String? monosError;
  int monosPage = 1, monosGeneration = 0;
  String monosQuery = '', loadedQuery = '';
  int monosSite = -1; // fuente cuyas tarjetas hay en monosCards
  @override
  void initState() {
    super.initState();
    mal.load().then((_) {
      if (mounted) setState(() {});
    });
    translator.load().then((_) {
      if (mounted) setState(() {});
    });
    malSync = MalSync(mal, anilist)
      ..onMessage = (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
          );
        }
      };
    library
        .load()
        .then((_) async {
          if (!mounted) return;
          api.enabledProviders
            ..clear()
            ..addAll(library.enabledSources);
          final initialCatalog = load();
          refreshRecent();
          calendar.ensureFresh();
          recentTimer = Timer.periodic(
            const Duration(minutes: 15),
            (_) => refreshRecent(),
          );
          await initialCatalog;
          if (mounted) setState(() => startupLoading = false);
        })
        .catchError((Object failure) {
          if (!mounted) return;
          setState(() {
            startupLoading = false;
            loading = false;
            error = cleanError(failure);
          });
        });
    library.addListener(changed);
    calendar.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    recentTimer?.cancel();
    ++monosGeneration;
    monosClient?.close();
    api.close();
    malSync = null;
    translator.close();
    anilist.close();
    mal.close();
    library.removeListener(changed);
    calendar.removeListener(changed);
    calendar.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  /// Lee las novedades de OtakusTV, AnimeYT y AnimeYTX (las que estén activas).
  Future<void> refreshExtraRecents() async {
    final sites = [
      for (final i in enabledMonosSiteIndexes)
        if (extraRecentSupported(i)) i,
    ];
    extraRecents.removeWhere((site, _) => !sites.contains(site));
    await Future.wait([
      for (final site in sites)
        () async {
          final client = MonosClient(monosSites[site]);
          try {
            final list = await fetchExtraRecents(client, site)
                .timeout(const Duration(seconds: 25));
            if (list.isNotEmpty) extraRecents[site] = list;
          } catch (_) {
            // Se conserva la lista anterior si falla una lectura puntual.
          } finally {
            client.close();
          }
        }(),
    ]);
  }

  Future<void> refreshRecent() async {
    if (!mounted || refreshingRecent) return;
    setState(() => refreshingRecent = true);
    try {
      await Future.wait([
        recent.refresh(api.enabledProviders),
        refreshExtraRecents(),
      ]);
    } finally {
      if (mounted) setState(() => refreshingRecent = false);
    }
  }

  Future<void> openRecent(RecentEpisode episode) async {
    try {
      final anime = await recent.animeFor(episode);
      if (mounted) open(anime);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la ficha. Vuelve a intentarlo.'),
          ),
        );
      }
    }
  }

  Future<void> load({bool append = false}) async {
    final request = ++generation;
    loadedQuery = query;
    if (append) {
      setState(() => loadingMore = true);
    } else {
      setState(() {
        loading = true;
        error = null;
        page = 1;
      });
    }
    try {
      final result = await api.catalog(
        page: page,
        query: query,
        onPartial: (partial) {
          if (!mounted || request != generation || append) return;
          setState(() {
            cards = partial.cards;
            more = partial.more;
            loading = false;
          });
        },
      );
      if (!mounted || request != generation) return;
      setState(() {
        cards = append
            ? ProviderClient.merge([...cards, ...result.cards])
            : result.cards;
        more = result.more;
        error = null;
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() {
          error = cleanError(e);
          if (append && page > 1) page--;
        });
      }
    } finally {
      if (mounted && request == generation) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  MonosClient monosFor(int site) {
    final current = monosClient;
    if (current != null && current.site == monosSites[site]) return current;
    current?.close();
    return monosClient =
        widget.monosClientFactory?.call(site) ?? MonosClient(monosSites[site]);
  }

  Future<void> loadMonos({bool append = false}) async {
    final id = ++monosGeneration;
    final client = monosFor(section - 6);
    setState(() {
      monosBusy = true;
      monosError = null;
      if (!append) {
        monosPage = 1;
        monosQuery = query;
        monosSite = section - 6;
        monosCards = [];
      }
    });
    try {
      final data = await client.catalog(monosPage, search: query);
      if (!mounted || id != monosGeneration) return;
      setState(() {
        monosCards = append
            ? [
                ...monosCards,
                ...data.where((e) => !monosCards.any((o) => o.url == e.url)),
              ]
            : data;
      });
    } catch (e) {
      if (mounted && id == monosGeneration) {
        setState(() {
          monosError = cleanError(e);
          if (append && monosPage > 1) monosPage--;
        });
      }
    } finally {
      if (mounted && id == monosGeneration) setState(() => monosBusy = false);
    }
  }

  void openMonosSource(int site) {
    setState(() {
      section = site + 6;
      selectedAnime = null;
      selectedMonos = null;
    });
    if (monosCards.isEmpty || monosQuery != query || monosSite != site) {
      loadMonos();
    }
  }

  /// Índice en monosSites de una fuente habilitada por su nombre (o null).
  int? monosIndexOf(String label) {
    for (final i in enabledMonosSiteIndexes) {
      if (monosSites[i].label == label) return i;
    }
    return null;
  }

  Widget monosBody() {
    final site = section - 6;
    if (monosBusy && monosCards.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (monosError != null && monosCards.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'El catálogo no está disponible',
        message: monosError!,
        action: () => loadMonos(),
        actionText: 'Volver a intentar',
      );
    }
    final list = [...monosCards];
    if (sortOrder != 'Original') {
      list.sort(
        (a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()) *
            (sortOrder == 'Z–A' ? -1 : 1),
      );
    }
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            query.isEmpty ? 'Explorar catálogo' : 'Resultados para “$query”',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            '${list.length} animes · ${monosSites[site].label}',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 32),
          if (list.isEmpty && !monosBusy)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Text(
                'No se encontraron animes para esta búsqueda.',
                style: TextStyle(color: muted),
              ),
            ),
          LayoutBuilder(
            builder: (context, c) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (c.maxWidth / 154).floor().clamp(1, 10),
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: .61,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => AnimePoster(
                anime: Anime(list[i].title, list[i].url, list[i].image),
                sourceLabel: monosSites[site].label,
                favorite: false,
                showFavorite: false,
                onFavorite: () {},
                onTap: () => setState(() => selectedMonos = list[i]),
              ),
            ),
          ),
          if (list.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 26),
                child: OutlinedButton.icon(
                  onPressed: monosBusy
                      ? null
                      : () {
                          monosPage++;
                          loadMonos(append: true);
                        },
                  icon: monosBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: const Text('Cargar más animes'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void open(Anime anime) => setState(() => selectedAnime = anime);
  List<Anime> get visible {
    var list = section == 2
        ? library.savedAnime
              .where(
                (a) =>
                    listStatus == 'Todos' || library.statusFor(a) == listStatus,
              )
              .toList()
        : section == 3
        ? library.history.values
              .toList()
              .reversed
              .map((e) => Anime.fromJson(Map<String, dynamic>.from(e['anime'])))
              .toList()
        : cards;
    return filterAnimePresentation(list, source: filter, order: sortOrder);
  }

  void selectSource(String value) => setState(() {
    filter = value;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: StartupOverlay(
      loading: startupLoading,
      child: Theme(
        data: Theme.of(context).copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff8239e4),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              textStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xff0e121d),
              foregroundColor: const Color(0xffded9ef),
              minimumSize: const Size(0, 40),
              side: const BorderSide(color: Color(0xff30243f)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, size) {
            return Row(
              children: [
                sidebar(size.maxWidth < 900),
                Expanded(
                  child: Column(
                    children: [
                      topbar(),
                      if (section != 5 && section != -1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                          child: sourceTabs(),
                        ),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: section == -1 ? calendarBody() : section >= 6 ? monosBody()
                                  : section == 5
                                  ? settings()
                                  : section == 4
                                  ? recentBody()
                                  : body(),
                            ),
                            if (section < 5 && selectedAnime != null)
                              SizedBox(
                                width: size.maxWidth < 1000 ? 300 : 350,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      left: BorderSide(color: border),
                                    ),
                                    color: surface,
                                  ),
                                  child: DetailPage(
                                    key: ValueKey(
                                      '${selectedAnime!.url}:$filter',
                                    ),
                                    anime: selectedAnime!,
                                    api: api,
                                    library: library,
                                    initialSource: filter,
                                    embedded: true,
                                    onClose: () =>
                                        setState(() => selectedAnime = null),
                                  ),
                                ),
                              ),
                            if (section >= 6 && selectedMonos != null)
                              SizedBox(
                                width: size.maxWidth < 1000 ? 300 : 350,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      left: BorderSide(color: border),
                                    ),
                                    color: surface,
                                  ),
                                  child: monosDetailPanel(
                                    client: monosFor(section - 6),
                                    anime: selectedMonos!,
                                    onClose: () =>
                                        setState(() => selectedMonos = null),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget sidebar(bool compact) => Container(
    width: compact ? 56 : 180,
    decoration: const BoxDecoration(
      color: Color(0xff090e18),
      border: Border(right: BorderSide(color: border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 3 : 8, 10, compact ? 3 : 8, 8),
          child: SizedBox(
            width: double.infinity,
            height: compact ? 28 : 76,
            child: Image.asset(
              'assets/neko_logo_sleeping.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'Neko Anime',
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              navItem(
                Icons.home_rounded,
                'Inicio',
                section == 0,
                compact,
                () => setState(() {
                  section = 0;
                  filter = 'Todas';
                }),
              ),
              navItem(
                Icons.grid_view_rounded,
                'Catálogo',
                section == 1 && filter == 'Todas',
                compact,
                () => setState(() {
                  section = 1;
                  filter = 'Todas';
                }),
              ),
              navItem(
                Icons.bookmark_border_rounded,
                'Mi lista',
                section == 2,
                compact,
                () => setState(() {
                  section = 2;
                  filter = 'Todas';
                }),
              ),
              navItem(
                Icons.history_rounded,
                'Historial',
                section == 3,
                compact,
                () => setState(() {
                  section = 3;
                  filter = 'Todas';
                }),
              ),
              navLabel('FUENTES', compact),
              for (final source in [
                'AnimeFLV',
                'TioAnime',
                'AnimeAV1',
                if (api.enabledProviders.contains('JKAnime')) 'JKAnime',
              ])
                navItem(
                  Icons.layers_rounded,
                  source,
                  section == 1 && filter == source,
                  compact,
                  () => setState(() {
                    section = 1;
                    filter = source;
                  }),
                  color: sourceColor(source),
                ),
              for (final i in enabledMonosSiteIndexes)
                navItem(
                  Icons.pets_outlined,
                  monosSites[i].label,
                  section == i + 6,
                  compact,
                  () => openMonosSource(i),
                  color: sourceColor('MonosChinos1'),
                ),
              navLabel('DESCUBRIR', compact),
              navItem(
                Icons.new_releases_outlined,
                'Nuevos episodios',
                section == 4,
                compact,
                () => setState(() {
                  section = 4;
                  filter = 'Todas';
                }),
              ),
              navItem(
                Icons.calendar_month_rounded,
                'Calendario',
                section == -1,
                compact,
                () => setState(() {
                  section = -1;
                  filter = 'Todas';
                }),
              ),
              navLabel('SISTEMA', compact),
              navItem(Icons.download_rounded, 'Descargas', false, compact,
                () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsPage())),
              ),
              navItem(
                Icons.extension_rounded,
                'Complementos',
                false,
                compact,
                () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AddonsPage(),
                )),
              ),
              navItem(
                Icons.tune_rounded,
                'Ajustes',
                section == 5,
                compact,
                () => setState(() => section = 5),
              ),
            ],
          ),
        ),
        SidebarMascot(compact: compact),
      ],
    ),
  );

  Widget navLabel(String text, bool compact) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 0, 5),
    child: compact
        ? const Divider(height: 1)
        : Text(
            text,
            style: const TextStyle(
              color: muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
  );
  Widget navItem(
    IconData icon,
    String label,
    bool selected,
    bool compact,
    VoidCallback action, {
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Tooltip(
      message: label,
      child: InkWell(
        onTap: () {
          action();
          if (scroll.hasClients) scroll.jumpTo(0);
        },
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xff6730bf), Color(0xff20123f)],
                  )
                : null,
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: .3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : color ?? muted,
              ),
              if (!compact) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? ink : const Color(0xffb9c3da),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget topbar() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 15, 22, 16),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 510),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: search,
                  onSubmitted: (value) {
                    query = value.trim();
                    if (section >= 6) {
                      loadMonos();
                    } else {
                      setState(() => section = 1);
                      load();
                    }
                  },
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Buscar anime…',
                    hintStyle: const TextStyle(fontSize: 12, color: muted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        search.clear();
                        query = '';
                        section >= 6 ? loadMonos() : load();
                      },
                      icon: const Icon(Icons.close, size: 15),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  final MenuController sourceMenu = MenuController();

  void pickSource(String source) {
    final monosIndex = monosIndexOf(source);
    if (monosIndex != null) {
      openMonosSource(monosIndex);
    } else {
      final backFromMonos = section >= 6;
      setState(() {
        if (backFromMonos) section = 1;
        filter = source;
        selectedMonos = null;
      });
      if (backFromMonos && query != loadedQuery) load();
    }
  }

  String get currentSource =>
      section >= 6 && section - 6 < monosSites.length
      ? monosSites[section - 6].label
      : filter;

  /// Color estable para cada fuente (según su nombre).
  static Color sourceColor(String name) {
    var hue = 0;
    for (final unit in name.codeUnits) {
      hue = (hue * 31 + unit) % 360;
    }
    return HSLColor.fromAHSL(1, hue.toDouble(), .5, .46).toColor();
  }

  Widget sourceAvatar(String name, {double size = 26}) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: name == 'Todas' ? accent : sourceColor(name),
      borderRadius: BorderRadius.circular(8),
    ),
    child: name == 'Todas'
        ? Icon(Icons.apps_rounded, size: size * .65, color: Colors.white)
        : Text(
            name.isEmpty ? '' : name[0].toUpperCase(),
            style: TextStyle(
              fontSize: size * .5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
  );

  Widget sourceCard(String source, double width) {
    final selected = currentSource == source;
    return SizedBox(
      width: width,
      child: Material(
        color: selected ? accent.withValues(alpha: .16) : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            sourceMenu.close();
            pickSource(source);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? accent : Colors.transparent),
            ),
            child: Row(
              children: [
                sourceAvatar(source),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    source == 'Todas' ? 'Todas las fuentes' : source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded, size: 17, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Botón "Fuente: X" que abre un panel con una tarjeta por fuente.
  Widget sourcePicker(List<String> sources) => MenuAnchor(
    controller: sourceMenu,
    style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(surface),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
    ),
    menuChildren: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 2, bottom: 8),
                child: Text(
                  'Elige dónde buscar',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
              sourceCard('Todas', 416),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final s in sources) sourceCard(s, 204)],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 10),
                child: Text(
                  '${sources.length} fuentes activas · se cambian en Ajustes',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
    builder: (context, controller, child) => OutlinedButton(
      onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: border),
        foregroundColor: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          sourceAvatar(currentSource, size: 24),
          const SizedBox(width: 9),
          const Text('Fuente:', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(width: 6),
          Text(
            currentSource == 'Todas' ? 'Todas las fuentes' : currentSource,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        ],
      ),
    ),
  );

  Widget sourceTabs() => LayoutBuilder(
    builder: (context, c) {
      final sources = sourcePicker([
        ...api.enabledProviders,
        for (final i in enabledMonosSiteIndexes) monosSites[i].label,
      ]);
      final order = DropdownButton<String>(
        key: const ValueKey('catalog-order'),
        value: sortOrder,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(
            value: 'Original',
            child: Text('Orden de la fuente', style: TextStyle(fontSize: 12)),
          ),
          DropdownMenuItem(
            value: 'A–Z',
            child: Text('Alfabético (A–Z)', style: TextStyle(fontSize: 12)),
          ),
          DropdownMenuItem(
            value: 'Z–A',
            child: Text('Alfabético (Z–A)', style: TextStyle(fontSize: 12)),
          ),
        ],
        onChanged: (value) => setState(() => sortOrder = value!),
      );
      return c.maxWidth >= 1000
          ? Row(children: [sources, const Spacer(), order])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [sources, order],
            );
    },
  );

  Widget body() {
    if (loading && section < 2) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (error != null && cards.isEmpty && section < 2) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'El catálogo no está disponible',
        message: error!,
        action: () => load(),
        actionText: 'Volver a intentar',
      );
    }
    final list = visible;
    if (section == 3 && list.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'Historial vacío',
        message: 'Los episodios que reproduzcas aparecerán aquí para continuar después.',
      );
    }
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (api.notice.isNotEmpty && section < 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: notice(api.notice, () => load()),
            ),
          if (section == 0 && query.isEmpty && list.isNotEmpty) ...[
            LayoutBuilder(
              builder: (context, c) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: bannerSection(list.first)),
                  if (c.maxWidth > 850) ...[
                    const SizedBox(width: 16),
                    SizedBox(width: 254, child: continuePanel()),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (library.history.isNotEmpty) ...[
              rail(
                'Seguir viendo',
                library.history.values
                    .toList()
                    .reversed
                    .map(
                      (e) =>
                          Anime.fromJson(Map<String, dynamic>.from(e['anime'])),
                    )
                    .toList(),
                removable: true,
              ),
              const SizedBox(height: 22),
            ],
            sectionHeading(
              'Últimos episodios',
              Icons.auto_awesome_rounded,
              () => setState(() => section = 4),
            ),
            const SizedBox(height: 10),
            const SizedBox(height: 14),
            homeRecentRail(),
            const SizedBox(height: 22),
            rail('Explorar catálogo', list.take(16).toList()),
            const SizedBox(height: 22),
            if (list.length > 16)
              rail('Más para descubrir', list.skip(16).toList()),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section == 2
                            ? 'Mi lista'
                            : section == 3
                            ? 'Tu historial'
                            : query.isEmpty
                            ? 'Explorar catálogo'
                            : 'Resultados para “$query”',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${list.length} animes${section < 2 ? ' · ${(filter == 'Todas' ? api.enabledProviders.join(' + ') : filter)}' : ''}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            if (section == 2) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Todos', ...Library.statuses].map((status) {
                  final count = status == 'Todos'
                      ? library.savedAnime.length
                      : library.savedAnime
                            .where((a) => library.statusFor(a) == status)
                            .length;
                  return ChoiceChip(
                    label: Text('$status ($count)'),
                    selected: listStatus == status,
                    onSelected: (_) => setState(() => listStatus = status),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],
            if (list.isEmpty)
              Padding(
                padding: EdgeInsets.all(48),
                child: Text(
                  section == 2
                      ? 'No hay animes en esta lista. Abre una ficha para guardar su estado de seguimiento.'
                      : 'No se encontraron animes para esta búsqueda.',
                  style: const TextStyle(color: muted),
                ),
              ),
            LayoutBuilder(
              builder: (context, c) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (c.maxWidth / 154).floor().clamp(1, 10),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  childAspectRatio: .61,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => poster(list[i], removable: section == 3),
              ),
            ),
          ],
          if (more && section < 2)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 26),
                child: OutlinedButton.icon(
                  onPressed: loadingMore
                      ? null
                      : () {
                          page++;
                          load(append: true);
                        },
                  icon: loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: const Text('Cargar más animes'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget recentBody() {
    final items = recent.items(provider: filter);
    if (sortOrder != 'Original') {
      items.sort(
        (a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()) *
            (sortOrder == 'Z–A' ? -1 : 1),
      );
    }
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nuevos episodios',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Últimas publicaciones de las fuentes activas. Actualización automática cada 15 minutos mientras Neko está abierto.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: refreshingRecent ? null : refreshRecent,
                icon: refreshingRecent
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  refreshingRecent ? 'Actualizando…' : 'Actualizar ahora',
                ),
              ),
              if (recent.checkedAt != null)
                Text(
                  'Última revisión: ${recent.checkedAt!.hour.toString().padLeft(2, '0')}:${recent.checkedAt!.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
            ],
          ),
          if (recent.failures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No se pudo actualizar: ${recent.failures.join(', ')}. Se conserva el último listado disponible.',
                style: const TextStyle(color: muted),
              ),
            ),
          const SizedBox(height: 20),
          if (items.isEmpty && !refreshingRecent)
            const Text(
              'No hay episodios recientes disponibles en estas fuentes. Puedes volver a actualizar.',
              style: TextStyle(color: muted),
            ),
          LayoutBuilder(
            builder: (_, c) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (c.maxWidth / 160).floor().clamp(1, 10),
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: .64,
              ),
              itemCount: items.length,
              itemBuilder: (_, index) => AnimePoster(
                anime: items[index].card,
                favorite: false,
                showFavorite: false,
                onFavorite: () {},
                onTap: () => openRecent(items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionHeading(String title, IconData icon, VoidCallback action) =>
      Row(
        children: [
          Icon(icon, color: accent, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: action,
            child: const Text('Ver todo →', style: TextStyle(fontSize: 11)),
          ),
        ],
      );

  Widget homeRecentRail() {
    final items = recent.items(provider: filter).take(12).toList();
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.update_rounded, color: muted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                refreshingRecent
                    ? 'Consultando últimos episodios…'
                    : 'No hay novedades disponibles para esta fuente.',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: refreshingRecent ? null : refreshRecent,
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 248,
      child: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.trackpad,
          },
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(
            width: 146,
            child: AnimePoster(
              anime: items[i].card,
              favorite: false,
              showFavorite: false,
              onFavorite: () {},
              onTap: () => openRecent(items[i]),
            ),
          ),
        ),
      ),
    );
  }

  Widget continuePanel() {
    final entries = library.history.values.toList().reversed.take(3).toList();
    return Container(
      height: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Continúa viendo',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Ver historial',
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: accent,
                ),
                onPressed: () => setState(() => section = 3),
              ),
            ],
          ),
          if (entries.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Tu próximo episodio te espera.\nEl progreso aparecerá aquí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: muted, height: 1.8),
                ),
              ),
            ),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Builder(
                builder: (_) {
                  final anime = Anime.fromJson(
                    Map<String, dynamic>.from(entry['anime']),
                  );
                  final total = (entry['duration'] as num?)?.toDouble() ?? 0;
                  final seconds = (entry['seconds'] as num?)?.toDouble() ?? 0;
                  final progress = total > 0
                      ? (seconds / total).clamp(0.0, 1.0)
                      : 0.0;
                  return InkWell(
                    onTap: () => open(anime),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: SizedBox(
                            width: 58,
                            height: 47,
                            child: Cover(anime.cover),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                anime.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Episodio ${entry['episode']}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                borderRadius: BorderRadius.circular(3),
                                backgroundColor: border,
                                color: accent,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static const bannerModes = [
    ('recent', 'Recientes'),
    ('season', 'Estrenos'),
    ('trending', 'Tendencia'),
    ('popular', 'Más populares'),
    ('top', 'Mejor puntuados'),
  ];

  Widget bannerSection(Anime fallback) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final mode in bannerModes)
              ChoiceChip(
                label: Text(mode.$2),
                selected: bannerMode == mode.$1,
                onSelected: (_) => setState(() => bannerMode = mode.$1),
              ),
          ],
        ),
      ),
      bannerMode == 'recent' ? homeBanner(fallback) : rankedBanner(fallback),
    ],
  );

  Widget rankedBanner(Anime fallback) {
    final mode = bannerMode;
    final future = rankings.putIfAbsent(mode, () => anilist.ranking(mode));
    return FutureBuilder<List<AniListInfo>>(
      key: ValueKey(mode),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            height: 292,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const CircularProgressIndicator(),
          );
        }
        final items = snapshot.data ?? const <AniListInfo>[];
        if (snapshot.hasError || items.isEmpty) {
          final reason = snapshot.hasError
              ? cleanError(snapshot.error!)
              : 'AniList no devolvió resultados';
          return Column(
            children: [
              notice('No se pudo cargar este ranking de AniList: $reason', () {
                rankings.remove(mode);
                setState(() {});
              }),
              const SizedBox(height: 10),
              homeBanner(fallback),
            ],
          );
        }
        return HomeBanner(
          key: ValueKey(mode),
          slides: [
            for (var i = 0; i < items.length; i++) rankedSlide(items[i], i + 1, mode),
          ],
        );
      },
    );
  }

  BannerSlide rankedSlide(AniListInfo info, int rank, String mode) {
    final hit = rankedHit[info.id];
    return BannerSlide(
      id: 'rank-$mode-${info.id}',
      title: info.titleEnglish.isNotEmpty ? info.titleEnglish : info.title,
      cover: info.cover,
      source: hit?.provider ?? '',
      label: switch (mode) {
        'season' => 'Esta temporada #$rank',
        'trending' => 'Tendencia #$rank',
        'popular' => 'Popular #$rank',
        _ => 'Top #$rank',
      },
      saved: hit?.anime != null && library.favorites.containsKey(hit!.anime!.url),
      onOpen: () => openRanked(info),
      onSave: () => saveRanked(info),
      infoStream: () => rankedInfoStream(info),
    );
  }

  static String _titleKey(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  /// Busca el anime de un ranking en TODAS las fuentes activas: las cuatro del
  /// catálogo principal y las demás (MonosChinos, LatAnime, OtakusTV, AnimeYT,
  /// AnimeYTX...). Prefiere coincidencia exacta de título; si no, una muy
  /// parecida; si no hay, devuelve null.
  Future<_RankedHit?> findInSources(AniListInfo info) => rankedFound.putIfAbsent(info.id, () async {
    final wanted = {
      _titleKey(info.title),
      _titleKey(info.titleEnglish),
    }..remove('');
    if (wanted.isEmpty) return null;

    int match(Iterable<String> titles) {
      var best = 0;
      for (final title in titles) {
        final key = _titleKey(title);
        if (key.isEmpty) continue;
        if (wanted.contains(key)) return 2;
        for (final w in wanted) {
          final shorter = key.length < w.length ? key.length : w.length;
          final longer = key.length < w.length ? w.length : key.length;
          if (shorter >= 6 &&
              shorter / longer >= .75 &&
              (key.contains(w) || w.contains(key))) {
            best = 1;
          }
        }
      }
      return best;
    }

    _RankedHit? exact, close;
    void consider(int quality, _RankedHit hit) {
      if (quality == 2) {
        exact ??= hit;
      } else if (quality == 1) {
        close ??= hit;
      }
    }

    final sites = enabledMonosSiteIndexes;
    for (final name in {info.title, info.titleEnglish}.where((s) => s.isNotEmpty)) {
      await Future.wait<void>([
        () async {
          try {
            final result = await api.catalog(query: name);
            for (final card in result.cards) {
              consider(match([card.title, ...card.alternatives]), _RankedHit.anime(card));
            }
          } catch (_) {}
        }(),
        for (final site in sites)
          () async {
            final client = MonosClient(monosSites[site]);
            try {
              final result = await client
                  .catalog(1, search: name)
                  .timeout(const Duration(seconds: 12));
              for (final entry in result) {
                consider(match([entry.title]), _RankedHit.monos(entry, site));
              }
            } catch (_) {
            } finally {
              client.close();
            }
          }(),
      ]);
      if (exact != null) break;
    }
    final hit = exact ?? close;
    if (hit != null) rankedHit[info.id] = hit;
    return hit;
  });

  /// Igual que [rankedInfo], pero entrega primero lo rápido (imagen, nota,
  /// géneros, que ya vienen de AniList) y después la sinopsis en español.
  Stream<BannerInfo?> rankedInfoStream(AniListInfo info) async* {
    BannerInfo make(String synopsis) => BannerInfo(
      status: info.status,
      synopsis: synopsis,
      banner: info.banner,
      cover: info.cover,
      score: info.score,
      genres: info.genres,
    );
    final hitFuture = findInSources(info); // en paralelo, no bloquea la imagen
    yield make('');
    var synopsis = '';
    try {
      final hit = await hitFuture;
      final anime = hit?.anime;
      if (anime != null) {
        synopsis = (await api.detail(anime)).synopsis.trim();
      } else if (hit?.entry != null) {
        synopsis = await spanishFromSite(hit!.site, hit.entry!);
      }
    } catch (_) {}
    if (synopsis.isEmpty) synopsis = await translator.toSpanish(info.description);
    if (mounted) setState(() {}); // actualiza la insignia de fuente
    yield make(synopsis);
  }

  Future<BannerInfo?> rankedInfo(AniListInfo info) async {
    var synopsis = '';
    try {
      final hit = await findInSources(info);
      final anime = hit?.anime;
      if (anime != null) {
        synopsis = (await api.detail(anime)).synopsis.trim();
      } else if (hit?.entry != null) {
        synopsis = await spanishFromSite(hit!.site, hit.entry!);
      }
    } catch (_) {}
    if (mounted) setState(() {});
    return BannerInfo(
      status: info.status,
      synopsis: synopsis.isNotEmpty
          ? synopsis
          : await translator.toSpanish(info.description),
      banner: info.banner,
      cover: info.cover,
      score: info.score,
      genres: info.genres,
    );
  }

  void notFoundInSources(AniListInfo info) {
    if (!mounted) return;
    final name = info.titleEnglish.isNotEmpty ? info.titleEnglish : info.title;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No encontré "$name" en tus fuentes activas.')),
    );
  }

  Widget calendarBody() => CalendarView(
    controller: calendar,
    scroll: scroll,
    followed: <String>{
      for (final a in library.savedAnime)
        for (final t in [a.title, ...a.alternatives])
          if (calendarKey(t).isNotEmpty) calendarKey(t),
    },
    onOpen: openAiring,
  );

  Future<void> openAiring(AiringItem item) async {
    showCompactNotice(context, 'Buscando "${item.title}" en tus fuentes...');
    final info = item.toInfo();
    await openRanked(info);
    if (mounted && rankedHit.containsKey(info.id)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void openHit(_RankedHit hit) {
    final anime = hit.anime;
    if (anime != null) {
      open(anime);
      return;
    }
    // Fuentes extra: se abre su catálogo con la ficha del anime ya elegida.
    final entry = hit.entry!;
    openMonosSource(hit.site);
    setState(() => selectedMonos = entry);
  }

  Future<void> openRanked(AniListInfo info) async {
    final hit = await findInSources(info);
    if (!mounted) return;
    if (hit == null) {
      notFoundInSources(info);
      return;
    }
    openHit(hit);
  }

  Future<void> saveRanked(AniListInfo info) async {
    final hit = await findInSources(info);
    if (!mounted) return;
    if (hit == null) {
      notFoundInSources(info);
      return;
    }
    final anime = hit.anime;
    if (anime != null) {
      library.toggle(anime);
      return;
    }
    // Las fuentes extra guardan su lista desde su propia ficha.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Está en ${monosSites[hit.site].label}. Guárdalo desde su ficha.'),
      ),
    );
    openHit(hit);
  }

  /// Banner del Inicio: rota entre los últimos episodios publicados por las
  /// fuentes activas. Si todavía no hay novedades, muestra el banner de siempre.
  Widget homeBanner(Anime fallback) {
    final latest = recent.items(provider: filter);
    // Las fuentes extra solo entran cuando se ven "Todas las fuentes".
    final extras = [
      if (filter == 'Todas')
        for (final site in enabledMonosSiteIndexes)
          if (extraRecents[site] != null) extraRecents[site]!,
    ];
    final groups = <List<Object>>[latest, ...extras];
    final slides = <BannerSlide>[];
    final seen = <String>{};
    // Se reparte por turnos entre las fuentes, un episodio por anime, hasta 12.
    for (var i = 0; slides.length < 12 && groups.any((g) => i < g.length); i++) {
      for (final group in groups) {
        if (i >= group.length || slides.length >= 12) continue;
        final item = group[i];
        if (item is RecentEpisode) {
          if (seen.add(ProviderClient.key(item.title))) slides.add(mainSlide(item));
        } else if (item is ExtraRecent) {
          if (seen.add(ProviderClient.key(item.title))) slides.add(extraSlide(item));
        }
      }
    }
    if (slides.isEmpty) return hero(fallback);
    return HomeBanner(slides: slides);
  }

  BannerSlide mainSlide(RecentEpisode item) => BannerSlide(
    id: item.episodeUrl,
    title: item.title,
    cover: item.cover,
    source: item.provider,
    label: 'Episodio ${item.number}',
    saved: () {
      final url = item.animeUrl ?? recentAnime[item.episodeUrl]?.url;
      return url != null && library.favorites.containsKey(url);
    }(),
    onOpen: () => openRecent(item),
    onSave: () => saveRecent(item),
    infoStream: () => bannerInfoStream(item),
  );

  BannerSlide extraSlide(ExtraRecent item) => BannerSlide(
    id: item.episodeUrl,
    title: item.title,
    cover: item.cover,
    source: item.label,
    label: item.note.isEmpty
        ? 'Episodio ${item.number}'
        : 'Episodio ${item.number} · ${item.note}',
    onOpen: () => openExtra(item),
    onSave: () {
      // Las fuentes extra guardan su lista desde su propia ficha.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Está en ${item.label}. Guárdalo desde su ficha.')),
      );
      openExtra(item);
    },
    infoStream: () => extraInfoStream(item),
  );

  /// Abre la ficha de una novedad de una fuente extra. Si la dirección era una
  /// suposición (LatAnime), primero la confirma buscando el título en la fuente.
  Future<void> openExtra(ExtraRecent item) async {
    var entry = item.anime;
    if (item.verify) {
      final client = MonosClient(monosSites[item.site]);
      try {
        final results = await client
            .catalog(1, search: item.searchTitle)
            .timeout(const Duration(seconds: 15));
        final guessed = Uri.parse(item.anime.url).path;
        MonosEntry? pick;
        for (final r in results) {
          if (Uri.parse(r.url).path == guessed) {
            pick = r;
            break;
          }
        }
        pick ??= results
            .where((r) => ProviderClient.key(r.title) == ProviderClient.key(item.searchTitle))
            .firstOrNull;
        pick ??= results.firstOrNull;
        if (pick != null) entry = pick;
      } catch (_) {
        // Si la búsqueda falla se intenta con la dirección supuesta.
      } finally {
        client.close();
      }
    }
    if (!mounted) return;
    openHit(_RankedHit.monos(entry, item.site));
  }

  /// Datos de AniList para una novedad de una fuente extra. La sinopsis en
  /// español sale de la ficha de la fuente; si no hay, se traduce la de AniList.
  /// Sinopsis en español leída de la ficha del anime en una fuente extra
  /// ('' si no se pudo).
  Future<String> spanishFromSite(int site, MonosEntry entry) async {
    final client = MonosClient(monosSites[site]);
    try {
      return await MonosSynopsis.load(client, entry)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return '';
    } finally {
      client.close();
    }
  }

  /// Igual que [extraInfo], pero entrega primero lo de AniList y después la
  /// sinopsis (la de la fuente, o la de AniList traducida).
  Stream<BannerInfo?> extraInfoStream(ExtraRecent item) async* {
    final siteFuture = spanishFromSite(item.site, item.anime);
    AniListInfo? meta;
    try {
      meta = await anilist.lookup(item.title);
    } catch (_) {}
    BannerInfo make(String synopsis) => BannerInfo(
      status: meta?.status ?? '',
      synopsis: synopsis,
      banner: meta?.banner ?? '',
      cover: meta?.cover ?? '',
      score: meta?.score,
      genres: meta?.genres ?? const [],
    );
    if (meta != null) yield make('');
    var synopsis = await siteFuture;
    if (synopsis.isEmpty) synopsis = await translator.toSpanish(meta?.description ?? '');
    if (meta != null || synopsis.isNotEmpty) yield make(synopsis);
  }

  Future<BannerInfo?> extraInfo(ExtraRecent item) async {
    try {
      final meta = await anilist.lookup(item.title);
      final fromSite = await spanishFromSite(item.site, item.anime);
      if (meta == null) {
        return fromSite.isEmpty ? null : BannerInfo(synopsis: fromSite);
      }
      return BannerInfo(
        status: meta.status,
        synopsis: fromSite.isNotEmpty
            ? fromSite
            : await translator.toSpanish(meta.description),
        banner: meta.banner,
        cover: meta.cover,
        score: meta.score,
        genres: meta.genres,
      );
    } catch (_) {
      return null;
    }
  }

  /// Igual que [bannerInfo], pero entrega primero lo de AniList (imagen, nota,
  /// géneros) y después la sinopsis, pidiendo ambas a la vez.
  Stream<BannerInfo?> bannerInfoStream(RecentEpisode item) async* {
    final sourceFuture = () async {
      try {
        final anime = await recent.animeFor(item);
        return (await api.detail(anime)).synopsis.trim();
      } catch (_) {
        return '';
      }
    }();
    AniListInfo? meta;
    try {
      meta = await anilist.lookup(item.title);
    } catch (_) {}
    BannerInfo make(String synopsis) => BannerInfo(
      status: meta?.status ?? '',
      synopsis: synopsis,
      banner: meta?.banner ?? '',
      cover: meta?.cover ?? '',
      score: meta?.score,
      genres: meta?.genres ?? const [],
    );
    if (meta != null) yield make('');
    var synopsis = await sourceFuture;
    if (synopsis.isEmpty) synopsis = await translator.toSpanish(meta?.description ?? '');
    if (meta != null || synopsis.isNotEmpty) yield make(synopsis);
  }

  /// Completa una diapositiva: nota, géneros, estado y arte horizontal vienen
  /// de AniList; la sinopsis, en español, de la propia fuente. Cada parte es
  /// opcional: si una falla, el banner se muestra con lo que haya.
  Future<BannerInfo?> bannerInfo(RecentEpisode item) async {
    Future<AniListInfo?> fromAniList() async {
      try {
        return await anilist.lookup(item.title);
      } catch (_) {
        return null;
      }
    }

    Future<String> fromSource() async {
      try {
        final anime = await recent.animeFor(item);
        return (await api.detail(anime)).synopsis.trim();
      } catch (_) {
        return '';
      }
    }

    final results = await Future.wait<Object?>([fromAniList(), fromSource()]);
    final meta = results[0] as AniListInfo?;
    final synopsis = results[1] as String;
    if (meta == null && synopsis.isEmpty) return null;
    return BannerInfo(
      status: meta?.status ?? '',
      synopsis: synopsis.isNotEmpty
          ? synopsis
          : await translator.toSpanish(meta?.description ?? ''),
      banner: meta?.banner ?? '',
      cover: meta?.cover ?? '',
      score: meta?.score,
      genres: meta?.genres ?? const [],
    );
  }

  Future<void> saveRecent(RecentEpisode item) async {
    try {
      final anime = await recent.animeFor(item);
      recentAnime[item.episodeUrl] = anime;
      library.toggle(anime);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar en Mi lista. Vuelve a intentarlo.'),
          ),
        );
      }
    }
  }

  Widget hero(Anime anime) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (anime.cover.isNotEmpty)
            Image.network(
              anime.cover,
              fit: BoxFit.cover,
              alignment: const Alignment(.3, -.4),
              errorBuilder: (_, _, _) => Container(color: surface),
            ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xff10131e),
                  Color(0xe610131e),
                  Color(0x6610131e),
                ],
                stops: [0, .46, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: c.maxWidth * .86,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        anime.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${animeForSource(anime, filter).provider}${anime.alternatives.isNotEmpty ? ' + más fuentes' : ''}  ·  ${anime.badge.isEmpty ? 'Anime' : anime.badge}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 25),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: () => open(anime),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Ver episodios'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => library.toggle(anime),
                            icon: Icon(
                              library.favorites.containsKey(anime.url)
                                  ? Icons.check
                                  : Icons.add,
                            ),
                            label: Text(
                              library.favorites.containsKey(anime.url)
                                  ? 'En mi lista'
                                  : 'Mi lista',
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 12,
                              ),
                              foregroundColor: ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget rail(String title, List<Anime> items, {bool removable = false}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => section = 1),
              child: const Text('Ver catálogo  →'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 252,
          child: ScrollConfiguration(
            behavior: const MaterialScrollBehavior().copyWith(
              scrollbars: true,
              dragDevices: {
                PointerDeviceKind.mouse,
                PointerDeviceKind.touch,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(
                width: 146,
                child: poster(items[i], removable: removable),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget poster(Anime anime, {bool removable = false}) => AnimePoster(
    anime: animeForSource(anime, filter),
    onRemoveHistory: removable ? () => library.removeHistory(anime) : null,
    favorite: library.favorites.containsKey(anime.url),
    onTap: () => open(anime),
    onFavorite: () => library.toggle(anime),
  );
  Future<void> malConnect() async {
    setState(() => malBusy = true);
    try {
      await mal.login();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo conectar con MAL: $e')),
        );
      }
    }
    if (mounted) setState(() => malBusy = false);
  }

  Widget malTile() {
    if (!mal.configured) {
      return const ListTile(
        leading: Icon(Icons.link_off_rounded, color: accent),
        title: Text('MyAnimeList'),
        subtitle: Text('Falta configurar el Client ID en mal_client.dart.'),
      );
    }
    if (!mal.connected) {
      return ListTile(
        leading: const Icon(Icons.account_circle_outlined, color: accent),
        title: const Text('Conectar con MyAnimeList'),
        subtitle: Text(
          malBusy
              ? 'Autoriza en el navegador y vuelve a Neko…'
              : 'Inicia sesión con tu cuenta de MAL para ver tu lista aquí. '
                    'Neko no ve tu contraseña y los datos quedan solo en este equipo.',
        ),
        trailing: FilledButton(
          onPressed: malBusy ? null : malConnect,
          child: Text(malBusy ? 'Esperando…' : 'Conectar'),
        ),
      );
    }
    return Column(children: [
      ListTile(
      leading: const Icon(Icons.verified_user_outlined, color: accent),
      title: Text(mal.name.isEmpty ? 'Cuenta de MAL' : mal.name),
      subtitle: const Text('Cuenta de MyAnimeList conectada'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => showMalList(context, mal, (title) {
              search.text = title;
              query = title;
              setState(() => section = 1);
              load();
            }),
            child: const Text('Ver mi lista'),
          ),
          TextButton(
            onPressed: () async {
              await mal.logout();
              if (mounted) setState(() {});
            },
            child: const Text('Desconectar'),
          ),
        ],
      ),
    ),
      SwitchListTile(
        title: const Text('Marcar episodios vistos automáticamente'),
        subtitle: const Text(
          'Al pasar el 80% de un episodio se actualiza tu lista de MAL. '
          'Nunca baja el contador ni toca animes ya completados.',
        ),
        value: mal.autoSync,
        onChanged: (value) {
          setState(() => mal.autoSync = value);
          mal.saveSettings();
        },
      ),
    ]);
  }

  Widget settings() => SingleChildScrollView(
    padding: const EdgeInsets.all(36),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ajustes',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 28),
        const ListTile(
          leading: Icon(Icons.palette_outlined, color: accent),
          title: Text('La identidad de Neko'),
          subtitle: Text(
            'Tema oscuro con acento violeta. Diseñado para teclado y ratón.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.storage_rounded, color: accent),
          title: Text('Biblioteca local'),
          subtitle: Text(
            'Tu lista y el progreso se guardan en este equipo. No necesitas una cuenta.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.dns_outlined, color: accent),
          title: Text('Fuentes de contenido'),
          subtitle: Text(
            'TioAnime, AnimeFLV y AnimeAV1. La disponibilidad y calidad dependen de cada servidor.',
          ),
        ),
        for (final provider in ['TioAnime', 'AnimeFLV', 'AnimeAV1', 'JKAnime'])
          SwitchListTile(
            title: Text(provider),
            subtitle: Text(
              provider == 'JKAnime'
                  ? 'Respaldo opcional'
                  : provider == 'AnimeFLV'
                  ? 'animeflv.or.at'
                  : provider == 'TioAnime'
                  ? 'tioanime.com'
                  : 'animeav1.com',
            ),
            value: api.enabledProviders.contains(provider),
            onChanged: (enabled) {
              if (!enabled && api.enabledProviders.length == 1) return;
              setState(() {
                if (enabled) {
                  api.enabledProviders.add(provider);
                } else {
                  api.enabledProviders.remove(provider);
                  if (filter == provider) filter = 'Todas';
                }
                library.enabledSources
                  ..clear()
                  ..addAll(api.enabledProviders);
              });
              library.save();
              load();
              recent.bySource.removeWhere(
                (source, _) => !api.enabledProviders.contains(source),
              );
              refreshRecent();
            },
          ),
        for (final i in switchableMonosSiteIndexes)
          SwitchListTile(
            title: Text(monosSites[i].label),
            subtitle: Text(Uri.parse(monosSites[i].base).host),
            value: !userDisabledMonosLabels.contains(monosSites[i].label),
            onChanged: (enabled) {
              final label = monosSites[i].label;
              setState(() {
                if (enabled) {
                  userDisabledMonosLabels.remove(label);
                } else {
                  userDisabledMonosLabels.add(label);
                  selectedMonos = null;
                }
              });
              library.save();
            },
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Traducir sinopsis al español'),
          subtitle: const Text(
            'Las sinopsis que solo existen en inglés se traducen automáticamente '
            '(usa un traductor en línea gratuito).',
          ),
          value: translator.enabled,
          onChanged: (value) {
            setState(() => translator.enabled = value);
            translator.setEnabled(value);
          },
        ),
        const SizedBox(height: 28),
        const Text(
          'MyAnimeList',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        malTile(),
        const SizedBox(height: 28),
        const Text('AniList', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        AniListAccountTile(onSearch: (title) {
          search.text = title;
          query = title;
          setState(() => section = 1);
          load();
        }),
        const SizedBox(height: 28),
        const Text(
          'Acerca de Neko Anime 0.3.1 Stable',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded, color: accent),
            title: const Text('Acerca de'),
            subtitle: const Text(
              'Desarrollador, créditos, API, enlaces y licencias',
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 18),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const NekoAboutPage())),
          ),
        ),
        const SizedBox(height: 12),

      ],
    ),
  );
}

class AnimePoster extends StatefulWidget {
  final String? sourceLabel;
  final Anime anime;
  final bool favorite;
  final bool showFavorite;
  final VoidCallback onTap, onFavorite;
  final VoidCallback? onRemoveHistory;
  const AnimePoster({
    super.key,
    required this.anime,
    this.sourceLabel,
    required this.favorite,
    this.showFavorite = true,
    required this.onTap,
    required this.onFavorite,
    this.onRemoveHistory,
  });
  @override
  State<AnimePoster> createState() => _PosterState();
}

class _PosterState extends State<AnimePoster> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    cursor: SystemMouseCursors.click,
    child: InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: hover ? accent : border, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Cover(widget.anime.cover, thumbnail: true),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x33000000),
                          Colors.transparent,
                          Color(0xcc090c13),
                        ],
                        stops: [0, .5, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 9,
                    bottom: 9,
                    child: sourceBadge(
                      widget.sourceLabel ?? widget.anime.provider,
                    ),
                  ),
                  if (widget.onRemoveHistory != null)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: IconButton.filledTonal(
                        tooltip: 'Quitar de Seguir viendo',
                        onPressed: widget.onRemoveHistory,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
                  if (widget.showFavorite)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton(
                        tooltip: widget.favorite
                            ? 'Quitar de mi lista'
                            : 'Guardar en mi lista',
                        onPressed: widget.onFavorite,
                        icon: Icon(
                          widget.favorite
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: widget.favorite ? accent : Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  if (hover)
                    const Center(
                      child: CircleAvatar(
                        backgroundColor: accent,
                        foregroundColor: background,
                        child: Icon(Icons.play_arrow_rounded),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.anime.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.anime.badge.isEmpty ? 'Anime' : widget.anime.badge,
            style: const TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ),
    ),
  );
}

class Cover extends StatelessWidget {
  final String url;
  final bool thumbnail;
  const Cover(this.url, {super.key, this.thumbnail=false});
  @override
  Widget build(BuildContext context) => url.isEmpty
      ? const ColoredBox(
          color: elevated,
          child: Icon(Icons.movie_outlined, color: muted),
        )
      : LayoutBuilder(builder:(context,constraints)=> Image.network(
          url,
          cacheWidth: thumbnail && constraints.hasBoundedWidth
              ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1,2048)
              : null,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: elevated,
            child: Icon(Icons.movie_outlined, color: muted),
          ),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : const ColoredBox(color: elevated),
        ));
}

Widget tag(String text, {bool small = false}) => Container(
  padding: EdgeInsets.symmetric(
    horizontal: small ? 7 : 10,
    vertical: small ? 4 : 6,
  ),
  decoration: BoxDecoration(
    color: const Color(0xcc191328),
    borderRadius: BorderRadius.circular(7),
    border: Border.all(color: accent.withValues(alpha: .25)),
  ),
  child: Text(
    text,
    style: TextStyle(
      fontSize: small ? 9 : 10,
      color: accent,
      fontWeight: FontWeight.w700,
      letterSpacing: small ? 0 : 1.4,
    ),
  ),
);
Widget notice(String text, VoidCallback retry) => Container(
  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
  decoration: BoxDecoration(
    color: surface,
    border: Border.all(color: border),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      const Icon(Icons.info_outline, color: accent, size: 18),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text, style: const TextStyle(color: muted, fontSize: 12)),
      ),
      TextButton(onPressed: retry, child: const Text('Reintentar')),
    ],
  ),
);
String cleanError(Object error) => error.toString().replaceFirst(
  RegExp(r'^(Exception|FormatException|HttpException|SocketException):\s*'),
  '',
);

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final VoidCallback? action;
  final String actionText;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.actionText = 'Reintentar',
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: accent),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, height: 1.7),
            ),
            if (action != null) ...[
              const SizedBox(height: 22),
              FilledButton(onPressed: action, child: Text(actionText)),
            ],
          ],
        ),
      ),
    ),
  );
}

class DetailPage extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onClose;
  final String initialSource;
  final Anime anime;
  final ProviderClient api;
  final Library library;
  const DetailPage({
    super.key,
    required this.anime,
    this.initialSource = 'Todas',
    this.embedded = false,
    this.onClose,
    required this.api,
    required this.library,
  });
  @override
  State<DetailPage> createState() => _DetailState();
}

class _DetailState extends State<DetailPage> {
  Detail? data;
  String? error;
  bool busy = true;
  late Anime selected;
  final episodeSearch = TextEditingController();
  @override
  void initState() {
    super.initState();
    selected = animeForSource(widget.anime, widget.initialSource);
    load();
  }

  @override
  void dispose() {
    episodeSearch.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.detail(selected);
      if (mounted) setState(() => data = result);
    } catch (e) {
      if (mounted) setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void play(Episode episode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaybackPage(
          detail: data!,
          episode: episode,
          api: widget.api,
          library: widget.library,
        ),
      ),
    );
  }

  Widget panel() => AnimeDetailPanel(
    title: selected.title,
    cover: selected.cover,
    source: selected.provider,
    synopsis: data?.synopsis ?? '',
    loading: busy,
    error: error,
    onRetry: load,
    onClose: widget.onClose,
    saved: widget.library.favorites.containsKey(widget.anime.url),
    onSave: () {
      widget.library.toggle(widget.anime);
      setState(() {});
    },
    onPlay: data == null || data!.episodes.isEmpty
        ? null
        : () => play(data!.episodes.first),
    episodes: [
      for (final e in data?.episodes ?? <Episode>[])
        PanelEpisode(
          number: e.number,
          resume: widget.library.resume(e) > 0,
          onTap: () => play(e),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return panel();
    final choices = [widget.anime.url, ...widget.anime.alternatives];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: background,
        title: Text(selected.title, style: const TextStyle(fontSize: 16)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Estado de seguimiento',
            initialValue: widget.library.statusFor(widget.anime),
            onSelected: (status) {
              widget.library.setStatus(
                widget.anime,
                status == 'Quitar seguimiento' ? null : status,
              );
              setState(() {});
            },
            itemBuilder: (_) => [...Library.statuses, 'Quitar seguimiento']
                .map(
                  (status) => CheckedPopupMenuItem(
                    value: status,
                    checked: widget.library.statusFor(widget.anime) == status,
                    child: Text(status),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.playlist_add_check_rounded, color: accent),
                  const SizedBox(width: 8),
                  Text(widget.library.statusFor(widget.anime) ?? 'Seguimiento'),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Mi lista',
            onPressed: () {
              widget.library.toggle(widget.anime);
              setState(() {});
            },
            icon: Icon(
              widget.library.favorites.containsKey(widget.anime.url)
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color: accent,
            ),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? EmptyState(
              icon: Icons.cloud_off,
              title: 'No se pudo abrir el anime',
              message: error!,
              action: load,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          width: 152,
                          height: 228,
                          child: Cover(selected.cover),
                        ),
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            tag(selected.provider.toUpperCase()),
                            const SizedBox(height: 18),
                            Text(
                              selected.title,
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              data!.synopsis.isEmpty
                                  ? 'Sin sinopsis disponible.'
                                  : data!.synopsis,
                              style: const TextStyle(color: muted, height: 1.8),
                              maxLines: 7,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 22),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                if (data!.episodes.isNotEmpty)
                                  FilledButton.icon(
                                    onPressed: () => play(data!.episodes.first),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Comenzar a ver'),
                                  ),
                                if (choices.length > 1)
                                  DropdownButton<String>(
                                    value: selected.url,
                                    items: choices
                                        .map(
                                          (url) => DropdownMenuItem(
                                            value: url,
                                            child: Text(providerForUrl(url)),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (url) {
                                      if (url == null) return;
                                      selected = Anime(
                                        widget.anime.title,
                                        url,
                                        widget.anime.cover,
                                      );
                                      load();
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 38),
                  Row(
                    children: [
                      Text(
                        'Episodios · ${data!.episodes.length}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 190,
                        child: TextField(
                          controller: episodeSearch,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Buscar episodio',
                            prefixIcon: Icon(Icons.search, size: 18),
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (data!.episodes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Text(
                        'Este anime todavía no tiene episodios disponibles.',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  LayoutBuilder(
                    builder: (context, c) {
                      final episodes = data!.episodes
                          .where(
                            (e) =>
                                episodeSearch.text.isEmpty ||
                                e.number.contains(episodeSearch.text.trim()),
                          )
                          .toList();
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: (c.maxWidth / 175).floor().clamp(
                            2,
                            8,
                          ),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 90,
                        ),
                        itemCount: episodes.length,
                        itemBuilder: (_, i) {
                          final episode = episodes[i];
                          final resume = widget.library.resume(episode);
                          return OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.all(16),
                              side: BorderSide(
                                color: resume > 0 ? accent : border,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            onPressed: () => play(episode),
                            child: Row(
                              children: [
                                Icon(
                                  resume > 0
                                      ? Icons.play_circle_fill
                                      : Icons.play_circle_outline,
                                  color: accent,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Episodio ${episode.number}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: ink,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        resume > 0
                                            ? 'Continuar · ${resume ~/ 60} min'
                                            : 'Ver servidores',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class PlaybackPage extends StatefulWidget {
  final Detail detail;
  final Episode episode;
  final ProviderClient api;
  final Library library;
  final String? sourceLabel;
  const PlaybackPage({
    super.key,
    required this.detail,
    required this.episode,
    required this.api,
    required this.library,
    this.sourceLabel,
  });
  @override
  State<PlaybackPage> createState() => _PlaybackState();
}

class _PlaybackState extends State<PlaybackPage> {
  final Map<int,StreamSource> resolvedSources = {};
  StreamSource? currentSource;
  final Map<int,double> serverSpeeds = {};
  late final Player player;
  late final VideoController controller;
  late Episode episode;
  List<Server> servers = [];
  int selected = 0, request = 0;
  bool loading = true;
  String? error;
  Timer? saveTimer;
  StreamSubscription<String>? errors;
  // Calidades: solo se muestran si el video las ofrece (p. ej. listas HLS).
  StreamSubscription<Tracks>? tracksSub;
  List<VideoTrack> qualities = [];
  String qualityId = 'auto';
  final health = PlaybackHealth();
  Timer? healthTimer;
  bool mediaOpened = false, checkingHealth = false, nativeFailure = false;
  Future<void> checkHealth() async {
    if (!mounted || !mediaOpened || loading || checkingHealth) return;
    checkingHealth = true;
    final id = request;
    try {
      bool idle = false;
      bool paused = false;
      final native = player.platform;
      if (native is NativePlayer) {
        idle = await native.getProperty('idle-active') == 'yes';
        paused = await native.getProperty('pause') == 'yes';
      }
      if (!mounted || id != request || !mediaOpened) return;
      final failed = health.sample(
        now: DateTime.now(),
        currentPosition: player.state.position,
        currentDuration: player.state.duration,
        completed: player.state.completed,
        idle: idle,
        paused: paused,
      );
      if (failed && !nativeFailure) {
        setState(() {
          nativeFailure = true;
          error = health.hasProgress
              ? 'La reproducción se interrumpió. Puedes reintentar desde donde quedó.'
              : 'El servidor no empezó a reproducir el episodio. Puedes reintentar.';
        });
      } else if (!failed && nativeFailure) {
        setState(() {
          nativeFailure = false;
          error = null;
        });
      }
    } catch (_) {
      // A snapshot can race a server change or widget disposal; retry next tick.
    } finally {
      checkingHealth = false;
    }
  }

  @override
  void initState() {
    super.initState();
    episode = widget.episode;
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'Neko Anime 0.3.1 Stable',
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    controller = VideoController(player);
    errors = player.stream.error.listen((message) {
      if (mounted && mediaOpened) health.note(message);
    });
    tracksSub = player.stream.tracks.listen((tracks) {
      if (!mounted) return;
      final list = tracks.video
          .where((t) => t.id != 'auto' && t.id != 'no')
          .toList();
      setState(() => qualities = list);
    });
    healthTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => checkHealth(),
    );
    saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => save(notify: false),
    );
    loadEpisode();
  }

  void save({bool notify = true}) {
    widget.library.record(
      widget.detail.anime,
      episode,
      player.state.position,
      player.state.duration,
      notify: notify,
    );
    // Al pasar el 80% del episodio se marca como visto en MyAnimeList.
    malSync?.onProgress(
      widget.detail.anime,
      episode,
      player.state.position,
      player.state.duration,
    );
  }
  @override
  void dispose() {
    save();
    saveTimer?.cancel();
    healthTimer?.cancel();
    mediaOpened = false;
    ++request;
    errors?.cancel();
    tracksSub?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> loadEpisode() async {
    final id = ++request;
    mediaOpened = false;
    nativeFailure = false;
    health.reset(DateTime.now());
    setState(() {
      loading = true;
      error = null;
      servers = [];
      resolvedSources.clear(); serverSpeeds.clear(); currentSource=null;
    });
    try {
      final list = await widget.api.servers(episode);
      if (!mounted || id != request) return;
      setState(() {
        servers = list;
        selected = 0;
      });
      final ranked = await ServerSelector.rank([
        for(var i=0;i<list.length;i++) () async {
          final source=await widget.api.resolve(list[i],episode);
          if(mounted && id==request) resolvedSources[i]=source;
          return MediaSource(list[i].name,source.url,{
            'User-Agent':userAgent, if(source.referer.isNotEmpty) 'Referer':source.referer,
            if(source.cookies.isNotEmpty) 'Cookie':source.cookies,
          });
        },
      ],cancelled:()=>!mounted || id!=request);
      if(!mounted || id!=request) return;
      if(ranked.isEmpty) throw const FormatException('No hay servidores disponibles.');
      for(final measurement in ranked) {serverSpeeds[measurement.index]=measurement.bytesPerSecond;}
      await openServer(ranked.first.index);
    } catch (e) {
      if (mounted && id == request) {
        setState(() {
          loading = false;
          error = cleanError(e);
        });
      }
    }
  }

  Future<void> openServer(int index) async {
    final id = ++request;
    final resume = player.state.position.inSeconds > 5
        ? player.state.position.inSeconds
        : health.position.inSeconds > 5
        ? health.position.inSeconds
        : widget.library.resume(episode);
    mediaOpened = false;
    nativeFailure = false;
    health.reset(DateTime.now());
    setState(() {
      selected = index;
      loading = true;
      error = null;
      qualities = [];
      qualityId = 'auto';
    });
    try {
      // stop() y la resolución del enlace son independientes: van en paralelo.
      final stopping = player.stop();
      final StreamSource source;
      try {
        source = resolvedSources[index] ?? await widget.api.resolve(servers[index], episode);
      } finally {
        await stopping.catchError((_) {});
      }
      if (!mounted || id != request) return;
      currentSource=source;
      await configurePlayback(player);
      if (!mounted || id != request) return;
      await player.open(
        Media(
          source.url,
          httpHeaders: {
            'User-Agent': userAgent,
            'Referer': source.referer,
            if (source.cookies.isNotEmpty) 'Cookie': source.cookies,
          },
        ),
      );
      if (resume > 0) {
        // Con streams de red, buscar antes de conocer la duración suele fallar.
        try {
          await player.stream.duration
              .firstWhere((d) => d > Duration.zero)
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
        if (!mounted || id != request) return;
        await player.seek(Duration(seconds: resume));
      }
      if (mounted && id == request) {
        health.reset(DateTime.now());
        mediaOpened = true;
        setState(() => loading = false);
      }
    } catch (e) {
      if (mounted && id == request) {
        setState(() {
          loading = false;
          error = cleanError(e);
        });
      }
    }
  }

  String qualityLabel(VideoTrack t, int index) {
    if ((t.h ?? 0) > 0) return '${t.h}p';
    if ((t.bitrate ?? 0) > 0) return '${(t.bitrate! / 1000).round()} kbps';
    return 'Opción ${index + 1}';
  }

  Future<void> setQuality(VideoTrack track) async {
    await player.setVideoTrack(track);
    if (mounted) setState(() => qualityId = track.id);
  }

  Widget qualityButton() => PopupMenuButton<VideoTrack>(
    key: const ValueKey('quality-menu'),
    tooltip: 'Calidad',
    color: elevated,
    icon: const Icon(Icons.high_quality_rounded, color: ink),
    onSelected: setQuality,
    itemBuilder: (_) => [
      CheckedPopupMenuItem(
        value: VideoTrack.auto(),
        checked: qualityId == 'auto',
        child: const Text('Automática'),
      ),
      for (final entry in qualities.indexed)
        CheckedPopupMenuItem(
          value: entry.$2,
          checked: qualityId == entry.$2.id,
          child: Text(qualityLabel(entry.$2, entry.$1)),
        ),
    ],
  );

  Future<void> next() async {
    final index = widget.detail.episodes.indexWhere(
      (e) => e.url == episode.url,
    );
    if (index >= 0 && index + 1 < widget.detail.episodes.length) {
      save();
      ++request;
      await player.stop();
      if (!mounted) return;
      setState(() => episode = widget.detail.episodes[index + 1]);
      loadEpisode();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: background,
      automaticallyImplyLeading: false,
      toolbarHeight: 68,
      titleSpacing: 8,
      leadingWidth: 112,
      leading: TextButton.icon(
        key: const ValueKey('player-back'),
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Volver'),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.detail.anime.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          Text(
            'Episodio ${episode.number} · ${widget.sourceLabel ?? widget.detail.anime.provider}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
      actions: [
        DownloadButton(title:'${widget.detail.anime.title} - Episodio ${episode.number}',
          source:loading || currentSource==null ? null : () async {
            final source=currentSource!;
            return MediaSource(servers[selected].name,source.url,{
              'User-Agent':userAgent, if(source.referer.isNotEmpty) 'Referer':source.referer,
              if(source.cookies.isNotEmpty) 'Cookie':source.cookies,
            });
          }),
        if (servers.isNotEmpty)
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 700 ? 125 : 210,
            child: DropdownButton<int>(
              isExpanded: true,
              value: selected,
              underline: const SizedBox.shrink(),
              items: servers.indexed
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.$1,
                      child: Text(
                        s.$2.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: loading
                  ? null
                  : (index) {
                      if (index != null) openServer(index);
                    },
            ),
          ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'Siguiente episodio',
          onPressed: widget.detail.episodes.last.url == episode.url
              ? null
              : next,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: Stack(
      children: [
        Positioned.fill(
          child: Video(
            controller: controller,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            controls: (videoState) {
              final theme = MaterialDesktopVideoControlsThemeData(
                buttonBarButtonColor: ink,
                seekBarColor: const Color(0x33FFFFFF),
                seekBarHoverColor: const Color(0x33FFFFFF),
                seekBarBufferColor: accent.withValues(alpha: .28),
                seekBarPositionColor: accent,
                seekBarThumbColor: accent,
                volumeBarColor: const Color(0x33FFFFFF),
                volumeBarActiveColor: accent,
                volumeBarThumbColor: accent,
                // Un solo indicador de carga: mientras la pantalla muestra el
                // suyo, el del reproductor se oculta; luego usa el color de Neko.
                bufferingIndicatorBuilder: (_) => loading
                    ? const SizedBox.shrink()
                    : const CircularProgressIndicator(color: accent),
                bottomButtonBar: [
                  const MaterialDesktopPlayOrPauseButton(),
                  const MaterialDesktopVolumeButton(),
                  const MaterialDesktopPositionIndicator(),
                  const Spacer(),
                  if (qualities.length > 1) qualityButton(),
                  const MaterialDesktopFullscreenButton(),
                ],
                topButtonBar: [
                  Builder(
                    builder: (videoContext) => FilledButton.tonalIcon(
                      key: const ValueKey('video-back'),
                      onPressed: () async {
                        if (isFullscreen(videoContext)) {
                          await exitFullscreen(videoContext);
                        }
                        if (context.mounted) Navigator.of(context).maybePop();
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Volver al anime'),
                    ),
                  ),
                ],
              );
              return MaterialDesktopVideoControlsTheme(
                normal: theme,
                fullscreen: theme,
                child: MaterialDesktopVideoControls(videoState),
              );
            },
          ),
        ),
        if (loading)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: accent),
                SizedBox(height: 18),
                Text(
                  'Conectando con el servidor…',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        if (error != null)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xe6090c13),
              child: EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Probemos otra opción',
                message: error!,
                action: servers.isNotEmpty
                    ? () => openServer(selected)
                    : loadEpisode,
                actionText: 'Reintentar este servidor',
              ),
            ),
          ),
      ],
    ),
  );
}
