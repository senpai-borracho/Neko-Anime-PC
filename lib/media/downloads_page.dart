import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart' show accent, muted;
import '../app_ui.dart';
import '../addons/addon_player.dart';
import 'downloads.dart';
import 'source.dart';

class DownloadButton extends StatefulWidget {
  final String title;
  final Future<MediaSource> Function()? source;
  const DownloadButton({super.key, required this.title, required this.source});
  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  bool busy = false;
  Future<void> download() async {
    setState(() => busy = true);
    try {
      final source = await widget.source!();
      await Downloads.shared.enqueue(widget.title, source);
      if (mounted) showCompactNotice(context, 'Añadido a Descargas.');
    } catch (e) {
      if (mounted) showCompactNotice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Descargar episodio',
    onPressed: busy || widget.source == null ? null : download,
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.download_rounded),
  );
}

class DownloadsPage extends StatefulWidget {
  final Downloads? downloads;
  const DownloadsPage({super.key, this.downloads});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  late final manager = widget.downloads ?? Downloads.shared;
  String? error;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      await manager.ready;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => ready = true);
  }

  Future<void> open(DownloadTask task) async {
    if (!await File(task.path).exists()) {
      if (mounted) {
        showCompactNotice(
          context,
          'El archivo ya no está en la carpeta de descargas.',
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AddonPlayer(
          title: task.title,
          streams: [
            MediaSource('Descarga local', Uri.file(task.path).toString(), {}, [
              if (task.subtitlePath.isNotEmpty)
                {'url': Uri.file(task.subtitlePath).toString(), 'lang': 'es'},
            ]),
          ],
        ),
      ),
    );
  }

  final Set<String> deleting = {};
  Future<void> remove(DownloadTask task) async {
    if (deleting.contains(task.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar episodio'),
        content: Text(
          '¿Eliminar "${task.title}" del disco y del historial de descargas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deleting.add(task.id));
    try {
      await manager.remove(task);
    } catch (e) {
      if (mounted) showCompactNotice(context, e);
    } finally {
      if (mounted) setState(() => deleting.remove(task.id));
    }
  }

  String downloadingStatus(DownloadTask task) {
    final mb = (task.bytes / 1048576).toStringAsFixed(1);
    final value = task.progressValue;
    if (task.total > 0) {
      return 'Descargando · $mb / ${(task.total / 1048576).toStringAsFixed(1)} MB · ${(value! * 100).floor()} %';
    }
    if (task.segmentsTotal > 0) {
      return 'Descargando · $mb MB · ${task.segmentsDone}/${task.segmentsTotal} segmentos · ${(value! * 100).floor()} %';
    }
    return 'Descargando · $mb MB · Tamaño total desconocido';
  }

  String status(DownloadTask task) => switch (task.status) {
    DownloadStatus.queued => 'En cola',
    DownloadStatus.downloading => downloadingStatus(task),
    DownloadStatus.done =>
      'Completada · ${(task.bytes / 1048576).toStringAsFixed(1)} MB',
    DownloadStatus.cancelled => 'Cancelada',
    DownloadStatus.failed => task.error,
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Descargas'),
      actions: [
        IconButton(
          tooltip: 'Abrir carpeta',
          icon: const Icon(Icons.folder_open),
          onPressed: () async {
            await manager.directory.create(recursive: true);
            if (Platform.isWindows) {
              await Process.start('explorer.exe', [manager.directory.path]);
            }
          },
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: !ready
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: SelectableText(error!))
        : AnimatedBuilder(
            animation: manager,
            builder: (context, _) => manager.tasks.isEmpty
                ? const Center(
                    child: Text(
                      'Descarga un episodio desde su reproductor.',
                      style: TextStyle(color: muted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(22),
                    itemCount: manager.tasks.length,
                    itemBuilder: (context, i) {
                      final task = manager.tasks[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              ListTile(
                                title: Text(task.title),
                                subtitle: Text(
                                  '${task.source.name} · ${status(task)}',
                                ),
                                trailing: task.status == DownloadStatus.done
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Reproducir sin conexión',
                                            icon: const Icon(
                                              Icons.play_circle_outline,
                                            ),
                                            onPressed: () => open(task),
                                          ),
                                          IconButton(
                                            tooltip: 'Eliminar episodio',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed:
                                                deleting.contains(task.id)
                                                ? null
                                                : () => remove(task),
                                          ),
                                        ],
                                      )
                                    : [
                                        DownloadStatus.queued,
                                        DownloadStatus.downloading,
                                      ].contains(task.status)
                                    ? IconButton(
                                        tooltip: 'Cancelar',
                                        icon: const Icon(Icons.close),
                                        onPressed: () => manager.cancel(task),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Reintentar',
                                            icon: const Icon(Icons.refresh),
                                            onPressed: () =>
                                                manager.retry(task),
                                          ),
                                          IconButton(
                                            tooltip: 'Eliminar episodio',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed:
                                                deleting.contains(task.id)
                                                ? null
                                                : () => remove(task),
                                          ),
                                        ],
                                      ),
                              ),
                              if (task.status == DownloadStatus.downloading)
                                DownloadProgress(value: task.progressValue),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
  );
}

class DownloadProgress extends StatelessWidget {
  final double? value;
  const DownloadProgress({super.key, required this.value});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: value,
              color: accent,
              backgroundColor: const Color(0xFF303747),
              minHeight: 4,
            ),
          ),
          Positioned(
            left: (constraints.maxWidth * (value ?? .5) - 28).clamp(
              0.0,
              (constraints.maxWidth - 56).clamp(0.0, double.infinity),
            ),
            bottom: 4,
            child: IgnorePointer(
              child: Image.asset(
                'assets/neko_download_wave.png',
                width: 56,
                height: 38,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
