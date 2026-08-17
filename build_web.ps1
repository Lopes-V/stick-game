[CmdletBinding()]
param(
    [string]$GodotExecutable,
    [string]$PythonExecutable
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
. "$projectRoot\tools\find_godot.ps1"

$godotInfo = Resolve-GodotExecutable -ProjectRoot $projectRoot -ExplicitPath $GodotExecutable
$godot = $godotInfo.Path
$python = Resolve-PythonExecutable -ExplicitPath $PythonExecutable
Write-Host "Using Godot: $godot"
Write-Host "Godot version: $($godotInfo.Version)"

$logDir = Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$quotedProjectRoot = '"' + $projectRoot.Replace('"', '\"') + '"'
$exportPath = Join-Path $projectRoot 'web_build\index.html'
$quotedExportPath = '"' + $exportPath.Replace('"', '\"') + '"'
$exportArguments = "--headless --path $quotedProjectRoot --export-release Web $quotedExportPath"
$exportStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$exportStartInfo.FileName = $godot
$exportStartInfo.Arguments = $exportArguments
$exportStartInfo.UseShellExecute = $false
$exportStartInfo.CreateNoWindow = $true
$exportStartInfo.RedirectStandardOutput = $true
$exportStartInfo.RedirectStandardError = $true
$exportProcess = [System.Diagnostics.Process]::new()
$exportProcess.StartInfo = $exportStartInfo
$exportProcess.Start() | Out-Null
$stdoutTask = $exportProcess.StandardOutput.ReadToEndAsync()
$stderrTask = $exportProcess.StandardError.ReadToEndAsync()
if (-not $exportProcess.WaitForExit(300000)) {
    try { $exportProcess.Kill() } catch {}
    try { $exportProcess.WaitForExit(2000) | Out-Null } catch {}
    $exportProcess.Dispose()
    throw 'Godot Web export timed out after 5 minutes.'
}
$exportProcess.WaitForExit()
$exportOutput = $stdoutTask.Result
$exportError = $stderrTask.Result
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText("$logDir\web-export.log", $exportOutput, $utf8)
[System.IO.File]::WriteAllText("$logDir\web-export-error.log", $exportError, $utf8)
$exportExitCode = $exportProcess.ExitCode
$exportProcess.Dispose()
if ($exportExitCode -ne 0) {
    Get-Content -LiteralPath "$logDir\web-export.log" -Tail 40 -ErrorAction SilentlyContinue
    Get-Content -LiteralPath "$logDir\web-export-error.log" -Tail 40 -ErrorAction SilentlyContinue
    throw "Godot Web export failed with exit code $exportExitCode."
}
if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) {
    throw 'Godot reported success but web_build/index.html is missing.'
}

$patchOutput = @(& $python "$projectRoot\tools\patch_web_build.py" $exportPath 2>&1)
$patchExitCode = $LASTEXITCODE
$patchOutput | ForEach-Object { Write-Host $_ }
if ($patchExitCode -ne 0) { throw "LAN Web patch failed with exit code $patchExitCode." }
if (-not ($patchOutput -match '^LAN_HTTP_PATCH_(APPLIED|ALREADY_APPLIED)$')) {
    throw 'LAN Web patch completed without a recognized success marker.'
}
Write-Host 'Web build ready: web_build/index.html' -ForegroundColor Green
