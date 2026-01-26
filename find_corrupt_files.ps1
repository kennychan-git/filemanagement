# 1. Setup paths and file discovery
$ffmpegPath = (Get-Command ffmpeg).Source
$files = Get-ChildItem -Recurse -Include *.mkv, *.mp4
$totalFiles = $files.Count
$counter = [hashtable]::Synchronized(@{ Count = 0 })
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

# 2. Advanced Multi-GPU Detection Logic
$gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Caption
$accel = "none"
$modeName = "Software (CPU)"

# Logic: Priority goes to Discrete GPUs (NVIDIA/AMD) over Integrated (Intel)
if ($gpus -match "NVIDIA") {
    $accel = "cuda"
    $modeName = "NVIDIA CUDA/NVDEC"
} elseif ($gpus -match "AMD" -or $gpus -match "Radeon") {
    # Check if it's an old R7 series (which might fail d3d11va)
    if ($gpus -match "R7" -or $gpus -match "HD 7000" -or $gpus -match "HD 8000") {
        $accel = "dxva2"  # Older AMD cards prefer the legacy DXVA2 API
        $modeName = "AMD Legacy (DXVA2)"
    } else {
        $accel = "d3d11va"
        $modeName = "AMD Modern (D3D11VA)"
    }
} elseif ($gpus -match "Intel") {
    $accel = "qsv"
    $modeName = "Intel QuickSync"
}

Write-Host ">>> System Hardware Identified: $gpus" -ForegroundColor Cyan
Write-Host ">>> Best Accelerator Chosen: $modeName" -ForegroundColor Yellow
Write-Host "--- Starting Scan ---"

# 3. Execution Block
$files | ForEach-Object -ThrottleLimit 4 -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $hw = $using:accel
    $sync = $using:counter
    $start = $using:startTime

    # Build command based on detection
    if ($hw -eq "none") {
        $check = & $ffexe -v error -i $file.FullName -f null - 2>&1
    } else {
        $check = & $ffexe -hwaccel $hw -v error -i $file.FullName -f null - 2>&1
    }
    
    # Progress Calculation
    $sync.Count++
    $c = $sync.Count
    $elapsed = $start.Elapsed.TotalSeconds
    $eta = [TimeSpan]::FromSeconds(($elapsed / $c) * ($using:totalFiles - $c)).ToString("hh\:mm\:ss")

    # Result Logging
    if ($check -match "error" -or $check -match "invalid" -or $check -match "corrupt") { 
        "$($file.FullName) - $($check)" | Out-File -FilePath "corrupt_files.txt" -Append -Encoding utf8
        Write-Host "[!] FAIL: $($file.Name) | ETA: $eta" -ForegroundColor Red
    } else {
        Write-Host "[$c/$($using:totalFiles)] OK: $($file.Name) | ETA: $eta" -ForegroundColor Green
    }
}

$startTime.Stop()
Write-Host "Scan Finished in $($startTime.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
