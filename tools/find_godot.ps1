function New-GodotValidationResult {
    param(
        [bool]$IsValid,
        [string]$Path,
        [string]$Version,
        [string]$Reason,
        [string]$Output
    )

    [pscustomobject]@{
        IsValid = $IsValid
        Path = $Path
        Version = $Version
        Reason = $Reason
        Output = $Output
    }
}

function Test-GodotExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$TimeoutMilliseconds = 5000
    )

    $candidatePath = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim([char]34))
    if ([string]::IsNullOrWhiteSpace($candidatePath)) {
        return New-GodotValidationResult $false $Path '' 'empty path' ''
    }
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        return New-GodotValidationResult $false $candidatePath '' 'file does not exist' ''
    }

    $item = Get-Item -LiteralPath $candidatePath -ErrorAction SilentlyContinue
    if (-not $item -or $item.Extension -ine '.exe') {
        return New-GodotValidationResult $false $candidatePath '' 'candidate is not a Windows executable' ''
    }
    $candidatePath = $item.FullName
    if ($item.Name -match '(?i)_console') {
        return New-GodotValidationResult $false $candidatePath '' '_console.exe is a wrapper, not a standalone engine executable' ''
    }
    if ($item.Name -match '(?i)mono|headless|dedicated[_-]?server') {
        return New-GodotValidationResult $false $candidatePath '' 'Mono/headless/server builds are not compatible with the complete host and Web export flow' ''
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $candidatePath
    $startInfo.Arguments = '--version'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            return New-GodotValidationResult $false $candidatePath '' 'process did not start' ''
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill() } catch {}
            try { $process.WaitForExit(2000) | Out-Null } catch {}
            return New-GodotValidationResult $false $candidatePath '' "--version timed out after $TimeoutMilliseconds ms" ''
        }
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $output = (($stdout, $stderr) -join "`n").Trim()
        if ($output -match '(?i)main executable.+not found') {
            return New-GodotValidationResult $false $candidatePath '' 'wrapper reported that its main executable is missing' $output
        }
        if ($output -match '(?i)(?:^|[.\s])mono(?:[.\s]|$)') {
            return New-GodotValidationResult $false $candidatePath '' 'Mono builds are not supported by this project launcher' $output
        }
        if ($process.ExitCode -ne 0) {
            return New-GodotValidationResult $false $candidatePath '' "--version exited with code $($process.ExitCode)" $output
        }
        $versionMatch = [regex]::Match($output, '(?im)(?:^|[\svV])(?<version>4\.\d+(?:\.\d+)?(?:[.-][A-Za-z0-9]+)*)')
        if (-not $versionMatch.Success) {
            return New-GodotValidationResult $false $candidatePath '' 'output does not identify a compatible Godot 4.x version' $output
        }
        return New-GodotValidationResult $true $candidatePath $versionMatch.Groups['version'].Value '' $output
    } catch {
        return New-GodotValidationResult $false $candidatePath '' $_.Exception.Message ''
    } finally {
        $process.Dispose()
    }
}

function Get-GodotExecutablesInLocation {
    param(
        [string]$Root,
        [int]$Depth = 1
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $Root -Filter 'Godot*.exe' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '(?i)_console|mono|headless|dedicated[_-]?server' } |
        Sort-Object Name -Descending
    if ($Depth -le 0) { return }

    $godotDirectories = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)godot' }
    foreach ($directory in $godotDirectories) {
        Get-ChildItem -LiteralPath $directory.FullName -Filter 'Godot*.exe' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '(?i)_console|mono|headless|dedicated[_-]?server' } |
            Sort-Object Name -Descending
        if ($Depth -le 1) { continue }
        foreach ($childDirectory in (Get-ChildItem -LiteralPath $directory.FullName -Directory -ErrorAction SilentlyContinue)) {
            Get-ChildItem -LiteralPath $childDirectory.FullName -Filter 'Godot*.exe' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '(?i)_console|mono|headless|dedicated[_-]?server' } |
                Sort-Object Name -Descending
        }
    }
}

function Get-GodotNotFoundMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string[]]$RejectedCandidates = @()
    )

    $portableDirectory = Join-Path $ProjectRoot 'tools\godot'
    $details = ''
    if ($RejectedCandidates.Count -gt 0) {
        $details = "`nRejected candidates:`n- " + ($RejectedCandidates -join "`n- ") + "`n"
    }
    return @"
========================================
GODOT NOT FOUND
========================================

Godot 4.x not found. No valid Godot 4.x executable was found.

Options:

1. Install Godot 4.x and add it to PATH.

2. Set it for the current PowerShell session:
   `$env:GODOT_EXE = "C:\Godot\Godot_v4.x-stable_win64.exe"

3. Place the portable main executable in:
   $portableDirectory

Godot executables are intentionally not stored in Git.
Do not use a *_console.exe wrapper without its corresponding main executable.
$details
========================================
"@
}

function Find-Godot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [switch]$SkipPath,
        [switch]$SkipCommonLocations
    )

    $rawCandidates = [System.Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_EXE)) {
        $rawCandidates.Add([pscustomobject]@{ Path = $env:GODOT_EXE; Source = 'GODOT_EXE' }) | Out-Null
    }

    $portableDirectory = Join-Path $ProjectRoot 'tools\godot'
    foreach ($file in (Get-GodotExecutablesInLocation -Root $portableDirectory -Depth 0)) {
        $rawCandidates.Add([pscustomobject]@{ Path = $file.FullName; Source = 'portable tools/godot' }) | Out-Null
    }

    if (-not $SkipPath) {
        foreach ($commandName in @('godot4', 'godot', 'Godot.exe')) {
            foreach ($command in @(Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue)) {
                $rawCandidates.Add([pscustomobject]@{ Path = $command.Source; Source = "PATH ($commandName)" }) | Out-Null
            }
        }
    }

    if (-not $SkipCommonLocations) {
        $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        $desktop = [Environment]::GetFolderPath('Desktop')
        $commonLocations = @(
            [pscustomobject]@{ Path = (Join-Path $env:USERPROFILE 'Downloads'); Depth = 1; Source = 'Downloads' },
            [pscustomobject]@{ Path = $desktop; Depth = 1; Source = 'Desktop' },
            [pscustomobject]@{ Path = (Join-Path $env:LOCALAPPDATA 'Programs'); Depth = 1; Source = 'LOCALAPPDATA Programs' },
            [pscustomobject]@{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'); Depth = 2; Source = 'WinGet packages' },
            [pscustomobject]@{ Path = $env:ProgramFiles; Depth = 1; Source = 'Program Files' },
            [pscustomobject]@{ Path = $programFilesX86; Depth = 1; Source = 'Program Files (x86)' }
        )
        foreach ($location in $commonLocations) {
            foreach ($file in (Get-GodotExecutablesInLocation -Root $location.Path -Depth $location.Depth)) {
                $rawCandidates.Add([pscustomobject]@{ Path = $file.FullName; Source = $location.Source }) | Out-Null
            }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rejected = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $rawCandidates) {
        $candidatePath = [Environment]::ExpandEnvironmentVariables(([string]$candidate.Path).Trim().Trim([char]34))
        if (-not $seen.Add($candidatePath)) { continue }
        $validation = Test-GodotExecutable -Path $candidatePath
        if ($validation.IsValid) {
            return [pscustomobject]@{
                Path = $validation.Path
                Version = $validation.Version
                Source = $candidate.Source
            }
        }
        $rejected.Add("$candidatePath [$($validation.Reason)]") | Out-Null
    }

    throw [System.IO.FileNotFoundException]::new((Get-GodotNotFoundMessage -ProjectRoot $ProjectRoot -RejectedCandidates $rejected.ToArray()))
}

function Resolve-GodotExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string]$ExplicitPath
    )

    if ([string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return Find-Godot -ProjectRoot $ProjectRoot
    }
    $validation = Test-GodotExecutable -Path $ExplicitPath
    if (-not $validation.IsValid) {
        $reason = "$ExplicitPath [$($validation.Reason)]"
        throw [System.IO.FileNotFoundException]::new((Get-GodotNotFoundMessage -ProjectRoot $ProjectRoot -RejectedCandidates @($reason)))
    }
    return [pscustomobject]@{
        Path = $validation.Path
        Version = $validation.Version
        Source = 'explicit build parameter'
    }
}

function Find-Python {
    foreach ($commandName in @('python', 'python3', 'py')) {
        foreach ($command in @(Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue)) {
            if ($command.Source -and $command.Source -notmatch 'WindowsApps') {
                return $command.Source
            }
        }
    }
    throw 'Python 3 not found. Install Python 3 and make it available in PATH.'
}

function Resolve-PythonExecutable {
    param([string]$ExplicitPath)

    if ([string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return Find-Python
    }
    $candidatePath = [Environment]::ExpandEnvironmentVariables($ExplicitPath.Trim().Trim([char]34))
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf) -or $candidatePath -match 'WindowsApps') {
        throw "Python executable is invalid: $ExplicitPath"
    }
    return (Get-Item -LiteralPath $candidatePath).FullName
}
