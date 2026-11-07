param(
 [Parameter(Mandatory=$true)][string]$InnoCompiler,
 [Parameter(Mandatory=$true)][string]$CrtDirectory,
 [Parameter(Mandatory=$true)][string]$Destination,
 [string]$BuildDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('NekoPC-'+[guid]::NewGuid().ToString('N').Substring(0,8)))
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Destination=[IO.Path]::GetFullPath($Destination)
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
if(-not(Test-Path -LiteralPath $InnoCompiler)){throw 'Falta el compilador Inno Setup.'}
if(-not(Test-Path -LiteralPath $CrtDirectory)){throw 'Falta el runtime Microsoft Visual C++.'}
if(Test-Path -LiteralPath $Destination){throw 'Usa una carpeta de entrega nueva; no se borran entregas existentes.'}
if(Test-Path -LiteralPath $BuildDirectory){throw 'Usa una carpeta de compilacion nueva.'}
if($BuildDirectory.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'La compilacion temporal debe estar fuera del proyecto.'}
& (Join-Path $PSScriptRoot 'Prepare-Node.ps1')
New-Item -ItemType Directory -Path $BuildDirectory | Out-Null
robocopy $project $BuildDirectory /E /XD build .dart_tool ephemeral .git work /XF '*.zip' '*.log' .flutter-plugins-dependencies /NFL /NDL /NJH /NJS
if($LASTEXITCODE -ge 8){throw 'Fallo la copia de compilacion.'}
Push-Location $BuildDirectory
try{
 & flutter.bat pub get
 if(-not(Test-Path '.flutter-plugins-dependencies')){throw 'No se pudieron resolver las dependencias.'}
 $metadata=Get-Content '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
 $links=Join-Path $BuildDirectory 'windows\flutter\ephemeral\.plugin_symlinks'
 New-Item -ItemType Directory -Path $links -Force | Out-Null
 foreach($plugin in $metadata.plugins.windows){
   $link=Join-Path $links $plugin.name
   if(-not(Test-Path -LiteralPath $link)){New-Item -ItemType Junction -Path $link -Target $plugin.path | Out-Null}
 }
 & flutter.bat pub get
 if($LASTEXITCODE -ne 0){throw 'No se pudieron resolver las dependencias.'}
 & flutter.bat build windows --release --no-pub
 if($LASTEXITCODE -ne 0){throw 'La compilacion fallo.'}
 $release=Join-Path $BuildDirectory 'build\windows\x64\runner\Release'
 if(-not(Test-Path (Join-Path $release 'runtime\node\node.exe'))){throw 'El ejecutable no tiene el runtime incluido.'}
 $portable=Join-Path $Destination 'Neko_Anime_0.3.1_Stable'
 New-Item -ItemType Directory -Path $Destination | Out-Null
 Copy-Item -LiteralPath $release -Destination $portable -Recurse
 Get-ChildItem -LiteralPath $CrtDirectory -Filter '*.dll' -File | Copy-Item -Destination $portable
 Copy-Item -LiteralPath 'LICENSE','README-STABLE.md' -Destination $portable
 Copy-Item -LiteralPath 'licenses' -Destination $portable -Recurse
 'Abre Neko_Anime_0.3.1_Stable.exe. No requiere instalar Node.js, npm, Flutter ni Visual Studio. Conserva toda la carpeta, incluido runtime/node.' | Set-Content -LiteralPath (Join-Path $portable 'LEEME-STANDALONE.txt') -Encoding UTF8
 & (Join-Path $PSScriptRoot 'Test-Standalone.ps1') -Directory $portable
 Compress-Archive -LiteralPath $portable -DestinationPath (Join-Path $Destination 'Neko_Anime_0.3.1_Stable_Standalone.zip')
 & $InnoCompiler /Q "/DPayload=$portable" "/DDestination=$Destination" (Join-Path $PSScriptRoot 'NekoPlayer.iss')
 if($LASTEXITCODE -ne 0){throw 'La construccion del instalador fallo.'}
 Get-ChildItem -LiteralPath $Destination -File | Get-FileHash -Algorithm SHA256 | Format-Table -AutoSize | Out-String | Set-Content (Join-Path $Destination 'SHA256.txt')
 Write-Host "Entregas: $Destination"
}finally{Pop-Location}
