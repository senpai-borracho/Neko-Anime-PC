# Pruebas MonosChinos — 2026-10-29

Se agregaron dos entradas separadas en la navegación: MonosChinos1 y MonosChinos2. Cada una abre su propia fuente; también se puede cambiar entre ellas con los selectores superiores.

## Correcciones

- MonosChinos1: catálogo /animes, búsqueda buscar y paginación pag; episodios mediante ajax_pagination con acc=episodes; servidores mediante acc=opt y data-player en base64.
- MonosChinos2: catálogo /animes, búsqueda /buscar?q= y paginación p; episodios y servidores publicados en el HTML.
- Se comprueba el dominio completo de los enlaces del catálogo.
- Las páginas HTML de servidores se resuelven antes de abrir el reproductor. Se reutiliza ProviderClient sin modificar catalog.dart. VOE aparece primero; los servidores sin extractor compatible muestran un error y permiten elegir otro.
- Se envían Referer y cookies al video. Los errores de reproducción son visibles.
- Una carga adicional fallida permite reintentar la misma página. La búsqueda activa se conserva al paginar.
- Las respuestas de verificación de navegador muestran un mensaje explícito.

## Verificación reproducible

```powershell
flutter test test --no-pub
flutter test integration_test/monoschinos_live_test.dart -d windows --no-pub
dart analyze lib/main.dart lib/monoschinos_client.dart lib/monoschinos_page.dart integration_test/monoschinos_live_test.dart
flutter build windows --release --no-pub
```

La prueba nativa verifica catálogo, búsqueda, una segunda página distinta, episodios y reproducción real con VOE: duración mayor a un minuto, imagen decodificada y posición de reproducción superior a 1,5 segundos. Guarda los resultados por fuente en tool/MonosChinos1-verification.json y tool/MonosChinos2-verification.json.

No todos los servidores están soportados. La disponibilidad de las webs y sus verificaciones puede cambiar; no se desactivan validaciones TLS ni se ejecutan scripts remotos para extraer los enlaces.

## Resultados obtenidos

- Analizador de los archivos modificados: sin incidencias.
- Pruebas existentes: 28 aprobadas.
- MonosChinos1: 30 tarjetas en página 1, 29 en página 2; búsqueda correcta; 4 episodios y 8 servidores. VOE reprodujo a 1280×720, duración 1422 s, posición comprobada 2833 ms.
- MonosChinos2: 24 tarjetas en página 1, 23 en página 2; búsqueda correcta; 1 episodio y 8 servidores en la ficha probada. VOE reprodujo a 1920×1080, duración 1538 s, posición comprobada 2168 ms.
- El primer intento de la prueba nativa detectó el parámetro incorrecto de página en MonosChinos2; se corrigió a p y la repetición pasó.
