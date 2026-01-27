# 1. System Identity & FFmpeg Check
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

$cpuName = (Get-CimInstance Win32_Processor).Name.Trim()
$gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Caption -notmatch "Remote|Microsoft|Basic" } | Select-Object -ExpandProperty Caption

# 2. Determine Primary Accelerator and Decoder Suffix
$accel = "none"
$suffix = ""
if ($gpus -match "NVIDIA") { 
    $accel = "cuda"; $suffix = "_cuvid" 
} elseif ($gpus -match "AMD|Radeon") { 
    $accel = ($gpus -match "HD 8|HD 7|R7|R5") ? "dxva2" : "d3d11va"; $suffix = "_amf"
} elseif ($gpus -match "Intel") { 
    $accel = "qsv"; $suffix = "_qsv" 
}

# 3. Print Diagnostic Header
Clear-Host
Write-Host "================ SYSTEM IDENTITY ================" -ForegroundColor Cyan
Write-Host "CPU : $cpuName"
Write-Host "GPU : $gpus"
Write-Host "MODE: $($accel.ToUpper())" -ForegroundColor Yellow
Write-Host "================================================="

# Generate Dynamic Capability Table
$decoders = & $ffmpegPath -decoders | Select-String $suffix
$report = foreach ($line in $decoders) {
    if ($line -match "V\.\.\.\s+(\w+)\s+(.*)") {
        [PSCustomObject]@{
            Codec    = $matches[1].Replace($suffix, "").ToUpper()
            Hardware = $matches[1]
        }
    }
}
$report | Format-Table -AutoSize
Write-Host "=================================================`n"

# 4. File Discovery
$files = Get-ChildItem -Recurse -Include *.mkv, *.mp4 | Where-Object { $_.Length -gt 5mb }
$totalFiles = $files.Count
$counter = [hashtable]::Synchronized(@{ Count = 0 })
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

if ($totalFiles -eq 0) { Write-Host "No media files found!" -ForegroundColor Red; return }

# 5. Parallel Execution Loop
$files | ForEach-Object -ThrottleLimit 4 -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $primaryHw = $using:accel
    $sync = $using:counter
    $total = $using:totalFiles

    # --- ATTEMPT 1: Hardware ---
    $result = & $ffexe -hwaccel $primaryHw -v error -i $file.FullName -f null - 2>&1
    $modeUsed = $primaryHw

    # --- ATTEMPT 2: Software Fallback (If HW fails, e.g., 8K60) ---
    if ($result) {
        $result = & $ffexe -v error -i $file.FullName -f null - 2>&1
        $modeUsed = "software"
    }
    
    # Sync Progress and ETA
    $sync.Count++
    $c = $sync.Count
    $elapsed = $using:startTime.Elapsed.TotalSeconds
    $eta = [TimeSpan]::FromSeconds(($elapsed / $c) * ($total - $c)).ToString("hh\:mm\:ss")

    if ($result) { 
        "[$(Get-Date -Format 'HH:mm:ss')] FAIL: $($file.FullName) | Mode: $modeUsed" | Out-File "corrupt_files.txt" -Append
        Write-Host "[!] FAIL: $($file.Name) (HW/SW both failed)" -ForegroundColor Red
    } else {
        Write-Host "[$c/$total] OK: $($file.Name) ($($modeUsed.ToUpper())) | ETA: $eta" -ForegroundColor Green
    }
}

$startTime.Stop()
Write-Host "`nScan Finished in $($startTime.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
