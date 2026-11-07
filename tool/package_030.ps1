$ErrorActionPreference='Stop'
$root='C:\Users\Francisco\Documents\Codex\npc'
$outputs='C:\Users\Francisco\Documents\Codex\2026-10-28\files-mentioned-by-the-user-bastardo\outputs'
$dest=Join-Path $outputs 'NekoPlayerPC_0.3.0'
if(Test-Path -LiteralPath $dest){throw 'La entrega ya existe.'}
New-Item -ItemType Directory -Path $dest | Out-Null
$app=Join-Path $dest 'NekoPlayerPC'
Copy-Item -LiteralPath "$root\build\windows\x64\runner\Release" -Destination $app -Recurse
Get-ChildItem -LiteralPath 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Redist\MSVC\14.51.36231\x64\Microsoft.VC145.CRT' -Filter '*.dll' -File | Copy-Item -Destination $app
foreach($name in @('LICENSE','README-NEKO-PC.md','CAMBIOS-0.1.1.md','CAMBIOS-0.2.0.md','CAMBIOS-0.2.1.md','CAMBIOS-0.2.2.md','CAMBIOS-0.3.0.md','licenses')){Copy-Item -LiteralPath (Join-Path $root $name) -Destination $app -Recurse}
$stage=Join-Path $dest 'Codigo'
& robocopy $root $stage /E /XD build .dart_tool .idea ephemeral fixtures .git tool /XF '*.iml' .flutter-plugins-dependencies /NFL /NDL /NJH /NJS /NP | Out-Null
if($LASTEXITCODE -gt 7){throw 'Error al copiar fuentes.'}
New-Item -ItemType Directory -Path "$stage\tool" -Force | Out-Null
Get-ChildItem -LiteralPath "$root\tool" -File | Where-Object {$_.Extension -in '.dart','.ps1','.mp4'} | Copy-Item -Destination "$stage\tool"
Compress-Archive -LiteralPath $stage -DestinationPath "$dest\Neko_Player_PC_Codigo_0.3.0.zip"
Compress-Archive -LiteralPath $app -DestinationPath "$dest\Neko_Player_PC_Portable_0.3.0.zip"
& 'C:\Users\Francisco\Documents\Codex\2026-10-28\files-mentioned-by-the-user-kiltro\work\inno\ISCC.exe' /Q "/DPayload=$app" "/DDestination=$dest" "$root\packaging\NekoPlayer.iss"
if($LASTEXITCODE -ne 0){throw 'Error al construir instalador.'}
& robocopy $stage (Join-Path $outputs 'NekoPlayerPC') /E /NFL /NDL /NJH /NJS /NP | Out-Null
if($LASTEXITCODE -gt 7){throw 'Error al actualizar copia de fuentes.'}
@"
# Verificación de Neko Player PC 0.3.0 — 2026-10-29

- Flutter analyze: sin incidencias. 28 pruebas automáticas aprobadas.
- Prueba nativa con clip local: Volver al anime se oculta tras inactividad, reaparece al mover el cursor y permite retornar desde ventana y pantalla completa.
- Video configurado con BoxFit.contain y centrado, sin recortar ni deformar.
- Eliminación persistente de Seguir viendo/Historial sin borrar favoritos ni estado de seguimiento, comprobada con almacenamiento aislado.
- Frases decorativas eliminadas.
- Listados públicos comprobados: 27 publicaciones distintas; AnimeAV1 20, TioAnime 20 y AnimeFLV 24 antes de eliminar duplicados. Una ficha por fuente confirmó el episodio anunciado.
- Nuevos episodios general, sin depender de favoritos: al iniciar, cada 15 minutos mientras está abierto y bajo demanda. Pruebas de analizadores, deduplicación, filtros y conservación ante fallos temporales.
- Proveedores/resolutores (catalog.dart), playback_config.dart y playback_health.dart idénticos por SHA256 a 0.2.0. Binario libmpv sin cambios.
- La verificación de novedades consultó solo portadas y fichas públicas. No se abrieron servidores de video. Servidores y resolutores intactos.
- Instalador generado; no se instaló sobre la aplicación del usuario.
"@ | Set-Content "$dest\VERIFICACION.md" -Encoding UTF8
Get-ChildItem -LiteralPath $dest -File | Where-Object {$_.Extension -in '.exe','.zip'} | Get-FileHash -Algorithm SHA256 | Format-Table -AutoSize | Out-String -Width 240 | Set-Content "$dest\SHA256.txt"
Get-ChildItem -LiteralPath $dest -File | Select-Object Name,Length



