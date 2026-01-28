# 1. Hardware Engine Discovery
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

$gpuSearch = Get-CimInstance Win32_VideoController | Where-Object { $_.Caption -notmatch "Remote|Microsoft|Basic" }
$hasQsv = $false; $dGpu = "none"

foreach ($gpu in $gpuSearch) {
    if ($gpu.Caption -match "NVIDIA") { $dGpu = "cuda" }
    elseif ($gpu.Caption -match "Intel") { $hasQsv = $true }
    elseif ($gpu.Caption -match "AMD|Radeon") { $dGpu = "d3d11va" }
}

# 2. Strategy Selector (Baseline Priority)
$primaryEngine = "none"
if ($hasQsv) {
    $primaryEngine = "qsv"
    $strategy = "Laptop Mode: QSV Primary -> SW Fallback"
} elseif ($dGpu -ne "none") {
    $primaryEngine = $dGpu
    $strategy = "Server Mode (Xeon/Ryzen): $($dGpu.ToUpper()) Primary -> SW Fallback"
} else {
    $strategy = "Software-Only Mode"
}

# 3. Data Setup
$allFiles = Get-ChildItem -Recurse -Include *.mkv, *.mp4 | Where-Object { $_.Length -gt 1mb }
$totalFiles = $allFiles.Count
$totalSizeInBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum

# 4. UI Header
Clear-Host
Write-Host "================ UNIVERSAL HYBRID SCANNER v7.6 ================" -ForegroundColor Cyan
Write-Host "MACHINE   : $env:COMPUTERNAME"
Write-Host "STRATEGY  : $strategy" -ForegroundColor Yellow
Write-Host "HW ENGINE : $($primaryEngine.ToUpper())"
Write-Host "===============================================================" -ForegroundColor Cyan

$sync = [hashtable]::Synchronized(@{ Count = 0; Errors = 0 })
$globalWatch = [System.Diagnostics.Stopwatch]::StartNew()

# 5. Parallel Execution
$allFiles | ForEach-Object -ThrottleLimit 8 -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $s = $using:sync
    $total = $using:totalFiles
    $watch = $using:globalWatch
    $engine = $using:primaryEngine

    $activeEngine = $engine
    $isFallback = $false

    # --- ATTEMPT 1: HARDWARE DECODE ---
    # We use a 1s timeout check (vignette) or just standard error piping
    $result = & $ffexe -hwaccel $activeEngine -probesize 16777216 -v error -i $file.FullName -f null - 2>&1
    
    # --- ATTEMPT 2: SOFTWARE FALLBACK ---
    # Triggered if Hardware fails (returns anything to $result)
    if ($result) {
        $isFallback = $true
        $activeEngine = "software"
        $result = & $ffexe -v error -i $file.FullName -f null - 2>&1
    }
    
    # Result Processing
    $s.Count++
    $eta = [TimeSpan]::FromSeconds(($watch.Elapsed.TotalSeconds / $s.Count) * ($total - $s.Count)).ToString("hh\:mm\:ss")
    
    # UI Output
    $displayEngine = if ($isFallback) { "SW-DECODE" } else { $engine.ToUpper().PadRight(9) }
    $statusColor = if ($result) { "Red" } else { "Green" }
    $name = if ($file.Name.Length -gt 35) { $file.Name.Substring(0,32) + "..." } else { $file.Name }
    
    Write-Host "[$($s.Count)/$total] $displayEngine | $name | ETA: $eta" -ForegroundColor $statusColor
}

# 6. Final Efficiency
$globalWatch.Stop()
$mbs = [math]::Round(($totalSizeInBytes / 1MB) / $globalWatch.Elapsed.TotalSeconds, 2)
Write-Host "`nEfficiency: $mbs MB/s | Total Time: $($globalWatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
