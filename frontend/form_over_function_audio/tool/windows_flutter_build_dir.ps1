param()

$ErrorActionPreference = 'Stop'

# Flutter stores the build-dir setting in the user's Flutter config. The value
# must be relative, so this path escapes the nested Flutter project and lands in
# C:\b\fof. Keeping this very short prevents generated MSBuild plugin paths
# from hitting Windows' classic 260-character path limit.
$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$ShortBuildDir = '..\..\..\..\b\fof'

function Resolve-FlutterCommand {
    $fromPath = Get-Command flutter -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    $knownSdk = 'C:\Development\flutter\flutter\bin\flutter.bat'
    if (Test-Path $knownSdk) {
        return $knownSdk
    }

    throw 'Could not find flutter. Add Flutter to PATH or update this script with your Flutter SDK location.'
}

$Flutter = Resolve-FlutterCommand

Push-Location $ProjectDir
try {
    & $Flutter config "--build-dir=$ShortBuildDir"
    $resolvedBuildDir = [System.IO.Path]::GetFullPath((Join-Path $ProjectDir $ShortBuildDir))
    Write-Host "Flutter build-dir configured as: $ShortBuildDir"
    Write-Host "Resolved Windows build output: $resolvedBuildDir"
}
finally {
    Pop-Location
}
