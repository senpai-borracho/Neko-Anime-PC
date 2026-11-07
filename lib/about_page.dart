import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'runtime/node_runtime.dart';

class NekoAboutPage extends StatelessWidget {
  const NekoAboutPage({super.key});
  static const credits = <(String, String)>[
    (
      'Anix · Proyecto de origen de las extensiones',
      'https://github.com/MaidLover69/Anix',
    ),
    (
      'Anix extensions · Paquete comunitario incluido',
      'https://github.com/MaidLover69/Anix_plugins',
    ),
    (
      'Anix · Distribución del paquete integrado',
      'https://anix-linux.vercel.app/extensions',
    ),
    (
      'Seanime · Especificación de proveedores onlinestream-provider',
      'https://github.com/5rahim/seanime',
    ),
    (
      'AniList · API GraphQL: metadatos, portadas y rankings',
      'https://docs.anilist.co/',
    ),
    (
      'MyAnimeList · API oficial v2: cuenta, listas y seguimiento',
      'https://myanimelist.net/apiconfig/references/api/v2',
    ),
    (
      'Jikan · API no oficial de MyAnimeList: catálogo visual y portadas',
      'https://jikan.moe/',
    ),
    (
      'Google Translate · Traducción de sinopsis',
      'https://translate.google.com/',
    ),
    (
      'MyMemory / Translated · API de traducción de sinopsis',
      'https://mymemory.translated.net/doc/spec.php',
    ),
    (
      'AnimeAV1 · API e integración: FxxMorgan/anime1v-api · MIT',
      'https://github.com/FxxMorgan/anime1v-api',
    ),
    ('Flutter · Interfaz de escritorio', 'https://flutter.dev/'),
    ('Dart · Lenguaje y runtime', 'https://dart.dev/'),
    ('Node.js · Runtime incluido para complementos', 'https://nodejs.org/'),
    (
      'Stremio · Protocolo de complementos compatible',
      'https://github.com/Stremio/stremio-addon-sdk',
    ),
    ('Nuvio · Compatibilidad con proveedores getStreams', 'https://nuvio.tv/'),
    (
      'media_kit · Reproducción · MIT',
      'https://github.com/media-kit/media-kit',
    ),
    ('mpv / libmpv · Motor de vídeo', 'https://mpv.io/'),
    (
      'Manrope · Tipografía · SIL Open Font License',
      'https://github.com/sharanda/manrope',
    ),
    ('TioAnime', 'https://tioanime.com/'),
    ('AnimeFLV', 'https://animeflv.or.at/'),
    ('AnimeAV1', 'https://animeav1.com/'),
    ('MonosChinos1', 'https://vww.monoschinos2.net/'),
    ('LatAnime', 'https://latanime.org/'),
    ('OtakusTV', 'https://www.otakustv.net/'),
    ('AnimeYT', 'https://vvw.animeyt.one/'),
    ('AnimeYTX', 'https://animeytx.org/'),
    ('MonosChinos2 · Fuente inhabilitada', 'https://monoschinos.st/'),
    ('JKAnime · Fuente opcional', 'https://jkanime.net/'),
  ];
  static Future<String> _license(String path) async {
    if (path == 'runtime/node/LICENSE-Node.txt') {
      return File('${File(NodeRuntime.resolve()).parent.path}/LICENSE-Node.txt')
          .readAsString();
    }
    return rootBundle.loadString(path);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Acerca de')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.pets_rounded, size: 36, color: Color(0xffae80ff)),
            const SizedBox(height: 12),
            const Text(
              'Neko Anime 0.3.1 Stable',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const SelectableText(
              'Versión 0.3.1 Stable\nDesarrollado por SenpaiBorracho © 2026\nBasada en Neko Anime Android 0.4.4.\nAplicación gratuita, independiente y sin publicidad.',
              style: TextStyle(height: 1.7),
            ),
            const SizedBox(height: 24),
            const Text(
              'Paquete Anix integrado',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const SelectableText(
              'Neko Anime incluye el paquete comunitario Anix extensions, publicado por el proyecto Anix. '
              'Los proveedores JavaScript del paquete se utilizan mediante el adaptador de Complementos de Neko; '
              'sus autores se identifican en los metadatos del paquete. '
              'Las fuentes en español incluidas son AniZone, AnimeParadise, Latanime y MonosChinos. '
              'La selección y activación de cada fuente se realiza desde Complementos.',
              style: TextStyle(fontSize: 13, height: 1.7),
            ),
            const SizedBox(height: 24),
            const Text(
              'Créditos, API y enlaces',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final credit in credits)
              Card(
                child: ListTile(
                  title: Text(credit.$1, style: const TextStyle(fontSize: 13)),
                  subtitle: SelectableText(
                    credit.$2,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xffae80ff),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Abrir enlace',
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    onPressed: () async {
                      try {
                        await Process.run('explorer.exe', [credit.$2]);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No se pudo abrir el enlace. Puedes copiarlo.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              'Licencias completas',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final item in const <(String, String)>[
              ('Neko Anime · GNU GPL v3', 'LICENSE'),
              (
                'anime1v-api · MIT · Feer (FxxMorgan)',
                'licenses/anime1v-api-MIT.txt',
              ),
              ('media_kit · MIT', 'licenses/media_kit-MIT.txt'),
              ('Manrope · SIL Open Font License', 'licenses/Manrope-OFL.txt'),
              (
                'Node.js · Licencia y avisos del runtime incluido',
                'runtime/node/LICENSE-Node.txt',
              ),
            ])
              Card(
                child: ExpansionTile(
                  title: Text(item.$1, style: const TextStyle(fontSize: 13)),
                  children: [
                    FutureBuilder<String>(
                      future: _license(item.$2),
                      builder: (_, snapshot) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          snapshot.data ??
                              (snapshot.hasError
                                  ? 'No se pudo cargar la licencia.'
                                  : 'Cargando…'),
                          style: const TextStyle(fontSize: 11, height: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Neko Anime',
                applicationVersion: '0.3.1 Stable',
                applicationLegalese: 'SenpaiBorracho © 2026',
              ),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text(
                'Todas las licencias de Flutter y dependencias',
              ),
            ),
            const SizedBox(height: 16),
            const SelectableText(
              'Neko Anime no está afiliado oficialmente a los proveedores de contenido. Los créditos y las licencias de cada componente se conservan con sus respectivos autores.',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Color(0xff9aa3b9),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
