$ErrorActionPreference = 'Stop'

$destRoot = 'I:\mobile\iq007\internal_storage'
$logPath = 'I:\mobile\iq007\mtp_copy_progress.log'

function Write-Log {
    param([string]$Message)
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line
}

Write-Log 'Starting MTP copy job.'

$shell = New-Object -ComObject Shell.Application
$pc = $shell.Namespace(17)
$phone = $pc.Items() | Where-Object { $_.Name -eq 'iQOO 7 Legend' } | Select-Object -First 1
if (-not $phone) { throw 'Phone not found in This PC view.' }

$phoneNs = $shell.Namespace($phone.Path)
$internal = @($phoneNs.Items()) | Where-Object { $_.Name -eq 'Internal storage' } | Select-Object -First 1
if (-not $internal) { throw 'Internal storage not found.' }
if (-not (Test-Path -LiteralPath $destRoot)) { throw 'Destination root not found.' }

$script:copied = 0
$script:skipped = 0
$script:foldersCreated = 0
$script:renamed = 0
$script:failed = 0
$script:invalidMapPath = 'I:\mobile\iq007\mtp_invalid_name_map.txt'
$script:failedLogPath = 'I:\mobile\iq007\mtp_copy_failed_items.txt'

function Get-SafeName {
    param([string]$Name)

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Name
    foreach ($char in $invalidChars) {
        $safe = $safe.Replace([string]$char, '_')
    }

    if ($safe -ne $Name) {
        $script:renamed++
        Add-Content -LiteralPath $script:invalidMapPath -Value ("{0}`t{1}" -f $Name, $safe)
        Write-Log ("Renamed invalid Windows name: '{0}' -> '{1}'" -f $Name, $safe)
    }

    return $safe
}

function Copy-MtpFolder {
    param(
        [Parameter(Mandatory = $true)] $SourceFolder,
        [Parameter(Mandatory = $true)] [string] $DestPath,
        [Parameter(Mandatory = $false)] [string] $DisplayPath = ''
    )

    foreach ($item in @($SourceFolder.Items())) {
        $name = [string]$item.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $safeName = Get-SafeName -Name $name

        $targetPath = Join-Path $DestPath $safeName
        $itemDisplayPath = if ($DisplayPath) { "$DisplayPath\$name" } else { $name }

        if ($item.IsFolder) {
            if (-not (Test-Path -LiteralPath $targetPath)) {
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                $script:foldersCreated++
                Write-Log ("Created folder: {0}" -f $itemDisplayPath)
            } else {
                Write-Log ("Scanning existing folder: {0}" -f $itemDisplayPath)
            }

            $childFolder = $item.GetFolder
            if ($childFolder) {
                Copy-MtpFolder -SourceFolder $childFolder -DestPath $targetPath -DisplayPath $itemDisplayPath
            }
        } else {
            if (Test-Path -LiteralPath $targetPath) {
                $script:skipped++
                Write-Log ("Skipped existing file: {0}" -f $itemDisplayPath)
            } else {
                $targetShell = $shell.Namespace($DestPath)
                if (-not $targetShell) { throw "Cannot open destination shell folder: $DestPath" }

                Write-Log ("Copying file: {0}" -f $itemDisplayPath)
                $targetShell.CopyHere($item, 16 + 1024)

                $waitCount = 0
                while (-not (Test-Path -LiteralPath $targetPath)) {
                    Start-Sleep -Milliseconds 300
                    $waitCount++
                    if ($waitCount -gt 400) {
                        $script:failed++
                        Add-Content -LiteralPath $script:failedLogPath -Value ("{0}`t{1}" -f $itemDisplayPath, $targetPath)
                        Write-Log ("Timed out and skipped: {0}" -f $itemDisplayPath)
                        $targetPath = $null
                        break
                    }
                }

                if ($targetPath) {
                    $script:copied++
                }
            }
        }
    }
}

try {
    Copy-MtpFolder -SourceFolder $internal.GetFolder -DestPath $destRoot
    Write-Log ("Completed. Folders created: {0}, Files copied: {1}, Files skipped(existing): {2}, Invalid-name rewrites: {3}, Failed items: {4}" -f $foldersCreated, $copied, $skipped, $renamed, $failed)
} catch {
    Write-Log ("FAILED: {0}" -f $_.Exception.Message)
    throw
}
