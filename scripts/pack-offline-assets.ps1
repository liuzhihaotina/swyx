# =============================================================
# Pack offline assets (run on an ONLINE machine that HAS the models)
# Windows PowerShell. ASCII-only to avoid encoding issues on PS 5.1.
#
# Packs the gitignored-but-required runtime assets so an offline
# server can restore them with restore-offline-assets.sh:
#   - DeepDOC OCR/layout/table ONNX models + updown_concat_xgb.model
#   - Chinese tokenizer dict huqie.txt.trie / huqie.txt
#   - nltk_data (trimmed)
#
# Usage (from project root):
#   powershell -ExecutionPolicy Bypass -File scripts/pack-offline-assets.ps1
# Output: offline-assets.zip in project root
# =============================================================

$ErrorActionPreference = "Stop"

# Project root = parent of this script's dir
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Write-Host "Project root: $root"

$backend = Join-Path $root "backend"

# Paths (relative to backend/) to include, keeping structure.
# For nltk_data we only include the resources the code actually uses,
# so the bundle stays small (full nltk_data on disk is ~780MB).
$items = @(
    "app/service/core/rag/res/deepdoc",
    "app/service/core/rag/res/huqie.txt.trie",
    "app/service/core/rag/res/huqie.txt",
    "nltk_data/corpora/wordnet.zip",
    "nltk_data/corpora/omw-1.4.zip",
    "nltk_data/corpora/stopwords.zip",
    "nltk_data/corpora/words.zip",
    "nltk_data/tokenizers/punkt.zip",
    "nltk_data/tokenizers/punkt_tab.zip",
    "nltk_data/taggers/averaged_perceptron_tagger.zip",
    "nltk_data/taggers/averaged_perceptron_tagger_eng.zip",
    "nltk_data/taggers/universal_tagset.zip"
)


# Verify presence
$missing = @()
foreach ($it in $items) {
    $p = Join-Path $backend $it
    if (-not (Test-Path $p)) { $missing += $it }
}
if ($missing.Count -gt 0) {
    Write-Host "[ERROR] Missing assets (run a parse once on an online machine to auto-download models):"
    $missing | ForEach-Object { Write-Host "   - $_" }
    exit 1
}

# Stage into temp so archive paths start with backend/
$staging = Join-Path $env:TEMP ("offline-assets-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    foreach ($it in $items) {
        $src = Join-Path $backend $it
        $dst = Join-Path $staging (Join-Path "backend" $it)
        $dstParent = Split-Path -Parent $dst
        New-Item -ItemType Directory -Force -Path $dstParent | Out-Null
        Write-Host "  + backend/$it"
        Copy-Item -Recurse -Force $src $dst
    }

    $zip = Join-Path $root "offline-assets.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Write-Host "Compressing to $zip ..."
    Compress-Archive -Path (Join-Path $staging "backend") -DestinationPath $zip -CompressionLevel Optimal

    $sizeMB = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host ""
    Write-Host "[OK] Packed: offline-assets.zip ($sizeMB MB)"
    Write-Host "Next: copy offline-assets.zip to the offline server project root, then run:"
    Write-Host "   bash scripts/restore-offline-assets.sh"
}
finally {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}
