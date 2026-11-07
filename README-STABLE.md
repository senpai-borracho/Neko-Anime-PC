# Neko Anime 0.3.1 Stable

Versión: 0.3.1, compilación 7. Esta es la copia optimizada del proyecto.

El ejecutable se llama Neko_Anime_0.3.1_Stable.exe.
Conserva la carpeta completa del standalone: contiene datos, bibliotecas y el runtime Node incluido.
No requiere instalar Node.js, npm, Flutter ni Visual Studio para utilizarlo.

Las funciones, los colores y los motores se conservan. Se ha actualizado el nombre
visible, la ventana, Acerca de, los metadatos Windows y los nombres de empaquetado.
La carpeta interna de datos NekoPlayerPC se conserva para mantener biblioteca,
historial, configuración y descargas anteriores.

Compilar el código:

    flutter pub get
    flutter build windows --release

El ejecutable y sus archivos quedan en build/windows/x64/runner/Release.
Los scripts packaging/Build-Windows.ps1 y packaging/Test-Standalone.ps1 ya usan
el nombre nuevo. Las próximas entregas serán:

    Neko_Anime_0.3.1_Stable_Setup.exe
    Neko_Anime_0.3.1_Stable_Standalone.zip

Todavía no se han generado esos paquetes con esta versión: los paquetes anteriores
no se renombraron porque corresponden a una compilación anterior.
