[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [switch]$HealthCheckOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
. "$projectRoot\tools\find_godot.ps1"
. "$projectRoot\tools\launcher_process_job.ps1"

$config = Get-Content -LiteralPath "$projectRoot\server_config.json" -Raw | ConvertFrom-Json
$httpPort = [int]$config.http_port
$internalGamePort = [int]$config.internal_game_port
$internalGameBind = [string]$config.internal_game_bind
$gameProcess = $null
$httpProcess = $null
$processJob = $null
$exitCode = 0
$redirectedProcessState = @{}

function Start-RedirectedProcess {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [string]$StandardOutputPath,
        [string]$StandardErrorPath
    )

    # Windows PowerShell's Start-Process can fail when the inherited Windows
    # environment contains PATH and Path entries with different casing. Build
    # ProcessStartInfo directly so the LAN launcher works in that environment.
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stdout = [System.IO.FileStream]::new(
        $StandardOutputPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite
    )
    $stderr = [System.IO.FileStream]::new(
        $StandardErrorPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $process.Start() | Out-Null
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdout)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($stderr)
        $script:redirectedProcessState[$process.Id] = @{
            Stdout = $stdout
            Stderr = $stderr
            Tasks = @($stdoutTask, $stderrTask)
        }
        return $process
    } catch {
        $stdout.Dispose()
        $stderr.Dispose()
        $process.Dispose()
        throw
    }
}

function Complete-RedirectedProcess {
    param([System.Diagnostics.Process]$Process)

    if (-not $Process) { return }
    $state = $script:redirectedProcessState[$Process.Id]
    if (-not $state) { return }
    try {
        if ($Process.HasExited) { $Process.WaitForExit() }
        [System.Threading.Tasks.Task]::WhenAll([System.Threading.Tasks.Task[]]$state.Tasks).Wait(2000) | Out-Null
    } catch {
        # Process shutdown can cancel a pending stream read; the files still
        # contain everything copied before termination.
    } finally {
        $state.Stdout.Flush()
        $state.Stderr.Flush()
        $state.Stdout.Dispose()
        $state.Stderr.Dispose()
        $script:redirectedProcessState.Remove($Process.Id)
    }
}

function Open-HostBrowser {
    param([string]$Url)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Url)
    $startInfo.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($startInfo) | Out-Null
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

function Get-TcpListener {
    param([int]$Port)

    return Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Assert-TcpPortAvailable {
    param(
        [int]$Port,
        [string]$ServiceName
    )

    $listener = Get-TcpListener -Port $Port
    if (-not $listener) { return }
    $processName = 'unknown'
    try {
        $owner = Get-Process -Id $listener.OwningProcess -ErrorAction Stop
        $processName = $owner.ProcessName
    } catch {}
    throw "$ServiceName port $Port is already in use by PID $($listener.OwningProcess) ($processName). Stop that process or change server_config.json."
}

function Test-OwnedTcpPort {
    param(
        [int]$Port,
        [int]$ProcessId,
        [string]$LocalAddress
    )

    $listeners = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -eq $ProcessId }
    if ($LocalAddress) {
        $listeners = $listeners | Where-Object { $_.LocalAddress -eq $LocalAddress }
    }
    $listener = $listeners | Select-Object -First 1
    return $null -ne $listener
}

function Test-WebSocketProxy {
    param(
        [int]$Port,
        [int]$TimeoutMilliseconds = 2000
    )

    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    $cancellation = [System.Threading.CancellationTokenSource]::new()
    $cancellation.CancelAfter($TimeoutMilliseconds)
    try {
        $socket.Options.SetRequestHeader('Origin', "http://127.0.0.1:$Port")
        $uri = [Uri]::new("ws://127.0.0.1:$Port/ws")
        $socket.ConnectAsync($uri, $cancellation.Token).GetAwaiter().GetResult()
        return $socket.State -eq [System.Net.WebSockets.WebSocketState]::Open
    } catch {
        return $false
    } finally {
        if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $socket.Abort()
        }
        $socket.Dispose()
        $cancellation.Dispose()
    }
}

function Write-LogTail {
    param(
        [string]$Label,
        [string]$Path,
        [int]$Lines = 30
    )

    Write-Host "--- $Label ---" -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Host '<log file not created>'
    } elseif ((Get-Item -LiteralPath $Path).Length -eq 0) {
        Write-Host '<empty>'
    } else {
        Get-Content -LiteralPath $Path -Tail $Lines | ForEach-Object { Write-Host $_ }
    }
    Write-Host "Full log: $Path"
}

function Write-ServerFailureLogs {
    param([string]$LogDirectory)

    Write-Host ''
    Write-Host 'GAME SERVER FAILED' -ForegroundColor Red
    Write-Host 'Last server output:'
    Write-LogTail -Label 'game-server-error.log' -Path "$LogDirectory\game-server-error.log"
    Write-LogTail -Label 'game-server.log' -Path "$LogDirectory\game-server.log"
}

function Write-HttpFailureLogs {
    param([string]$LogDirectory)

    Write-Host ''
    Write-Host 'HTTP SERVER FAILED' -ForegroundColor Red
    Write-LogTail -Label 'http-server-error.log' -Path "$LogDirectory\http-server-error.log"
    Write-LogTail -Label 'http-server.log' -Path "$LogDirectory\http-server.log"
}

function Stop-LauncherProcess {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Name
    )

    if (-not $Process) { return }
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            $Process.Kill()
            if (-not $Process.WaitForExit(5000)) {
                Write-Warning "$Name process PID $($Process.Id) did not exit within 5 seconds."
            }
        }
    } catch {
        Write-Warning "Unable to stop launcher-owned $Name process PID $($Process.Id): $($_.Exception.Message)"
    }
}

function Invoke-GodotProjectValidation {
    param(
        [string]$GodotPath,
        [string]$Root,
        [string]$LogDirectory,
        [ChaosStick.LauncherProcessJob]$Job
    )

    $stdoutPath = "$LogDirectory\project-validation.log"
    $stderrPath = "$LogDirectory\project-validation-error.log"
    $quotedRoot = '"' + $Root.Replace('"', '\"') + '"'
    $arguments = "--headless --editor --path $quotedRoot --quit"
    Write-Host 'Validating the Godot project...'
    $validationProcess = Start-RedirectedProcess -FilePath $GodotPath -Arguments $arguments `
        -StandardOutputPath $stdoutPath -StandardErrorPath $stderrPath
    $Job.Add($validationProcess)
    if (-not $validationProcess.WaitForExit(60000)) {
        Stop-LauncherProcess -Process $validationProcess -Name 'project validation'
        Complete-RedirectedProcess -Process $validationProcess
        Write-LogTail -Label 'project-validation-error.log' -Path $stderrPath
        Write-LogTail -Label 'project-validation.log' -Path $stdoutPath
        throw 'Godot project validation timed out after 60 seconds.'
    }
    Complete-RedirectedProcess -Process $validationProcess

    $parsePattern = 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script'
    $parseFailure = Select-String -Path $stdoutPath, $stderrPath -Pattern $parsePattern -ErrorAction SilentlyContinue
    if ($validationProcess.ExitCode -ne 0 -or $parseFailure) {
        Write-LogTail -Label 'project-validation-error.log' -Path $stderrPath
        Write-LogTail -Label 'project-validation.log' -Path $stdoutPath
        throw "Godot project validation failed with exit code $($validationProcess.ExitCode)."
    }
    Write-Host 'Godot project validation: PASS' -ForegroundColor Green
}

function Wait-ForHostStop {
    param(
        [System.Diagnostics.Process]$Game,
        [System.Diagnostics.Process]$Http
    )

    Write-Host 'Press ENTER to stop both servers'
    while ($true) {
        $Game.Refresh()
        $Http.Refresh()
        if ($Game.HasExited) { throw 'Game server exited while the launcher was running.' }
        if ($Http.HasExited) { throw 'HTTP server exited while the launcher was running.' }
        $keyAvailable = $false
        try { $keyAvailable = [Console]::KeyAvailable } catch {}
        if ($keyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Enter) { return }
        }
        Start-Sleep -Milliseconds 200
    }
}

$logDir = Join-Path $projectRoot 'logs'

try {
    # Fail before patching/building anything when required tools are unavailable.
    $python = Find-Python
    $godotInfo = Find-Godot -ProjectRoot $projectRoot
    $godot = $godotInfo.Path

    if ($internalGameBind -ne '127.0.0.1') {
        throw "The LAN launcher requires internal_game_bind to be 127.0.0.1, got '$internalGameBind'. Use --server-bind explicitly only for manual debug runs."
    }

    Write-Host "Using Godot: $godot"
    Write-Host "Godot version: $($godotInfo.Version)"
    Write-Host "Godot source: $($godotInfo.Source)"

    $requiredWebFiles = @('index.html', 'index.js', 'index.wasm', 'index.pck')
    $missingWebFiles = @($requiredWebFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path "$projectRoot\web_build" $_) -PathType Leaf) })
    if ($missingWebFiles.Count -gt 0) {
        Write-Host "Web build missing files ($($missingWebFiles -join ', ')); building it now..."
        & "$projectRoot\build_web.ps1" -GodotExecutable $godot -PythonExecutable $python
    }

    $patchOutput = @(& $python "$projectRoot\tools\patch_web_build.py" "$projectRoot\web_build\index.html" 2>&1)
    $patchExitCode = $LASTEXITCODE
    $patchOutput | ForEach-Object { Write-Host $_ }
    if ($patchExitCode -ne 0) { throw "LAN Web patch failed with exit code $patchExitCode." }
    if (-not ($patchOutput -match '^LAN_HTTP_PATCH_(APPLIED|ALREADY_APPLIED)$')) {
        throw 'LAN Web patch completed without a recognized success marker.'
    }

    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $diagnostics = @(
        "Using Godot: $godot",
        "Godot version: $($godotInfo.Version)",
        "Godot source: $($godotInfo.Source)",
        "Project root: $projectRoot",
        "Public HTTP/WebSocket: 0.0.0.0:$httpPort",
        "Internal Godot: $internalGameBind`:$internalGamePort"
    )
    $diagnostics | Set-Content -LiteralPath "$logDir\launcher.log" -Encoding UTF8
    $diagnostics | ForEach-Object { Write-Host $_ }

    Assert-TcpPortAvailable -Port $httpPort -ServiceName 'Public LAN HTTP/WebSocket server'
    Assert-TcpPortAvailable -Port $internalGamePort -ServiceName 'Internal Godot server'

    $processJob = New-LauncherProcessJob
    Invoke-GodotProjectValidation -GodotPath $godot -Root $projectRoot -LogDirectory $logDir -Job $processJob

    $quotedProjectRoot = '"' + $projectRoot.Replace('"', '\"') + '"'
    $quotedGodotLog = '"' + "$logDir\godot-runtime.log".Replace('"', '\"') + '"'
    $gameArguments = "--headless --log-file $quotedGodotLog --path $quotedProjectRoot -- --server --server-bind=$internalGameBind --internal-game-port=$internalGamePort"
    $httpScript = '"' + "$projectRoot\tools\lan_http_server.py".Replace('"', '\"') + '"'
    $httpDirectory = '"' + "$projectRoot\web_build".Replace('"', '\"') + '"'
    $httpArguments = "$httpScript --directory $httpDirectory --port $httpPort --websocket-upstream-host $internalGameBind --websocket-upstream-port $internalGamePort"

    $gameProcess = Start-RedirectedProcess -FilePath $godot -Arguments $gameArguments `
        -StandardOutputPath "$logDir\game-server.log" `
        -StandardErrorPath "$logDir\game-server-error.log"
    $processJob.Add($gameProcess)

    $gameReady = $false
    foreach ($attempt in 1..150) {
        $gameProcess.Refresh()
        if ($gameProcess.HasExited) { throw 'Game server exited before opening its WebSocket port.' }
        if (Test-OwnedTcpPort -Port $internalGamePort -ProcessId $gameProcess.Id -LocalAddress $internalGameBind) {
            $gameReady = $true
            break
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $gameReady) {
        $ownedListeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -eq $gameProcess.Id })
        $portListeners = @(Get-NetTCPConnection -State Listen -LocalPort $internalGamePort -ErrorAction SilentlyContinue)
        $portOwners = @($portListeners | ForEach-Object { "$($_.LocalAddress) PID $($_.OwningProcess)" })
        throw "Game server PID $($gameProcess.Id) did not open $internalGameBind`:$internalGamePort within 30 seconds; owned listeners: $($ownedListeners.LocalAddress -join ', '); port owners: $($portOwners -join ', ')."
    }
    if (Test-OwnedTcpPort -Port $internalGamePort -ProcessId $gameProcess.Id -LocalAddress '0.0.0.0') {
        throw "Internal Godot port $internalGamePort is exposed on 0.0.0.0 instead of localhost."
    }
    if (Test-OwnedTcpPort -Port $internalGamePort -ProcessId $gameProcess.Id -LocalAddress '::') {
        throw "Internal Godot port $internalGamePort is exposed on [::] instead of localhost."
    }

    $httpProcess = Start-RedirectedProcess -FilePath $python -Arguments $httpArguments `
        -StandardOutputPath "$logDir\http-server.log" `
        -StandardErrorPath "$logDir\http-server-error.log"
    $processJob.Add($httpProcess)

    $healthy = $false
    foreach ($attempt in 1..50) {
        $gameProcess.Refresh()
        $httpProcess.Refresh()
        if ($gameProcess.HasExited) { throw 'Game server exited during health check.' }
        if ($httpProcess.HasExited) { throw 'HTTP server exited during health check.' }
        $httpOk = $false
        try {
            $httpResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$httpPort/status" -TimeoutSec 1
            $httpOk = $httpResponse.StatusCode -eq 200 -and [string]$httpResponse.Headers['Server'] -like 'ChaosStickHTTP/*'
        } catch {}
        $httpOwned = Test-OwnedTcpPort -Port $httpPort -ProcessId $httpProcess.Id -LocalAddress '0.0.0.0'
        $gameOwned = Test-OwnedTcpPort -Port $internalGamePort -ProcessId $gameProcess.Id -LocalAddress $internalGameBind
        $webSocketOk = $false
        if ($httpOk -and $httpOwned -and $gameOwned) {
            $webSocketOk = Test-WebSocketProxy -Port $httpPort
        }
        if ($httpOk -and $httpOwned -and $gameOwned -and $webSocketOk) {
            $healthy = $true
            break
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $healthy) { throw 'Health check failed: HTTP /status or WebSocket /ws did not become available.' }

    $lanIp = Get-LanAddress
    $roomUrl = "http://${lanIp}:$httpPort"
    $webSocketUrl = "ws://${lanIp}:$httpPort/ws"
    $localUrl = "http://localhost:$httpPort"
    Clear-Host
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '        CHAOS STICK ARENA' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host "Godot:      $godot"
    Write-Host "Version:    $($godotInfo.Version)"
    Write-Host 'Godot Server: ONLINE (localhost only)' -ForegroundColor Green
    Write-Host 'LAN Gateway:  ONLINE' -ForegroundColor Green
    Write-Host "Players:     0/$($config.max_players)"
    Write-Host "Local IP:    $lanIp"
    Write-Host ''
    Write-Host 'PUBLIC LAN:' -ForegroundColor Yellow
    Write-Host $roomUrl -ForegroundColor White
    Write-Host ''
    Write-Host 'WebSocket:' -ForegroundColor Yellow
    Write-Host $webSocketUrl -ForegroundColor White
    Write-Host ''
    Write-Host 'Internal Godot:' -ForegroundColor Yellow
    Write-Host "$internalGameBind`:$internalGamePort" -ForegroundColor White
    Write-Host ''
    Write-Host "Host browser: $localUrl"
    Write-Host 'Send the PUBLIC LAN link to players on the same Wi-Fi/Ethernet.'
    Write-Host "Remote clients only need TCP $httpPort; port $internalGamePort stays on localhost."
    Write-Host '========================================' -ForegroundColor Cyan
    if ($HealthCheckOnly) {
        Write-Host 'HOST_HEALTH_CHECK_PASS' -ForegroundColor Green
    } else {
        if (-not $NoBrowser) { Open-HostBrowser -Url $localUrl }
        Wait-ForHostStop -Game $gameProcess -Http $httpProcess
    }
} catch {
    $exitCode = 1
    $failureMessage = $_.Exception.Message
    Write-Host ''
    Write-Host 'HOST FAILED' -ForegroundColor Red
    Write-Host $failureMessage -ForegroundColor Red
    $gameExited = $false
    $httpExited = $false
    if ($gameProcess) { try { $gameProcess.Refresh(); $gameExited = $gameProcess.HasExited } catch { $gameExited = $true } }
    if ($httpProcess) { try { $httpProcess.Refresh(); $httpExited = $httpProcess.HasExited } catch { $httpExited = $true } }
    if ($gameExited) { Complete-RedirectedProcess -Process $gameProcess }
    if ($httpExited) { Complete-RedirectedProcess -Process $httpProcess }
    if ($gameProcess -and ($gameExited -or $failureMessage -match 'Game server|WebSocket|Health check')) {
        Write-ServerFailureLogs -LogDirectory $logDir
    }
    if ($httpProcess -and ($httpExited -or $failureMessage -match 'HTTP server|Health check')) {
        Write-HttpFailureLogs -LogDirectory $logDir
    }
} finally {
    $startedAnyProcess = $null -ne $gameProcess -or $null -ne $httpProcess
    Stop-LauncherProcess -Process $httpProcess -Name 'HTTP server'
    Stop-LauncherProcess -Process $gameProcess -Name 'game server'
    Complete-RedirectedProcess -Process $httpProcess
    Complete-RedirectedProcess -Process $gameProcess
    if ($processJob) { $processJob.Dispose() }
    if ($startedAnyProcess) { Write-Host 'Chaos Stick Arena host stopped.' }
}

if ($exitCode -ne 0) { exit $exitCode }
