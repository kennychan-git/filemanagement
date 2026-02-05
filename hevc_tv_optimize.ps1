# FFmpeg Library Standardizer v1.2
# MODES: Video Stream Copy + Audio Injection + Jellyfin Fallback

# 1. ROBUST PATH DETECTION
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source }
              elseif (Test-Path "C:\Program Files\Jellyfin\Server\ffmpeg.exe") { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
              elseif (Test-Path "$env:LocalAppData\jellyfin\ffmpeg.exe") { "$env:LocalAppData\jellyfin\ffmpeg.exe" }
              else { Write-Error "FFmpeg not found! Please install FFmpeg or Jellyfin."; break }

$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

Write-Host "================ LIBRARY STANDARDIZER v1.2 ================" -ForegroundColor Cyan
Write-Host "FFMPEG PATH : $ffmpegPath"
Write-Host "MODE        : Video Stream Copy (All Codecs)"
Write-Host "===========================================================" -ForegroundColor Cyan

# Grab files that haven't been standardized yet
$files = Get-ChildItem -File | Where-Object { $_.Extension -eq ".mkv" -and $_.Name -notlike "*_standardized*" -and $_.Name -notlike "*_x265*" }

foreach ($file in $files) {
    # Metadata gathering
    $origDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName
    $audioCount = (& $ffprobePath -v error -select_streams a -show_entries stream=index -of csv=p=0 $file.FullName | Measure-Object).Count
    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_standardized.mkv")

    Write-Host "Processing: $($file.Name)" -ForegroundColor Cyan

    # 2. CONSTRUCT ARGUMENTS
    # We use -c:v copy to preserve the original video bitstream perfectly
    $ffArgs = @("-hide_banner", "-loglevel", "error", "-stats", "-i", $file.FullName, "-map", "0:v:0", "-c:v", "copy")

    if ($audioCount -gt 0) {
        # Keep original audio tracks (DTS, TrueHD, etc.)
        for ($i=0; $i -lt $audioCount; $i++) { $ffArgs += "-map", "0:a:$i", "-c:a:$i", "copy" }
        
        # Inject the TV Optimized track as the last audio stream
        $tvIdx = $audioCount
        $audioFilter = "[0:a:0]pan=stereo|c0=c0+0.707*c2+0.5*c4|c1=c1+0.707*c2+0.5*c5,loudnorm=I=-16:TP=-1.5:LRA=11[tvout]"
        $ffArgs += "-filter_complex", $audioFilter
        $ffArgs += "-map", "[tvout]", "-c:a:$tvIdx", "aac", "-b:a:$tvIdx", "160k", "-metadata:s:a:$tvIdx", "title=TV Optimized"
        
        # JELLYFIN OPTIMIZATION: Clear all defaults and make the TV track the primary
        $ffArgs += "-disposition:a", "0", "-disposition:a:$tvIdx", "default"
    }

    # Pass-through subtitles and global metadata
    $ffArgs += "-map", "0:s?", "-c:s", "copy", "-map_metadata", "0", $outputPath

    # 3. RUN
    & $ffmpegPath @ffArgs

    # 4. AUDIT
    if ($LASTEXITCODE -eq 0) {
        $newDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $outputPath
        if ([Math]::Abs([double]$origDuration - [double]$newDuration) -lt 0.5) {
            Write-Host "SUCCESS: Created $($outputPath)" -ForegroundColor Green
        } else {
            Write-Host "FAILURE: Duration mismatch!" -ForegroundColor Red
        }
    }
}
