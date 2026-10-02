param(
    [switch]$Execute,
    [switch]$IncludeBrowserCache
)

$ErrorActionPreference = "SilentlyContinue"

function Format-Bytes {
    param([double]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "{0:N0} bytes" -f $Bytes
}

function Get-TargetFiles {
    param(
        [string]$Path,
        [string[]]$Patterns = @("*")
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    foreach ($pattern in $Patterns) {
        Get-ChildItem -LiteralPath $Path -Filter $pattern -Recurse -Force -File -ErrorAction SilentlyContinue
    }
}

function Clear-FolderFiles {
    param(
        [string]$Label,
        [string]$Path,
        [string[]]$Patterns = @("*")
    )

    $files = @(Get-TargetFiles -Path $Path -Patterns $Patterns)
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if (-not $bytes) { $bytes = 0 }

    $script:TotalFiles += $files.Count
    $script:TotalBytes += $bytes

    Write-Host ("{0}: {1} files, {2}" -f $Label, $files.Count, (Format-Bytes $bytes))

    if ($Execute -and $files.Count -gt 0) {
        foreach ($file in $files) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }

        # Remove empty folders left behind, deepest folders first.
        Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
    }
}

function Stop-SafeOptionalProcess {
    param([string]$Name)

    $processes = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    Write-Host ("Stopping optional process: {0}" -f $Name)
    if ($Execute) {
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

$TotalFiles = 0
$TotalBytes = 0
$temp = $env:TEMP
$localAppData = $env:LOCALAPPDATA

Write-Host "Safe cleanup scan"
Write-Host "Mode:" ($(if ($Execute) { "DELETE" } else { "PREVIEW only. Re-run with -Execute to delete." }))
Write-Host ""

Clear-FolderFiles -Label "User temp" -Path $temp
Clear-FolderFiles -Label "Windows temp" -Path "C:\Windows\Temp"
Clear-FolderFiles -Label "Windows error reports" -Path (Join-Path $localAppData "Microsoft\Windows\WER")
Clear-FolderFiles -Label "Crash dumps" -Path (Join-Path $localAppData "CrashDumps") -Patterns @("*.dmp", "*.mdmp")
Clear-FolderFiles -Label "Thumbnail cache" -Path (Join-Path $localAppData "Microsoft\Windows\Explorer") -Patterns @("thumbcache_*.db", "iconcache_*.db")
Clear-FolderFiles -Label "DirectX shader cache" -Path (Join-Path $localAppData "D3DSCache")
Clear-FolderFiles -Label "Delivery optimization cache" -Path "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"

if ($IncludeBrowserCache) {
    Write-Host ""
    Write-Host "Browser cache cleanup requested."
    Stop-SafeOptionalProcess -Name "chrome"
    Stop-SafeOptionalProcess -Name "brave"
    Stop-SafeOptionalProcess -Name "msedge"

    Clear-FolderFiles -Label "Chrome cache" -Path (Join-Path $localAppData "Google\Chrome\User Data\Default\Cache")
    Clear-FolderFiles -Label "Chrome code cache" -Path (Join-Path $localAppData "Google\Chrome\User Data\Default\Code Cache")
    Clear-FolderFiles -Label "Brave cache" -Path (Join-Path $localAppData "BraveSoftware\Brave-Browser\User Data\Default\Cache")
    Clear-FolderFiles -Label "Brave code cache" -Path (Join-Path $localAppData "BraveSoftware\Brave-Browser\User Data\Default\Code Cache")
    Clear-FolderFiles -Label "Edge cache" -Path (Join-Path $localAppData "Microsoft\Edge\User Data\Default\Cache")
    Clear-FolderFiles -Label "Edge code cache" -Path (Join-Path $localAppData "Microsoft\Edge\User Data\Default\Code Cache")
}

Write-Host ""
Write-Host ("Total matched: {0} files, {1}" -f $TotalFiles, (Format-Bytes $TotalBytes))

if ($Execute) {
    Write-Host "Cleanup finished. Some locked files may remain; that is normal."
    Write-Host "For memory release, restart Windows after cleanup."
}
else {
    Write-Host "No files were deleted."
    Write-Host "To delete safe temp/cache files: .\SafeCleanup.ps1 -Execute"
    Write-Host "To also clear browser cache and close browsers: .\SafeCleanup.ps1 -Execute -IncludeBrowserCache"
}
