# Empaquetado lite

Node.js 24.21.0 x64 se distribuye de forma privada en runtime/node/node.exe.
No hace falta instalar Node, npm ni modificar el PATH del equipo destino.
Se verifico el ZIP oficial de nodejs.org mediante su SHA-256; incluye la licencia.

Anix y Nuvio arrancan este binario por ruta absoluta relativa al ejecutable de Neko.
En desarrollo, Flutter/Dart utiliza el mismo runtime en la carpeta del proyecto.
No hay alternativa a Node global y se excluyen NODE_OPTIONS y NODE_PATH heredados.
Solo se modifica el arranque del puente Anix; extractores y contratos conservados.

Windows/CMakeLists.txt copia el runtime a Release en cada compilacion.
packaging/Prepare-Node.ps1 prepara/verifica la version fijada para futuras compilaciones.
packaging/Build-Windows.ps1 crea el portable y el setup con el runtime y las DLL de Visual C++.
La compilacion se realiza en una carpeta temporal corta para evitar problemas de rutas.
No se reemplaza el original ni se instala el setup durante las pruebas.

La comprobacion --verify-bundled-runtime ejecuta el binario compilado con un PATH sin Node:
- confirma el executablePath privado de Node;
- carga las 38 entradas de Anix y obtiene los ajustes de Latanime;
- ejecuta getStreams de una fixture Nuvio;
- no instala repositorios ni descarga videos.
El resultado se guarda fuera del payload para no distribuir rutas personales.
Tambien se comprobo visualmente el arranque del standalone y el catalogo de Anix con portadas.
Las 46 pruebas del proyecto pasaron.

Para distribuir, entrega el ZIP completo o el setup. El EXE solo no es portable.
El setup todavia no esta firmado con un certificado de editor.
