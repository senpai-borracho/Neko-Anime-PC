# Complementos — copia lite de Neko PC

Corrección de portadas Anix: Jikan tiene alternativa en AniList y caché de portadas
por página. La búsqueda de extensiones sigue disponible mientras se carga el catálogo.
Los errores de metadatos se muestran aparte y tienen botón Reintentar.
La selección de fuentes se conserva. Latanime y MonosChinos quedan desactivadas
por defecto para no duplicar las fuentes normales; se pueden activar manualmente.
El modo doblaje solo se habilita si alguna fuente seleccionada lo declara en español.

El ZIP original no se modifica. La copia añade Complementos al menú Sistema.
Conserva los colores, el tema y los componentes de portadas de la aplicación.
El catálogo principal, la biblioteca, los ajustes y los motores originales no cambian.

## Uso

- Complementos → Agregar repositorio: URL HTTPS de un manifiesto Stremio o repositorio Nuvio.
- AnimES: https://pigamer37.alwaysdata.net/manifest.json → Instalar → Ver catálogo.
  Incluye portadas, búsqueda, géneros, ficha, episodios y reproducción HTTP(S)
  con las cabeceras enviadas por el addon. Su catálogo exige búsqueda o género.
- Nuvio: instala un proveedor o importa su archivo .js; abre Buscar enlaces Nuvio.
  El contrato getStreams requiere ID de TMDB, tipo y temporada/episodio.
  Estos scripts no proporcionan catálogo propio. Utiliza el runtime Node incluido con Neko.
- Extensiones Anix: abre la pantalla y el puente que ya venían en el ZIP.
  Se registran sus recursos, que antes faltaban en pubspec.yaml. Utiliza el runtime Node incluido con Neko.
- Se pueden actualizar, desactivar y eliminar complementos y quitar repositorios.
  El estado se guarda aparte, en LOCALAPPDATA/NekoPlayerPC/plugins; no escribe library.json.

Los índices Aniyomi se reconocen, pero sus APK Android no se ejecutan en Windows.
Los streams Stremio admitidos son HTTP(S); no se añaden motores de torrents, DRM
ni un navegador para externalUrl. Se cargan los subtítulos externos identificados
como español y se priorizan las pistas de audio/subtítulos en español.
Solo se admiten enlaces identificados como español, español latino o subtitulados
al español. Los idiomas desconocidos se bloquean, salvo enlaces sin etiqueta de
proveedores que declaren exclusivamente español para el modo elegido.
Los metadatos del proveedor no permiten verificar por sí solos el idioma real del video.
Los controles de reproducción son los de media_kit, en una pantalla propia de Complementos.
Los proveedores JavaScript usan el Node incluido; node:vm no constituye un aislamiento de seguridad.

## Alcance de los cambios

- lib/main.dart: entrada de Complementos y, por petición posterior, acceso global a
  Descargas, botón de descarga y selección automática por velocidad en el reproductor.
- pubspec.yaml: solo registrar assets/extensions/.
- lib/anix_page.dart: filtro de español y subtítulos dentro de Complementos; sin cambiar su motor.
- Nuevos archivos lib/addons/, test/addons_test.dart y tool/probe_addons.dart.
- Descargas y velocidad: lib/media/, test/downloads_test.dart y DESCARGAS-LITE.md.
- Sin nuevas dependencias ni cambios de versiones.
- Todos los demás archivos originales de código se comparan mediante SHA-256 con el ZIP.
- La copia fuente omite cachés y compilaciones regenerables del ZIP.

## Verificación

    flutter pub get
    flutter test
    flutter analyze --no-pub lib/addons
    dart run tool/probe_addons.dart

Las 30 pruebas originales y las 5 pruebas de Complementos pasaron.
El análisis específico de lib/addons no presenta incidencias.
El análisis completo detecta tres overrides incompatibles en integration_test
que ya estaban en el ZIP; se conservan sin modificar por quedar fuera de Complementos.
No se ha probado reproducción de video en una ventana Windows ni generado un nuevo instalador.

Para compilar cuando se requiera:

    flutter build windows --release
