$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$migrationScript = Join-Path $repoRoot 'tools\Migrate-LocalATTData.ps1'

if (-not (Test-Path -LiteralPath $migrationScript -PathType Leaf)) {
    throw "Migration script does not exist: $migrationScript"
}

$env:ATM_MIGRATION_FUNCTIONS_ONLY = '1'
try {
    . $migrationScript
}
finally {
    Remove-Item Env:\ATM_MIGRATION_FUNCTIONS_ONLY -ErrorAction SilentlyContinue
}

$passed = 0
$failed = 0
$utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
$utf8Bom = New-Object System.Text.UTF8Encoding($true, $true)
$oldRoot = 'AzerothTravelTrackerDB'
$newRoot = 'AzerothTravelMetricsDB'
$missingProcessName = 'NoSuchProcess-' + [guid]::NewGuid().ToString('N')
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'AzerothTravelMetrics-migration-tests-' + [guid]::NewGuid().ToString('N')
)

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-BytesEqual {
    param(
        [byte[]]$Expected,
        [byte[]]$Actual,
        [string]$Message
    )

    Assert-True `
        -Condition ($Expected.Length -eq $Actual.Length) `
        -Message "$Message Lengths differ."
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Expected[$index] -ne $Actual[$index]) {
            throw "$Message Bytes differ at offset $index."
        }
    }
}

function Invoke-Test {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        & $Action
        Write-Output "PASS $Name"
        $script:passed++
    }
    catch {
        Write-Output "FAIL $Name"
        Write-Output "  $($_.Exception.Message)"
        $script:failed++
    }
}

function Assert-Throws {
    param(
        [scriptblock]$Action,
        [string]$MessagePattern
    )

    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            throw "Unexpected error: $($_.Exception.Message)"
        }
        return
    }

    throw 'Expected an exception.'
}

function New-TestCase {
    param([string]$Name)

    $root = Join-Path $fixtureRoot $Name
    $savedVariablesRoot = Join-Path $root 'SavedVariables'
    $backupRoot = Join-Path $root 'backups'
    New-Item -ItemType Directory -Path $savedVariablesRoot -Force | Out-Null
    return [pscustomobject]@{
        Root = $root
        OldPath = Join-Path $savedVariablesRoot 'AzerothTravelTracker.lua'
        NewPath = Join-Path $savedVariablesRoot 'AzerothTravelMetrics.lua'
        BackupRoot = $backupRoot
    }
}

function Write-Utf8Fixture {
    param(
        [string]$Path,
        [string]$Text,
        [bool]$WithBom = $false
    )

    $encoding = $utf8NoBom
    if ($WithBom) {
        $encoding = $utf8Bom
    }
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Invoke-FixtureMigration {
    param(
        [pscustomobject]$Fixture,
        [datetime]$BackupTimestamp = [datetime]'2026-09-21T18:08:20',
        [string]$WowProcessName = $missingProcessName
    )

    return Invoke-LocalSavedVariablesMigration `
        -OldSavedVariablesPath $Fixture.OldPath `
        -NewSavedVariablesPath $Fixture.NewPath `
        -BackupDirectory $Fixture.BackupRoot `
        -WowProcessName $WowProcessName `
        -BackupTimestamp $BackupTimestamp
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

    Invoke-Test 'rejects a missing source without mutation' {
        $fixture = New-TestCase 'missing-source'
        Assert-Throws `
            -MessagePattern 'does not exist|not a file' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.NewPath)) `
            -Message 'Destination was created.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'refuses an existing destination file' {
        $fixture = New-TestCase 'destination-file'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = {}`r`n"
        Write-Utf8Fixture -Path $fixture.NewPath -Text 'existing'
        $originalDestination = [System.IO.File]::ReadAllBytes($fixture.NewPath)
        Assert-Throws `
            -MessagePattern 'destination already exists' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-BytesEqual `
            -Expected $originalDestination `
            -Actual ([System.IO.File]::ReadAllBytes($fixture.NewPath)) `
            -Message 'Existing destination changed.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'refuses an existing destination directory' {
        $fixture = New-TestCase 'destination-directory'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = {}`n"
        New-Item -ItemType Directory -Path $fixture.NewPath | Out-Null
        Assert-Throws `
            -MessagePattern 'destination already exists' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'rejects zero top-level root assignments' {
        $fixture = New-TestCase 'zero-root'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "DifferentRoot = {}`n"
        Assert-Throws `
            -MessagePattern 'exactly one.*found 0' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'rejects duplicate top-level root assignments' {
        $fixture = New-TestCase 'duplicate-root'
        Write-Utf8Fixture `
            -Path $fixture.OldPath `
            -Text "$oldRoot = {}`n$oldRoot`t=`t{}`n"
        Assert-Throws `
            -MessagePattern 'exactly one.*found 2' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'rejects an indented non-top-level assignment' {
        $fixture = New-TestCase 'indented-root'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "  $oldRoot = {}`n"
        Assert-Throws `
            -MessagePattern 'exactly one.*found 0' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'rejects a comparison root without mutation' {
        $fixture = New-TestCase 'comparison-root'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot == {}`n"
        $sourceBytes = [System.IO.File]::ReadAllBytes($fixture.OldPath)
        Assert-Throws `
            -MessagePattern 'exactly one.*found 0' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-BytesEqual `
            -Expected $sourceBytes `
            -Actual ([System.IO.File]::ReadAllBytes($fixture.OldPath)) `
            -Message 'Source changed.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.NewPath)) `
            -Message 'Destination was created.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'rejects a space-separated multiple-equals root without mutation' {
        $fixture = New-TestCase 'space-separated-equals-root'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = = {}`n"
        $sourceBytes = [System.IO.File]::ReadAllBytes($fixture.OldPath)
        Assert-Throws `
            -MessagePattern 'exactly one.*found 0' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-BytesEqual `
            -Expected $sourceBytes `
            -Actual ([System.IO.File]::ReadAllBytes($fixture.OldPath)) `
            -Message 'Source changed.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.NewPath)) `
            -Message 'Destination was created.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'rejects a tab-separated multiple-equals root without mutation' {
        $fixture = New-TestCase 'tab-separated-equals-root'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot =`t= {}`n"
        $sourceBytes = [System.IO.File]::ReadAllBytes($fixture.OldPath)
        Assert-Throws `
            -MessagePattern 'exactly one.*found 0' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-BytesEqual `
            -Expected $sourceBytes `
            -Actual ([System.IO.File]::ReadAllBytes($fixture.OldPath)) `
            -Message 'Source changed.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.NewPath)) `
            -Message 'Destination was created.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'replaces only the equal-length root bytes' {
        $fixture = New-TestCase 'exact-replacement'
        $sourceText = "-- prefix $oldRoot`r`n$oldRoot`t = {`r`n  marker = '$oldRoot',`r`n}`r`n"
        Write-Utf8Fixture -Path $fixture.OldPath -Text $sourceText
        $sourceBytes = [System.IO.File]::ReadAllBytes($fixture.OldPath)
        Invoke-FixtureMigration -Fixture $fixture | Out-Null
        $newBytes = [System.IO.File]::ReadAllBytes($fixture.NewPath)
        Assert-True -Condition ($sourceBytes.Length -eq $newBytes.Length) `
            -Message 'Destination byte length changed.'
        $restoredBytes = [byte[]]$newBytes.Clone()
        $newToken = [System.Text.Encoding]::ASCII.GetBytes($newRoot)
        $oldToken = [System.Text.Encoding]::ASCII.GetBytes($oldRoot)
        $changedOffset = -1
        for ($offset = 0; $offset -le $newBytes.Length - $newToken.Length; $offset++) {
            $matches = $true
            for ($tokenIndex = 0; $tokenIndex -lt $newToken.Length; $tokenIndex++) {
                if ($newBytes[$offset + $tokenIndex] -ne $newToken[$tokenIndex]) {
                    $matches = $false
                    break
                }
            }
            if ($matches) {
                $changedOffset = $offset
                break
            }
        }
        Assert-True -Condition ($changedOffset -ge 0) -Message 'New root was not found.'
        [System.Array]::Copy(
            $oldToken,
            0,
            $restoredBytes,
            $changedOffset,
            $oldToken.Length
        )
        Assert-BytesEqual `
            -Expected $sourceBytes `
            -Actual $restoredBytes `
            -Message 'Bytes outside the root changed.'
    }

    Invoke-Test 'creates the timestamped backup name' {
        $fixture = New-TestCase 'backup-name'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = {}`n"
        $result = Invoke-FixtureMigration -Fixture $fixture
        Assert-True `
            -Condition (
                [System.IO.Path]::GetFileName($result.BackupPath) -eq
                'AzerothTravelTracker_20260921_180820.lua'
            ) `
            -Message "Unexpected backup name: $($result.BackupPath)"
    }

    Invoke-Test 'creates a byte-identical backup' {
        $fixture = New-TestCase 'backup-content'
        $unicodeName = ([char]0x00C9) + 'owyn'
        Write-Utf8Fixture `
            -Path $fixture.OldPath `
            -Text "$oldRoot = { value = '$unicodeName' }`n"
        $sourceBytes = [System.IO.File]::ReadAllBytes($fixture.OldPath)
        $result = Invoke-FixtureMigration -Fixture $fixture
        Assert-BytesEqual `
            -Expected $sourceBytes `
            -Actual ([System.IO.File]::ReadAllBytes($result.BackupPath)) `
            -Message 'Backup differs from source.'
    }

    Invoke-Test 'does not mutate the source' {
        $fixture = New-TestCase 'source-unchanged'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = { value = 42 }`r`n"
        $sourceBytes = [System.IO.File]::ReadAllBytes($fixture.OldPath)
        Invoke-FixtureMigration -Fixture $fixture | Out-Null
        Assert-BytesEqual `
            -Expected $sourceBytes `
            -Actual ([System.IO.File]::ReadAllBytes($fixture.OldPath)) `
            -Message 'Source changed.'
    }

    Invoke-Test 'preserves a UTF-8 BOM' {
        $fixture = New-TestCase 'with-bom'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = {}`n" -WithBom $true
        Invoke-FixtureMigration -Fixture $fixture | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($fixture.NewPath)
        Assert-True `
            -Condition (
                $bytes.Length -ge 3 -and
                $bytes[0] -eq 0xEF -and
                $bytes[1] -eq 0xBB -and
                $bytes[2] -eq 0xBF
            ) `
            -Message 'Destination BOM is missing.'
    }

    Invoke-Test 'preserves UTF-8 without a BOM' {
        $fixture = New-TestCase 'without-bom'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = {}`n"
        Invoke-FixtureMigration -Fixture $fixture | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($fixture.NewPath)
        $hasBom = (
            $bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
        )
        Assert-True -Condition (-not $hasBom) -Message 'Destination gained a BOM.'
    }

    Invoke-Test 'preserves Unicode payload bytes' {
        $fixture = New-TestCase 'unicode-payload'
        $unicodeName = (
            ([char]0x00C9) + 'owyn-' + ([char]0x9280) + ([char]0x6708)
        )
        $unicodePhrase = (
            'Za' + ([char]0x017C) + ([char]0x00F3) + ([char]0x0142) +
            ([char]0x0107) + ' g' + ([char]0x0119) + ([char]0x015B) +
            'l' + ([char]0x0105) + ' ja' + ([char]0x017A) + ([char]0x0144)
        )
        $sourceText = "$oldRoot = { ['$unicodeName'] = '$unicodePhrase' }`n"
        Write-Utf8Fixture -Path $fixture.OldPath -Text $sourceText
        Invoke-FixtureMigration -Fixture $fixture | Out-Null
        $newText = $utf8NoBom.GetString(
            [System.IO.File]::ReadAllBytes($fixture.NewPath)
        )
        Assert-True `
            -Condition (
                $newText -ceq $sourceText.Replace($oldRoot, $newRoot)
            ) `
            -Message 'Unicode payload changed.'
    }

    Invoke-Test 'rejects invalid UTF-8 before creating output' {
        $fixture = New-TestCase 'invalid-utf8'
        $validPrefix = [System.Text.Encoding]::ASCII.GetBytes("$oldRoot = {`n")
        $invalidBytes = New-Object byte[] ($validPrefix.Length + 3)
        [System.Array]::Copy($validPrefix, $invalidBytes, $validPrefix.Length)
        $invalidBytes[$validPrefix.Length] = 0xC3
        $invalidBytes[$validPrefix.Length + 1] = 0x28
        $invalidBytes[$validPrefix.Length + 2] = 0x0A
        [System.IO.File]::WriteAllBytes($fixture.OldPath, $invalidBytes)
        Assert-Throws `
            -MessagePattern 'UTF-8' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.NewPath)) `
            -Message 'Destination was created.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'refuses migration while the configured process exists' {
        $fixture = New-TestCase 'wow-running'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = {}`n"
        $sourceBytes = [System.IO.File]::ReadAllBytes($fixture.OldPath)
        $currentProcessName = (Get-Process -Id $PID).ProcessName
        Assert-Throws `
            -MessagePattern 'must be closed' `
            -Action {
                Invoke-FixtureMigration `
                    -Fixture $fixture `
                    -WowProcessName $currentProcessName
            }
        Assert-BytesEqual `
            -Expected $sourceBytes `
            -Actual ([System.IO.File]::ReadAllBytes($fixture.OldPath)) `
            -Message 'Source changed.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.NewPath)) `
            -Message 'Destination was created.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.BackupRoot)) `
            -Message 'Backup directory was created.'
    }

    Invoke-Test 'refuses a backup collision without overwrite' {
        $fixture = New-TestCase 'backup-collision'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = {}`n"
        New-Item -ItemType Directory -Path $fixture.BackupRoot | Out-Null
        $collisionPath = Join-Path (
            $fixture.BackupRoot
        ) 'AzerothTravelTracker_20260921_180820.lua'
        [System.IO.File]::WriteAllText($collisionPath, 'do not overwrite')
        $collisionBytes = [System.IO.File]::ReadAllBytes($collisionPath)
        Assert-Throws `
            -MessagePattern 'backup already exists' `
            -Action { Invoke-FixtureMigration -Fixture $fixture }
        Assert-BytesEqual `
            -Expected $collisionBytes `
            -Actual ([System.IO.File]::ReadAllBytes($collisionPath)) `
            -Message 'Existing backup changed.'
        Assert-True -Condition (-not (Test-Path -LiteralPath $fixture.NewPath)) `
            -Message 'Destination was created.'
    }

    Invoke-Test 'returns source destination and backup hashes' {
        $fixture = New-TestCase 'result-hashes'
        Write-Utf8Fixture -Path $fixture.OldPath -Text "$oldRoot = { value = 7 }`n"
        $result = Invoke-FixtureMigration -Fixture $fixture
        $sourceHash = (
            Get-FileHash -LiteralPath $fixture.OldPath -Algorithm SHA256
        ).Hash
        $destinationHash = (
            Get-FileHash -LiteralPath $fixture.NewPath -Algorithm SHA256
        ).Hash
        $backupHash = (
            Get-FileHash -LiteralPath $result.BackupPath -Algorithm SHA256
        ).Hash
        Assert-True -Condition ($result.OldHash -eq $sourceHash) `
            -Message 'OldHash is incorrect.'
        Assert-True -Condition ($result.NewHash -eq $destinationHash) `
            -Message 'NewHash is incorrect.'
        Assert-True -Condition ($result.BackupHash -eq $backupHash) `
            -Message 'BackupHash is incorrect.'
    }
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

Write-Output "Migration tests: $passed passed, $failed failed"
if ($failed -gt 0) {
    exit 1
}

exit 0
