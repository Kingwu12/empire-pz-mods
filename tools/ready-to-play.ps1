# One command to get Project Zomboid ready for the Empire run (B42.22.2).
#   .\tools\ready-to-play.ps1           stage everything, then print READY or the exact list of what is missing
#   .\tools\ready-to-play.ps1 -Check    only report, change nothing
# Run in PowerShell on the PC, game CLOSED. Safe to run again at any time (idempotent), and run it
# again after every Steam update of the game (Steam resets the JVM heap) and after subscribing to mods.
#
# What it does:
#   1. JVM heap: -Xms2048m -Xmx6144m (calls apply-jvm-tuning.ps1; Steam overwrites that file on updates).
#   2. Presets: copies docs\presets\*.txt into Zomboid\mods (the folder the in-game preset list reads).
#   3. Sandbox preset EmpirePlay: a copy of your empire.cfg with zombie population Low, because NPC mods
#      cost more the more zombies exist. Your empire.cfg is never touched.
#   4. Checks the chosen preset (default EmpirePlay) against what is installed: every mod present, every
#      required mod present and loaded BEFORE the mod that needs it, no mod id installed twice.
#   5. If everything checks out it makes EmpirePlay the default mod list for new games (backup kept).
# Needs nothing outside Windows PowerShell 5.1. Plain ASCII on purpose.
param(
    [switch]$Check,
    [string]$Preset = 'EmpirePlay',
    [string]$ZomboidDir = (Join-Path $env:USERPROFILE 'Zomboid'),
    [string]$GameVersion = '42.22.2'
)
$ErrorActionPreference = 'Stop'
$repo      = Split-Path $PSScriptRoot -Parent
$presetSrc = Join-Path $repo 'docs\presets'
$modsDir   = Join-Path $ZomboidDir 'mods'
$problems  = New-Object System.Collections.ArrayList
function Say($m)  { Write-Host $m }
function Bad($m)  { [void]$problems.Add($m); Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Good($m) { Write-Host "  [ok] $m" -ForegroundColor Green }

# ---- game + Steam library ------------------------------------------------------------------
$roots = @()
$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
if ($steam) {
    $roots += $steam
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $roots += ($_.Matches[0].Groups[1].Value -replace '\\\\', '\') }
    }
}
$lib = $null
foreach ($r in ($roots | Select-Object -Unique)) { if (Test-Path (Join-Path $r 'steamapps\common\ProjectZomboid\ProjectZomboid64.json')) { $lib = $r; break } }
Say "== Project Zomboid"
if (-not $lib) { throw "Could not find the game in any Steam library." }
$workshop = Join-Path $lib 'steamapps\workshop\content\108600'
Good "game in $lib"
if (Get-Process ProjectZomboid64 -ErrorAction SilentlyContinue) {
    if ($Check) { Bad "the game is running (fine for -Check, but close it before staging)" }
    else { throw "Project Zomboid is running. Close it, then run this again." }
}

# ---- 1. JVM heap ---------------------------------------------------------------------------
Say "== JVM heap"
$jvm = Join-Path $PSScriptRoot 'apply-jvm-tuning.ps1'
if ($Check) { & $jvm -Check } else { & $jvm }
$jsonPath = Join-Path $lib 'steamapps\common\ProjectZomboid\ProjectZomboid64.json'
if ((Get-Content -Raw $jsonPath) -notmatch '"-Xmx6144m"') { if ($Check) { Bad "heap is still stock (run without -Check to apply 6 GB)" } }
else { Good "heap is -Xms2048m -Xmx6144m" }

# ---- installed mods index ------------------------------------------------------------------
Say "== Installed mods"
$index = @{}        # mod id -> list of @{ Item=...; Req=@(...) }, built from the mod.info the game really uses
$recs  = New-Object System.Collections.ArrayList   # every mod.info found, before choosing one per mod
function Read-Mods($root, $tag) {
    if (-not (Test-Path -LiteralPath $root)) { return }
    $root = (Resolve-Path -LiteralPath $root).ProviderPath
    foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -Filter mod.info -File -ErrorAction SilentlyContinue)) {
        $id = $null; $req = @(); $inc = @()
        foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
            if ($line -match '^\s*id\s*=\s*(.+?)\s*$') { $id = $Matches[1] -replace '^\d+/', '' }
            elseif ($line -match '^\s*incompatible\s*=\s*(.+?)\s*$') {
                $inc += ($Matches[1] -split '[,;]' | ForEach-Object { ($_.Trim().TrimStart('\') -replace '^\d+/', '') } | Where-Object { $_ })
            }
            elseif ($line -match '^\s*require\s*=\s*(.+?)\s*$') {
                $req += ($Matches[1] -split '[,;]' | ForEach-Object { ($_.Trim().TrimStart('\') -replace '^\d+/', '') } | Where-Object { $_ })
            }
        }
        if (-not $id) { continue }
        $item = $tag
        if ($tag -eq 'workshop') { $item = 'workshop:' + ($f.FullName.Substring($root.Length).TrimStart('\') -split '\\')[0] }
        $parent = $f.Directory
        $ver = 'root'; $modDir = $parent.FullName
        if ($parent.Name -match '^(common|\d+(\.\d+)*)$') { $ver = $parent.Name; $modDir = $parent.Parent.FullName }
        [void]$recs.Add(@{ Id = $id; Item = $item; Req = $req; Inc = $inc; ModDir = $modDir; Ver = $ver })
    }
}
Read-Mods $workshop 'workshop'
Read-Mods $modsDir 'local'
Read-Mods (Join-Path $ZomboidDir 'Workshop') 'zomboid-workshop'
# A mod can ship several mod.info files (B41 root file, 42, 42.13, common). B42 reads the one in the highest
# version folder that is not newer than the game; mods with no version folder only have the root file.
$gameVer = [version]$GameVersion
function Select-Effective($group) {
    $best = $null; $bestV = $null
    foreach ($r in $group) {
        if ($r.Ver -match '^\d+(\.\d+)*$') {
            $vs = $r.Ver; if ($vs -notmatch '\.') { $vs = $vs + '.0' }
            $v = [version]$vs
            if (($v -le $gameVer) -and (($null -eq $bestV) -or ($v -gt $bestV))) { $best = $r; $bestV = $v }
        }
    }
    if ($best) { return $best }
    foreach ($r in $group) { if ($r.Ver -eq 'root') { return $r } }
    foreach ($r in $group) { if ($r.Ver -eq 'common') { return $r } }
    return $group[0]
}
foreach ($g in ($recs | Group-Object { $_.ModDir })) {
    $r = Select-Effective @($g.Group)
    if (-not $index.ContainsKey($r.Id)) { $index[$r.Id] = New-Object System.Collections.ArrayList }
    [void]$index[$r.Id].Add(@{ Item = $r.Item; Req = $r.Req; Inc = $r.Inc })
}
Good ("{0} mod ids found (Steam Workshop + local mods)" -f $index.Count)
# Workshop items we swapped for a maintained one (26 Nov audit): old item id -> new item id
$replacedItems = @{ '3452711271' = '3737864976' }   # H.E.C.U. (B41 listing) -> H.E.C.U. B42.20, same mod id
foreach ($old in $replacedItems.Keys) {
    $new = $replacedItems[$old]
    if ((Test-Path (Join-Path $workshop $old)) -and -not (Test-Path (Join-Path $workshop $new))) {
        Bad "H.E.C.U.: only the old Workshop item is installed. Subscribe https://steamcommunity.com/sharedfiles/filedetails/?id=$new then unsubscribe https://steamcommunity.com/sharedfiles/filedetails/?id=$old"
    }
}
$dupes = @($index.Keys | Where-Object { @($index[$_] | ForEach-Object { $_.Item } | Select-Object -Unique).Count -gt 1 })

# Workshop ids for the "subscribe to these" list: audit table + the mods added on 26 Nov
$wsId = @{ VB_CommonSense = '3750253491'; EvolvingTraitsWorld = '2914075159'; H_E_C_U = '3737864976'; Bandits2 = '3268487204';
           NPCCrew = '3800132623'; KI5PerfPatch = '3808100388'; KI5GeneralFixes = '3789366983';
           # Louisville Shipping Port (the port map with the shipping containers) and the tile packs it needs
           SimonMDLVHarbor = '3149613879'; simonMDsTiles = '2852704777'; 'Diederiks Tile Palooza' = '2337452747'; DylansTiles = '2599752664';
           melos_tiles_for_miles_pack = '2879745353'; tkTiles_01 = '2384329562'; UnofficialMappersCommunityTilePack = '3628736763';
           MoodleFramework = '3396446795';   # Moodle Framework: required by Evolving Traits World
           ammomaker = '2788256295';         # Ammo Maker: craft gunpowder and ammo from scratch (Guns of Marz has its own API table for it)
           # Guns of Marz stack (27 Nov 2026; replaces Guns of 93)
           SWMG = '3722064198'; GunsOfMarz = '3722134990'; HeavyOrdnance = '3802070967';
           ReloadBackAgain = '3837229266'; GunHitFix42_22 = '3837999415' }
$auditCsv = Join-Path $presetSrc 'pack-audit.csv'
if (Test-Path $auditCsv) { foreach ($r in (Import-Csv $auditCsv)) { if (-not $wsId.ContainsKey($r.mod_id)) { $wsId[$r.mod_id] = $r.workshop_id } } }

function Read-Preset($file) {
    @([System.IO.File]::ReadAllLines($file) | ForEach-Object { if ($_ -match '^\s*mod\s*=\s*(.+?),?\s*$') { $Matches[1].Trim() } })
}
# NPC Crew needs Bandits2 even before either is installed
$knownReq = @{ NPCCrew = @('Bandits2') }

function Test-Preset($name, $isTarget) {
    $file = Join-Path $presetSrc ($name + '.txt')
    if (-not (Test-Path $file)) { if ($isTarget) { Bad "preset $name.txt not found in docs\presets" }; return $null }
    $mods = Read-Preset $file
    Say ("== Preset {0} ({1} mods)" -f $name, $mods.Count)
    $pos = @{}; for ($i = 0; $i -lt $mods.Count; $i++) { $pos[$mods[$i]] = $i }
    $missing = @($mods | Where-Object { -not $index.ContainsKey($_) })
    $local = New-Object System.Collections.ArrayList
    foreach ($m in $mods) {
        if (-not $index.ContainsKey($m)) { continue }
        $reqs = @($index[$m] | ForEach-Object { $_.Req } | Select-Object -Unique)
        if ($knownReq.ContainsKey($m)) { $reqs += $knownReq[$m] }
        foreach ($x in @($index[$m] | ForEach-Object { $_.Inc } | Select-Object -Unique)) {
            if ($pos.ContainsKey($x)) { [void]$local.Add("$m is marked incompatible with $x (the game will refuse to enable one of them)") }
        }
        foreach ($r in $reqs) {
            if (-not $pos.ContainsKey($r)) { [void]$local.Add("$m needs $r, which is not in the preset") }
            elseif ($pos[$r] -gt $pos[$m]) { [void]$local.Add("$m is listed before $r, which it needs") }
        }
    }
    $presetDupes = @($dupes | Where-Object { $pos.ContainsKey($_) })
    $ok = $true
    if ($missing.Count -gt 0) {
        $ok = $false
        $msg = "$($missing.Count) mod(s) not installed. Subscribe on Steam, then run this again:"
        if ($isTarget) { Bad $msg } else { Say "  [--] $msg" }
        foreach ($m in $missing) {
            Say ("         {0}  https://steamcommunity.com/sharedfiles/filedetails/?id={1}" -f $m, $wsId[$m])
            # the Workshop item is on disk but its mod id is not the one the preset names: show what it really provides
            if ($wsId[$m] -and (Test-Path -LiteralPath (Join-Path $workshop $wsId[$m]))) {
                $have = @($index.Keys | Where-Object { @($index[$_] | Where-Object { $_.Item -eq ('workshop:' + $wsId[$m]) }).Count -gt 0 })
                Say ("           item {0} is installed but has no mod id '{1}'. Ids it provides: {2}" -f $wsId[$m], $m, ($have -join ', '))
            }
        }
    }
    foreach ($d in $presetDupes) {
        $ok = $false
        $items = ($index[$d] | ForEach-Object { $_.Item } | Select-Object -Unique) -join ' and '
        $msg = "mod id $d is installed twice ($items). Unsubscribe the OLD Workshop item so only one remains."
        if ($isTarget) { Bad $msg } else { Say "  [--] $msg" }
    }
    foreach ($l in $local) { $ok = $false; if ($isTarget) { Bad $l } else { Say "  [--] $l" } }
    if ($ok) { Good "all mods installed, every requirement present and in order" }
    return $ok
}

$state = @{}
foreach ($f in (Get-ChildItem $presetSrc -Filter *.txt -ErrorAction SilentlyContinue)) {
    $n = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $state[$n] = Test-Preset $n ($n -eq $Preset)
}

# ---- 2. stage presets + 3. sandbox preset --------------------------------------------------
if (-not $Check) {
    Say "== Staging"
    foreach ($f in (Get-ChildItem $presetSrc -Filter *.txt)) {
        $dest = Join-Path $modsDir $f.Name
        if ((Test-Path $dest) -and ((Get-FileHash $dest).Hash -ne (Get-FileHash $f.FullName).Hash)) {
            $bak = $dest + '.bak-empire'
            if (-not (Test-Path $bak)) { Copy-Item $dest $bak }
        }
        Copy-Item $f.FullName $dest -Force
    }
    Good "presets copied to $modsDir"
    $sbDir = Join-Path $ZomboidDir 'Sandbox Presets'
    $src = Join-Path $sbDir 'empire.cfg'; $dst = Join-Path $sbDir 'EmpirePlay.cfg'
    if (-not (Test-Path $src)) { Bad "Sandbox Presets\empire.cfg not found, so no EmpirePlay sandbox preset was made (pick settings by hand)" }
    elseif (Test-Path $dst) { Good "sandbox preset EmpirePlay already exists (left as is)" }
    else {
        $t = [System.IO.File]::ReadAllText($src)
        $t2 = [regex]::Replace($t, '(?m)^Zombies=\d+', 'Zombies=5')
        [System.IO.File]::WriteAllText($dst, $t2, (New-Object System.Text.UTF8Encoding($false)))
        Good "sandbox preset EmpirePlay created (your empire.cfg with zombie population Low)"
    }
    # mod options for the EmpirePlay sandbox preset (NPCs, traits): written idempotently from docs\presets\EmpirePlay-mod-options.cfg
    $optFile = Join-Path $presetSrc 'EmpirePlay-mod-options.cfg'
    if ((Test-Path $dst) -and (Test-Path $optFile)) {
        $t = [System.IO.File]::ReadAllText($dst); $orig = $t; $note = ''
        foreach ($line in [System.IO.File]::ReadAllLines($optFile)) {
            if ($line -match '^\s*$') { $note = ''; continue }
            if ($line -match '^\s*#') { $note = $note + $line + "`r`n"; continue }
            if ($line -match '^([A-Za-z0-9_.]+)=(.*)$') {
                $k = $Matches[1]; $v = $Matches[2]
                $re = '(?m)^' + [regex]::Escape($k) + '=[^\r\n]*'
                if ([regex]::IsMatch($t, $re)) { $t = [regex]::Replace($t, $re, ($k + '=' + $v)) }
                else { $t = $t.TrimEnd() + "`r`n`r`n" + $note + $k + '=' + $v + "`r`n" }
                $note = ''
            }
        }
        if ($t -ne $orig) {
            if (-not (Test-Path ($dst + '.bak-empire'))) { Copy-Item $dst ($dst + '.bak-empire') }
            [System.IO.File]::WriteAllText($dst, $t, (New-Object System.Text.UTF8Encoding($false)))
            Good "mod options written to the EmpirePlay sandbox preset (no hostile bandits, crew cap, no dynamic traits)"
        } else { Good "mod options already in the EmpirePlay sandbox preset" }
    }
    if ($state[$Preset] -eq $true) {
        $def = Join-Path $modsDir 'default.txt'
        if ((Test-Path $def) -and (-not (Test-Path ($def + '.bak-empire')))) { Copy-Item $def ($def + '.bak-empire') }
        Copy-Item (Join-Path $presetSrc ($Preset + '.txt')) $def -Force
        Good "$Preset is now the default mod list for new games"
    }
}

# ---- verdict -------------------------------------------------------------------------------
Say ""
if ($problems.Count -eq 0 -and $state[$Preset] -eq $true) {
    Write-Host "READY. In the game: New Game > Mods > preset $Preset (already ticked), Sandbox > preset EmpirePlay." -ForegroundColor Green
    Say "First run: press Numpad 9 once and look for FAIL lines in console.txt ([EmpireTest])."
} else {
    Write-Host ("NOT READY YET: {0} thing(s) above need fixing." -f $problems.Count) -ForegroundColor Yellow
    Say "Fix them (usually: subscribe on Steam and wait for the download), then run this script again."
}
