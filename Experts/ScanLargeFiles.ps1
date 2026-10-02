param(
    [string[]]$Path = @("C:\"),
    [int]$MinSizeMB = 500,
    [int]$Top = 50,
    [switch]$IncludeDDrive,
    [switch]$NoProgress,
    [string]$ReportPath = ""
)

$ErrorActionPreference = "SilentlyContinue"

function Format-Bytes {
    param([double]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "{0:N0} bytes" -f $Bytes
}

function Get-LargeFiles {
    param(
        [string[]]$ScanPaths,
        [int64]$MinimumBytes
    )

    $checked = 0
    $matched = 0
    $timer = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($scanPath in $ScanPaths) {
        if (-not (Test-Path -LiteralPath $scanPath)) {
            Write-Warning "Path not found: $scanPath"
            continue
        }

        Write-Host "Scanning files in $scanPath ..."
        foreach ($file in Get-ChildItem -LiteralPath $scanPath -Recurse -Force -File -ErrorAction SilentlyContinue) {
            $checked++

            if (-not $NoProgress -and ($checked % 250 -eq 0)) {
                $status = "Checked: $checked | Matches: $matched | Elapsed: {0:N0}s" -f $timer.Elapsed.TotalSeconds
                Write-Progress -Activity "Scanning large files" -Status $status -CurrentOperation $file.FullName
            }

            if ($file.Length -ge $MinimumBytes) {
                $matched++
                [pscustomobject]@{
                    FullName = $file.FullName
                    SizeGB = [math]::Round($file.Length / 1GB, 2)
                    SizeMB = [math]::Round($file.Length / 1MB, 1)
                    LastWriteTime = $file.LastWriteTime
                }
            }
        }
    }

    if (-not $NoProgress) {
        Write-Progress -Activity "Scanning large files" -Completed
    }
}

function Get-TopFolderSizes {
    param(
        [string[]]$ScanPaths,
        [int]$Limit
    )

    foreach ($scanPath in $ScanPaths) {
        if (-not (Test-Path -LiteralPath $scanPath)) {
            continue
        }

        Write-Host "Checking biggest direct folders in $scanPath ..."
        $folders = @(Get-ChildItem -LiteralPath $scanPath -Force -Directory -ErrorAction SilentlyContinue)
        $index = 0

        foreach ($folder in $folders) {
            $index++

            if (-not $NoProgress) {
                Write-Progress -Activity "Checking top-level folder sizes" -Status "$index of $($folders.Count)" -CurrentOperation $folder.FullName
            }

            $sum = (Get-ChildItem -LiteralPath $folder.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum

            if (-not $sum) { $sum = 0 }

            [pscustomobject]@{
                Folder = $folder.FullName
                SizeGB = [math]::Round($sum / 1GB, 2)
                SizeMB = [math]::Round($sum / 1MB, 1)
            }
        }

        if (-not $NoProgress) {
            Write-Progress -Activity "Checking top-level folder sizes" -Completed
        }
    }
}

if ($IncludeDDrive -and -not ($Path -contains "D:\")) {
    $Path += "D:\"
}

$minimumBytes = $MinSizeMB * 1MB

Write-Host "Large file scan only. Nothing will be deleted."
Write-Host ("Paths: {0}" -f ($Path -join ", "))
Write-Host ("Minimum file size: {0}" -f (Format-Bytes $minimumBytes))
Write-Host ""

$largeFiles = @(Get-LargeFiles -ScanPaths $Path -MinimumBytes $minimumBytes |
    Sort-Object SizeMB -Descending |
    Select-Object -First $Top)

Write-Host ""
Write-Host ("Top large files, max {0}:" -f $Top)
$largeFiles | Format-Table -AutoSize

Write-Host ""
Write-Host "Biggest top-level folders:"
$topFolders = @(Get-TopFolderSizes -ScanPaths $Path -Limit 15)
$topFolders |
    Sort-Object SizeMB -Descending |
    Select-Object -First 15 |
    Format-Table -AutoSize

if ($ReportPath -ne "") {
    $report = [ordered]@{
        ScanTime = Get-Date
        Paths = $Path
        MinSizeMB = $MinSizeMB
        LargeFiles = $largeFiles
        TopFolders = $topFolders
    }

    $report | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $ReportPath -Encoding UTF8
    Write-Host ""
    Write-Host "Report saved to: $ReportPath"
}

Write-Host ""
Write-Host "Tip: review results before deleting anything. Do not remove files from Windows, Program Files, or AppData unless you know what they are."
