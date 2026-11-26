# Re-apply Project Zomboid heap tuning after a Steam update (Steam overwrites ProjectZomboid64.json).
# Run in PowerShell:   .\apply-jvm-tuning.ps1            (auto-finds the game, prints what it did)
#                      .\apply-jvm-tuning.ps1 -Check     (only report, change nothing)
#                      .\apply-jvm-tuning.ps1 -Path C:\x\ProjectZomboid64.json -XmxMB 8192
# Safe to run twice (idempotent), keeps a one-time backup next to the file, touches only the
# -Xms/-Xmx lines. Everything else (ZGC, native-access flags) stays stock. Close the game first.
# 26 Nov 2026 (B42.22.2): stock is -Xmx3072m; a ~100+ mod pack wants more headroom. 6 GB is
# the default here: more heap does not mean more FPS (bigger GC pauses, less left for the OS).
param(
    [string]$Path,
    [int]$XmsMB = 2048,
    [int]$XmxMB = 6144,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $roots = @()
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $roots += $steam
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object {
                $roots += ($_.Matches[0].Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    foreach ($r in ($roots | Select-Object -Unique)) {
        $cand = Join-Path $r 'steamapps\common\ProjectZomboid\ProjectZomboid64.json'
        if (Test-Path $cand) { $Path = $cand; break }
    }
}
if (-not $Path -or -not (Test-Path $Path)) { throw "ProjectZomboid64.json not found. Pass -Path <file>." }

$text = [System.IO.File]::ReadAllText($Path)
$cur = [regex]::Match($text, '"-Xmx(\d+)([mMgG])"')
if (-not $cur.Success) { throw "No -Xmx entry in $Path (file layout changed?). Not touching it." }
$xms = '"-Xms{0}m"' -f $XmsMB
$xmx = '"-Xmx{0}m"' -f $XmxMB
"File:    $Path"
"Current: " + $cur.Value + $(if ($text -match '"-Xms\d+[mMgG]"') { '  ' + [regex]::Match($text, '"-Xms\d+[mMgG]"').Value } else { '  (no -Xms)' })
"Target:  $xms $xmx"
if ($Check) { return }

$new = [regex]::Replace($text, '"-Xms\d+[mMgG]",?\s*', '')           # drop any old -Xms line
$new = [regex]::Replace($new, '"-Xmx\d+[mMgG]"', $xmx)                # set -Xmx
$new = $new -replace [regex]::Escape($xmx), ($xms + ",`r`n`t`t" + $xmx)  # -Xms right before -Xmx
if ($new -eq $text) { "Already tuned. Nothing to do."; return }

$bak = $Path + '.bak-empire'
if (-not (Test-Path $bak)) { Copy-Item $Path $bak }
[System.IO.File]::WriteAllText($Path, $new)
# sanity: still valid JSON
try { $null = $new | ConvertFrom-Json } catch { Copy-Item $bak $Path -Force; throw "Result was not valid JSON; restored the backup." }
"Done. Backup: $bak"
