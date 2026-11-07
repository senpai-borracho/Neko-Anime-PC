# Descargas y selección de servidor

Aplicado a la copia lite de PC. No se cambian los motores, extractores ni sus
reglas de resolución. Se usan las APIs existentes desde las pantallas.

## Servidor automático

El reproductor compara pequeñas muestras reales de video (hasta 512 KiB por
servidor), con dos comparaciones en paralelo y tiempos máximos de espera.
Para HLS mide un fragmento de video, no solo la lista. Elige el enlace con
mayor transferencia observada. Es una estimación de ese momento; no garantiza
la velocidad durante todo el episodio. Conserva la selección manual.
Si un servidor permite reproducir pero bloquea la muestra, queda como alternativa
sin velocidad medida. El orden de la lista no se toma como indicador de velocidad.

Se aplica a las fuentes normales, las fuentes extra y Complementos (Stremio,
Nuvio y Anix). Los complementos mantienen la política de español.

## Descargas

- Botón Descargar en la barra de todos los reproductores.
- Nueva entrada Descargas en el menú; permite ver progreso, cancelar, reintentar,
  abrir la carpeta y reproducir los archivos completos sin conexión.
- Carpeta predeterminada: USERPROFILE/Downloads/Neko.
- Cola de una transferencia a la vez; preserva cabeceras de los proveedores.
- Admite archivos directos MP4/WebM/MKV y HLS VOD sin cifrado, con audio integrado.
- HLS MPEG-TS se guarda como .ts; HLS fMP4 con una inicialización se guarda como .mp4.
- Los subtítulos externos en español se guardan al lado del video y se cargan
  al reproducir desde Descargas.
- Solo marca completado al terminar; comprueba tamaños conocidos y rechaza HTML,
  respuestas parciales incompletas y formatos HLS no soportados.
- No admite HLS cifrado, audio separado, rangos HLS, emisiones en vivo, DRM ni torrents.
  En esos casos muestra un motivo y permite elegir otro servidor.
- Cancelar elimina solo el archivo parcial de esa tarea; Reintentar empieza de cero.
  Al reiniciar Neko, las tareas interrumpidas requieren pulsar Reintentar.
- Los enlaces firmados pueden caducar: si un reintento falla, vuelve a abrir el
  episodio y solicita una descarga nueva.
- No se ha añadido un descargador al motor ni modificado la biblioteca.
  El estado se guarda aparte en LOCALAPPDATA/NekoPlayerPC/downloads.json.

## Validación

    flutter test --no-pub
    flutter analyze --no-pub lib/media lib/addons

La batería completa incluye 42 pruebas de fuentes, biblioteca, interfaz,
Complementos, medición de velocidad y descargas con servidores HTTP locales.
No se han descargado episodios completos durante las pruebas.
Esta entrega es código fuente; aún no se ha generado un ejecutable Windows nuevo.
