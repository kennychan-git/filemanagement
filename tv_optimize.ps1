# --- 1. Robust Path Detection ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source }
              elseif (Test-Path "C:\Program Files\Jellyfin\Server\ffmpeg.exe") { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
              else { Write-Error "FFmpeg not found!"; break }

$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

Write-Host "================ LIBRARY STANDARDIZER v1.4 ================" -ForegroundColor Cyan
Write-Host "MODE    : Universal Remux + TV Mix Injection"
Write-Host "===========================================================" -ForegroundColor Cyan

# TARGET: All .mkv files that haven't been standardized yet
$files = Get-ChildItem -File | Where-Object { $_.Extension -eq ".mkv" -and $_.Name -notlike "*_standardized*" }

foreach ($file in $files) {
    # Metadata gathering
    $origDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName
    $audioCount = (& $ffprobePath -v error -select_streams a -show_entries stream=index -of csv=p=0 $file.FullName | Measure-Object).Count
    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_standardized.mkv")

    Write-Host "Standardizing: $($file.Name)" -ForegroundColor Cyan

    # 2. CONSTRUCT ARGUMENTS
    # -map 0:v:0 ensures we only grab the actual video and skip any MJPEG/cover art
    $ffArgs = @("-hide_banner", "-loglevel", "error", "-stats", "-i", $file.FullName, "-map", "0:v:0", "-c:v", "copy")

    if ($audioCount -gt 0) {
        # Keep original audio tracks (DTS, TrueHD, AC3, etc.)
        for ($i=0; $i -lt $audioCount; $i++) { $ffArgs += "-map", "0:a:$i", "-c:a:$i", "copy" }
        
        # TV-Optimization Injection
        $tvIdx = $audioCount
        $audioFilter = "[0:a:0]pan=stereo|c0=c0+0.707*c2+0.5*c4|c1=c1+0.707*c2+0.5*c5,loudnorm=I=-16:TP=-1.5:LRA=11[tvout]"
        $ffArgs += "-filter_complex", $audioFilter
        $ffArgs += "-map", "[tvout]", "-c:a:$tvIdx", "aac", "-b:a:$tvIdx", "192k", "-metadata:s:a:$tvIdx", "title=TV Optimized"
        
        # JELLYFIN: Set the newly injected TV track as the default
        $ffArgs += "-disposition:a", "0", "-disposition:a:$tvIdx", "default"
    }

    # Pass-through subtitles and keep global metadata for library recognition
    $ffArgs += "-map", "0:s?", "-c:s", "copy", "-map_metadata", "0", $outputPath

    # 3. RUN
    & $ffmpegPath @ffArgs

    # 4. AUDIT
    if ($LASTEXITCODE -eq 0) {
        $newDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $outputPath
        if ([Math]::Abs([double]$origDuration - [double]$newDuration) -lt 0.5) {
            Write-Host "SUCCESS: Created $($outputPath)" -ForegroundColor Green
        } else {
            Write-Host "FAILURE: Duration mismatch on $($file.Name)!" -ForegroundColor Red
        }
    }
}
