$ErrorActionPreference = 'Stop'
$jakrouteRoot = Split-Path -Parent $PSScriptRoot
$jakrouteBackend = Join-Path $jakrouteRoot 'backend'
$jakroutePython = Join-Path $jakrouteBackend '.venv\Scripts\python.exe'
if (-not (Test-Path $jakroutePython)) {
    & python -m venv (Join-Path $jakrouteBackend '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Gagal membuat venv. Gunakan Python 3.12.' }
}
& $jakroutePython -m pip install -r (Join-Path $jakrouteBackend 'requirements-dev.txt')
if ($LASTEXITCODE -ne 0) { throw 'Instalasi dependency gagal.' }
if (-not (Test-Path (Join-Path $jakrouteBackend '.env'))) {
    Copy-Item (Join-Path $jakrouteBackend '.env.example') (Join-Path $jakrouteBackend '.env')
}
Push-Location $jakrouteBackend
try {
    & $jakroutePython -m pytest -q
    if ($LASTEXITCODE -ne 0) { throw 'Pengujian belum lolos.' }
} finally { Pop-Location }
Write-Host 'Setup dan testing selesai. Jalankan scripts/jakroute_run.ps1 di terminal backend.'
