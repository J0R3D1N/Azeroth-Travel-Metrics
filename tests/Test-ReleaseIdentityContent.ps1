$ErrorActionPreference = 'Stop'

$identityScript = Join-Path $PSScriptRoot 'Test-ReleaseIdentity.ps1'
$repoRoot = Split-Path -Parent $PSScriptRoot
$addonRoot = Join-Path $repoRoot 'AzerothTravelMetrics'
$fixtureRoot = Join-Path $PSScriptRoot (
    '.identity-content-fixture-' + [guid]::NewGuid().ToString('N')
)
$legacyCommand = [System.Text.Encoding]::ASCII.GetString([byte[]](47, 97, 116, 116))
$hostExecutable = (Get-Process -Id $PID).Path
$passed = 0
$failed = 0

function Test-RejectsFixture {
    param(
        [string]$Name,
        [string]$FileName,
        [byte[]]$Content
    )

    $fixturePath = Join-Path $fixtureRoot $FileName
    [System.IO.File]::WriteAllBytes($fixturePath, $Content)

    try {
        $output = & $hostExecutable -NoProfile -File $identityScript 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -and $output -match [regex]::Escape($fixturePath)) {
            Write-Output "PASS $Name"
            $script:passed++
            return
        }

        Write-Output "FAIL $Name"
        Write-Output "  Expected identity guard to reject $fixturePath."
        Write-Output "  Exit code: $LASTEXITCODE"
        Write-Output "  Output: $($output.Trim())"
        $script:failed++
    }
    finally {
        Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    Test-RejectsFixture `
        -Name 'rejects legacy content in an ordinary text file' `
        -FileName 'active-content.txt' `
        -Content $utf8.GetBytes("fixture`n$legacyCommand`n")
    Test-RejectsFixture `
        -Name 'rejects legacy content in an ordinary Lua file' `
        -FileName 'active-content.lua' `
        -Content $utf8.GetBytes("-- fixture`n$legacyCommand`n")
    Test-RejectsFixture `
        -Name 'rejects legacy content in a binary file without crashing' `
        -FileName 'active-content.bin' `
        -Content ([byte[]](0, 255, 47, 97, 116, 116, 0, 254))

    $packagedIgnoredDirectory = Join-Path $addonRoot 'artifacts'
    $packagedFixturePath = Join-Path $packagedIgnoredDirectory 'Shipped.lua'
    $createdPackagedIgnoredDirectory = $false
    try {
        if (Test-Path -LiteralPath $packagedFixturePath) {
            throw "Packaged identity fixture already exists: $packagedFixturePath"
        }
        if (-not (Test-Path -LiteralPath $packagedIgnoredDirectory)) {
            New-Item -ItemType Directory -Path $packagedIgnoredDirectory |
                Out-Null
            $createdPackagedIgnoredDirectory = $true
        }
        [System.IO.File]::WriteAllBytes(
            $packagedFixturePath,
            $utf8.GetBytes("-- shipped fixture`n$legacyCommand`n")
        )

        $output = & $hostExecutable -NoProfile -File $identityScript 2>&1 |
            Out-String
        if (
            $LASTEXITCODE -ne 0 -and
            $output -match [regex]::Escape($packagedFixturePath)
        ) {
            Write-Output (
                'PASS rejects legacy content below an ignored directory ' +
                'name in the packaged addon'
            )
            $passed++
        }
        else {
            Write-Output (
                'FAIL rejects legacy content below an ignored directory ' +
                'name in the packaged addon'
            )
            Write-Output "  Expected identity guard to reject $packagedFixturePath."
            Write-Output "  Exit code: $LASTEXITCODE"
            Write-Output "  Output: $($output.Trim())"
            $failed++
        }
    }
    finally {
        Remove-Item `
            -LiteralPath $packagedFixturePath `
            -Force `
            -ErrorAction SilentlyContinue
        if (
            $createdPackagedIgnoredDirectory -and
            (Test-Path -LiteralPath $packagedIgnoredDirectory)
        ) {
            Remove-Item -LiteralPath $packagedIgnoredDirectory -Force
        }
    }
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

Write-Output "Release identity content tests: $passed passed, $failed failed"
if ($failed -gt 0) {
    exit 1
}

exit 0
