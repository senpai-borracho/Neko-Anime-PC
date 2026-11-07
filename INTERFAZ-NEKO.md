# Interfaz Neko — 2026-10-29

Cambios de presentación, sin modificaciones en los clientes de catálogo ni los resolutores de video.

- Navegación compacta con accesos por fuente, lista, historial, novedades y ajustes.
- Cabecera, portadas y tarjetas más pequeñas; tema oscuro y colores por fuente.
- Inicio con destacado, novedades reales y panel de progreso cuando hay espacio.
- Filtros combinables de fuente y formato, orden alfabético y restablecimiento. Conteos del catálogo cargado; no simulan totales del sitio.
- La fuente seleccionada se refleja en la tarjeta y al abrir la ficha. Se conserva la identidad original para favoritos y seguimiento.
- MonosChinos1 y MonosChinos2 conservan clientes independientes y comparten la ventana, la navegación lateral y las tarjetas de Neko. Su vista se mantiene separada en monoschinos_catalog_view.dart.
- Avisos de servidor flotantes de hasta 420 px, con cierre, duración reducida y texto sin prefijos técnicos.
- El diseño ocupa el área disponible de la ventana. En ventanas pequeñas se retira el panel lateral y los filtros se abren desde la cabecera.
- Las capturas de pruebas usan superficies fijas; el ejecutable Release usa el tamaño real de la ventana y no depende de integration_test.

Validación: 33 pruebas unitarias/de widgets aprobadas antes del ajuste final de etiquetas y accesos; las 5 pruebas de interfaz se repitieron después y pasaron. Revisión nativa de Windows aprobada. Analizador de los archivos modificados: sin incidencias. Las huellas de catalog.dart, monoschinos_client.dart, playback_config.dart y playback_health.dart coinciden con el respaldo anterior al rediseño.

No se inventan géneros, temporadas ni estadísticas de popularidad que los datos actuales del catálogo no suministran.


Comprobación final en el ejecutable Release real: abierto desde Codigo y revisado en ventana normal y maximizada mediante captura nativa. La interfaz ocupa todo el cliente, sin bandas negras laterales; el panel de filtros se adapta al ancho. El ejecutable se dejó abierto maximizado para revisión.

Versión 0.3.1: 34 pruebas aprobadas, incluidas navegación de ambos catálogos sin abrir rutas adicionales y reutilización de las tarjetas de Neko. Los clientes y resolutores conservan sus huellas originales.


Filtro de formato completado: Todos, Series / TV, Películas, OVA, ONA, Especiales y Sin especificar, con conteos de los datos cargados para la fuente seleccionada. Se normalizan etiquetas explícitas (Movie, película, TV, OVAs, etc.). La etiqueta genérica Anime no demuestra que sea una serie y se muestra en Sin especificar. No se agregaron géneros ni se modificaron extractores. Siete pruebas de interfaz aprobadas después de este ajuste; analizador sin incidencias.


Fichas de MonosChinos1 y MonosChinos2 rediseñadas en monoschinos_detail_view.dart: portada, título de presentación sin prefijos publicitarios, fuente, cantidad de episodios y botón para comenzar. Tarjetas de capítulos con número y acción de reproducción; búsqueda numérica exacta y orden ascendente/descendente. Encabezado visible durante la carga y ante errores, con reintento. Tres pruebas visuales/funcionales aprobadas en 480 y 1280 px; analizador sin incidencias. Se conservan los objetos de episodio originales y los callbacks existentes de servidores y reproducción. Clientes y configuración de reproducción verificados por SHA256 sin cambios.


Simplificación final: eliminado el panel lateral de filtros, el filtro de formato y los controles redundantes de la cabecera. Fuentes y orden alfabético permanecen en una barra superior adaptable. Acerca de muestra 0.3.1, los sitios de MonosChinos1 y MonosChinos2 y la atribución de la integración AnimeAV1 a FxxMorgan/anime1v-api (MIT).

Sinopsis de MonosChinos recuperada del texto narrativo de sus propias fichas mediante monoschinos_synopsis.dart, separado de los clientes existentes. Carga y reintento independientes de los episodios. Comprobación real por comandos: Cyberpunk en MonosChinos1 y Watashi no Shiawase na Kekkon S2 en MonosChinos2 devolvieron sus sinopsis. Suite existente de 38 pruebas aprobada y 3 pruebas específicas nuevas aprobadas; analizador sin incidencias. Esta revisión se realizó sin control de escritorio ni apertura de la aplicación.
