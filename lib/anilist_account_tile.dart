import 'package:flutter/material.dart';

import 'anilist_account.dart';

class AniListAccountTile extends StatefulWidget {
  final AniListAccount? account;
  final ValueChanged<String> onSearch;
  const AniListAccountTile({super.key, this.account, required this.onSearch});
  @override
  State<AniListAccountTile> createState() => _AniListAccountTileState();
}

class _AniListAccountTileState extends State<AniListAccountTile> {
  late final account = widget.account ?? AniListAccount();
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      await account.load();
    } catch (_) {
      error = 'No se pudo leer la sesión de AniList. Vuelve a conectar.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    if (widget.account == null) account.close();
    super.dispose();
  }

  Future<void> connect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await account.login();
    } catch (e) {
      if (mounted) error = '$e'.replaceFirst(RegExp(r'^\w+Exception: *'), '');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showList() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _AniListDialog(account: account, onSearch: widget.onSearch),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(account.connected ? account.name : 'Conectar con AniList'),
        subtitle: Text(
          loading
              ? 'Cargando sesión…'
              : busy
              ? 'Autoriza en el navegador y vuelve a Neko…'
              : account.connected
              ? 'Cuenta de AniList conectada'
              : 'Inicia sesión en AniList para consultar tu lista de anime.',
        ),
        trailing: loading
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (account.connected) ...[
                    TextButton(
                      onPressed: busy ? null : showList,
                      child: const Text('Ver mi lista'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                await account.logout();
                                if (mounted) setState(() {});
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => error = 'No se pudo cerrar la sesión. Reintenta.',
                                  );
                                }
                              }
                            },
                      child: const Text('Desconectar'),
                    ),
                  ] else ...[
                    if (busy)
                      TextButton(
                        onPressed: account.cancelLogin,
                        child: const Text('Cancelar'),
                      ),
                    FilledButton(
                      onPressed: busy ? null : connect,
                      child: Text(busy ? 'Esperando…' : 'Conectar'),
                    ),
                  ],
                ],
              ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

class _AniListDialog extends StatefulWidget {
  final AniListAccount account;
  final ValueChanged<String> onSearch;
  const _AniListDialog({required this.account, required this.onSearch});
  @override
  State<_AniListDialog> createState() => _AniListDialogState();
}

class _AniListDialogState extends State<_AniListDialog> {
  late Future<List<Map>> entries = widget.account.animeList();
  String filter = 'ALL';
  static const statuses = {
    'ALL': 'Todos',
    'CURRENT': 'Viendo',
    'PLANNING': 'Pendientes',
    'COMPLETED': 'Completados',
    'PAUSED': 'En pausa',
    'DROPPED': 'Abandonados',
    'REPEATING': 'Volviendo a ver',
  };
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Lista de AniList · ${widget.account.name}'),
    content: SizedBox(
      width: 720,
      height: 460,
      child: Column(
        children: [
          DropdownButton<String>(
            value: filter,
            isExpanded: true,
            items: [
              for (final item in statuses.entries)
                DropdownMenuItem(value: item.key, child: Text(item.value)),
            ],
            onChanged: (value) => setState(() => filter = value ?? 'ALL'),
          ),
          Expanded(
            child: FutureBuilder<List<Map>>(
              future: entries,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No se pudo cargar tu lista de AniList.'),
                        TextButton(
                          onPressed: () => setState(
                            () => entries = widget.account.animeList(),
                          ),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!
                    .where((e) => filter == 'ALL' || e['status'] == filter)
                    .toList();
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No hay animes en esta lista.'),
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    final media = entry['media'] is Map
                        ? entry['media'] as Map
                        : const {};
                    final title = media['title'] is Map
                        ? '${media['title']['userPreferred'] ?? ''}'
                        : '';
                    final cover = media['coverImage'] is Map
                        ? media['coverImage']['medium']
                        : null;
                    return ListTile(
                      leading: cover is String
                          ? Image.network(
                              cover,
                              width: 38,
                              height: 54,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.movie_outlined),
                            )
                          : const Icon(Icons.movie_outlined),
                      title: Text(title),
                      subtitle: Text(
                        '${statuses[entry['status']] ?? entry['status']} · ${entry['progress'] ?? 0}/${media['episodes'] ?? '?'} episodios',
                      ),
                      trailing: const Icon(Icons.search),
                      onTap: title.isEmpty
                          ? null
                          : () {
                              Navigator.pop(context);
                              widget.onSearch(title);
                            },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}
