$ffmpegPath = (Get-Command ffmpeg).Source
$files = Get-ChildItem -Recurse -Include *.mkv, *.mp4
$totalFiles = $files.Count
$counter = [hashtable]::Synchronized(@{ Count = 0 })
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Starting GPU-Accelerated Scan (Throttle: 8)..." -ForegroundColor Cyan

$files | ForEach-Object -ThrottleLimit 8 -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $sync = $using:counter
    $start = $using:startTime

    # D3D11VA Hardware Acceleration for RX 580
    $check = & $ffexe -hwaccel d3d11va -v error -i $file.FullName -f null - 2>&1
    
    $sync.Count++
    $currentCount = $sync.Count

    # Calculate Time Remaining
    $elapsed = $start.Elapsed.TotalSeconds
    $avgTimePerFile = $elapsed / $currentCount
    $remainingFiles = $using:totalFiles - $currentCount
    $secondsLeft = $avgTimePerFile * $remainingFiles
    $eta = [TimeSpan]::FromSeconds($secondsLeft).ToString("hh\:mm\:ss")

    Write-Progress -Activity "AMD GPU Integrity Scan" `
                   -Status "Files: $currentCount/$($using:totalFiles) | ETA: $eta" `
                   -PercentComplete (($currentCount / $using:totalFiles) * 100) `
                   -CurrentOperation "Current: $($file.Name)"

    if ($check) { 
        "$($file.FullName) - $($check)" | Out-File -FilePath "corrupt_files.txt" -Append -Encoding utf8
        Write-Host "[!] Found Corruption: $($file.Name)" -ForegroundColor Red
    }
}

$startTime.Stop()
$totalTime = $startTime.Elapsed.ToString("hh\:mm\:ss")
Write-Host "Scan Complete in $totalTime! Check corrupt_files.txt" -ForegroundColor Green
