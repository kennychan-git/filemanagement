# FFmpeg x265 Batch Transcoder v4.4 - "The Completionist"
# PS7 Optimized + Audio Logic Fix + Session Summary

$ffmpegPath = (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue).Source
$ffprobePath = (Get-Command ffprobe.exe -ErrorAction SilentlyContinue).Source

$cpu = (Get-WmiObject Win32_Processor).Name
$x265Asm = ($cpu -match "i9-1[1234]") ? "asm=avx512" : "asm=avx2"

Write-Host "System: $cpu | Acceleration: $x265Asm" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------"

$files = Get-ChildItem -File | Where-Object { $_.Extension -match "mp4|mkv|avi|mov" -and $_.Name -notlike "*_x265*" }
$totalSavedBytes = 0
$fileCount = 0

foreach ($file in $files) {
    # 1. Analyze Stream Data
    $codec = & $ffprobePath -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $file.FullName
    if ($codec -eq "hevc") { continue }

    $audioCount = (& $ffprobePath -v error -select_streams a -show_entries stream=index -of csv=p=0 $file.FullName | Measure-Object).Count
    $subCount = (& $ffprobePath -v error -select_streams s -show_entries stream=index -of csv=p=0 $file.FullName | Measure-Object).Count
    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_x265.mkv")
    if (Test-Path $outputPath) { continue }

    Write-Host "File: $($file.Name)" -ForegroundColor Yellow
    
    # 2. Argument Construction
    $ffArgs = @("-hide_banner", "-loglevel", "error", "-stats", "-i", $file.FullName, "-map", "0:v:0", "-c:v", "libx265", "-crf", "28", "-preset", "medium", "-x265-params", "$($x265Asm):log-level=error", "-pix_fmt", "yuv420p10le")

    if ($audioCount -gt 0) {
        Write-Host " -> Audio: $audioCount tracks. Adding TV-Optimized track." -ForegroundColor Gray
        for ($i=0; $i -lt $audioCount; $i++) { $ffArgs += "-map", "0:a:$i", "-c:a:$i", "copy" }
        $tvIdx = $audioCount
        $ffArgs += "-filter_complex", "[0:a:0]loudnorm=I=-16:TP=-1.5:LRA=11,pan=stereo|c0=c0|c1=c1[tvout]"
        $ffArgs += "-map", "[tvout]", "-c:a:$tvIdx", "aac", "-b:a:$tvIdx", "128k", "-metadata:s:a:$tvIdx", "title=TV Optimized"
        $ffArgs += "-disposition:a", "0", "-disposition:a:$tvIdx", "default"
    } else {
        Write-Host " -> Audio: None found. Skipping audio filters." -ForegroundColor DarkGray
    }

    if ($subCount -gt 0) { Write-Host " -> Subs:  $subCount tracks mapped." -ForegroundColor Gray }
    $ffArgs += "-map", "0:s?", "-c:s", "copy", "-map_metadata", "0", $outputPath

    # 3. Execution
    $startTime = Get-Date
    & $ffmpegPath @ffArgs
    $endTime = Get-Date

    # 4. Results
    if ($LASTEXITCODE -eq 0) {
        $oldSize = $file.Length
        $newSize = (Get-Item $outputPath).Length
        $saved = $oldSize - $newSize
        $totalSavedBytes += $saved
        $fileCount++
        
        $diffMB = [Math]::Round($saved / 1MB, 2)
        $pct = [Math]::Round(($saved / $oldSize) * 100, 1)
        
        Write-Host "Done in $([Math]::Round(($endTime - $startTime).TotalMinutes, 2)) min | Saved: $diffMB MB ($pct%)" -ForegroundColor Green
        Write-Host "----------------------------------------------------------"
    }
}

# 5. Grand Total Summary
if ($fileCount -gt 0) {
    $totalMB = [Math]::Round($totalSavedBytes / 1MB, 2)
    $totalGB = [Math]::Round($totalSavedBytes / 1GB, 2)
    Write-Host "`nSESSION COMPLETE" -ForegroundColor Cyan
    Write-Host "Processed: $fileCount files"
    Write-Host "Total Space Reclaimed: $totalMB MB ($totalGB GB)" -ForegroundColor Green
}
