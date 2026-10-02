param(
    [string]$AdbPath = "C:\Users\ASUS\AppData\Local\Android\Sdk\platform-tools\adb.exe",
    [string]$Destination = "D:\mobile\iq007\internal_storage",
    [switch]$VerifyOnly,
    [switch]$FastTar
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$script:SanitizedPaths = New-Object System.Collections.Generic.List[string]

function ConvertTo-SafeWindowsSegment {
    param([string]$Segment)

    $safe = $Segment -replace '[<>:"/\\|?*]', '_'
    $safe = $safe.TrimEnd(" .")
    if (-not $safe) {
        $safe = "_"
    }
    return $safe
}

function Require-Command {
    param([string]$CommandPath, [string]$Name)

    if ($CommandPath -eq "tar") {
        $found = Get-Command tar -ErrorAction SilentlyContinue
        if (-not $found) {
            throw "Windows tar was not found in PATH."
        }
        return
    }

    if (-not (Test-Path -LiteralPath $CommandPath)) {
        throw "$Name was not found at: $CommandPath"
    }
}

function Run-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    & $AdbPath @Args
    if ($LASTEXITCODE -ne 0) {
        throw "ADB command failed: $($Args -join ' ')"
    }
}

function Invoke-AdbPull {
    param(
        [string]$PhonePath,
        [string]$LocalPath
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $AdbPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $escapedPhonePath = $PhonePath.Replace('"', '\"')
    $escapedLocalPath = $LocalPath.Replace('"', '\"')
    $psi.Arguments = "pull `"$escapedPhonePath`" `"$escapedLocalPath`""

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Output = (($stdout, $stderr) -join " ").Trim()
    }
}

function Get-RemoteFiles {
    Write-Host "Reading file list from phone..."
    $commands = @(
        "cd /sdcard && find . -type f 2>/dev/null; exit 0",
        "cd /storage/emulated/0 && find . -type f 2>/dev/null; exit 0"
    )

    $files = $null
    $lastOutput = $null

    foreach ($command in $commands) {
        $lastOutput = & $AdbPath shell $command
        if ($lastOutput) {
            $files = $lastOutput
            break
        }
    }

    if (-not $files) {
        Write-Host "ADB devices:"
        & $AdbPath devices -l
        Write-Host ""
        Write-Host "No readable files were returned from /sdcard or /storage/emulated/0."
        throw "Could not read /sdcard file list. Try setting USB mode to File Transfer, keep the phone unlocked, and confirm USB debugging is still allowed."
    }

    $readableFiles = @($files |
        ForEach-Object { $_.TrimEnd("`r") } |
        Where-Object { $_ -and $_ -ne "." -and $_ -notmatch "Permission denied" })

    $keptFiles = New-Object System.Collections.Generic.List[string]
    $skippedFiles = New-Object System.Collections.Generic.List[string]

    foreach ($file in $readableFiles) {
        if (Should-SkipRemoteFile $file) {
            $skippedFiles.Add($file)
        } else {
            $keptFiles.Add($file)
        }
    }

    if ($skippedFiles.Count -gt 0) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        $skipReport = Join-Path $Destination "_skipped_unneeded_files.txt"
        $skippedFiles | Set-Content -LiteralPath $skipReport -Encoding UTF8
        Write-Host "Skipped unneeded files: $($skippedFiles.Count)"
        Write-Host "Skipped file report: $skipReport"
    }

    $keptFiles
}

function Should-SkipRemoteFile {
    param([string]$RemotePath)

    $normalized = $RemotePath.TrimStart(".").TrimStart("/")
    $lower = $normalized.ToLowerInvariant()
    $leaf = ($lower -split "/")[-1]
    $extension = ""
    $lastDot = $leaf.LastIndexOf(".")
    if ($lastDot -ge 0 -and $lastDot -lt ($leaf.Length - 1)) {
        $extension = $leaf.Substring($lastDot)
    }

    $skipExtensions = @(
        ".tmp", ".temp", ".log", ".old", ".bak", ".backup",
        ".crdownload", ".download", ".part", ".partial",
        ".dmp", ".dump", ".trace", ".stacktrace"
    )

    if ($skipExtensions -contains $extension) {
        return $true
    }

    if ($leaf -in @("thumbs.db", "desktop.ini")) {
        return $true
    }

    $skipPathPatterns = @(
        "*/cache/*",
        "*/caches/*",
        "*/cached/*",
        "*/.cache/*",
        "*/tmp/*",
        "*/temp/*",
        "*/logs/*",
        "*/log/*",
        "*/crash/*",
        "*/crashes/*",
        "*/tombstones/*",
        "*/.thumbnails/*",
        "*/thumbnails/*",
        "*/debug/*",
        "*/diagnostics/*"
    )

    foreach ($pattern in $skipPathPatterns) {
        if ($lower -like $pattern) {
            return $true
        }
    }

    return $false
}

function Convert-RemotePathToLocalPath {
    param([string]$RemotePath)

    $relative = $RemotePath
    if ($relative.StartsWith("./")) {
        $relative = $relative.Substring(2)
    }

    $segments = $relative -split "/"
    $safeSegments = foreach ($segment in $segments) {
        ConvertTo-SafeWindowsSegment $segment
    }

    $safeRelative = $safeSegments -join "\"
    if ($safeRelative -ne ($relative -replace "/", "\")) {
        $script:SanitizedPaths.Add("$RemotePath => $safeRelative")
    }

    Join-Path $Destination $safeRelative
}

function Get-BackupCategory {
    param([string]$RemotePath)

    $normalizedPath = $RemotePath.TrimStart(".").TrimStart("/")
    if ($normalizedPath -like "Android/*") {
        return "Android"
    }

    $leafName = ($RemotePath -split "/")[-1]
    $lastDot = $leafName.LastIndexOf(".")
    $extension = ""
    if ($lastDot -ge 0 -and $lastDot -lt ($leafName.Length - 1)) {
        $extension = $leafName.Substring($lastDot).ToLowerInvariant()
    }

    $documents = @(
        ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
        ".txt", ".rtf", ".csv", ".tsv", ".odt", ".ods", ".odp",
        ".html", ".htm", ".xml", ".json", ".md", ".epub"
    )
    $images = @(
        ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".heic",
        ".heif", ".tif", ".tiff", ".svg", ".dng", ".raw"
    )
    $audio = @(
        ".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg", ".opus",
        ".amr", ".mid", ".midi", ".wma"
    )
    $video = @(
        ".mp4", ".mkv", ".mov", ".avi", ".3gp", ".webm", ".m4v",
        ".flv", ".wmv", ".ts"
    )

    if ($documents -contains $extension) {
        return "Documents"
    }
    if ($images -contains $extension) {
        return "Images"
    }
    if ($audio -contains $extension) {
        return "Audio"
    }
    if ($video -contains $extension) {
        return "Video"
    }
    return "Other"
}

function Get-BackupPriority {
    param([string]$Category)

    switch ($Category) {
        "Documents" { 1; break }
        "Images" { 2; break }
        "Audio" { 3; break }
        "Video" { 4; break }
        "Other" { 5; break }
        "Android" { 6; break }
        default { 5; break }
    }
}

function Get-PrioritizedRemoteFiles {
    param([string[]]$RemoteFiles)

    $RemoteFiles |
        ForEach-Object {
            $category = Get-BackupCategory $_
            [PSCustomObject]@{
                Path = $_
                Category = $category
                Priority = Get-BackupPriority $category
            }
        } |
        Sort-Object Priority, Path
}

function Verify-Backup {
    $remoteFiles = @(Get-RemoteFiles)
    $missing = New-Object System.Collections.Generic.List[string]

    $checked = 0
    foreach ($remote in $remoteFiles) {
        $checked++
        $local = Convert-RemotePathToLocalPath $remote
        if (-not (Test-Path -LiteralPath $local -PathType Leaf)) {
            $missing.Add($remote)
        }

        if (($checked % 1000) -eq 0) {
            Write-Host "Verified $checked / $($remoteFiles.Count) files..."
        }
    }

    Write-Host ""
    Write-Host "Verification complete."
    Write-Host "Remote files checked: $($remoteFiles.Count)"
    Write-Host "Missing locally: $($missing.Count)"

    if ($missing.Count -gt 0) {
        $report = Join-Path $Destination "_missing_files.txt"
        $missing | Set-Content -LiteralPath $report -Encoding UTF8
        Write-Host "Missing file report: $report"
        Write-Host "First missing files:"
        $missing | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        exit 2
    }

    if ($script:SanitizedPaths.Count -gt 0) {
        $sanitizedReport = Join-Path $Destination "_sanitized_windows_paths.txt"
        $script:SanitizedPaths | Sort-Object -Unique | Set-Content -LiteralPath $sanitizedReport -Encoding UTF8
        Write-Host "Sanitized path report: $sanitizedReport"
    }
}

function Copy-WithProgress {
    $remoteFiles = @(Get-RemoteFiles)
    Write-Host "Files found on phone: $($remoteFiles.Count)"
    $prioritizedFiles = @(Get-PrioritizedRemoteFiles $remoteFiles)

    Write-Host "Copy priority:"
    foreach ($group in ($prioritizedFiles | Group-Object Category | Sort-Object { Get-BackupPriority $_.Name })) {
        Write-Host "  $($group.Name): $($group.Count)"
    }
    Write-Host ""

    $copied = 0
    $skipped = 0
    $failed = New-Object System.Collections.Generic.List[string]
    $index = 0
    $currentCategory = $null

    foreach ($file in $prioritizedFiles) {
        $index++
        $remote = $file.Path
        if ($currentCategory -ne $file.Category) {
            $currentCategory = $file.Category
            Write-Host "Starting category: $currentCategory"
        }

        $local = Convert-RemotePathToLocalPath $remote

        $percent = 0
        if ($prioritizedFiles.Count -gt 0) {
            $percent = [int](($index / $prioritizedFiles.Count) * 100)
        }

        Write-Progress `
            -Activity "Backing up phone internal storage" `
            -Status "$currentCategory - $index / $($prioritizedFiles.Count): $remote" `
            -PercentComplete $percent

        if (Test-Path -LiteralPath $local -PathType Leaf) {
            $skipped++
            if (($index % 100) -eq 0) {
                Write-Host "Progress: $index / $($prioritizedFiles.Count), category=$currentCategory, copied=$copied, skipped=$skipped, failed=$($failed.Count)"
            }
            continue
        }

        $parent = Split-Path -Parent $local
        if ($parent) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }

        $phonePath = "/sdcard/" + ($remote.TrimStart(".") -replace "\\", "/").TrimStart("/")
        $pullResult = Invoke-AdbPull -PhonePath $phonePath -LocalPath $local

        if ($pullResult.ExitCode -eq 0 -and (Test-Path -LiteralPath $local -PathType Leaf)) {
            $copied++
        } else {
            $failed.Add("$remote`n  local: $local`n  adb: $($pullResult.Output)")
            Write-Warning "Failed: $remote"
        }

        if (($index % 25) -eq 0) {
            Write-Host "Progress: $index / $($prioritizedFiles.Count), category=$currentCategory, copied=$copied, skipped=$skipped, failed=$($failed.Count)"
        }
    }

    Write-Progress -Activity "Backing up phone internal storage" -Completed
    Write-Host ""
    Write-Host "Copy pass complete."
    Write-Host "Copied:  $copied"
    Write-Host "Skipped: $skipped"
    Write-Host "Failed:  $($failed.Count)"

    if ($failed.Count -gt 0) {
        $report = Join-Path $Destination "_failed_copy_files.txt"
        $failed | Set-Content -LiteralPath $report -Encoding UTF8
        Write-Host "Failed copy report: $report"
    }

    if ($script:SanitizedPaths.Count -gt 0) {
        $sanitizedReport = Join-Path $Destination "_sanitized_windows_paths.txt"
        $script:SanitizedPaths | Sort-Object -Unique | Set-Content -LiteralPath $sanitizedReport -Encoding UTF8
        Write-Host "Sanitized path report: $sanitizedReport"
    }
}

Require-Command $AdbPath "ADB"
Require-Command "tar" "tar"

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

Write-Host "Checking connected phone..."
Run-Adb devices
Run-Adb shell "test -d /sdcard"

if (-not $VerifyOnly) {
    Write-Host ""
    Write-Host "Starting backup:"
    Write-Host "  Source:      /sdcard"
    Write-Host "  Destination: $Destination"
    Write-Host "  Existing files: kept, not overwritten"
    if ($FastTar) {
        Write-Host "  Mode:        fast tar stream, no per-file progress"
    } else {
        Write-Host "  Mode:        per-file progress"
    }
    Write-Host ""

    if ($FastTar) {
        & $AdbPath exec-out "cd /sdcard && tar -cf - ." | tar -xkf - -C $Destination
        $tarExit = $LASTEXITCODE

        if ($tarExit -ne 0) {
            Write-Warning "Backup command returned exit code $tarExit. This can happen when files already exist or Android blocks access to some app-private paths."
        }
    } else {
        Copy-WithProgress
    }
}

Write-Host ""
Verify-Backup
