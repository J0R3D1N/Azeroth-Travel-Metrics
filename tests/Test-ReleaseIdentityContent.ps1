$ErrorActionPreference = 'Stop'

$identityScript = Join-Path $PSScriptRoot 'Test-ReleaseIdentity.ps1'
$repoRoot = Split-Path -Parent $PSScriptRoot
$addonRoot = Join-Path $repoRoot 'AzerothTravelMetrics'
$fixtureRoot = Join-Path $PSScriptRoot (
    '.identity-content-fixture-' + [guid]::NewGuid().ToString('N')
)
$legacyCommand = [System.Text.Encoding]::ASCII.GetString([byte[]](47, 97, 116, 116))
$windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$windowsPowerShellVersion = & $windowsPowerShell -NoProfile -Command (
    '$PSVersionTable.PSVersion.ToString()'
)
if (
    $LASTEXITCODE -ne 0 -or
    -not $windowsPowerShellVersion.StartsWith('5.1')
) {
    throw (
        'Expected powershell.exe 5.1, found: ' +
        ($windowsPowerShellVersion | Out-String).Trim()
    )
}
$passed = 0
$failed = 0

function Invoke-IdentityGuard {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $windowsPowerShell `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $identityScript 2>&1 |
            Out-String
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Test-RejectsFixture {
    param(
        [string]$Name,
        [string]$FileName,
        [byte[]]$Content
    )

    $fixturePath = Join-Path $fixtureRoot $FileName
    [System.IO.File]::WriteAllBytes($fixturePath, $Content)

    try {
        $result = Invoke-IdentityGuard
        if (
            $result.ExitCode -ne 0 -and
            $result.Output -match [regex]::Escape($fixturePath)
        ) {
            Write-Output "PASS $Name"
            $script:passed++
            return
        }

        Write-Output "FAIL $Name"
        Write-Output "  Expected identity guard to reject $fixturePath."
        Write-Output "  Exit code: $($result.ExitCode)"
        Write-Output "  Output: $($result.Output.Trim())"
        $script:failed++
    }
    finally {
        Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
    }
}

function Test-RejectsNamedItem {
    param(
        [string]$Name,
        [string]$ItemName,
        [switch]$Directory
    )

    $fixturePath = Join-Path $fixtureRoot $ItemName
    if ($Directory) {
        New-Item -ItemType Directory -Path $fixturePath | Out-Null
    }
    else {
        [System.IO.File]::WriteAllText($fixturePath, 'fixture')
    }

    try {
        $result = Invoke-IdentityGuard
        if (
            $result.ExitCode -ne 0 -and
            $result.Output -match [regex]::Escape($fixturePath)
        ) {
            Write-Output "PASS $Name"
            $script:passed++
            return
        }

        Write-Output "FAIL $Name"
        Write-Output "  Expected identity guard to reject $fixturePath."
        Write-Output "  Exit code: $($result.ExitCode)"
        Write-Output "  Output: $($result.Output.Trim())"
        $script:failed++
    }
    finally {
        Remove-Item `
            -LiteralPath $fixturePath `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $legacyInitialism = [System.Text.Encoding]::ASCII.GetString(
        [byte[]](65, 84, 84)
    )
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
    Test-RejectsNamedItem `
        -Name 'rejects a legacy file name' `
        -ItemName "$legacyInitialism-file.txt"
    Test-RejectsNamedItem `
        -Name 'rejects a legacy directory name' `
        -ItemName "$legacyInitialism-directory" `
        -Directory

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

        $result = Invoke-IdentityGuard
        if (
            $result.ExitCode -ne 0 -and
            $result.Output -match [regex]::Escape($packagedFixturePath)
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
            Write-Output "  Exit code: $($result.ExitCode)"
            Write-Output "  Output: $($result.Output.Trim())"
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

    $outsideIgnoredDirectory = Join-Path $PSScriptRoot 'artifacts'
    $outsideIgnoredFixture = Join-Path (
        $outsideIgnoredDirectory
    ) 'identity-content-fixture.txt'
    $createdOutsideIgnoredDirectory = $false
    try {
        if (Test-Path -LiteralPath $outsideIgnoredFixture) {
            throw "Identity fixture already exists: $outsideIgnoredFixture"
        }
        if (-not (Test-Path -LiteralPath $outsideIgnoredDirectory)) {
            New-Item -ItemType Directory -Path $outsideIgnoredDirectory |
                Out-Null
            $createdOutsideIgnoredDirectory = $true
        }
        [System.IO.File]::WriteAllBytes(
            $outsideIgnoredFixture,
            $utf8.GetBytes("ignored fixture`n$legacyCommand`n")
        )

        $result = Invoke-IdentityGuard
        if ($result.ExitCode -eq 0) {
            Write-Output (
                'PASS ignores configured directories outside the packaged addon'
            )
            $passed++
        }
        else {
            Write-Output (
                'FAIL ignores configured directories outside the packaged addon'
            )
            Write-Output "  Expected identity guard to ignore $outsideIgnoredFixture."
            Write-Output "  Exit code: $($result.ExitCode)"
            Write-Output "  Output: $($result.Output.Trim())"
            $failed++
        }
    }
    finally {
        Remove-Item `
            -LiteralPath $outsideIgnoredFixture `
            -Force `
            -ErrorAction SilentlyContinue
        if (
            $createdOutsideIgnoredDirectory -and
            (Test-Path -LiteralPath $outsideIgnoredDirectory)
        ) {
            Remove-Item -LiteralPath $outsideIgnoredDirectory -Force
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
