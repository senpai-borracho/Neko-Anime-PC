# Neko — Nueva versión

Código fuente correspondiente al instalador `Neko_Player_PC_Setup.exe` que está en la carpeta superior. Incluye la mascota del mockup con cuatro poses e interacciones, Acerca de en Ajustes, créditos y licencias, barra lateral compacta y ficha de anime dentro del panel derecho con un único desplazamiento.

Desarrollador: SenpaiBorracho.

## Compilar en Windows

Requiere Flutter compatible con Dart 3.13.7 y Visual Studio Build Tools con desarrollo de escritorio C++ y Windows SDK. Ejecutar desde esta carpeta:

```powershell
flutter pub get
flutter test
flutter build windows --release
```

El ejecutable queda en `build/windows/x64/runner/Release/neko_player_pc.exe`. Mantener las DLL y la carpeta `data` junto al ejecutable.

Se incluyen código, recursos, configuración de Windows, pruebas, `pubspec.lock`, licencias y archivos de empaquetado. Se excluyen cachés, compilaciones y cargas de instaladores anteriores. Los scripts históricos de empaquetado pueden contener rutas de la máquina original; `packaging/NekoPlayer.iss` recibe las rutas mediante los parámetros `Payload` y `Destination`.

Validación de la versión entregada: 44 pruebas aprobadas y compilación Release correcta. `SHA256-FUENTES.txt` registra las huellas de los 107 archivos copiados y verificados contra el proyecto original.
