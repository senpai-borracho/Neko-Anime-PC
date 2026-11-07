# Copia optimizada de Neko PC lite

Esta copia parte de Neko_Prueba_Instalador_lite. La carpeta de origen y sus
instaladores/standalone existentes no se modificaron.

Cambios de ejecución:

- Las respuestas HTTP de Complementos y listas HLS se acumulan en buffers de
  bytes tipados, evitando listas de enteros con mayor sobrecarga por byte.
- Stremio comparte las peticiones simultáneas del mismo manifiesto y lo reutiliza
  durante 60 segundos. La caché admite como máximo ocho repositorios por cliente;
  una petición fallida se puede reintentar y no se guarda como resultado válido.
- Las descargas esperan al disco cada MiB y al terminar cada respuesta. Se evita
  acumular indefinidamente datos pendientes cuando la red supera al disco.
- Se liberan los completers de tareas completadas o canceladas, conservando
  el historial y los estados visibles de las descargas.
- Las portadas de tarjetas se decodifican según el ancho físico mostrado. Las
  imágenes de detalle conservan su decodificación anterior. Se mantienen colores,
  proporciones, textos y controles.

Código modificado: lib/main.dart (solo portadas), tres archivos de lib/addons
(stremio_client, plugin_manager y anix_catalog) y dos de lib/media (http_media y
downloads). No se modificaron motores, extractores, reglas de idioma, runtimes,
dependencias, archivos de empaquetado ni funcionalidades.

Validación: 51 pruebas aprobadas, incluidas peticiones compartidas, expiración y
recuperación de caché, miniaturas, descargas de 8 MiB sin truncamiento y cancelación
en cola. Análisis de lib/main.dart, lib/addons y lib/media: sin incidencias.

Microprueba independiente de acumulación y decodificación de una respuesta de
8 MiB, ejecutada dos veces por variante en procesos Dart separados:

| Medición | Implementación anterior | Buffer optimizado |
| --- | --- | --- |
| Tiempo observado | 240–247 ms | 24,6–25,3 ms |
| Incremento de RSS observado | 126,8–147,1 MiB | 7,7–7,9 MiB |

Son resultados de esa operación sintética en este equipo, no del consumo total,
FPS ni rendimiento general de Neko. El JIT, el recolector y el sistema operativo
influyen en las cifras. No se ha medido todavía la RAM total con un uso real.

Para reproducir la microprueba:

    dart run tool/benchmark_buffers.dart original
    dart run tool/benchmark_buffers.dart optimized

Esta entrega contiene código fuente, recursos y Node privado. Omite cachés,
compilaciones y ZIP duplicados. Los paquetes anteriores siguen correspondiendo
a la versión anterior: todavía no se ha generado setup/standalone optimizado.

Para compilar esta copia:

    flutter pub get
    flutter build windows --release

El runtime Node se copia automáticamente a Release mediante CMake.
