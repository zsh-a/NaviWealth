# Build the self-hosted Latin webfont subsets — Inter (4 weights) + Outfit
# Bold. Mirrors apps/mobile/tool/build-latin-fonts.sh for Windows. Outputs
# are gitignored build artifacts.
#
# Usage: powershell -File apps/mobile/tool/build-latin-fonts.ps1
$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

$CacheDir  = ".dart_tool/latin_fonts"
$AssetsDir = "assets/fonts"
$VenvDir   = Join-Path $CacheDir "venv"
$SourceDir = Join-Path $CacheDir "src"

$InterUrl    = if ($env:INTER_URL) { $env:INTER_URL } else { "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf" }
$InterSha256 = if ($env:INTER_SHA256) { $env:INTER_SHA256 } else { "" }
$InterFont   = Join-Path $SourceDir "Inter[opsz,wght].ttf"

$OutfitUrl    = if ($env:OUTFIT_URL) { $env:OUTFIT_URL } else { "https://raw.githubusercontent.com/google/fonts/main/ofl/outfit/Outfit%5Bwght%5D.ttf" }
$OutfitSha256 = if ($env:OUTFIT_SHA256) { $env:OUTFIT_SHA256 } else { "" }
$OutfitFont   = Join-Path $SourceDir "Outfit[wght].ttf"

$TotalBudgetBytes = if ($env:TOTAL_BUDGET_BYTES) { [int]$env:TOTAL_BUDGET_BYTES } else { 204800 }

New-Item -ItemType Directory -Force -Path $CacheDir, $AssetsDir, $SourceDir | Out-Null

$Pyftsubset = Join-Path $VenvDir "Scripts/pyftsubset.exe"
$Python     = Join-Path $VenvDir "Scripts/python.exe"
if (-not (Test-Path $Pyftsubset)) {
    Write-Host "creating fonttools venv at $VenvDir"
    python -m venv $VenvDir
    & $Python -m pip install --quiet --upgrade pip
    & $Python -m pip install --quiet "fonttools[woff]>=4.50,<5"
}

function Get-Sha256($path) {
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

function Fetch-Pinned($url, $out, $pin) {
    if ((Test-Path $out) -and ($pin -ne "")) {
        if ((Get-Sha256 $out) -eq $pin.ToLower()) { return }
    }
    Write-Host "fetching $(Split-Path $out -Leaf) from $url"
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    if ($pin -ne "") {
        $got = Get-Sha256 $out
        if ($got -ne $pin.ToLower()) {
            Write-Error "$(Split-Path $out -Leaf) sha256 mismatch: expected $pin, got $got"
            exit 1
        }
    }
}

Fetch-Pinned $InterUrl  $InterFont  $InterSha256
Fetch-Pinned $OutfitUrl $OutfitFont $OutfitSha256

$LatinUnicodes = "U+0020-007E,U+00A0-00FF,U+0100-017F,U+02B9-02FF,U+2000-206F,U+2070-209F,U+20A0-20CF,U+2190-21FF,U+2200-22FF,U+25A0-25FF"

$CommonArgs = @(
    "--flavor=woff2",
    "--with-zopfli",
    "--layout-features=*",
    "--glyph-names",
    "--no-hinting",
    "--notdef-glyph",
    "--notdef-outline",
    "--recommended-glyphs",
    "--name-legacy",
    "--drop-tables+=DSIG"
)

function Instance-And-Subset($source, $axis, $out, $label) {
    $tmp = [System.IO.Path]::GetTempFileName() + ".ttf"
    Write-Host "instancing $label ($axis) -> static TTF"
    & $Python -m fontTools.varLib.instancer --output=$tmp --quiet $source $axis.Split(' ')
    Write-Host "subsetting $label -> $out"
    & $Pyftsubset $tmp "--unicodes=$LatinUnicodes" "--output-file=$out" @CommonArgs
    Remove-Item -Force $tmp
}

Instance-And-Subset $InterFont "wght=400 opsz=14" (Join-Path $AssetsDir "inter-regular.woff2")  "Inter Regular"
Instance-And-Subset $InterFont "wght=500 opsz=14" (Join-Path $AssetsDir "inter-medium.woff2")   "Inter Medium"
Instance-And-Subset $InterFont "wght=600 opsz=14" (Join-Path $AssetsDir "inter-semibold.woff2") "Inter SemiBold"
Instance-And-Subset $InterFont "wght=700 opsz=14" (Join-Path $AssetsDir "inter-bold.woff2")     "Inter Bold"
Instance-And-Subset $OutfitFont "wght=700"        (Join-Path $AssetsDir "outfit-bold.woff2")    "Outfit Bold"

$total = 0
$files = @(
    (Join-Path $AssetsDir "inter-regular.woff2"),
    (Join-Path $AssetsDir "inter-medium.woff2"),
    (Join-Path $AssetsDir "inter-semibold.woff2"),
    (Join-Path $AssetsDir "inter-bold.woff2"),
    (Join-Path $AssetsDir "outfit-bold.woff2")
)
foreach ($f in $files) {
    $size = (Get-Item $f).Length
    Write-Host ("  {0,-40} {1,8} bytes" -f (Split-Path $f -Leaf), $size)
    $total += $size
}
Write-Host "total subset size: $total bytes (budget: $TotalBudgetBytes)"
if ($total -gt $TotalBudgetBytes) {
    Write-Error "Latin subsets total $total bytes, exceeds budget $TotalBudgetBytes (200 KB)"
    exit 1
}
Write-Host "ok - Latin subsets within 200 KB budget"
