# 1. System Identity & Environment Setup
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

$cpuName = (Get-CimInstance Win32_Processor).Name.Trim()
$gpuName = (Get-CimInstance Win32_VideoController | Where-Object { $_.Caption -notmatch "Remote|Microsoft|Basic" } | Select-Object -ExpandProperty Caption) -join " + "
$computerName = $env:COMPUTERNAME

# 2. Determine Primary Accelerator
$accel = "none"
if ($gpuName -match "NVIDIA") { $accel = "cuda" } 
elseif ($gpuName -match "AMD|Radeon") { $accel = ($gpuName -match "HD 8|HD 7|R7|R5") ? "dxva2" : "d3d11va" }
elseif ($gpuName -match "Intel") { $accel = "qsv" }

# 3. Print Clean UI Header
Clear-Host
Write-Host "================ MEDIA INTEGRITY SCANNER ================" -ForegroundColor Cyan
Write-Host "MACHINE : $computerName"
Write-Host "CPU     : $cpuName"
Write-Host "GPU     : $gpuName"
Write-Host "ENGINE  : $($accel.ToUpper())" -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Cyan

# 4. File Discovery (> 5MB to ignore metadata junk)
$files = Get-ChildItem -Recurse -Include *.mkv, *.mp4 | Where-Object { $_.Length -gt 5mb }
$totalFiles = $files.Count
$counter = [hashtable]::Synchronized(@{ Count = 0 })
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

if ($totalFiles -eq 0) { Write-Host "No media files found in this directory!" -ForegroundColor Red; return }

# 5. Parallel Execution Loop
$files | ForEach-Object -ThrottleLimit 4 -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $primaryHw = $using:accel
    $sync = $using:counter
    $total = $using:totalFiles
    $cName = $using:computerName

    # --- ATTEMPT 1: Hardware Acceleration ---
    $result = & $ffexe -hwaccel $primaryHw -v error -i $file.FullName -f null - 2>&1
    $modeUsed = $primaryHw

    # --- ATTEMPT 2: Software Fallback (If HW fails/limits hit) ---
    if ($result) {
        $result = & $ffexe -v error -i $file.FullName -f null - 2>&1
        $modeUsed = "software"
    }
    
    # Progress Calculation
    $sync.Count++
    $c = $sync.Count
    $elapsed = $using:startTime.Elapsed.TotalSeconds
    $eta = [TimeSpan]::FromSeconds(($elapsed / $c) * ($total - $c)).ToString("hh\:mm\:ss")

    if ($result) { 
        # ENHANCED LOGGING: Includes Computer Name and uses thread-safe UTF8 encoding
        $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$cName] FAIL: $($file.FullName) | Mode: $modeUsed"
        
        # We use a simple retry loop to handle potential file-access collisions on the NAS
        $logged = $false
        while (-not $logged) {
            try {
                $logEntry | Out-File -FilePath "corrupt_files.txt" -Append -Encoding utf8 -ErrorAction Stop
                $logged = $true
            } catch { Start-Sleep -Milliseconds 200 }
        }
        
        Write-Host "[!] FAIL: $($file.Name) (HW/SW both failed)" -ForegroundColor Red
    } else {
        Write-Host "[$c/$total] OK: $($file.Name) ($($modeUsed.ToUpper())) | ETA: $eta" -ForegroundColor Green
    }
}

$startTime.Stop()
Write-Host "`nScan Finished in $($startTime.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
Write-Host "Check 'corrupt_files.txt' for any detected issues."
