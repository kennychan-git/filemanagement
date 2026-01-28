# 1. Hardware Engine Audit
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

$gpuSearch = Get-CimInstance Win32_VideoController | Where-Object { $_.Caption -notmatch "Remote|Microsoft|Basic" }
$engines = @()
foreach ($gpu in $gpuSearch) {
    if ($gpu.Caption -match "NVIDIA") { $engines += "cuda" }
    elseif ($gpu.Caption -match "Intel") { $engines += "qsv" }
}

# --- THE STATIC STRATEGY ---
# If Intel is found, we lock the whole machine to QSV for maximum stability.
# If only NVIDIA is found (Xeon), we use CUDA with a safety cap.
$finalEngine = "none"
if ($engines -contains "qsv") {
    $finalEngine = "qsv"
    $strategy = "iGPU Priority (Global)"
    $maxThreads = 8
} elseif ($engines -contains "cuda") {
    $finalEngine = "cuda"
    $strategy = "dGPU Fallback (Xeon/Discrete)"
    $maxThreads = 2 # Keep VRAM safe on 4GB/8GB cards
} else {
    $finalEngine = "none"
    $strategy = "Software Only"
    $maxThreads = 4
}

# 2. UI Header
Clear-Host
Write-Host "================ UNIVERSAL HYBRID SCANNER v6.0 ================" -ForegroundColor Cyan
Write-Host "MACHINE   : $env:COMPUTERNAME"
Write-Host "STRATEGY  : $strategy" -ForegroundColor Yellow
Write-Host "ENGINE    : $($finalEngine.ToUpper())" -ForegroundColor Yellow
Write-Host "THROTTLE  : $maxThreads Concurrent Scans"
Write-Host "===============================================================" -ForegroundColor Cyan

# 3. Data Setup
$files = Get-ChildItem -Recurse -Include *.mkv, *.mp4 | Where-Object { $_.Length -gt 5mb }
$totalFiles = $files.Count
$totalSizeInBytes = ($files | Measure-Object -Property Length -Sum).Sum
$sync = [hashtable]::Synchronized(@{ Count = 0; Errors = 0 })
$globalWatch = [System.Diagnostics.Stopwatch]::StartNew()

# 4. The Loop
$files | ForEach-Object -ThrottleLimit $maxThreads -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $s = $using:sync
    $engine = $using:finalEngine
    
    # Execution (Aggressive 32MB buffer for VRAM safety)
    $result = & $ffexe -hwaccel $engine -probesize 33554432 -v error -i $file.FullName -f null - 2>&1
    
    $displayEngine = $engine.ToUpper().PadRight(5)

    # Fallback to Software if HW fails
    if ($result) {
        $result = & $ffexe -v error -i $file.FullName -f null - 2>&1
        $displayEngine = "SW   "
    }
    
    $s.Count++
    $elapsed = $using:globalWatch.Elapsed.TotalSeconds
    $eta = [TimeSpan]::FromSeconds(($elapsed / $s.Count) * ($using:totalFiles - $s.Count)).ToString("hh\:mm\:ss")

    $name = if ($file.Name.Length -gt 40) { $file.Name.Substring(0,37) + "..." } else { $file.Name }
    Write-Host "[$($s.Count)/$($using:totalFiles)] OK: $name | $displayEngine | ETA: $eta" -ForegroundColor Green
}

# 5. Efficiency Score
$globalWatch.Stop()
$mbs = [math]::Round(($totalSizeInBytes / 1MB) / $globalWatch.Elapsed.TotalSeconds, 2)
Write-Host "`nEfficiency: $mbs MB/s | Total Time: $($globalWatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
