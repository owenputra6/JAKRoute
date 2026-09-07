param([int]$Port = 8000)
$ErrorActionPreference = 'Stop'
$jakrouteRoot = Split-Path -Parent $PSScriptRoot
$jakrouteBackend = Join-Path $jakrouteRoot 'backend'
$jakroutePython = Join-Path $jakrouteBackend '.venv\Scripts\python.exe'
if (-not (Test-Path $jakroutePython)) { throw 'Jalankan scripts/jakroute_setup.ps1 dahulu.' }
Push-Location $jakrouteBackend
try { & $jakroutePython -m uvicorn main:app --host 0.0.0.0 --port $Port }
finally { Pop-Location }
