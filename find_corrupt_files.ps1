# 1. Locate FFmpeg (Auto-finds it in Jellyfin folder)
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

if (-not (Test-Path $ffmpegPath)) {
    Write-Host "[!] ERROR: FFmpeg not found. I checked the Jellyfin folder but it's not there." -ForegroundColor Red
    return
}

$files = Get-ChildItem -Recurse -Include *.mkv, *.mp4
$totalFiles = $files.Count
$counter = [hashtable]::Synchronized(@{ Count = 0 })
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

# 2. Hardware Detection (Bypasses RDP/Remote Display Adapter)
$gpus = Get-CimInstance Win32_VideoController | Where-Object { 
    $_.Caption -notmatch "Remote" -and $_.Caption -notmatch "Microsoft" -and $_.Caption -notmatch "Basic"
} | Select-Object -ExpandProperty Caption

$accel = "none"
$modeName = "Software (CPU)"

if ($gpus -match "NVIDIA") {
    $accel = "cuda"; $modeName = "NVIDIA CUDA/NVDEC"
} elseif ($gpus -match "AMD" -or $gpus -match "Radeon") {
    $accel = ($gpus -match "R7|HD 7000|HD 8000") ? "dxva2" : "d3d11va"
    $modeName = "AMD ($accel)"
} elseif ($gpus -match "Intel") {
    $accel = "qsv"; $modeName = "Intel QuickSync"
}

Write-Host ">>> FFmpeg Path: $ffmpegPath" -ForegroundColor Gray
Write-Host ">>> Actual Hardware Found: $gpus" -ForegroundColor Cyan
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
        # Using -hwaccel to force the GPU to handle the heavy decoding
        $check = & $ffexe -hwaccel $hw -v error -i $file.FullName -f null - 2>&1
    }
    
    $sync.Count++
    $c = $sync.Count
    $elapsed = $start.Elapsed.TotalSeconds
    $eta = [TimeSpan]::FromSeconds(($elapsed / $c) * ($using:totalFiles - $c)).ToString("hh\:mm\:ss")

    if ($check -match "error" -or $check -match "invalid" -or $check -match "corrupt") { 
        "$($file.FullName) - $($check)" | Out-File -FilePath "corrupt_files.txt" -Append -Encoding utf8
        Write-Host "[!] FAIL: $($file.Name) | ETA: $eta" -ForegroundColor Red
    } else {
        Write-Host "[$c/$($using:totalFiles)] OK: $($file.Name) | ETA: $eta" -ForegroundColor Green
    }
}

$startTime.Stop()
Write-Host "Scan Finished in $($startTime.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
