param(
  [string]$Destination = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
  [string]$InnoCompiler = (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
  [string]$CrtDirectory = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Redist\MSVC\14.51.36231\x64\Microsoft.VC145.CRT'
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$Destination = [IO.Path]::GetFullPath($Destination)
$build = Join-Path ([IO.Path]::GetTempPath()) ('NekoSetup-' + [guid]::NewGuid().ToString('N').Substring(0,8))
if (-not (Test-Path -LiteralPath $InnoCompiler)) { throw 'No se encuentra Inno Setup 6.' }
if (-not (Test-Path -LiteralPath $CrtDirectory)) { throw 'No se encuentra el runtime de Visual C++.' }
& (Join-Path $PSScriptRoot 'Prepare-Node.ps1')
New-Item -ItemType Directory -Path $build | Out-Null
robocopy $project $build /E /XD build .dart_tool ephemeral .git work /XF '*.zip' '*.log' .flutter-plugins-dependencies /NFL /NDL /NJH /NJS
if ($LASTEXITCODE -ge 8) { throw 'Fallo la copia temporal.' }
Push-Location $build
try {
  & flutter.bat pub get
  if (-not (Test-Path '.flutter-plugins-dependencies')) { throw 'No se resolvieron las dependencias.' }
  $metadata = Get-Content '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
  $links = Join-Path $build 'windows\flutter\ephemeral\.plugin_symlinks'
  New-Item -ItemType Directory -Path $links -Force | Out-Null
  foreach ($plugin in $metadata.plugins.windows) {
    $link = Join-Path $links $plugin.name
    if (-not (Test-Path -LiteralPath $link)) { New-Item -ItemType Junction -Path $link -Target $plugin.path | Out-Null }
  }
  & flutter.bat pub get
  if ($LASTEXITCODE -ne 0) { throw 'No se resolvieron las dependencias.' }
  & flutter.bat build windows --release --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Fallo la compilacion de Windows.' }
  $release = Join-Path $build 'build\windows\x64\runner\Release'
  if (-not (Test-Path (Join-Path $release 'runtime\node\node.exe'))) { throw 'Falta el runtime incluido.' }
  Get-ChildItem -LiteralPath $CrtDirectory -Filter '*.dll' -File | Copy-Item -Destination $release -Force
  Copy-Item -LiteralPath 'LICENSE','README-STABLE.md' -Destination $release -Force
  Copy-Item -LiteralPath 'licenses' -Destination $release -Recurse -Force
  & (Join-Path $PSScriptRoot 'Test-Standalone.ps1') -Directory $release
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  & $InnoCompiler /Q "/DPayload=$release" "/DDestination=$Destination" (Join-Path $PSScriptRoot 'NekoPlayer.iss')
  if ($LASTEXITCODE -ne 0) { throw 'Fallo la creacion del Setup.' }
  Write-Host ('Setup listo: ' + (Join-Path $Destination 'Neko_Anime_0.3.1_Stable_Setup.exe'))
} finally { Pop-Location }
