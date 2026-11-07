// Ventana "Mi lista de MyAnimeList": pestañas por estado. Al tocar un anime se
// busca su título en las fuentes de Neko.
import 'package:flutter/material.dart';

import 'mal_client.dart';

const _tabs = [
  ('watching', 'Viendo'),
  ('plan_to_watch', 'Pendientes'),
  ('completed', 'Completados'),
  ('on_hold', 'En pausa'),
  ('dropped', 'Abandonados'),
];

Future<void> showMalList(
  BuildContext context,
  MalClient mal,
  void Function(String title) onSearch,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: DefaultTabController(
          length: _tabs.length,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mi lista de MyAnimeList · ${mal.name}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              TabBar(tabs: [for (final tab in _tabs) Tab(text: tab.$2)]),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final tab in _tabs)
                      _MalTab(
                        mal: mal,
                        status: tab.$1,
                        onPick: (title) {
                          Navigator.of(dialogContext).pop();
                          onSearch(title);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MalTab extends StatefulWidget {
  final MalClient mal;
  final String status;
  final void Function(String title) onPick;
  const _MalTab({required this.mal, required this.status, required this.onPick});

  @override
  State<_MalTab> createState() => _MalTabState();
}

class _MalTabState extends State<_MalTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<MalEntry>> future = widget.mal.list(widget.status);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<MalEntry>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
                FilledButton(
                  onPressed: () => setState(
                    () => future = widget.mal.list(widget.status),
                  ),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const Center(child: Text('No hay animes en esta lista.'));
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            final progress = item.total > 0
                ? '${item.watched}/${item.total} eps'
                : '${item.watched} eps';
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: item.picture.isEmpty
                    ? const SizedBox(width: 40, height: 56)
                    : Image.network(
                        item.picture,
                        width: 40,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox(width: 40, height: 56),
                      ),
              ),
              title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                item.score > 0 ? '$progress · ★ ${item.score}/10' : progress,
              ),
              trailing: const Icon(Icons.search_rounded, size: 18),
              onTap: () => widget.onPick(item.title),
            );
          },
        );
      },
    );
  }
}
