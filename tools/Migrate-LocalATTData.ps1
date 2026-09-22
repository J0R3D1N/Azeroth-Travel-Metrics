param(
    [string]$OldSavedVariablesPath = (
        'D:\Games\World of Warcraft\_classic_beta_\WTF\Account\' +
        '50347838#1\SavedVariables\AzerothTravelTracker.lua'
    ),
    [string]$NewSavedVariablesPath = (
        'D:\Games\World of Warcraft\_classic_beta_\WTF\Account\' +
        '50347838#1\SavedVariables\AzerothTravelMetrics.lua'
    ),
    [string]$BackupDirectory = (
        'D:\Games\World of Warcraft\_classic_beta_\WTF\ForeverSVFix\' +
        'migration-backups'
    ),
    [string]$WowProcessName = 'WowB'
)

$ErrorActionPreference = 'Stop'

function Test-ByteArraysEqual {
    param(
        [byte[]]$Left,
        [byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }

    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }

    return $true
}

function Write-NewFileBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $stream = New-Object System.IO.FileStream(
        $Path,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush()
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-LocalSavedVariablesMigration {
    param(
        [Parameter(Mandatory)][string]$OldSavedVariablesPath,
        [Parameter(Mandatory)][string]$NewSavedVariablesPath,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [string]$WowProcessName = 'WowB',
        [datetime]$BackupTimestamp = (Get-Date)
    )

    if (Get-Process -Name $WowProcessName -ErrorAction SilentlyContinue) {
        throw 'WoW must be closed before migrating SavedVariables.'
    }
    if (-not (Test-Path -LiteralPath $OldSavedVariablesPath -PathType Leaf)) {
        throw "Legacy SavedVariables source does not exist or is not a file: $OldSavedVariablesPath"
    }
    if (Test-Path -LiteralPath $NewSavedVariablesPath) {
        throw "ATM SavedVariables destination already exists: $NewSavedVariablesPath"
    }

    $sourceBytes = [System.IO.File]::ReadAllBytes($OldSavedVariablesPath)
    $hasBom = (
        $sourceBytes.Length -ge 3 -and
        $sourceBytes[0] -eq 0xEF -and
        $sourceBytes[1] -eq 0xBB -and
        $sourceBytes[2] -eq 0xBF
    )
    $bodyOffset = 0
    if ($hasBom) {
        $bodyOffset = 3
    }

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $text = $strictUtf8.GetString(
            $sourceBytes,
            $bodyOffset,
            $sourceBytes.Length - $bodyOffset
        )
    }
    catch [System.Text.DecoderFallbackException] {
        throw "Legacy SavedVariables source is not valid UTF-8: $OldSavedVariablesPath"
    }

    $rootPattern = '(?m)^AzerothTravelTrackerDB(?=[ \t]*=(?![ \t]*=))'
    $rootMatches = [regex]::Matches($text, $rootPattern)
    if ($rootMatches.Count -ne 1) {
        throw (
            'Expected exactly one top-level legacy SavedVariables root, ' +
            "found $($rootMatches.Count)."
        )
    }

    $oldRootBytes = [System.Text.Encoding]::ASCII.GetBytes(
        'AzerothTravelTrackerDB'
    )
    $newRootBytes = [System.Text.Encoding]::ASCII.GetBytes(
        'AzerothTravelMetricsDB'
    )
    if ($oldRootBytes.Length -ne $newRootBytes.Length) {
        throw 'SavedVariables root names must have equal byte lengths.'
    }

    $rootByteOffset = $bodyOffset + $strictUtf8.GetByteCount(
        $text.Substring(0, $rootMatches[0].Index)
    )
    $destinationBytes = [byte[]]$sourceBytes.Clone()
    [System.Array]::Copy(
        $newRootBytes,
        0,
        $destinationBytes,
        $rootByteOffset,
        $newRootBytes.Length
    )

    $roundTripBytes = [byte[]]$destinationBytes.Clone()
    [System.Array]::Copy(
        $oldRootBytes,
        0,
        $roundTripBytes,
        $rootByteOffset,
        $oldRootBytes.Length
    )
    if (-not (Test-ByteArraysEqual -Left $sourceBytes -Right $roundTripBytes)) {
        throw 'Migration byte round-trip verification failed.'
    }

    $currentSourceBytes = [System.IO.File]::ReadAllBytes(
        $OldSavedVariablesPath
    )
    if (-not (Test-ByteArraysEqual -Left $sourceBytes -Right $currentSourceBytes)) {
        throw 'Legacy SavedVariables source changed during migration validation.'
    }

    $stamp = $BackupTimestamp.ToString('yyyyMMdd_HHmmss')
    $backupPath = Join-Path $BackupDirectory (
        "AzerothTravelTracker_$stamp.lua"
    )
    if (Test-Path -LiteralPath $backupPath) {
        throw "Migration backup already exists: $backupPath"
    }

    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $backupPath) {
        throw "Migration backup already exists: $backupPath"
    }
    try {
        Write-NewFileBytes -Path $backupPath -Bytes $sourceBytes
    }
    catch [System.IO.IOException] {
        if (Test-Path -LiteralPath $backupPath) {
            throw "Migration backup already exists or could not be created safely: $backupPath"
        }
        throw
    }

    $backupBytes = [System.IO.File]::ReadAllBytes($backupPath)
    if (-not (Test-ByteArraysEqual -Left $sourceBytes -Right $backupBytes)) {
        throw "Migration backup byte verification failed: $backupPath"
    }

    $currentSourceBytes = [System.IO.File]::ReadAllBytes(
        $OldSavedVariablesPath
    )
    if (-not (Test-ByteArraysEqual -Left $sourceBytes -Right $currentSourceBytes)) {
        throw 'Legacy SavedVariables source changed before destination creation.'
    }

    Write-NewFileBytes -Path $NewSavedVariablesPath -Bytes $destinationBytes

    $writtenDestinationBytes = [System.IO.File]::ReadAllBytes(
        $NewSavedVariablesPath
    )
    if (
        -not (
            Test-ByteArraysEqual `
                -Left $destinationBytes `
                -Right $writtenDestinationBytes
        )
    ) {
        throw 'ATM SavedVariables destination byte verification failed.'
    }

    $currentSourceBytes = [System.IO.File]::ReadAllBytes(
        $OldSavedVariablesPath
    )
    if (-not (Test-ByteArraysEqual -Left $sourceBytes -Right $currentSourceBytes)) {
        throw 'Legacy SavedVariables source changed during destination creation.'
    }

    return [pscustomobject]@{
        BackupPath = $backupPath
        OldHash = (
            Get-FileHash -LiteralPath $OldSavedVariablesPath -Algorithm SHA256
        ).Hash
        NewHash = (
            Get-FileHash -LiteralPath $NewSavedVariablesPath -Algorithm SHA256
        ).Hash
        BackupHash = (
            Get-FileHash -LiteralPath $backupPath -Algorithm SHA256
        ).Hash
    }
}

if ($env:ATM_MIGRATION_FUNCTIONS_ONLY -ne '1') {
    Invoke-LocalSavedVariablesMigration `
        -OldSavedVariablesPath $OldSavedVariablesPath `
        -NewSavedVariablesPath $NewSavedVariablesPath `
        -BackupDirectory $BackupDirectory `
        -WowProcessName $WowProcessName
}
