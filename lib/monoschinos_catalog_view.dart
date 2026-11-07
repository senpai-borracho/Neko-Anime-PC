import 'package:flutter/material.dart';

import 'monoschinos_client.dart';

// Presentation only. The source clients and playback remain in their modules.
class MonosCatalogView extends StatefulWidget {
  final int selected;
  final List<MonosEntry> entries;
  final bool busy;
  final String? error;
  final TextEditingController search;
  final VoidCallback onSearch, onMore;
  final ValueChanged<int> onSourceChanged;
  final Widget Function(MonosEntry, VoidCallback) cardBuilder;
  final ValueChanged<MonosEntry> onOpen;
  const MonosCatalogView({
    super.key,
    required this.selected,
    required this.entries,
    required this.busy,
    required this.error,
    required this.search,
    required this.onSearch,
    required this.onMore,
    required this.onSourceChanged,
    required this.cardBuilder,
    required this.onOpen,
  });
  @override
  State<MonosCatalogView> createState() => _MonosCatalogViewState();
}

class _MonosCatalogViewState extends State<MonosCatalogView> {
  String order = 'Original';
  @override
  Widget build(BuildContext context) {
    final cards = [...widget.entries];
    if (order != 'Original') {
      cards.sort(
        (a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()) *
            (order == 'Z–A' ? -1 : 1),
      );
    }
    final source = monosSites[widget.selected].label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
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
                        controller: widget.search,
                        onSubmitted: (_) => widget.onSearch(),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Buscar en $source…',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Buscar en $source',
                            onPressed: widget.busy ? null : widget.onSearch,
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Actualizar catálogo',
                onPressed: widget.busy ? null : widget.onSearch,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.busy && cards.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xffa577ff)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Explorar catálogo',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${cards.length} animes · $source',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff8e98ad),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (var i = 0; i < monosSites.length; i++)
                            ChoiceChip(
                              label: Text(monosSites[i].label),
                              selected: widget.selected == i,
                              onSelected: (_) => widget.onSourceChanged(i),
                            ),
                          DropdownButton<String>(
                            value: order,
                            underline: const SizedBox.shrink(),
                            style: Theme.of(context).textTheme.bodySmall,
                            items: const [
                              DropdownMenuItem(
                                value: 'Original',
                                child: Text('Orden de la fuente'),
                              ),
                              DropdownMenuItem(
                                value: 'A–Z',
                                child: Text('Alfabético (A–Z)'),
                              ),
                              DropdownMenuItem(
                                value: 'Z–A',
                                child: Text('Alfabético (Z–A)'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => order = value!),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (widget.error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xff191929),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: Color(0xffa577ff),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.error!.replaceFirst(
                                    RegExp(r'^(Exception|FormatException):\s*'),
                                    '',
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              TextButton(
                                onPressed: widget.busy ? null : widget.onSearch,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      if (cards.isEmpty && !widget.busy && widget.error == null)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No se encontraron animes para esta búsqueda.',
                          ),
                        ),
                      LayoutBuilder(
                        builder: (context, c) => GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: (c.maxWidth / 154)
                                    .floor()
                                    .clamp(1, 10),
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16,
                                childAspectRatio: .61,
                              ),
                          itemCount: cards.length,
                          itemBuilder: (_, i) => widget.cardBuilder(
                            cards[i],
                            () => widget.onOpen(cards[i]),
                          ),
                        ),
                      ),
                      if (cards.isNotEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 26),
                            child: OutlinedButton.icon(
                              onPressed: widget.busy ? null : widget.onMore,
                              icon: widget.busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xffa577ff),
                                      ),
                                    )
                                  : const Icon(Icons.expand_more),
                              label: const Text('Cargar más animes'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
