# --- 1. Path & Hardware Setup ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

# --- NEW: HW Accel Selection ---
Write-Host "Select Hardware Acceleration for Auditing:" -ForegroundColor Cyan
Write-Host "1. None (CPU)"
Write-Host "2. NVIDIA (cuda)"
Write-Host "3. Intel (qsv)"
Write-Host "4. AMD (amf)"
Write-Host "5. DXVA2 (Windows Generic)"
$choice = Read-Host "Selection (Default 1)"

$hwengine = switch ($choice) {
    "2" { "cuda" }
    "3" { "qsv" }
    "4" { "amf" }
    "5" { "dxva2" }
    Default { "none" }
}

# --- 2. File Discovery ---
$files = Get-ChildItem -Path "." -File | Where-Object { 
    $_.Extension -match "\.(mp4|mov|avi)$" -and 
    $_.Name -notlike "*_standardized*" 
}

if ($files.Count -eq 0) {
    Write-Host "NOTE: No MP4/MOV/AVI files found. If your files are already MKV, use the Standardizer instead." -ForegroundColor Yellow
    return
}

$startTime = Get-Date
$filesProcessed = 0

Clear-Host
Write-Host "================ UNIVERSAL REMUXER v3.4 ================" -ForegroundColor Cyan
Write-Host "AUDIT ENGINE  : $(if ($hwengine -eq 'none') { "CPU (Software)" } else { $hwengine.ToUpper() })" -ForegroundColor Gray
Write-Host "STABILITY     : EIA-608 Captions & Telemetry Shield" -ForegroundColor Gray
Write-Host "CLEANUP       : MANUAL (Originals will be preserved)" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan

foreach ($file in $files) {
    $newName = $file.BaseName + ".mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    
    if (Test-Path $outputPath) { 
        Write-Host "SKIPPING: $($newName) already exists." -ForegroundColor Gray
        continue 
    }

    Write-Host "`n[1/2] Remuxing: $($file.Name)" -ForegroundColor Cyan
    
    $mapArgs = @("-map", "0:v", "-map", "0:a?", "-map", "0:s?", "-map", "0:d?")

    # TRY 1: SRT Conversion
    $action = "SRT Transcode"
    & $ffmpegPath -i "$($file.FullName)" $mapArgs -c:v copy -c:a copy -c:s srt -ignore_unknown -map_metadata 0 -v error "$outputPath"

    # FALLBACK 1: Stream Copy
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path $outputPath) { Remove-Item $outputPath }
        $action = "Stream Copy"
        & $ffmpegPath -i "$($file.FullName)" $mapArgs -c:v copy -c:a copy -c:s copy -ignore_unknown -map_metadata 0 -v error "$outputPath"
    }

    # FALLBACK 2: Telemetry Shield
    if ($LASTEXITCODE -ne 0) {
        Write-Host "         ! Muxing error detected. Stripping Data streams..." -ForegroundColor Yellow
        if (Test-Path $outputPath) { Remove-Item $outputPath }
        $action = "Clean Remux (Stripped Data)"
        & $ffmpegPath -i "$($file.FullName)" -map 0:v -map 0:a? -map 0:s? -c:v copy -c:a copy -c:s copy -dn -ignore_unknown -map_metadata 0 -v error "$outputPath"
    }

    if ($LASTEXITCODE -eq 0) {
        # --- 3. Audit for Success with HW Fallback ---
        Write-Host "[2/2] Auditing..." -ForegroundColor Gray
        
        $auditPass = $false
        
        # Primary Audit (Selected HW)
        if ($hwengine -ne "none") {
            $audit = & $ffmpegPath -hwaccel $hwengine -i "$outputPath" -f null - 2>&1
            if ($audit -match 'frame=') { $auditPass = $true }
            else { Write-Host "        ! HW Audit failed/unsupported. Falling back to CPU..." -ForegroundColor Yellow }
        }

        # Fallback Audit (CPU) if HW failed or wasn't selected
        if (-not $auditPass) {
            $audit = & $ffmpegPath -i "$outputPath" -f null - 2>&1
            if ($audit -match 'frame=') { $auditPass = $true }
        }
        
        if ($auditPass) {
            Write-Host "        SUCCESS: $action" -ForegroundColor Green
            $filesProcessed++
        } else {
            Write-Host "        WARNING: Remux created but Audit failed (Possible corruption)." -ForegroundColor Red
        }
    }
}

# --- Final Report ---
$totalTime = (Get-Date) - $startTime
Write-Host "`n======================= REPORT =========================" -ForegroundColor Magenta
Write-Host "Files Successfully Remuxed : $filesProcessed"
Write-Host "Total Duration             : $($totalTime.ToString('hh\:mm\:ss'))"
Write-Host "========================================================" -ForegroundColor Magenta
