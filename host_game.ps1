[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [switch]$HealthCheckOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$config = Get-Content -LiteralPath "$projectRoot\server_config.json" -Raw | ConvertFrom-Json
$gameProcess = $null
$httpProcess = $null

function Find-Godot {
    $candidates = @()
    # Use the real executable, not the console wrapper. Stopping the wrapper can
    # otherwise leave the headless child process listening after the launcher exits.
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
                Where-Object { $_.Name -notmatch 'mono' } |
                Sort-Object @{ Expression = { $_.Name -match '_console' }; Descending = $false } |
                Select-Object -First 1
            if ($found) { $candidates += $found.FullName }
        }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw 'Godot 4.x not found. Restore tools\godot or put Godot in PATH/set GODOT_EXE.'
}

function Find-Python {
    foreach ($commandName in @('python', 'python3', 'py')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command -and $command.Source -notmatch 'WindowsApps') { return $command.Source }
    }
    throw 'Python 3 not found. Install Python or serve web_build with another static HTTP server.'
}

function Get-LanAddress {
    try {
        $udp = [System.Net.Sockets.UdpClient]::new()
        $udp.Connect('8.8.8.8', 53)
        $address = ([System.Net.IPEndPoint]$udp.Client.LocalEndPoint).Address.ToString()
        $udp.Dispose()
        if ($address -and $address -notmatch '^127\.') { return $address }
    } catch {}
    $fallback = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
        Sort-Object InterfaceMetric |
        Select-Object -First 1
    if ($fallback) { return $fallback.IPAddress }
    return '127.0.0.1'
}

function Test-OwnedTcpPort([int]$Port, [int]$ProcessId) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -eq $ProcessId } |
        Select-Object -First 1
    return $null -ne $listener
}

try {
    $python = Find-Python
    if (-not (Test-Path -LiteralPath "$projectRoot\web_build\index.html")) {
        Write-Host 'Web build missing; building it now...'
        & "$projectRoot\build_web.ps1"
    }
    & $python "$projectRoot\tools\patch_web_build.py" "$projectRoot\web_build\index.html"
    if ($LASTEXITCODE -ne 0) { throw "LAN Web patch failed with exit code $LASTEXITCODE." }

    $godot = Find-Godot
    $logDir = "$projectRoot\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $quotedProjectRoot = '"' + $projectRoot.Replace('"', '\"') + '"'
    $gameArguments = "--headless --path $quotedProjectRoot -- --server"
    $httpScript = '"' + "$projectRoot\tools\lan_http_server.py".Replace('"', '\"') + '"'
    $httpDirectory = '"' + "$projectRoot\web_build".Replace('"', '\"') + '"'
    $httpArguments = "$httpScript --directory $httpDirectory --port $($config.http_port)"

    $gameProcess = Start-Process -FilePath $godot -ArgumentList $gameArguments `
        -RedirectStandardOutput "$logDir\game-server.log" -RedirectStandardError "$logDir\game-server-error.log" -WindowStyle Hidden -PassThru
    $httpProcess = Start-Process -FilePath $python -ArgumentList $httpArguments `
        -RedirectStandardOutput "$logDir\http-server.log" -RedirectStandardError "$logDir\http-server-error.log" -WindowStyle Hidden -PassThru

    $healthy = $false
    foreach ($attempt in 1..50) {
        if ($gameProcess.HasExited) { throw "Game server exited early. Read logs/game-server-error.log." }
        if ($httpProcess.HasExited) { throw "HTTP server exited early. Read logs/http-server-error.log." }
        $httpOk = $false
        try {
            $httpResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$($config.http_port)/status" -TimeoutSec 1
            $httpOk = $httpResponse.StatusCode -eq 200 -and [string]$httpResponse.Headers['Server'] -like 'ChaosStickHTTP/*'
        } catch {}
        $httpOwned = Test-OwnedTcpPort ([int]$config.http_port) $httpProcess.Id
        $gameOwned = Test-OwnedTcpPort ([int]$config.game_port) $gameProcess.Id
        if ($httpOk -and $httpOwned -and $gameOwned) { $healthy = $true; break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $healthy) { throw 'Health check failed: HTTP or WebSocket server did not become available.' }

    $lanIp = Get-LanAddress
    $roomUrl = "http://${lanIp}:$($config.http_port)"
    $localUrl = "http://localhost:$($config.http_port)"
    Clear-Host
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '        CHAOS STICK ARENA' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host 'Game Server: ONLINE' -ForegroundColor Green
    Write-Host 'Web Server:  ONLINE' -ForegroundColor Green
    Write-Host "Players:     0/$($config.max_players)"
    Write-Host "Local IP:    $lanIp"
    Write-Host ''
    Write-Host 'ROOM LINK:' -ForegroundColor Yellow
    Write-Host $roomUrl -ForegroundColor White
    Write-Host ''
    Write-Host "Host browser: $localUrl"
    Write-Host 'Send the ROOM LINK to players on the same Wi-Fi/Ethernet.'
    Write-Host 'If access fails, allow TCP ports 8080 and 9000 in Windows Firewall.'
    Write-Host '========================================' -ForegroundColor Cyan
    if ($HealthCheckOnly) {
        Write-Host 'HOST_HEALTH_CHECK_PASS' -ForegroundColor Green
        return
    }
    if (-not $NoBrowser) { Start-Process $localUrl }
    Read-Host 'Press ENTER to stop both servers'
} finally {
    $startedAnyProcess = $false
    if ($httpProcess) { $startedAnyProcess = $true }
    if ($gameProcess) { $startedAnyProcess = $true }
    if ($httpProcess -and -not $httpProcess.HasExited) { Stop-Process -Id $httpProcess.Id -Force }
    if ($gameProcess -and -not $gameProcess.HasExited) { Stop-Process -Id $gameProcess.Id -Force }
    if ($startedAnyProcess) { Write-Host 'Chaos Stick Arena host stopped.' }
}
