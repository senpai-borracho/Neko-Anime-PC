// Novedades (últimos episodios) de las fuentes extra, para el banner del Inicio.
//
// Solo lee la portada de cada sitio como texto (nunca ejecuta JavaScript).
// Compatibles: OtakusTV, AnimeYT, AnimeYTX (plantilla article.li), LatAnime
// ("Añadidos recientemente") y MonosChinos1 ("últimos capítulos").
import 'package:html/parser.dart' as html;

import 'monoschinos_client.dart';
import 'monoschinos_sources.dart';

/// Tipos de fuente (MonosSite.kind) cuyas novedades sabemos leer.
const extraRecentKinds = {'otakustv', 'animeyt', 'animeytx', 'latanime', 'monos'};

/// ¿Sabemos leer las novedades de la fuente [site] (índice en monosSites)?
/// De la plantilla de MonosChinos solo se usa MonosChinos1 (la 2 está apagada).
bool extraRecentSupported(int site) {
  if (site < 0 || site >= monosSites.length) return false;
  final kind = monosSites[site].kind;
  if (kind == 'monos') return site == 0;
  return extraRecentKinds.contains(kind);
}

class ExtraRecent {
  /// Nombre de la fuente (por ejemplo "OtakusTV") y su índice en monosSites.
  final String label;
  final int site;
  final String title, number, cover, episodeUrl;

  /// Dato extra, como el idioma ("Latino", "Castellano"). Puede ir vacío.
  final String note;

  /// Ficha del anime (no del episodio), lista para abrirse en esa fuente.
  final MonosEntry anime;

  /// true si la dirección de la ficha es una suposición (LatAnime): antes de
  /// abrirla se confirma buscando [searchTitle] en la propia fuente.
  final bool verify;
  final String searchTitle;
  const ExtraRecent({
    required this.label,
    required this.site,
    required this.title,
    required this.number,
    required this.cover,
    required this.episodeUrl,
    required this.anime,
    this.note = '',
    this.verify = false,
    this.searchTitle = '',
  });
}

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Slug del anime según la imagen ("/portada/slug.webp", "/anime/slug.webp").
String _slugFromImage(String cover) =>
    RegExp(r'/(?:portada|anime)/([^/.?]+)\.(?:webp|jpe?g|png)')
        .firstMatch(cover)?[1] ??
    '';

Future<List<ExtraRecent>> fetchExtraRecents(MonosClient client, int site) async {
  final info = monosSites[site];
  if (!extraRecentKinds.contains(info.kind)) return const [];
  final base = '${info.base}/';
  final doc = html.parse(await client.get(base));
  final result = <ExtraRecent>[];
  final seen = <String>{};

  void add({
    required String link,
    required String title,
    required String number,
    required String cover,
    required String slug,
    String note = '',
    bool verify = false,
  }) {
    if (title.length < 2 || number.isEmpty || slug.isEmpty || !seen.add(link)) {
      return;
    }
    result.add(
      ExtraRecent(
        label: info.label,
        site: site,
        title: title,
        number: number,
        cover: cover,
        episodeUrl: link,
        note: note,
        verify: verify,
        searchTitle: title,
        anime: MonosEntry(title, '${info.base}/anime/$slug', cover),
      ),
    );
  }

  if (info.kind == 'latanime') {
    // Tarjetas <a href=".../ver/slug-episodio-N"> con <h2>Episodio N - Título Latino</h2>.
    for (final a in doc.querySelectorAll('a[href*="/ver/"]')) {
      final link = client.absolute(a.attributes['href'] ?? '', base);
      final slugMatch = RegExp(r'^/ver/(.+)-episodio-(\d+)$')
          .firstMatch(link.isEmpty ? '' : Uri.parse(link).path);
      final heading = a.querySelector('h2');
      if (slugMatch == null || heading == null) continue;
      final parts = RegExp(r'^Episodio\s+(\d+)\s*-\s*(.+)$')
          .firstMatch(_clean(heading.text));
      var title = parts?[2] ?? '';
      // El idioma viene pegado al título: "Psyren Latino", "Tank Chair Castellano".
      final language = RegExp(
        r'\s+(Latino|Castellano|Español|Subtitulado)$',
        caseSensitive: false,
      ).firstMatch(title);
      title = title.replaceFirst(language?[0] ?? '\u0000', '').trim();
      add(
        link: link,
        title: title,
        number: parts?[1] ?? slugMatch[2]!,
        cover: client.imageOf(a, base),
        slug: slugMatch[1]!,
        note: language?[1] ?? '',
        // El slug del anime se deduce del episodio: se confirma al abrir.
        verify: true,
      );
      if (result.length >= 12) break;
    }
    return result;
  }

  if (info.kind == 'monos') {
    // <li><article><a href=".../ver/slug-episodio-N"> ... <span class="episode">N</span> ... <h2>Título</h2>
    for (final item in doc.querySelectorAll('li article')) {
      final a = item.querySelector('a[href]');
      if (a == null) continue;
      final link = client.absolute(a.attributes['href'] ?? '', base);
      final slugMatch = RegExp(r'^/ver/(.+)-episodio-(\d+)$')
          .firstMatch(link.isEmpty ? '' : Uri.parse(link).path);
      if (slugMatch == null) continue;
      final cover = client.imageOf(item, base);
      add(
        link: link,
        title: _clean(item.querySelector('h2')?.text ?? ''),
        number: RegExp(r'\d+').firstMatch(item.querySelector('.episode')?.text ?? '')?[0] ??
            slugMatch[2]!,
        cover: cover,
        slug: _slugFromImage(cover).isNotEmpty ? _slugFromImage(cover) : slugMatch[1]!,
      );
      if (result.length >= 12) break;
    }
    return result;
  }

  // Plantilla OtakusTV / AnimeYT / AnimeYTX: tarjetas article.li.
  for (final item in doc.querySelectorAll('article.li')) {
    final a = item.querySelector('a[href]');
    if (a == null) continue;
    final link = client.absolute(a.attributes['href'] ?? '', base);
    if (link.isEmpty) continue;
    final path = Uri.parse(link).path;
    // Solo tarjetas de EPISODIO: /ver/slug-N (OtakusTV, AnimeYTX) o
    // /anime/slug-episodio-N (AnimeYT). Las tarjetas de anime se ignoran.
    final isEpisode = info.kind == 'animeyt'
        ? RegExp(r'^/anime/.+-episodio-\d+$').hasMatch(path)
        : RegExp(r'^/ver/.+-\d+$').hasMatch(path);
    if (!isEpisode) continue;
    final title = _clean(
      item.querySelector('h3 a')?.text ??
          item.querySelector('.n')?.text ??
          item.querySelector('img')?.attributes['alt'] ??
          '',
    ).replaceFirst(RegExp(r'\s+episodio\s+\d+$', caseSensitive: false), '');
    final number = RegExp(r'\d+').firstMatch(
          item.querySelector('.e')?.text ?? item.querySelector('u')?.text ?? '',
        )?[0] ??
        RegExp(r'(\d+)$').firstMatch(path)?[1] ??
        '';
    final cover = client.imageOf(item, base);
    var slug = _slugFromImage(cover);
    if (slug.isEmpty) {
      slug = path
          .split('/')
          .last
          .replaceFirst(RegExp(r'-episodio-\d+$'), '')
          .replaceFirst(RegExp(r'-\d+$'), '');
    }
    add(link: link, title: title, number: number, cover: cover, slug: slug);
    if (result.length >= 12) break;
  }
  return result;
}
