# 1. System Identity
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

$cpu = Get-CimInstance Win32_Processor
$gpuName = (Get-CimInstance Win32_VideoController | Where-Object { $_.Caption -notmatch "Remote|Microsoft|Basic" } | Select-Object -ExpandProperty Caption) -join " + "
$totalRamGB = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB)

# Settings
$dynamicThrottle = [math]::Max(4, [int]($cpu.NumberOfLogicalProcessors / 2))
$ramBuffer = "1G" # Using 1GB for FFmpeg's internal probesize

# 2. UI Header
Clear-Host
Write-Host "================ MEDIA INTEGRITY SCANNER ================" -ForegroundColor Cyan
Write-Host "MACHINE   : $env:COMPUTERNAME"
Write-Host "CPU       : $($cpu.Name.Trim())"
Write-Host "GPU       : $gpuName"
Write-Host "RAM       : $totalRamGB GB (Buffer: $ramBuffer)"
Write-Host "THROTTLE  : $dynamicThrottle Concurrent Scans" -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Cyan

# 3. Execution Data
$files = Get-ChildItem -Recurse -Include *.mkv, *.mp4 | Where-Object { $_.Length -gt 5mb }
$totalFiles = $files.Count
$sync = [hashtable]::Synchronized(@{ Count = 0; Errors = 0 })
$globalWatch = [System.Diagnostics.Stopwatch]::StartNew()

if ($totalFiles -eq 0) { Write-Host "No media files found!" -ForegroundColor Red; return }

# 4. The Loop
$files | ForEach-Object -ThrottleLimit $dynamicThrottle -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $s = $using:sync
    $watch = $using:globalWatch
    $total = $using:totalFiles
    
    # Accelerated selection
    $accel = ($using:gpuName -match "NVIDIA") ? "cuda" : "none"

    # Run FFmpeg
    $result = & $ffexe -hwaccel $accel -probesize $using:ramBuffer -v error -i $file.FullName -f null - 2>&1
    
    # Thread-Safe Counter Update
    $s.Count++
    
    # Robust ETA Calculation
    $elapsed = $watch.Elapsed.TotalSeconds
    $avg = $elapsed / $s.Count
    $remaining = $avg * ($total - $s.Count)
    $ts = [TimeSpan]::FromSeconds($remaining)
    $etaStr = "{0:D2}:{1:D2}:{2:D2}" -f $ts.Hours, $ts.Minutes, $ts.Seconds

    if ($result) { 
        $s.Errors++
        "[$(Get-Date)] [$($using:env:COMPUTERNAME)] FAIL: $($file.FullName)" | Out-File "corrupt_files.txt" -Append
        Write-Host "[!] FAIL: $($file.Name)" -ForegroundColor Red
    } else {
        $name = if ($file.Name.Length -gt 50) { $file.Name.Substring(0,47) + "..." } else { $file.Name }
        Write-Host "[$($s.Count)/$total] OK: $name | ETA: $etaStr" -ForegroundColor Green
    }
}

$globalWatch.Stop()
Write-Host "`nScan Finished. Total Time: $($globalWatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
if ($sync.Errors -eq 0) { Write-Host "Clean Scan! No corruption found." -ForegroundColor Green }
