import 'package:flutter/material.dart';

import '../main.dart' show accent, muted;
import '../app_ui.dart';
import 'plugin_models.dart';
import 'nuvio_runtime.dart';
import 'addon_player.dart';
import 'spanish_policy.dart';

class NuvioPage extends StatefulWidget {
  final InstalledPlugin plugin;
  const NuvioPage({super.key, required this.plugin});
  @override
  State<NuvioPage> createState() => _NuvioPageState();
}

class _NuvioPageState extends State<NuvioPage> {
  final id = TextEditingController(),
      season = TextEditingController(text: '1'),
      episode = TextEditingController(text: '1');
  String type = 'tv';
  bool busy = false;
  List<AddonVideo> streams = [];
  @override
  void dispose() {
    id.dispose();
    season.dispose();
    episode.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (int.tryParse(id.text.trim()) == null ||
        (type == 'tv' &&
            ((int.tryParse(season.text) ?? 0) < 1 ||
                (int.tryParse(episode.text) ?? 0) < 1))) {
      showCompactNotice(
        context,
        'Introduce el ID numérico de TMDB y un episodio válido.',
      );
      return;
    }
    setState(() {
      busy = true;
      streams = [];
    });
    try {
      final results = await NuvioRuntime.run(
        widget.plugin.file,
        id.text.trim(),
        type,
        type == 'tv' ? int.parse(season.text) : null,
        type == 'tv' ? int.parse(episode.text) : null,
      );
      final values = <AddonVideo>[];
      for (final result in results) {
        if (!SpanishPolicy.allows(
          result,
          trustedSpanish: SpanishPolicy.onlySpanish(widget.plugin.info.langs),
        )) {
          continue;
        }
        final url = Uri.tryParse('${result['url'] ?? ''}');
        if (url == null || !['http', 'https'].contains(url.scheme)) continue;
        final headers = <String, String>{};
        if (result['headers'] is Map) {
          (result['headers'] as Map).forEach(
            (k, v) => headers['$k'.toLowerCase()] = '$v',
          );
        }
        values.add(
          AddonVideo(
            '${result['title'] ?? result['name'] ?? 'Enlace'}',
            url.toString(),
            headers,
            SpanishPolicy.subtitles(result),
          ),
        );
      }
      if (mounted) {
        setState(() => streams = values);
        if (values.isEmpty) {
          showCompactNotice(
            context,
            'El complemento no devolvió enlaces con español identificado.',
          );
        }
      }
    } catch (e) {
      if (mounted) showCompactNotice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.plugin.info.name)),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          'Los scripts Nuvio buscan enlaces usando el ID de TMDB. No proporcionan un catálogo propio.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'tv', child: Text('Serie')),
                  DropdownMenuItem(value: 'movie', child: Text('Película')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => type = v);
                },
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: id,
                decoration: const InputDecoration(labelText: 'ID de TMDB'),
              ),
            ),
            if (type == 'tv') ...[
              SizedBox(
                width: 130,
                child: TextField(
                  controller: season,
                  decoration: const InputDecoration(labelText: 'Temporada'),
                ),
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: episode,
                  decoration: const InputDecoration(labelText: 'Episodio'),
                ),
              ),
            ],
            FilledButton(
              onPressed: busy ? null : search,
              child: const Text('Buscar enlaces'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (busy) const LinearProgressIndicator(color: accent),
        for (var i = 0; i < streams.length; i++)
          ListTile(
            title: Text(streams[i].name),
            trailing: const Icon(Icons.play_circle_outline),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AddonPlayer(
                  title: '${widget.plugin.info.name} · TMDB ${id.text.trim()}${type == 'tv' ? ' · T${season.text} E${episode.text}' : ''}',
                  streams: [...streams.skip(i), ...streams.take(i)],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
