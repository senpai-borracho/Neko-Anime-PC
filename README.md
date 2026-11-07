<img width="1074" height="614" alt="Screenshot_1" src="https://github.com/user-attachments/assets/a1c14604-ec72-4b66-a111-9634c724f923" />

# Neko Anime PC

### Catálogo y reproductor de anime para Windows

Neko Anime PC es una aplicación gratuita de escritorio desarrollada con **Flutter y Dart**, con reproducción integrada mediante **libmpv / media_kit**.

Permite buscar anime, consultar fichas y episodios, y reproducir contenido desde distintas fuentes. Está orientada principalmente a usuarios hispanohablantes, con contenido en español latino y subtitulado según la disponibilidad de cada fuente.

**Plataforma:** Windows x64 (probado en Windows 11)  
**Estado:** Desarrollo activo  
**Desarrollador original:** SenpaiBorracho

---

## Características

### Catálogo y búsqueda

- Catálogo con portadas, sinopsis y fichas de anime.
- Búsqueda de títulos y consulta de episodios.
- Agrupación de resultados de distintas fuentes.
- Sección de episodios recientes y actualización periódica mientras la aplicación está abierta.

### Reproducción

- Reproductor integrado mediante libmpv / media_kit.
- Selección de servidores disponibles.
- Controles de reproducción, volumen y pantalla completa.
- Reanudación desde el último punto guardado.
- Historial de reproducción.
- La calidad depende de lo que ofrezca cada servidor.

### Biblioteca personal

- Mi lista y favoritos.
- Continuar viendo.
- Seguimiento de títulos: viendo, terminados, pendientes, en pausa y abandonados.
- Progreso guardado localmente.

### Integraciones y funciones experimentales

- Integración con MyAnimeList y AniList.
- Consulta de información mediante API.
- Sección de complementos en desarrollo, con compatibilidad experimental con formatos de terceros.
- Funciones de descarga en desarrollo.

Las integraciones y funciones experimentales pueden presentar errores o limitaciones.

---

## Instalación

Descarga la versión disponible en [Releases](https://github.com/senpai-borracho/Neko-Anime-PC/releases).

- **Instalador:** ejecútalo y sigue las instrucciones.
- **Versión portable:** extrae la carpeta completa; no separes el ejecutable de sus DLL ni de la carpeta `data`.

Para utilizar una versión compilada no necesitas instalar Flutter ni Dart.

---

## Compilar desde el código fuente

### Requisitos

- Windows con soporte para Flutter Desktop.
- Flutter SDK y Dart (incluido con Flutter).
- Visual Studio / Build Tools con herramientas de C++ para escritorio y Windows SDK.

Clona el repositorio:

```powershell
git clone https://github.com/senpai-borracho/Neko-Anime-PC.git
cd Neko-Anime-PC
```

Instala las dependencias y compila:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

La compilación se genera normalmente en:

```text
build\windows\x64\runner\Release\
```

Para empaquetar el instalador o la versión portable, revisa los scripts de `packaging/` si están incluidos en la versión descargada.

---

## Fuentes y complementos

Neko Anime PC consulta fuentes externas. Los servidores pueden cambiar de dirección, modificar sus métodos de reproducción o dejar de funcionar sin previo aviso.

El sistema de complementos está en desarrollo. La compatibilidad y disponibilidad dependen de cada complemento y de su fuente.

Neko no garantiza la disponibilidad de episodios, resoluciones ni servidores.

---

## Contribuciones

Se aceptan reportes de errores, propuestas de mejora y *pull requests*.

Puedes crear un **fork**, modificar el código y distribuir versiones derivadas conforme a la licencia del repositorio. deben conservarse los avisos legales de autoría y licencia que correspondan.

---

## Aviso legal

Neko Anime PC no aloja archivos de video ni administra los servidores de las fuentes externas. Es una herramienta de catálogo y reproducción independiente.

No está afiliada oficialmente a AniList, MyAnimeList ni a los proveedores de contenido. Los derechos de cada contenido pertenecen a sus titulares.

---

## Licencia

El proyecto se distribuye bajo **GNU GPL-3.0**. Consulta el archivo [`LICENSE`](LICENSE) para conocer las condiciones de uso, modificación y redistribución.

Las dependencias y componentes de terceros mantienen sus licencias correspondientes.

---

**SenpaiBorracho — Neko Anime PC**




