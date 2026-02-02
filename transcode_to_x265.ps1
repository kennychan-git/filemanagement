# --- 1. Physical Hardware Interrogation ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

Write-Host "FFmpeg found at: $ffmpegPath" -ForegroundColor Yellow

# --- 2. Configuration ---
$crfValue   = 28
$preset     = "medium"

# --- 3. Processing ---
# Get video files in the current folder, excluding already processed ones
$files = Get-ChildItem -File | Where-Object { 
    $_.Extension -match "mp4|mkv|avi" -and $_.Name -notlike "*_x265*" 
}

foreach ($file in $files) {
    # Append _x265 to the filename
    $newName = $file.BaseName + "_x265.mkv"
    $outputPath = Join-Path $file.DirectoryName $newName

    Write-Host "`n------------------------------------------------"
    Write-Host "Processing: $($file.Name)" -ForegroundColor Cyan
    Write-Host "Target: $newName" -ForegroundColor DarkGray

    # Execute with AVX-512 and 10-bit optimization
    & $ffmpegPath -i $file.FullName `
             -map 0 `
             -c:v libx265 `
             -crf $crfValue `
             -preset $preset `
             -x265-params "asm=avx512:log-level=info" `
             -pix_fmt yuv420p10le `
             -c:a copy `
             -c:s copy `
             -stats $outputPath

    if (Test-Path $outputPath) {
        $oldSize = [math]::Round($file.Length / 1MB, 2)
        $newSize = [math]::Round((Get-Item $outputPath).Length / 1MB, 2)
        Write-Host "SUCCESS: Saved to $newSize MB (Original: $oldSize MB)" -ForegroundColor Green
    }
}
