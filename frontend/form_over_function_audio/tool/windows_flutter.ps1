param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FlutterArgs
)

$ErrorActionPreference = 'Stop'

# Wrapper for Windows Flutter commands. It first applies the short build-dir
# workaround so MSBuild plugin paths stay below the classic 260-character limit.
$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot '..')

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

if ($FlutterArgs.Count -eq 0) {
    $FlutterArgs = @('run', '-d', 'windows')
}

& (Join-Path $PSScriptRoot 'windows_flutter_build_dir.ps1')

$Flutter = Resolve-FlutterCommand
Push-Location $ProjectDir
try {
    & $Flutter @FlutterArgs
}
finally {
    Pop-Location
}
