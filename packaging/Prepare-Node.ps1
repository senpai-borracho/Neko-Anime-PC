param([string]$Version='24.21.0')
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Version Node invalida'}
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$destination=Join-Path $project 'runtime\node'
$metadata=Join-Path $destination 'runtime.json'
if(Test-Path -LiteralPath $metadata){
  $saved=Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
  $binary=Join-Path $destination 'node.exe'
  if($saved.version -eq $Version -and (Test-Path -LiteralPath $binary) -and
      (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -eq $saved.binarySha256){
    Write-Host "Node incluido verificado: $Version"; return
  }
  throw 'Ya existe un runtime distinto o alterado; no se sobrescribe.'
}
$archiveName="node-v$Version-win-x64.zip"
$url="https://nodejs.org/dist/v$Version"
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('neko-node-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try{
  Invoke-WebRequest "$url/SHASUMS256.txt" -OutFile (Join-Path $temporary 'SHASUMS256.txt') -UseBasicParsing
  $checksums=Get-Content (Join-Path $temporary 'SHASUMS256.txt')
  $line=$checksums | Where-Object {$_ -match ('  '+[regex]::Escape($archiveName)+'$')}
  if(-not $line){throw 'Falta checksum oficial de Node'}
  $expected=($line -split '\s+')[0]
  $archive=Join-Path $temporary $archiveName
  Invoke-WebRequest "$url/$archiveName" -OutFile $archive -UseBasicParsing
  if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected){throw 'SHA-256 de Node incorrecto'}
  Expand-Archive -LiteralPath $archive -DestinationPath $temporary
  $source=Join-Path $temporary "node-v$Version-win-x64"
  New-Item -ItemType Directory -Path $destination -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $source 'node.exe') -Destination $destination
  Copy-Item -LiteralPath (Join-Path $source 'LICENSE') -Destination (Join-Path $destination 'LICENSE-Node.txt')
  Copy-Item -LiteralPath (Join-Path $temporary 'SHASUMS256.txt') -Destination $destination
  @{version=$Version;source="$url/$archiveName";archiveSha256=$expected;
    binarySha256=(Get-FileHash (Join-Path $destination 'node.exe')).Hash} |
    ConvertTo-Json | Set-Content -LiteralPath $metadata -Encoding UTF8
  Write-Host "Node $Version incluido y verificado."
}finally{
  $resolved=[IO.Path]::GetFullPath($temporary)
  $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path $resolved -Leaf).StartsWith('neko-node-')){
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
