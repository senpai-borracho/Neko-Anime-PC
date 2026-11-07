# Neko PC — rama experimental de extensiones Anix

**Copia independiente de Neko Player PC 0.3.0.** La versión original no se modifica. Esta entrega es código fuente, no un EXE compilado ni un motor completamente validado en Windows.

## Qué se implementó

- Opción **Extensiones** en la barra lateral.
- Importación local del catálogo `anix-extensions.json` suministrado: 38 entradas, 33 proveedores JavaScript y 5 manifiestos externos Seanime (visibles pero deshabilitados).
- Puente Flutter/Dart ↔ proceso Node.js para `getSettings`, `search`, `findEpisodes` y `findEpisodeServer`.
- Interfaz de selección de proveedor, búsqueda, sub/dub, selección de anime, episodios y servidor, reproducción con `media_kit` / libmpv y encabezados HTTP retornados por el proveedor.
- Manejo de errores y tiempos de espera. Sin descarga/ejecución automática de actualizaciones de extensiones.

## Ejecutar en Windows

1. Instala **Node.js 22+** y comprueba `node --version` en PowerShell.
2. Instala Flutter y los componentes de Visual Studio para escritorio, como indica `README.md`.
3. En la carpeta `Codigo` ejecuta:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

En Neko, abre **Extensiones**. Selecciona un proveedor JavaScript, escribe un título, busca, elige el anime, el episodio y el servidor. Para probar únicamente el protocolo JS sin Flutter:

```powershell
'{"id":1,"op":"settings","plugin":"anizone"}' | node tool/anix_worker.cjs assets/extensions/anix-extensions.json
```

## Limitaciones importantes

- **No se ha compilado ni ejecutado Flutter en este entorno** (no hay Flutter/Dart instalados aquí). No se certifica la reproducción real ni que los 33 proveedores funcionen en vivo.
- Los 33 proveedores **sí se cargaron en Node y respondieron a `getSettings`** en la comprobación local. Esto no prueba las búsquedas ni los enlaces de reproducción.
- Los 5 proveedores con manifiestos Seanime requieren un intérprete distinto y no están implementados.
- Node.js debe estar instalado y disponible en `PATH`; aún no se integra al instalador. El motor Node es un puente funcional, **no el QuickJS embebido final**.
- Las fuentes pueden requerir otros formatos de parámetros, cabeceras, subtítulos, utilidades del host, autenticación o fallar si sus sitios cambian.
- Se toma la primera fuente HTTPS devuelta por el proveedor; aún no hay selección de calidad, pistas de subtítulos externas ni descarga de episodios en esta pantalla.
- El módulo `node:vm` **no es una barrera de seguridad** para ejecutar código no confiable. Ejecuta exclusivamente extensiones de confianza. No importes paquetes JS arbitrarios.
- Se necesita conexión para consultar los sitios de los proveedores; no se eluden captchas ni DRM.
- El bundle Anix se incluye como material aportado para interoperabilidad. Revisa las licencias y permisos de redistribución de cada extensión antes de publicar un instalador.

## Arquitectura

`lib/anix_page.dart` (interfaz) → `lib/anix_engine.dart` (mensajes JSON por stdin/stdout) → `assets/extensions/anix_worker.cjs` (adaptador JS) → extensión Anix local → `media_kit` (reproducción).

**Siguiente validación:** ejecutar `flutter analyze`, corregir cualquier diferencia de API de las versiones locales, probar búsqueda/episodios/servidor con uno o dos proveedores, después ampliar compatibilidad y sustituir el puente Node por un runtime embebido aislado si se desea distribuir sin dependencias externas.
