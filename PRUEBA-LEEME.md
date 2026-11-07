# Prueba: código del instalador (30-oct 12:17)

Mismo código que el instalador que sí reproduce. Todos los archivos de lib/ coinciden
con el paquete original (hash SHA-256) salvo main.dart, sidebar_mascot.dart y
startup_overlay.dart, que son los del paquete Cambios_Logo_Bienvenida.

Sirve para saber si el problema de reproducción está en el código nuevo o en cómo se compila.

    flutter clean
    flutter pub get
    flutter build windows --release

Ejecutar build\windows\x64\runner\Release\neko_player_pc.exe
