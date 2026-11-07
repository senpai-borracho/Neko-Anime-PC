# Neko PC — Anix, catálogo visual experimental

Esta entrega modifica **solo** `lib/anix_page.dart` y `lib/anix_engine.dart` respecto al ZIP experimental previo. `lib/catalog.dart` y los extractores Dart originales no se modificaron.

## Funciones
- Pestaña Extensiones → Anix con cuadrícula de portadas, carga paginada y búsqueda.
- Las portadas y los títulos de inicio proceden de **Jikan/MyAnimeList**; son una referencia visual, **no** un inventario verificado de los proveedores. Al pulsar una portada se busca el título en las extensiones activadas.
- Filtro automático por idioma `es` declarado en el manifiesto. En el manifiesto suministrado: Latanime, MonosChinos, AnimeParadise y AniZone. Las fuentes Seanime no ejecutables se excluyen.
- Búsqueda sucesiva en todas las fuentes seleccionadas, resultados identificados por proveedor, lista de episodios y reproductor existente con selector de servidor.
- Importación manual de un manifiesto JSON compatible con Anix mediante URL HTTPS. No hay actualizaciones automáticas de código remoto. El manifiesto importado es temporal para la sesión; al reiniciar se vuelve al paquete incluido.
- Fallos de una fuente no detienen las búsquedas en las demás.

## Límites y seguridad
- **Sin compilar ni probar en Windows en este entorno:** hay que ejecutar `flutter analyze`, `flutter test` y `flutter run -d windows` en la máquina de desarrollo.
- Node.js 22+ debe estar instalado y disponible en PATH.
- `node:vm` **no es una sandbox segura** para ejecutar código JavaScript de terceros. Solo importar manifiestos de fuentes confiables; el programa no ofrece aislamiento de procesos/permisos por extensión. No es adecuado distribuir importación arbitraria a usuarios finales sin endurecer la seguridad.
- Las extensiones pueden fallar por cambios del sitio, falta de ID de AniList, servidores caídos, bloqueos geográficos, etc. El buscador no garantiza correspondencia exacta del título.
- Jikan puede imponer límites de peticiones; la carga de portadas requiere Internet.
- El manifiesto de Anix no proporciona necesariamente un catálogo navegable. El catálogo visual de Jikan es independiente de la disponibilidad de episodios.
- La importación exige un documento JSON con campo `plugins`, no una página web HTML o enlace de Google Drive sin descarga JSON directa.

## Comandos en PowerShell, dentro de Codigo
```powershell
node --version
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Prueba aislada del puente JavaScript:
```powershell
node tool/test_anix_worker.cjs
```
