# --- 1. Robust Path Discovery ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Users\me\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe" }
$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

# --- 2. Reliable AVX-512 Hardware Check ---
# We try to initialize a dummy x265 session with AVX-512 forced. 
# If it doesn't error out, the hardware/software combo is good to go.
$isAVX512 = $false
try {
    $test = & $ffmpegPath -f lavfi -i color=c=black:s=16x16:d=0.1 -c:v libx265 -x265-params "asm=avx512" -f null - 2>&1
    if ($test -notmatch "invalid|error|not found") { $isAVX512 = $true }
} catch { $isAVX512 = $false }

if ($isAVX512) {
    $modeMsg = "AVX-512 (Ultra High Throughput)"
    $modeColor = "Yellow"
    $x265Asm = "asm=avx512"
} else {
    $modeMsg = "AVX2/Standard (Legacy Support)"
    $modeColor = "Cyan"
    $x265Asm = "auto" 
}

# --- 3. Stats Tracking ---
$startTime = Get-Date
$totalOriginalSize = 0
$totalNewSize = 0
$filesProcessed = 0

Write-Host "FFmpeg Expert Mode: $modeMsg" -ForegroundColor $modeColor
Write-Host "Using FFmpeg at: $ffmpegPath" -ForegroundColor Gray

# --- 4. Processing ---
$files = Get-ChildItem -File | Where-Object { $_.Extension -match "mp4|mkv|avi|mov" -and $_.Name -notlike "*_x265*" }

foreach ($file in $files) {
    # Codec Inspection
    $codec = & $ffprobePath -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $file.FullName
    
    if ($codec -eq "hevc") {
        Write-Host "SKIPPING: $($file.Name) is already HEVC." -ForegroundColor Gray
        continue
    }

    $newName = $file.BaseName + "_x265.mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    if (Test-Path $outputPath) { continue }

    Write-Host "`n------------------------------------------------" -ForegroundColor White
    Write-Host "Transcoding: $($file.Name)" -ForegroundColor Cyan
    
    & $ffmpegPath -i $file.FullName `
             -map 0 `
             -c:v:0 libx265 `
             -crf 28 `
             -preset medium `
             -x265-params "$($x265Asm):log-level=info" `
             -pix_fmt yuv420p10le `
             -c:a copy `
             -c:s copy `
             -map_metadata 0 `
             -stats $outputPath

    if (Test-Path $outputPath) {
        $totalOriginalSize += $file.Length
        $totalNewSize += (Get-Item $outputPath).Length
        $filesProcessed++
        Write-Host "SUCCESS: Saved to $([math]::Round((Get-Item $outputPath).Length/1MB,2)) MB" -ForegroundColor Green
    }
}

# --- 5. Final Summary ---
$endTime = Get-Date
$duration = $endTime - $startTime

if ($filesProcessed -gt 0) {
    $savedBytes = $totalOriginalSize - $totalNewSize
    $percent = [math]::Round(($savedBytes / $totalOriginalSize) * 100, 2)
    
    Write-Host "`n================================================" -ForegroundColor Magenta
    Write-Host "                FINAL BATCH REPORT" -ForegroundColor Magenta
    Write-Host "================================================" -ForegroundColor Magenta
    Write-Host "Total Files:     $filesProcessed"
    Write-Host "Total Time:      $($duration.ToString("hh\:mm\:ss"))"
    Write-Host "Total In:        $([math]::Round($totalOriginalSize/1GB, 3)) GB"
    Write-Host "Total Out:       $([math]::Round($totalNewSize/1GB, 3)) GB"
    Write-Host "Space Saved:     $([math]::Round($savedBytes/1GB, 3)) GB ($percent%)" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Magenta
}
