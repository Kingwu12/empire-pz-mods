# Opens each Workshop page the Empire pack needs in the Steam client (already signed in),
# one at a time, so all that is left for you is clicking Subscribe (or Unsubscribe on the last one).
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
    @('3452711271', 'UNSUBSCRIBE', 'OLD H.E.C.U. (two items with one mod id fight each other)')
)

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
