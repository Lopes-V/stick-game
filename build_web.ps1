[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot

function Find-Godot {
    $candidates = @()
    $bundledGodot = Join-Path $projectRoot 'tools\godot\Godot_v4.7.1-stable_win64.exe'
    if (Test-Path -LiteralPath $bundledGodot) { $candidates += $bundledGodot }
    if ($env:GODOT_EXE) { $candidates += $env:GODOT_EXE }
    foreach ($commandName in @('godot4', 'godot', 'Godot.exe')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    foreach ($searchRoot in @($projectRoot, "$projectRoot\tools", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:LOCALAPPDATA\Programs")) {
        if (Test-Path -LiteralPath $searchRoot) {
            $found = Get-ChildItem -LiteralPath $searchRoot -Filter 'Godot*.exe' -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '_console|mono' } |
                Select-Object -First 1
            if ($found) { $candidates += $found.FullName }
        }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw 'Godot 4.x not found. Restore tools\godot or put Godot in PATH/set GODOT_EXE.'
}

$godot = Find-Godot
Write-Host "Using Godot: $godot"
& $godot --headless --path $projectRoot --export-release 'Web' "$projectRoot\web_build\index.html"
if ($LASTEXITCODE -ne 0) { throw "Godot Web export failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath "$projectRoot\web_build\index.html")) { throw 'Godot reported success but web_build/index.html is missing.' }
$pythonCommand = Get-Command 'python' -ErrorAction SilentlyContinue
if (-not $pythonCommand -or $pythonCommand.Source -match 'WindowsApps') {
    throw 'Python 3 not found; unable to prepare the Web build for LAN HTTP.'
}
& $pythonCommand.Source "$projectRoot\tools\patch_web_build.py" "$projectRoot\web_build\index.html"
if ($LASTEXITCODE -ne 0) { throw "LAN Web patch failed with exit code $LASTEXITCODE." }
Write-Host 'Web build ready: web_build/index.html' -ForegroundColor Green
