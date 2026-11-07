# Neko Player PC 0.3.0

Aplicación nativa para Windows x64, con Flutter Desktop y reproducción integrada mediante libmpv/media_kit.

La referencia Android más reciente localizada es **Neko Anime 0.4.4**. Existe además una preview posterior específica para Fire TV. Android se conserva intacto; este proyecto es independiente.

## Funciones

- Interfaz de escritorio con navegación lateral, portada destacada y filas de animes.
- Paleta de Android: fondo `#090C13`, paneles `#141923`, texto `#F0F1F6`, violeta `#B483FF` y tipografía Manrope.
- Catálogo y búsqueda de TioAnime, AnimeFLV (animeflv.or.at) y AnimeAV1, con títulos duplicados agrupados y selección de fuente. JKAnime se conserva como respaldo opcional, desactivado por defecto.
- Carga progresiva: se muestra la primera fuente disponible mientras terminan las demás consultas.
- Fichas, sinopsis, episodios, filtro por número y selección de servidor.
- Reproductor nativo con controles de video, volumen, búsqueda temporal y pantalla completa.
- Fuentes activables desde Ajustes, conservadas al reiniciar.
- Seguimiento desde la ficha: Viendo, Terminados, Pendientes, En pausa y Abandonados. Filtros en Mi lista; selección manual, sin confundir terminar un episodio con terminar una serie.
- Retorno dentro de los controles de video: se oculta con ellos y reaparece al mover el cursor, en ventana y pantalla completa. Video centrado, con proporciones originales.
- Botón X en Seguir viendo e Historial para quitar un anime y su progreso de reanudación. Si vuelves a reproducirlo, aparecerá de nuevo. Favoritos y estados de seguimiento se conservan.
- Mi lista, historial y progreso guardados localmente en `%LOCALAPPDATA%\NekoPlayerPC\library.json`.
- Errores y reintentos visibles. No se simula una reproducción cuando un servidor falla.

## Nuevos episodios

Sección general para todos los animes que aparezcan en los listados de publicaciones recientes de las fuentes activas, sin necesidad de guardarlos. Actualiza al iniciar, cada 15 minutos mientras Neko esté abierto y mediante Actualizar ahora. Permite filtrar por fuente. Al abrir una tarjeta se muestra la ficha con su lista de episodios. No revisa todas las fichas históricas ni funciona con Neko cerrado.

## Usar

Con el instalador, abre Neko Player desde Inicio o el escritorio. La versión portable debe extraerse completa: no separes el EXE de sus DLL y la carpeta `data`. No necesitas instalar Flutter, Dart o mpv por separado.

Busca un anime y pulsa Enter. Abre su ficha, elige un episodio y selecciona un servidor desde el encabezado del reproductor si el primero falla. La disponibilidad, resolución y velocidad dependen del servidor; la aplicación no convierte automáticamente un video de baja resolución en HD.

Esta versión adapta los resolutores de enlaces directos, JKAnime Principal/Alternativo, MP4Upload, YourUpload y Voe. Los hosts que no expongan una URL compatible o soliciten captcha/verificación de navegador muestran un error; no se eluden esas verificaciones. No todos los servidores de internet están garantizados.

## Compilar

Herramientas utilizadas: Flutter 3.47.8 / Dart 3.13.7, Visual Studio Build Tools 2026 con desarrollo C++ para escritorio y Windows SDK. Las versiones de paquetes están fijadas en `pubspec.lock`.

Extrae el código en una ruta corta, por ejemplo `C:\src\NekoPC`. Las rutas largas pueden impedir que MSVC encuentre cabeceras de plugins.

```powershell
flutter pub get
flutter analyze
flutter test test
flutter build windows --release
```

Si Windows no permite crear enlaces de plugins, activa Modo de desarrollador o utiliza `packaging/Build-Windows.ps1`, que prepara junctions dentro del proyecto sin cambiar el SDK de Flutter ni los ajustes del sistema.

Para generar instalador y portable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\packaging\Build-Windows.ps1 `
  -InnoCompiler 'C:\Herramientas\Inno\ISCC.exe' `
  -CrtDirectory 'C:\Ruta\Microsoft.VC145.CRT' `
  -Destination 'C:\Entregas\NekoPlayerPC'
```

## Pruebas

`test/catalog_test.dart` comprueba datos Svelte, unión del catálogo y extracción de enlaces. `integration_test/desktop_test.dart` separa navegación, reproducción de un clip generado de prueba y un episodio real. La comprobación remota utiliza un reproductor nuevo y exige video decodificado, avance y duración superior a 60 segundos, para no confundirla con el clip local.

La versión 0.2.0 comprobó Dark Machine, episodio 1, mediante TioAnime (YourUpload, 720p) y AnimeFLV de animeflv.or.at (MP4Upload, 1080p), con avance real y sin aviso falso. La versión 0.1.1 también verificó el mismo episodio en AnimeAV1 y JKAnime. Son pruebas breves de muestras concretas, no una garantía de todos los episodios o servidores. El clip propio de prueba está en `tool/native_smoke.mp4`.

## Créditos y licencias

Desarrollado por SenpaiBorracho © 2026. Código de esta adaptación bajo GPL-3.0; texto en `LICENSE`, conservado del proyecto Android.

- Neko Anime / base mpv-android: se conservan sus avisos correspondientes.
- Integración AnimeAV1 adaptada de FxxMorgan/anime1v-api, MIT: `licenses/anime1v-api-MIT.txt`.
- Manrope: `licenses/Manrope-OFL.txt`.
- media_kit y media_kit_video: MIT. https://github.com/media-kit/media-kit
- Flutter y sus dependencias conservan sus avisos en los paquetes y en los avisos generados de Flutter.
- libmpv/FFmpeg y ANGLE: binarios suministrados por `media_kit_libs_windows_video`, sin modificarlos. Fuentes/builds de referencia: https://github.com/media-kit/libmpv-win32-video-build y https://mpv.io/ . Versión del archivo nativo fijada por el paquete: `mpv-dev-x86_64-20230924-git-652a1dd.7z`.
- Runtime Microsoft Visual C++: redistribución local de las DLL de la instalación de Build Tools; pertenece a Microsoft.

Neko Player es independiente y no está afiliado oficialmente a los sitios del catálogo. Las consultas se realizan a páginas públicas mediante HTTPS, con verificación normal de certificados. No se ejecutan scripts remotos ni se incluyen anuncios o credenciales de usuarios.




La ventana inicial se centra y limita al área útil del monitor para evitar quedar fuera de pantalla con la escala de Windows.


