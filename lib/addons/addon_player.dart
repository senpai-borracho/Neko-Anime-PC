import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../main.dart' show accent, muted;
import '../playback_config.dart';
import '../media/source.dart';
import '../media/server_selector.dart';
import '../media/downloads_page.dart';

typedef AddonVideo = MediaSource;

class AddonPlayer extends StatefulWidget {
  final String title;
  final List<AddonVideo> streams;
  final List<Future<MediaSource> Function()>? resolvers;
  const AddonPlayer({
    super.key,
    required this.title,
    this.streams = const [],
    this.resolvers,
  });
  @override
  State<AddonPlayer> createState() => _AddonPlayerState();
}

class _AddonPlayerState extends State<AddonPlayer> {
  late final player = Player();
  late final video = VideoController(player);
  int selected = 0, request = 0;
  bool loading = true;
  String? error;
  List<MediaSource> streams = [];
  final Map<String, double> speeds = {};
  @override
  void initState() {
    super.initState();
    selectBest();
  }

  Future<void> selectBest() async {
    final token = ++request;
    try {
      final ranked = await ServerSelector.rank(
        widget.resolvers ??
            [for (final source in widget.streams) () async => source],
        cancelled: () => !mounted || token != request,
      );
      if (!mounted || token != request) return;
      if (ranked.isEmpty) {
        throw const FormatException('No hay servidores disponibles.');
      }
      streams = [for (final result in ranked) result.source];
      for (final result in ranked) {
        speeds[result.source.url] = result.bytesPerSecond;
      }
      await play(0);
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    request++;
    player.dispose();
    super.dispose();
  }

  Future<void> play(int index) async {
    final token = ++request;
    setState(() {
      selected = index;
      loading = true;
      error = null;
    });
    try {
      await player.stop();
      if (!mounted || token != request) return;
      await configurePlayback(player);
      final native = player.platform;
      if (native is NativePlayer) {
        await native.setProperty('alang', 'es,spa,es-ES,es-419,es-MX');
        await native.setProperty('slang', 'es,spa,es-ES,es-419,es-MX');
      }
      if (!mounted || token != request) return;
      final stream = streams[index];
      await player.open(Media(stream.url, httpHeaders: stream.headers));
      if (stream.subtitles.isNotEmpty && mounted && token == request) {
        final subtitle = stream.subtitles.first;
        await player.setSubtitleTrack(
          SubtitleTrack.uri(
            '${subtitle['url']}',
            title: 'Español',
            language: 'es',
          ),
        );
      }
    } catch (e) {
      if (mounted && token == request) setState(() => error = '$e');
    } finally {
      if (mounted && token == request) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        DownloadButton(
          title: widget.title,
          source:
              loading ||
                  streams.isEmpty ||
                  Uri.parse(streams[selected].url).scheme == 'file'
              ? null
              : () async => streams[selected],
        ),
        if (streams.isNotEmpty)
          DropdownButton<int>(
            value: selected,
            items: [
              for (var i = 0; i < streams.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: SizedBox(
                    width: 220,
                    child: Text(
                      '${streams[i].name.replaceAll('\n', ' · ')}${(speeds[streams[i].url] ?? 0) > 0 && (speeds[streams[i].url] ?? 0).isFinite ? ' · ${((speeds[streams[i].url] ?? 0) / 1048576).toStringAsFixed(1)} MB/s' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            onChanged: loading
                ? null
                : (i) {
                    if (i != null) play(i);
                  },
          ),
        const SizedBox(width: 16),
      ],
    ),
    body: Column(
      children: [
        if (loading) const LinearProgressIndicator(color: accent),
        if (loading && streams.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Comparando velocidad de servidores…'),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(error!, style: const TextStyle(color: muted)),
          ),
        Expanded(
          child: Video(controller: video, controls: AdaptiveVideoControls),
        ),
      ],
    ),
  );
}
