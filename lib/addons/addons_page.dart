import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../main.dart' show surface, border, accent, muted;
import '../app_ui.dart';
import '../anix_page.dart';
import 'plugin_manager.dart';
import 'plugin_models.dart';
import 'stremio_page.dart';
import 'nuvio_page.dart';

class AddonsPage extends StatefulWidget {
  final PluginManager? manager;
  const AddonsPage({super.key, this.manager});
  @override
  State<AddonsPage> createState() => _AddonsPageState();
}

class _AddonsPageState extends State<AddonsPage> {
  late final manager = widget.manager ?? PluginManager();
  bool loading = true, busy = false;
  String filter = '';
  @override
  void initState() {
    super.initState();
    manager.addListener(changed);
    initialize();
  }

  Future<void> initialize() async {
    await manager.load();
    if (mounted) setState(() => loading = false);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    manager.removeListener(changed);
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showCompactNotice(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> ask(String title, String hint) async {
    var input = '';
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            onChanged: (value) => input = value,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.trim()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    return value;
  }

  Future<void> addRepo() async {
    final url = await ask('Agregar repositorio', 'https://…/manifest.json');
    if (url == null || url.isEmpty || !mounted) return;
    await run(() => manager.addRepo(url));
  }

  Future<void> importFile() async {
    await run(() async {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON o script Nuvio', extensions: ['json', 'js']),
        ],
      );
      if (selected == null || !mounted) return;
      final file = File(selected.path);
      if (await file.length() > 8 * 1024 * 1024) {
        throw const FormatException('Archivo demasiado grande.');
      }
      final text = await file.readAsString();
      if (file.path.toLowerCase().endsWith('.js')) {
        await manager.importScript(
          text,
          name: file.uri.pathSegments.last,
          lang: 'otro',
        );
      } else {
        try {
          await manager.importJson(text, fileName: file.uri.pathSegments.last);
        } on NeedBaseUrl {
          if (!mounted) return;
          final base = await ask('URL base del repositorio', 'https://…/');
          if (base == null || base.isEmpty) return;
          await manager.importJson(
            text,
            fileName: file.uri.pathSegments.last,
            baseUrl: base,
          );
        }
      }
    });
  }

  Future<void> remove(PluginEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar ${entry.info.name}'),
        content: const Text('¿Eliminar este complemento de Neko?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await run(() => manager.remove(entry.info));
  }

  Future<void> repos() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Repositorios'),
      content: SizedBox(
        width: 600,
        child: manager.repos.isEmpty
            ? const Text('No hay repositorios.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final repo in manager.repos)
                    ListTile(
                      title: Text(repo.name),
                      subtitle: Text(repo.url),
                      trailing: IconButton(
                        tooltip: 'Quitar repositorio',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          manager.removeRepo(repo);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final entries = manager
        .entries()
        .where(
          (e) => '${e.info.name} ${e.info.description}'.toLowerCase().contains(
            filter.toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complementos'),
        actions: [
          IconButton(
            tooltip: 'Repositorios',
            onPressed: repos,
            icon: const Icon(Icons.storage_rounded),
          ),
          IconButton(
            tooltip: 'Actualizar repositorios',
            onPressed: busy ? null : () => run(manager.refresh),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : addRepo,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar por URL'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : importFile,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Importar archivo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AnixPage(),
                        ),
                      ),
                      icon: const Icon(Icons.extension_outlined),
                      label: const Text('Extensiones Anix'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (v) => setState(() => filter = v),
                  decoration: const InputDecoration(
                    hintText: 'Buscar complemento',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                if (busy) const LinearProgressIndicator(color: accent),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Agrega un repositorio Nuvio o un manifest.json de Stremio para comenzar.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                for (final entry in entries) card(entry),
              ],
            ),
    );
  }

  Widget card(PluginEntry entry) {
    final info = entry.info, installed = entry.installed;
    final pending = manager.busy.containsKey(info.key);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
              if (info.logo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Image.network(
                    info.logo,
                    width: 42,
                    height: 42,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.extension, color: accent),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${info.kind.name.toUpperCase()} · v${info.version} · ${info.language.label}',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              if (pending)
                const CircularProgressIndicator()
              else if (installed == null)
                FilledButton(
                  onPressed: busy || info.kind == PluginKind.aniyomi
                      ? null
                      : () => run(() => manager.install(info)),
                  child: Text(
                    info.kind == PluginKind.aniyomi
                        ? 'Motor Aniyomi no disponible'
                        : 'Instalar',
                  ),
                )
              else ...[
                if (entry.update != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() => manager.install(entry.update!)),
                    child: const Text('Actualizar'),
                  ),
                Switch(
                  value: installed.enabled,
                  onChanged: busy ? null : (v) => manager.setEnabled(info, v),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  onPressed: busy ? null : () => remove(entry),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          if (info.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                info.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted),
              ),
            ),
          if (installed != null && installed.error.isNotEmpty)
            Text(installed.error, style: const TextStyle(color: muted)),
          if (installed != null && installed.enabled)
            OutlinedButton.icon(
              icon: Icon(
                info.kind == PluginKind.stremio
                    ? Icons.grid_view_rounded
                    : Icons.play_arrow,
              ),
              label: Text(
                info.kind == PluginKind.stremio
                    ? 'Ver catálogo'
                    : 'Buscar enlaces Nuvio',
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => info.kind == PluginKind.stremio
                      ? StremioPage(plugin: installed)
                      : NuvioPage(plugin: installed),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
