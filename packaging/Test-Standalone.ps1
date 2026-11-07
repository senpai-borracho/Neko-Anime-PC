param([Parameter(Mandatory=$true)][string]$Directory)
$ErrorActionPreference='Stop'
$Directory=[IO.Path]::GetFullPath($Directory)
$report=Join-Path (Split-Path $Directory -Parent) 'runtime-verification.json'
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=Join-Path $Directory 'Neko_Anime_0.3.1_Stable.exe'
$start.Arguments='--verify-bundled-runtime "'+$report+'"'
$start.WorkingDirectory=$Directory
$start.UseShellExecute=$false
$start.CreateNoWindow=$true
$start.EnvironmentVariables['PATH']=Join-Path $env:SystemRoot 'System32'
$start.EnvironmentVariables.Remove('NODE_OPTIONS')
$start.EnvironmentVariables.Remove('NODE_PATH')
$process=[Diagnostics.Process]::Start($start)
if(-not $process.WaitForExit(90000)){$process.Kill();throw 'Timeout de verificacion standalone.'}
if($process.ExitCode -ne 0){throw ('Fallo standalone: '+(Get-Content -LiteralPath $report -Raw -ErrorAction SilentlyContinue))}
$result=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
if($result.ok -ne $true -or $result.pathUsedForNode -ne $false){throw 'Resultado de verificacion invalido.'}
$expected=[IO.Path]::GetFullPath((Join-Path $Directory 'runtime\node\node.exe'))
if([IO.Path]::GetFullPath($result.node.path) -ne $expected){throw 'Se utilizo Node externo.'}
Write-Host ('Standalone verificado sin Node en PATH: '+$result.node.version)
