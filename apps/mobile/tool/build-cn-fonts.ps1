# Build the subset CN web fonts the app loads via @font-face.
#
#   assets/fonts/app-cn-base.woff2 — first-paint subset, target <= 250 KB.
#   assets/fonts/app-cn-ext.woff2  — lazy-loaded extension for GB 2312.
#
# Run locally before `flutter run -d chrome` / `flutter build web`.
# Idempotent — re-uses cached source font and venv when nothing has changed.
#
# Usage: powershell -File apps/mobile/tool/build-cn-fonts.ps1
$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

$CacheDir   = ".dart_tool/cn_fonts"
$AssetsDir  = "assets/fonts"
$VenvDir    = Join-Path $CacheDir "venv"
$SourceDir  = Join-Path $CacheDir "src"
$UnicodeDir = Join-Path $CacheDir "unicodes"

# Source font: Noto Sans SC variable (OFL). Pinned by SHA-256.
$NotoUrl    = if ($env:NOTO_URL) { $env:NOTO_URL } else { "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf" }
$NotoSha256 = if ($env:NOTO_SHA256) { $env:NOTO_SHA256 } else { "a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da" }
$SourceFont = Join-Path $SourceDir "NotoSansSC[wght].ttf"
$SourceStamp = Join-Path $SourceDir ".sha256"

$BaseOut = Join-Path $AssetsDir "app-cn-base.woff2"
$ExtOut  = Join-Path $AssetsDir "app-cn-ext.woff2"
$BaseBudgetBytes = if ($env:BASE_BUDGET_BYTES) { [int]$env:BASE_BUDGET_BYTES } else { 256000 }

New-Item -ItemType Directory -Force -Path $CacheDir, $AssetsDir, $SourceDir, $UnicodeDir | Out-Null

# 1. Provision a Python venv with fonttools[woff].
$Pyftsubset = Join-Path $VenvDir "Scripts/pyftsubset.exe"
$Python     = Join-Path $VenvDir "Scripts/python.exe"
if (-not (Test-Path $Pyftsubset)) {
    Write-Host "creating fonttools venv at $VenvDir"
    python -m venv $VenvDir
    & $Python -m pip install --quiet --upgrade pip
    & $Python -m pip install --quiet "fonttools[woff]>=4.50,<5"
}

# 2. Fetch the source font and verify its SHA-256.
function Get-FileSha256($Path) {
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

$currentSha = ""
if (Test-Path $SourceFont) {
    $currentSha = Get-FileSha256 $SourceFont
}
if ($currentSha -ne $NotoSha256) {
    Write-Host "fetching Noto Sans SC variable from $NotoUrl"
    Invoke-WebRequest -Uri $NotoUrl -OutFile $SourceFont -UseBasicParsing
    $currentSha = Get-FileSha256 $SourceFont
    if ($currentSha -ne $NotoSha256) {
        Write-Error "source font sha256 mismatch`n  expected: $NotoSha256`n  got:      $currentSha`n  Upstream changed; verify the new file then update NotoSha256 in this script."
        exit 1
    }
    $NotoSha256 | Set-Content -Path $SourceStamp -NoNewline
} else {
    Write-Host "source font already cached (sha256 $NotoSha256)"
}

# 3. Build the unicode lists from the live codebase.
$BaseUnicodes = Join-Path $UnicodeDir "base.txt"
$ExtUnicodes  = Join-Path $UnicodeDir "ext.txt"
& $Python tool/cn_font_chars.py `
    --lib-root lib `
    --out-base $BaseUnicodes `
    --out-ext $ExtUnicodes

# 4. Subset the source font into base + ext woff2 outputs.
$commonArgs = @(
    "--flavor=woff2"
    "--with-zopfli"
    "--layout-features=*"
    "--glyph-names"
    "--symbol-cmap"
    "--legacy-cmap"
    "--notdef-glyph"
    "--notdef-outline"
    "--recommended-glyphs"
    "--name-legacy"
    "--drop-tables+=DSIG"
    "--no-hinting"
)

Write-Host "subsetting -> $BaseOut"
& $Pyftsubset $SourceFont --unicodes-file=$BaseUnicodes --output-file=$BaseOut @commonArgs

Write-Host "subsetting -> $ExtOut"
& $Pyftsubset $SourceFont --unicodes-file=$ExtUnicodes --output-file=$ExtOut @commonArgs

# 5. Enforce the first-paint size budget.
$baseSize = (Get-Item $BaseOut).Length
$extSize  = (Get-Item $ExtOut).Length
Write-Host "produced $BaseOut ($baseSize bytes), $ExtOut ($extSize bytes)"
if ($baseSize -gt $BaseBudgetBytes) {
    Write-Error "$BaseOut is $baseSize bytes, exceeds budget $BaseBudgetBytes (250 KB). Trim ALWAYS_INCLUDE in tool/cn_font_chars.py, or move chars to the ext tier."
    exit 1
}
Write-Host "ok — base subset within 250 KB budget"
