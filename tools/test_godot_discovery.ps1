[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\find_godot.ps1"

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('chaos-stick-godot-discovery-' + [guid]::NewGuid().ToString('N'))
$portableDirectory = Join-Path $testRoot 'tools\godot'
$wrapperPath = Join-Path $portableDirectory 'Godot_v4.7.1-stable_win64_console.exe'
$mainPath = Join-Path $portableDirectory 'Godot_v4.5-stable_win64.exe'
$slowPath = Join-Path $testRoot 'Godot_v4.6-hung_win64.exe'
$previousGodotExe = $env:GODOT_EXE

try {
    New-Item -ItemType Directory -Path $portableDirectory -Force | Out-Null
    New-Item -ItemType File -Path $wrapperPath | Out-Null
    Remove-Item Env:GODOT_EXE -ErrorAction SilentlyContinue

    $wrapperResult = Test-GodotExecutable -Path $wrapperPath
    if ($wrapperResult.IsValid -or $wrapperResult.Reason -notmatch '_console') {
        throw 'The broken console wrapper was not rejected explicitly.'
    }
    Write-Output 'TEST_OK: broken _console wrapper is rejected'

    $notFound = $false
    try {
        Find-Godot -ProjectRoot $testRoot -SkipPath -SkipCommonLocations | Out-Null
    } catch [System.IO.FileNotFoundException] {
        $notFound = $_.Exception.Message -match 'GODOT NOT FOUND'
    }
    if (-not $notFound) {
        throw 'A project containing only the broken wrapper did not produce the clear not-found error.'
    }
    Write-Output 'TEST_OK: wrapper-only installation fails before launch'

    $slowSource = @'
using System.Threading;

namespace ChaosStickGodotTimeoutTest
{
    public static class Program
    {
        public static int Main(string[] args)
        {
            Thread.Sleep(10000);
            return 0;
        }
    }
}
'@
    Add-Type -TypeDefinition $slowSource -Language CSharp -OutputAssembly $slowPath -OutputType ConsoleApplication
    $slowResult = Test-GodotExecutable -Path $slowPath -TimeoutMilliseconds 200
    if ($slowResult.IsValid -or $slowResult.Reason -notmatch 'timed out') {
        throw 'A hung candidate was not rejected by the validation timeout.'
    }
    Write-Output 'TEST_OK: hung executable is terminated by validation timeout'

    $source = @'
using System;

namespace ChaosStickGodotDiscoveryTest
{
    public static class Program
    {
        public static int Main(string[] args)
        {
            Console.WriteLine("4.5.stable.official.discoverytest");
            return 0;
        }
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $mainPath -OutputType ConsoleApplication

    # An invalid explicit wrapper must not prevent discovery from continuing to
    # the valid portable main executable.
    $env:GODOT_EXE = $wrapperPath
    $found = Find-Godot -ProjectRoot $testRoot -SkipPath -SkipCommonLocations
    if ($found.Path -ne $mainPath -or $found.Version -notmatch '^4\.5' -or $found.Source -ne 'portable tools/godot') {
        throw 'Discovery did not continue from the invalid wrapper to the valid portable Godot 4.x executable.'
    }
    Write-Output 'TEST_OK: invalid GODOT_EXE falls through to valid portable Godot 4.x'
    Write-Output 'GODOT_DISCOVERY_TEST_PASS'
} finally {
    if ([string]::IsNullOrWhiteSpace($previousGodotExe)) {
        Remove-Item Env:GODOT_EXE -ErrorAction SilentlyContinue
    } else {
        $env:GODOT_EXE = $previousGodotExe
    }
    foreach ($path in @($mainPath, $slowPath, $wrapperPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if (Test-Path -LiteralPath $portableDirectory) { Remove-Item -LiteralPath $portableDirectory -Force }
    $toolsDirectory = Join-Path $testRoot 'tools'
    if (Test-Path -LiteralPath $toolsDirectory) { Remove-Item -LiteralPath $toolsDirectory -Force }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Force }
}
