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

function Get-BytesSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (
            [System.BitConverter]::ToString(
                $sha256.ComputeHash($Bytes)
            ).Replace('-', '')
        )
    }
    finally {
        $sha256.Dispose()
    }
}

function Read-AllStreamBytes {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)

    if ($Stream.Length -gt [int]::MaxValue) {
        throw 'Legacy SavedVariables source is too large to migrate safely.'
    }

    $Stream.Position = 0
    $bytes = New-Object byte[] ([int]$Stream.Length)
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -eq 0) {
            throw 'Legacy SavedVariables source ended before its snapshot was complete.'
        }
        $offset += $read
    }

    return ,$bytes
}

function Get-LuaLongBracket {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$Index
    )

    if ($Index -ge $Text.Length -or $Text[$Index] -ne '[') {
        return $null
    }

    $cursor = $Index + 1
    while ($cursor -lt $Text.Length -and $Text[$cursor] -eq '=') {
        $cursor++
    }
    if ($cursor -ge $Text.Length -or $Text[$cursor] -ne '[') {
        return $null
    }

    $equalsCount = $cursor - $Index - 1
    return [pscustomobject]@{
        OpenLength = $equalsCount + 2
        Close = ']' + ('=' * $equalsCount) + ']'
    }
}

function Find-LuaRootAssignments {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$RootName
    )

    $matches = New-Object 'System.Collections.Generic.List[int]'
    $index = 0
    $lineStart = $true

    while ($index -lt $Text.Length) {
        $character = $Text[$index]

        if ($character -eq "`r" -or $character -eq "`n") {
            if (
                $character -eq "`r" -and
                $index + 1 -lt $Text.Length -and
                $Text[$index + 1] -eq "`n"
            ) {
                $index += 2
            }
            else {
                $index++
            }
            $lineStart = $true
            continue
        }

        if (
            $character -eq '-' -and
            $index + 1 -lt $Text.Length -and
            $Text[$index + 1] -eq '-'
        ) {
            $longComment = Get-LuaLongBracket -Text $Text -Index ($index + 2)
            if ($null -ne $longComment) {
                $contentIndex = $index + 2 + $longComment.OpenLength
                $closeIndex = $Text.IndexOf(
                    $longComment.Close,
                    $contentIndex,
                    [System.StringComparison]::Ordinal
                )
                if ($closeIndex -lt 0) {
                    throw 'Lua source has an unterminated long comment; root detection is ambiguous.'
                }
                $index = $closeIndex + $longComment.Close.Length
                $lineStart = $false
                continue
            }

            $index += 2
            while (
                $index -lt $Text.Length -and
                $Text[$index] -ne "`r" -and
                $Text[$index] -ne "`n"
            ) {
                $index++
            }
            continue
        }

        if ($character -eq '[') {
            $longString = Get-LuaLongBracket -Text $Text -Index $index
            if ($null -ne $longString) {
                $contentIndex = $index + $longString.OpenLength
                $closeIndex = $Text.IndexOf(
                    $longString.Close,
                    $contentIndex,
                    [System.StringComparison]::Ordinal
                )
                if ($closeIndex -lt 0) {
                    throw 'Lua source has an unterminated long string; root detection is ambiguous.'
                }
                $index = $closeIndex + $longString.Close.Length
                $lineStart = $false
                continue
            }
        }

        if ($character -eq "'" -or $character -eq '"') {
            $quote = $character
            $index++
            $closed = $false
            while ($index -lt $Text.Length) {
                $quotedCharacter = $Text[$index]
                if ($quotedCharacter -eq '\') {
                    $index++
                    if ($index -ge $Text.Length) {
                        break
                    }
                    if (
                        $Text[$index] -eq "`r" -and
                        $index + 1 -lt $Text.Length -and
                        $Text[$index + 1] -eq "`n"
                    ) {
                        $index += 2
                    }
                    else {
                        $index++
                    }
                    continue
                }
                if ($quotedCharacter -eq $quote) {
                    $index++
                    $closed = $true
                    break
                }
                if (
                    $quotedCharacter -eq "`r" -or
                    $quotedCharacter -eq "`n"
                ) {
                    throw 'Lua source has a malformed quoted string; root detection is ambiguous.'
                }
                $index++
            }
            if (-not $closed) {
                throw 'Lua source has an unterminated quoted string; root detection is ambiguous.'
            }
            $lineStart = $false
            continue
        }

        if (
            $lineStart -and
            $index + $RootName.Length -le $Text.Length -and
            [string]::Compare(
                $Text,
                $index,
                $RootName,
                0,
                $RootName.Length,
                [System.StringComparison]::Ordinal
            ) -eq 0
        ) {
            $cursor = $index + $RootName.Length
            while (
                $cursor -lt $Text.Length -and
                ($Text[$cursor] -eq ' ' -or $Text[$cursor] -eq "`t")
            ) {
                $cursor++
            }
            if ($cursor -lt $Text.Length -and $Text[$cursor] -eq '=') {
                $operatorCursor = $cursor + 1
                while (
                    $operatorCursor -lt $Text.Length -and
                    (
                        $Text[$operatorCursor] -eq ' ' -or
                        $Text[$operatorCursor] -eq "`t"
                    )
                ) {
                    $operatorCursor++
                }
                if (
                    $operatorCursor -ge $Text.Length -or
                    '=<>~'.IndexOf($Text[$operatorCursor]) -lt 0
                ) {
                    $matches.Add($index)
                }
            }
        }

        $lineStart = $false
        $index++
    }

    return [pscustomobject]@{
        Indexes = [int[]]$matches.ToArray()
    }
}

function Write-VerifiedNewFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][scriptblock]$WriteBytesHook,
        [Parameter(Mandatory)][scriptblock]$ReadVerifiedBytesHook,
        [Parameter(Mandatory)][string]$VerificationFailureMessage,
        [Parameter(Mandatory)][string]$CollisionFailureMessage
    )

    $created = $false
    $stream = $null
    try {
        try {
            $stream = New-Object System.IO.FileStream(
                $Path,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )
            $created = $true
        }
        catch [System.IO.IOException] {
            if (Test-Path -LiteralPath $Path) {
                throw "$CollisionFailureMessage`: $Path"
            }
            throw
        }

        try {
            & $WriteBytesHook $stream $Bytes $Path
        }
        finally {
            $stream.Dispose()
            $stream = $null
        }

        $verifiedBytes = [byte[]]@(& $ReadVerifiedBytesHook $Path)
        if (-not (Test-ByteArraysEqual -Left $Bytes -Right $verifiedBytes)) {
            throw "$VerificationFailureMessage`: $Path"
        }

        return [pscustomobject]@{
            Bytes = $verifiedBytes
        }
    }
    catch {
        $failure = $_
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        if ($created -and (Test-Path -LiteralPath $Path)) {
            try {
                Remove-Item -LiteralPath $Path -Force
            }
            catch {
                throw (
                    "Failed to remove incomplete output '$Path' after: " +
                    $failure.Exception.Message
                )
            }
        }
        throw $failure
    }
}

function Invoke-LocalSavedVariablesMigration {
    param(
        [Parameter(Mandatory)][string]$OldSavedVariablesPath,
        [Parameter(Mandatory)][string]$NewSavedVariablesPath,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [string]$WowProcessName = 'WowB',
        [datetime]$BackupTimestamp = (Get-Date),
        [scriptblock]$WriteBytesHook,
        [scriptblock]$ReadVerifiedBytesHook,
        [scriptblock]$ProcessCheckHook
    )

    if ($null -eq $WriteBytesHook) {
        $WriteBytesHook = {
            param($Stream, [byte[]]$Bytes, [string]$Path)
            $Stream.Write($Bytes, 0, $Bytes.Length)
            $Stream.Flush()
        }
    }
    if ($null -eq $ReadVerifiedBytesHook) {
        $ReadVerifiedBytesHook = {
            param([string]$Path)
            return [System.IO.File]::ReadAllBytes($Path)
        }
    }
    if ($null -eq $ProcessCheckHook) {
        $ProcessCheckHook = {
            param([string]$Name)
            return $null -ne (
                Get-Process -Name $Name -ErrorAction SilentlyContinue |
                    Select-Object -First 1
            )
        }
    }

    if (& $ProcessCheckHook $WowProcessName) {
        throw 'WoW must be closed before migrating SavedVariables.'
    }
    if (-not (Test-Path -LiteralPath $OldSavedVariablesPath -PathType Leaf)) {
        throw "Legacy SavedVariables source does not exist or is not a file: $OldSavedVariablesPath"
    }
    if (Test-Path -LiteralPath $NewSavedVariablesPath) {
        throw "ATM SavedVariables destination already exists: $NewSavedVariablesPath"
    }

    try {
        $sourceStream = New-Object System.IO.FileStream(
            $OldSavedVariablesPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
    }
    catch {
        throw "Legacy SavedVariables source could not be opened safely: $OldSavedVariablesPath"
    }

    try {
        $sourceBytes = Read-AllStreamBytes -Stream $sourceStream
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

        $oldRootName = 'AzerothTravelTrackerDB'
        $newRootName = 'AzerothTravelMetricsDB'
        $rootScan = Find-LuaRootAssignments -Text $text -RootName $oldRootName
        $rootMatches = [int[]]$rootScan.Indexes
        if ($rootMatches.Count -ne 1) {
            throw (
                'Expected exactly one top-level legacy SavedVariables root, ' +
                "found $($rootMatches.Count)."
            )
        }

        $newRootScan = Find-LuaRootAssignments -Text $text -RootName $newRootName
        $newRootMatches = [int[]]$newRootScan.Indexes
        if ($newRootMatches.Count -ne 0) {
            throw (
                'Expected zero top-level ATM SavedVariables roots, ' +
                "found $($newRootMatches.Count)."
            )
        }

        $oldRootBytes = [System.Text.Encoding]::ASCII.GetBytes(
            $oldRootName
        )
        $newRootBytes = [System.Text.Encoding]::ASCII.GetBytes(
            $newRootName
        )
        if ($oldRootBytes.Length -ne $newRootBytes.Length) {
            throw 'SavedVariables root names must have equal byte lengths.'
        }

        $rootByteOffset = $bodyOffset + $strictUtf8.GetByteCount(
            $text.Substring(0, $rootMatches[0])
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
        if (& $ProcessCheckHook $WowProcessName) {
            throw 'WoW must be closed before migrating SavedVariables.'
        }

        $backupResult = Write-VerifiedNewFile `
            -Path $backupPath `
            -Bytes $sourceBytes `
            -WriteBytesHook $WriteBytesHook `
            -ReadVerifiedBytesHook $ReadVerifiedBytesHook `
            -VerificationFailureMessage 'Migration backup byte verification failed' `
            -CollisionFailureMessage (
                'Migration backup already exists or could not be created safely'
            )
        $backupBytes = [byte[]]$backupResult.Bytes

        if (& $ProcessCheckHook $WowProcessName) {
            throw 'WoW must be closed before migrating SavedVariables.'
        }

        $destinationResult = Write-VerifiedNewFile `
            -Path $NewSavedVariablesPath `
            -Bytes $destinationBytes `
            -WriteBytesHook $WriteBytesHook `
            -ReadVerifiedBytesHook $ReadVerifiedBytesHook `
            -VerificationFailureMessage (
                'ATM SavedVariables destination byte verification failed'
            ) `
            -CollisionFailureMessage (
                'ATM SavedVariables destination already exists or could not be created safely'
            )
        $writtenDestinationBytes = [byte[]]$destinationResult.Bytes

        return [pscustomobject]@{
            BackupPath = $backupPath
            OldHash = Get-BytesSha256 -Bytes $sourceBytes
            NewHash = Get-BytesSha256 -Bytes $writtenDestinationBytes
            BackupHash = Get-BytesSha256 -Bytes $backupBytes
        }
    }
    finally {
        $sourceStream.Dispose()
    }
}

if ($env:ATM_MIGRATION_FUNCTIONS_ONLY -ne '1') {
    Invoke-LocalSavedVariablesMigration `
        -OldSavedVariablesPath $OldSavedVariablesPath `
        -NewSavedVariablesPath $NewSavedVariablesPath `
        -BackupDirectory $BackupDirectory `
        -WowProcessName $WowProcessName
}
