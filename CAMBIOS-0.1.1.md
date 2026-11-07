# Neko Player PC 0.1.1 — corrección de reproducción

- Los mensajes de diagnóstico de libmpv ya no se interpretan automáticamente como fallos fatales.
- El aviso requiere una interrupción confirmada y ausencia de avance; desaparece si el video se recupera.
- Una pausa, el buffering normal y el final natural no disparan la pantalla de error.
- El inicio conserva un margen de 40 segundos, salvo errores explícitos al obtener el enlace.
- Timeout nativo de red: 20 segundos, igual que Android, en lugar de los 5 predeterminados de media_kit.
- Caché configurada a 64 MiB, como la base Android utilizada.
- Reintentar conserva la última posición disponible y vuelve a resolver el mismo servidor.
- Se mantienen las fuentes, resolutores y dependencias. El binario libmpv no se reemplaza ni se modifica.

Comprobaciones:
- flutter analyze sin incidencias.
- 12 pruebas unitarias aprobadas: cinco de catálogo y siete del seguimiento de reproducción.
- Dark Machine: The Animation, episodio 1, AnimeAV1/MP4Upload SUB: más de 36 s de avance, 1920×1080, duración 1370 s. Se recibió el diagnóstico real "Could not open codec." y el aviso permaneció oculto mientras el video avanzaba.
- Mismo episodio en JKAnime: más de 36 s de avance, 1920×1080, sin aviso falso ni errores nativos registrados durante ese intervalo.
- Se inyectó además un diagnóstico recuperable durante la reproducción para comprobar que no la tapa.
- La prueba no equivale a ver el episodio completo ni garantiza todos los servidores o condiciones de red.

Actualización: cerrar Neko Player y ejecutar el instalador 0.1.1. Se conserva el mismo identificador de instalación y la ubicación de Mi lista/historial. No se ejecutó una instalación sobre la aplicación del usuario durante estas pruebas.