# Opens each Workshop page the Empire pack still needs in the Steam client (already signed in),
# one at a time, so all that is left for you is clicking Subscribe (or Unsubscribe). Pages for items
# already on this PC are skipped, and an Unsubscribe page only opens while the item is still installed,
# so after the first run this only shows what is left.
#   .\tools\open-workshop-pages.ps1          opens page 1, waits for Enter, opens page 2, ...
#   .\tools\open-workshop-pages.ps1 -List    only prints the list, opens nothing
# Run it in PowerShell on the PC. Afterwards: .\tools\ready-to-play.ps1
param([switch]$List)

$items = @(
    @('3149613879', 'Subscribe',   'Louisville Shipping Port (the port map with the shipping containers)'),
    @('2852704777', 'Subscribe',   "Simon MD's Tiles (tile pack the port needs, 809 MB)"),
    @('2879745353', 'Subscribe',   'Melos Tiles for Miles Tilepack (tile pack, 1.6 GB)'),
    @('3628736763', 'Subscribe',   'Community Tile Pack (tile pack, 220 MB)'),
    @('2337452747', 'Subscribe',   'Daddy Dirkie dirks tiles (tile pack, 64 MB)'),
    @('2599752664', 'Subscribe',   "Dylan's Tile Pack (tile pack, 71 MB)"),
    @('2384329562', 'Subscribe',   "throttlekitty's tiles (tile pack, 10 MB)"),
    @('3750253491', 'Subscribe',   'Common Sense B42.20+ (VB_CommonSense)'),
    @('2914075159', 'Subscribe',   'Evolving Traits World'),
    @('3268487204', 'Subscribe',   'Bandits NPC'),
    @('3800132623', 'Subscribe',   'NPC Crew'),
    @('3737864976', 'Subscribe',   'H.E.C.U. B42.20 (replaces the old H.E.C.U.)'),
    @('3808100388', 'Subscribe',   'KI5 Vehicle Performance Patch'),
    @('3789366983', 'Subscribe',   'KI5 General Fixes'),
    @('3452711271', 'UNSUBSCRIBE', 'OLD H.E.C.U. (two items with one mod id fight each other)'),
    # 27 Nov 2026: the gun stack moved from Guns of 93 to Guns of Marz (docs/PLAY-READY.md "Guns")
    @('3722064198', 'Subscribe',   'Gunworks Framework (mod id SWMG; Guns of Marz needs it)'),
    @('3722134990', 'Subscribe',   'Guns of Marz (mod ids GunsOfMarz and MarzGuns; enable only GunsOfMarz, the new version)'),
    @('3802070967', 'Subscribe',   'Gunworks Heavy Ordnance (RPG-7 rocket launcher; needs the Framework)'),
    @('3837229266', 'Subscribe',   'Reload Your Weapons Again (fixes reload errors in ALICE-pack style gear)'),
    @('3837999415', 'Subscribe',   'Gun Hit Fix 42.22 (bullets that connect always do damage)')
    # Guns of 93 (3183820077) and its Ammo Loot Drop (3404184088) stay installed as a fallback until Guns of Marz has been played; unsubscribe them after.
)

# Skip what is already done: find the Workshop folder in the Steam libraries.
$workshopDirs = @()
$steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
if ($steamPath) {
    $libs = @($steamPath)
    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $libs += ($_.Matches[0].Groups[1].Value -replace '\\\\', '\') }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        $w = Join-Path $l 'steamapps\workshop\content\108600'
        if (Test-Path $w) { $workshopDirs += $w }
    }
}
function Installed($id) { foreach ($w in $workshopDirs) { if (Test-Path (Join-Path $w $id)) { return $true } }; return $false }
if ($workshopDirs.Count -gt 0) {
    $items = @($items | Where-Object { if ($_[1] -eq 'Subscribe') { -not (Installed $_[0]) } else { Installed $_[0] } })
    if ($items.Count -eq 0) { Write-Host 'Nothing left to click: every item is already as it should be.'; return }
}

$n = 0
foreach ($it in $items) {
    $n++
    $line = ('{0,2}/{1}  {2,-11} {3}  (item {4})' -f $n, $items.Count, $it[1], $it[2], $it[0])
    if ($List) { Write-Host $line; continue }
    Write-Host $line
    Start-Process ('steam://url/CommunityFilePage/' + $it[0])
    [void](Read-Host '      Click it in Steam, then press Enter for the next')
}
if (-not $List) { Write-Host 'Done. Wait for Steam to finish downloading, then run .\tools\ready-to-play.ps1' }
