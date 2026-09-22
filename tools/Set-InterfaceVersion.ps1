param(
    [Parameter(Mandatory = $true)]
    [string]$BetaAddOnsPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BetaAddOnsPath -PathType Container)) {
    throw "Beta AddOns path does not exist: $BetaAddOnsPath"
}

$interfaceVersions = foreach ($tocFile in Get-ChildItem -LiteralPath $BetaAddOnsPath -Filter '*.toc' -File -Recurse) {
    foreach ($line in Get-Content -LiteralPath $tocFile.FullName) {
        if ($line -match '^## Interface:\s*(\d+)\s*$') {
            [int]$Matches[1]
        }
    }
}

if (-not $interfaceVersions) {
    throw "No numeric Interface lines were found under: $BetaAddOnsPath"
}

$interfaceVersion = ($interfaceVersions | Measure-Object -Maximum).Maximum
$addonTocPath = Join-Path $PSScriptRoot `
    '..\AzerothTravelMetrics\AzerothTravelMetrics.toc'
$addonTocPath = (Resolve-Path -LiteralPath $addonTocPath).Path
$addonToc = Get-Content -LiteralPath $addonTocPath -Raw
$interfacePattern = [regex]::new('(?m)^## Interface:[^\S\r\n]*\d+[^\S\r\n]*(?=\r?$)')

if (-not $interfacePattern.IsMatch($addonToc)) {
    throw "Addon TOC does not contain a numeric Interface line: $addonTocPath"
}

$updatedToc = $interfacePattern.Replace($addonToc, "## Interface: $interfaceVersion", 1)
[System.IO.File]::WriteAllText(
    $addonTocPath,
    $updatedToc,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Output "Updated Interface to $interfaceVersion"
