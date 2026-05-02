# Materialize the two web assets drift's WasmDatabase needs at runtime:
#
#   apps/mobile/web/sqlite3.wasm        — sqlite3 compiled to WebAssembly
#   apps/mobile/web/drift_worker.dart.js — drift's worker entrypoint, JS-compiled
#
# Run locally before `flutter run -d chrome` / `flutter build web`.
# Idempotent — re-running only re-fetches if the version changed.
#
# Usage: powershell -File apps/mobile/tool/setup-drift-web.ps1
$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

$WebDir     = "web"
$CacheDir   = ".dart_tool/drift_web"
$WasmPath   = Join-Path $WebDir "sqlite3.wasm"
$WorkerSrc  = Join-Path $WebDir "drift_worker.dart"
$WorkerOut  = Join-Path $WebDir "drift_worker.dart.js"

New-Item -ItemType Directory -Force -Path $CacheDir, $WebDir | Out-Null

# Resolve the sqlite3 dart package version from pubspec.lock.
$SqliteVersion = $null
if (Test-Path pubspec.lock) {
    $inPkg = $false
    foreach ($line in Get-Content pubspec.lock) {
        if ($line -match '^\s+sqlite3:') { $inPkg = $true; continue }
        if ($inPkg -and $line -match '^\s+version:\s*["]?(.+?)["]?\s*$') {
            $SqliteVersion = $Matches[1]
            break
        }
    }
}
if (-not $SqliteVersion) { $SqliteVersion = "2.9.4" }

$WasmUrl = "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SqliteVersion/sqlite3.wasm"

# Re-download only when the pinned version changed.
$WasmStamp = Join-Path $CacheDir "sqlite3.wasm.version"
$needFetch = $false
if (-not (Test-Path $WasmPath)) {
    $needFetch = $true
} else {
    $savedVersion = if (Test-Path $WasmStamp) { Get-Content $WasmStamp -Raw } else { "" }
    if ($savedVersion.Trim() -ne $SqliteVersion) { $needFetch = $true }
}

if ($needFetch) {
    Write-Host "fetching sqlite3.wasm $SqliteVersion -> $WasmPath"
    Invoke-WebRequest -Uri $WasmUrl -OutFile $WasmPath -UseBasicParsing
    $SqliteVersion | Set-Content -Path $WasmStamp -NoNewline
} else {
    Write-Host "sqlite3.wasm $SqliteVersion already present"
}

if (-not (Test-Path $WorkerSrc)) {
    Write-Error "$WorkerSrc missing — drift worker source is required"
    exit 1
}

Write-Host "compiling $WorkerSrc -> $WorkerOut"
dart compile js -O4 -o $WorkerOut $WorkerSrc
# `dart compile js` also emits a .deps file we don't need shipped.
Remove-Item -Force -ErrorAction SilentlyContinue "$WorkerOut.deps"

Write-Host "drift web assets ready in $WebDir/"
