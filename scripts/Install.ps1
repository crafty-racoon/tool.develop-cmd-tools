param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Version,
    [string]$PackagePath,
    [string]$Repository = 'crafty-racoon/tool.develop-cmd-tools'
)

$ErrorActionPreference = 'Stop'
[string]$project = (Resolve-Path -LiteralPath $ProjectRoot).Path
[string]$destination = Join-Path $project 'tools/tool.develop-cmd-tools'
[string]$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("develop-cmd-tools-install-{0}" -f [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    [string]$archive = Join-Path $temporaryRoot 'package.zip'
    if ([string]::IsNullOrWhiteSpace($PackagePath)) {
        [string]$reference = if ([string]::IsNullOrWhiteSpace($Version)) { 'refs/heads/main' } else { "refs/tags/v$Version" }
        [string]$url = "https://github.com/$Repository/archive/$reference.zip"
        Write-Host "Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    } else {
        Copy-Item -LiteralPath (Resolve-Path -LiteralPath $PackagePath).Path -Destination $archive
    }

    [string]$expanded = Join-Path $temporaryRoot 'expanded'
    Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
    [string]$source = @(
        Get-ChildItem -LiteralPath $expanded -Directory -Recurse |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'scripts/version.json') -PathType Leaf }
    )[0].FullName
    if ([string]::IsNullOrWhiteSpace($source)) { throw 'The package does not contain tool.develop-cmd-tools.' }

    [string]$savedConfig = Join-Path $temporaryRoot 'develop-cmd-tools.local.json'
    [string]$currentConfig = Join-Path $destination 'scripts/develop-cmd-tools.local.json'
    if (Test-Path -LiteralPath $currentConfig -PathType Leaf) { Copy-Item -LiteralPath $currentConfig -Destination $savedConfig }
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse
    if (Test-Path -LiteralPath $savedConfig -PathType Leaf) {
        Copy-Item -LiteralPath $savedConfig -Destination (Join-Path $destination 'scripts/develop-cmd-tools.local.json')
    } else {
        Copy-Item -LiteralPath (Join-Path $destination 'scripts/develop-cmd-tools.json') `
            -Destination (Join-Path $destination 'scripts/develop-cmd-tools.local.json')
    }
    [object]$installed = Get-Content -LiteralPath (Join-Path $destination 'scripts/version.json') -Raw | ConvertFrom-Json
    Write-Host "Installed $($installed.name) $($installed.version) to $destination"
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}
