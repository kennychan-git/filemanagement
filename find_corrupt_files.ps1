$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

$files = Get-ChildItem -Recurse -Include *.mkv, *.mp4
$totalFiles = $files.Count
$counter = [hashtable]::Synchronized(@{ Count = 0 })
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

# Hardware Detection
$gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Caption -notmatch "Remote|Microsoft|Basic" } | Select-Object -ExpandProperty Caption
$accel = "none"

if ($gpus -match "NVIDIA") { $accel = "cuda" } 
elseif ($gpus -match "AMD|Radeon") {
    # HD 8000 series (like your 8490) usually needs dxva2, not d3d11va
    $accel = ($gpus -match "HD 8|HD 7|R7|R5") ? "dxva2" : "d3d11va"
} elseif ($gpus -match "Intel") { $accel = "qsv" }

Write-Host ">>> Using Hardware: $gpus (Mode: $accel)" -ForegroundColor Cyan

$files | ForEach-Object -ThrottleLimit 4 -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $hw = $using:accel
    $sync = $using:counter
    $start = $using:startTime

    # Attempt Hardware Scan first
    if ($hw -ne "none") {
        $check = & $ffexe -hwaccel $hw -v error -i $file.FullName -f null - 2>&1
        # If hardware fails immediately (Driver error), fallback to CPU
        if ($check -match "auto-decoder|failed|not supported") {
            $check = & $ffexe -v error -i $file.FullName -f null - 2>&1
        }
    } else {
        $check = & $ffexe -v error -i $file.FullName -f null - 2>&1
    }
    
    $sync.Count++
    $c = $sync.Count
    $elapsed = $start.Elapsed.TotalSeconds
    $eta = [TimeSpan]::FromSeconds(($elapsed / $c) * ($using:totalFiles - $c)).ToString("hh\:mm\:ss")

    if ($check -match "error|invalid|corrupt") { 
        # Thread-safe writing loop to avoid "File in use" errors
        $msg = "$($file.FullName) - $($check)"
        $done = $false
        while (-not $done) {
            try {
                $msg | Out-File -FilePath "corrupt_files.txt" -Append -Encoding utf8 -ErrorAction Stop
                $done = $true
            } catch { Start-Sleep -Milliseconds 100 }
        }
        Write-Host "[!] FAIL: $($file.Name)" -ForegroundColor Red
    } else {
        Write-Host "[$c/$($using:totalFiles)] OK: $($file.Name) | ETA: $eta" -ForegroundColor Green
    }
}
$startTime.Stop()
Write-Host "Scan Finished!" -ForegroundColor Yellow
