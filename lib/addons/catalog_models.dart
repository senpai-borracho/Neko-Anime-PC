import '../catalog.dart' show Episode;
import 'stremio_ref.dart';

class SourceRef {
  final int site;
  final String url, title, cover;
  const SourceRef(this.site, this.url, this.title, this.cover);
  String get label => StremioRef.parse(url)?.name ?? '';
}

class Series {
  final String title, cover;
  final List<SourceRef> refs;
  const Series(this.title, this.cover, this.refs);
}

class BrowseResult {
  final List<Series> items;
  final bool more;
  const BrowseResult(this.items, this.more);
}

class SeriesDetail {
  final Series series;
  final SourceRef ref;
  final String synopsis;
  final List<Episode> episodes;
  const SeriesDetail(this.series, this.ref, this.synopsis, this.episodes);
}
