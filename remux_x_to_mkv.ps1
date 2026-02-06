# --- 1. Path & Hardware Setup ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

# --- 2. File Discovery ---
# This targets the core "containers" you want to move into Matroska
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
Write-Host "================ UNIVERSAL REMUXER v3.3 ================" -ForegroundColor Cyan
Write-Host "STABILITY     : EIA-608 Captions & Telemetry Shield" -ForegroundColor Gray
Write-Host "CLEANUP       : MANUAL (Originals will be preserved)" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan

foreach ($file in $files) {
    $newName = $file.BaseName + ".mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    
    # Skip if output already exists to avoid redundant work
    if (Test-Path $outputPath) { 
        Write-Host "SKIPPING: $($newName) already exists." -ForegroundColor Gray
        continue 
    }

    Write-Host "`n[1/2] Remuxing: $($file.Name)" -ForegroundColor Cyan
    
    # MAPPING: Target Video, Audio, Subs, and Data (for EIA-608)
    $mapArgs = @("-map", "0:v", "-map", "0:a?", "-map", "0:s?", "-map", "0:d?")

    # TRY 1: SRT Conversion (Jellyfin optimized)
    $action = "SRT Transcode"
    & $ffmpegPath -i "$($file.FullName)" $mapArgs -c:v copy -c:a copy -c:s srt -ignore_unknown -map_metadata 0 -v error "$outputPath"

    # FALLBACK 1: Stream Copy (Original Subtitle format)
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path $outputPath) { Remove-Item $outputPath }
        $action = "Stream Copy"
        & $ffmpegPath -i "$($file.FullName)" $mapArgs -c:v copy -c:a copy -c:s copy -ignore_unknown -map_metadata 0 -v error "$outputPath"
    }

    # FALLBACK 2: Telemetry Shield (The "Mavic" Fix - Strips non-standard data)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "        ! Muxing error detected. Stripping Data streams..." -ForegroundColor Yellow
        if (Test-Path $outputPath) { Remove-Item $outputPath }
        $action = "Clean Remux (Stripped Data)"
        & $ffmpegPath -i "$($file.FullName)" -map 0:v -map 0:a? -map 0:s? -c:v copy -c:a copy -c:s copy -dn -ignore_unknown -map_metadata 0 -v error "$outputPath"
    }

    if ($LASTEXITCODE -eq 0) {
        # --- 3. Audit for Success ---
        Write-Host "[2/2] Auditing..." -ForegroundColor Gray
        $audit = & $ffmpegPath -hwaccel auto -i "$outputPath" -f null - 2>&1
        
        if ($audit -match 'frame=') {
            Write-Host "        SUCCESS: $action" -ForegroundColor Green
            $filesProcessed++
        } else {
            Write-Host "        WARNING: Remux created but Audit failed." -ForegroundColor Red
        }
    }
}

# --- Final Report ---
$totalTime = (Get-Date) - $startTime
Write-Host "`n======================= REPORT =========================" -ForegroundColor Magenta
Write-Host "Files Successfully Remuxed : $filesProcessed"
Write-Host "Total Duration             : $($totalTime.ToString('hh\:mm\:ss'))"
Write-Host "========================================================" -ForegroundColor Magenta
