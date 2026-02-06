# =========================================================
# 1. ROBUST PATH DETECTION
# =========================================================
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source }
              elseif (Test-Path "C:\Program Files\Jellyfin\Server\ffmpeg.exe") { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
              else { Write-Error "FFmpeg not found!"; break }

$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

Write-Host "================ LIBRARY STANDARDIZER v1.7 ================" -ForegroundColor Cyan
Write-Host "MODE    : X265 Priority + Robust Audio Detection"
Write-Host "===========================================================" -ForegroundColor Cyan

# =========================================================
# 2. TARGET SELECTION (Only the Transcoded Children)
# =========================================================
$files = Get-ChildItem -File | Where-Object { 
    $_.Extension -eq ".mkv" -and 
    $_.Name -notlike "*_standardized*" 
}

foreach ($file in $files) {
    # Metadata gathering
    $origDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName
    
    # Safely detect audio
    $audioCount = (& $ffprobePath -v error -select_streams a -show_entries stream=index -of csv=p=0 $file.FullName | Measure-Object).Count
    $channels = if ($audioCount -gt 0) { 
        & $ffprobePath -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 $file.FullName 
    } else { 0 }

    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_standardized.mkv")
    
    $audioTag = if ($audioCount -eq 0) { "SILENT" } else { "$($channels)ch Detected" }
    Write-Host "Standardizing: $($file.Name) [$audioTag]" -ForegroundColor Cyan

    # =========================================================
    # 3. CONSTRUCT ARGUMENTS
    # =========================================================
    $ffArgs = @(
        "-hide_banner", "-loglevel", "error", "-stats",
        "-fflags", "+genpts", 
        "-i", $file.FullName,
        "-avoid_negative_ts", "make_zero", 
        "-map", "0:v:0", "-c:v", "copy"
    )

    if ($audioCount -gt 0) {
        # Keep original audio tracks
        for ($i=0; $i -lt $audioCount; $i++) { $ffArgs += "-map", "0:a:$i", "-c:a:$i", "copy" }
        
        # TV-Optimization Logic (Downmix branch)
        $tvIdx = $audioCount
        $audioFilter = if ([int]$channels -ge 6) {
            "[0:a:0]pan=stereo|c0<c0+0.707*c2+0.5*c4|c1<c1+0.707*c2+0.5*c5,loudnorm=I=-16:TP=-1.5:LRA=11[tvout]"
        } elseif ([int]$channels -eq 2) {
            "[0:a:0]loudnorm=I=-16:TP=-1.5:LRA=11[tvout]"
        } else {
            "[0:a:0]aresample=async=1,pan=stereo|c0=c0|c1=c0,loudnorm=I=-16:TP=-1.5:LRA=11[tvout]"
        }

        $ffArgs += "-filter_complex", $audioFilter
        $ffArgs += "-map", "[tvout]", "-c:a:$tvIdx", "aac", "-b:a:$tvIdx", "192k", "-metadata:s:a:$tvIdx", "title=TV Optimized (R128)"
        
        # JELLYFIN: Set the newly injected TV track as the default
        $ffArgs += "-disposition:a", "0", "-disposition:a:$tvIdx", "default"
    }

    # Pass-through subtitles and preserve global metadata
    $ffArgs += "-map", "0:s?", "-c:s", "copy", "-map_metadata", "0", $outputPath

    # =========================================================
    # 4. EXECUTION & AUDIT
    # =========================================================
    & $ffmpegPath @ffArgs

    if ($LASTEXITCODE -eq 0) {
        $newDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $outputPath
        if ([Math]::Abs([double]$origDuration - [double]$newDuration) -lt 0.5) {
            Write-Host "SUCCESS: Created $($outputPath.Split('\')[-1])" -ForegroundColor Green
        } else {
            Write-Host "FAILURE: Duration mismatch!" -ForegroundColor Red
        }
    }
}
