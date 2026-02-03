# --- 1. Setup ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

$totalOriginalSize = 0
$totalNewSize = 0
$filesProcessed = 0

# --- 2. Configuration ---
$crfValue   = 28
$preset     = "medium"

Write-Host "FFmpeg Expert Mode: Activated (AVX-512)" -ForegroundColor Yellow

# --- 3. Processing (Added .mov to filter) ---
$files = Get-ChildItem -File | Where-Object { $_.Extension -match "mp4|mkv|avi|mov" -and $_.Name -notlike "*_x265*" }

foreach ($file in $files) {
    Write-Host "`n------------------------------------------------" -ForegroundColor White
    
    # Deep Codec Inspection
    $codec = & $ffprobePath -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $file.FullName
    
    if ($codec -eq "hevc") {
        Write-Host "SKIPPING: $($file.Name) is already HEVC." -ForegroundColor Gray
        continue
    }

    $newName = $file.BaseName + "_x265.mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    if (Test-Path $outputPath) { continue }

    Write-Host "Transcoding: $($file.Name) [Codec: $codec]" -ForegroundColor Cyan
    
    # AVX-512 Optimized Command
    & $ffmpegPath -i $file.FullName `
             -map 0 `
             -c:v:0 libx265 `
             -crf $crfValue `
             -preset $preset `
             -x265-params "asm=avx512:log-level=info" `
             -pix_fmt yuv420p10le `
             -c:a copy `
             -c:s copy `
             -map_metadata 0 `
             -stats $outputPath

    if (Test-Path $outputPath) {
        $oldSize = $file.Length
        $newSize = (Get-Item $outputPath).Length
        $totalOriginalSize += $oldSize
        $totalNewSize += $newSize
        $filesProcessed++
        Write-Host "DONE: $([math]::Round($newSize/1MB,2)) MB (was $([math]::Round($oldSize/1MB,2)) MB)" -ForegroundColor Green
    }
}

# --- 4. Final Summary ---
if ($filesProcessed -gt 0) {
    $savedBytes = $totalOriginalSize - $totalNewSize
    $percent = [math]::Round(($savedBytes / $totalOriginalSize) * 100, 2)
    Write-Host "`n================================================" -ForegroundColor Magenta
    Write-Host "                FINAL SUMMARY" -ForegroundColor Magenta
    Write-Host "================================================" -ForegroundColor Magenta
    Write-Host "Files Processed: $filesProcessed"
    Write-Host "Total In:        $([math]::Round($totalOriginalSize/1GB, 3)) GB"
    Write-Host "Total Out:       $([math]::Round($totalNewSize/1GB, 3)) GB"
    Write-Host "Space Saved:     $([math]::Round($savedBytes/1GB, 3)) GB ($percent%)" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Magenta
}
