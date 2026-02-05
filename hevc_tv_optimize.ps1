# FFmpeg Audio Injector v1.0
# Logic: Video Stream Copy (Zero Quality Loss) + TV Audio Injection

$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Users\me\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe" }
$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

Write-Host "================ AUDIO INJECTOR v1.0 ================" -ForegroundColor Cyan
Write-Host "MODE   : Stream Copy (Video) + Process (Audio)"
Write-Host "GOAL   : Standardizing HEVC Library for TV"
Write-Host "=====================================================" -ForegroundColor Cyan

$files = Get-ChildItem -File | Where-Object { $_.Extension -eq ".mkv" -and $_.Name -notlike "*_processed*" }

foreach ($file in $files) {
    # 1. Verify Codec (Ensure we aren't accidentally copying x264)
    $vCodec = & $ffprobePath -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $file.FullName
    if ($vCodec -ne "hevc") {
        Write-Host "Skipping: $($file.Name) (Not HEVC - Use Stage 2 Transcoder instead)" -ForegroundColor Red
        continue
    }

    $origDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName
    $audioCount = (& $ffprobePath -v error -select_streams a -show_entries stream=index -of csv=p=0 $file.FullName | Measure-Object).Count
    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_processed.mkv")

    Write-Host "Processing: $($file.Name)" -ForegroundColor Cyan

    # 2. Argument Construction (The "Lite" approach)
    # -c:v copy ensures zero CPU usage for video
    $ffArgs = @("-hide_banner", "-loglevel", "error", "-stats", "-i", $file.FullName, 
                "-map", "0:v:0", "-c:v", "copy")

    if ($audioCount -gt 0) {
        # Copy original tracks
        for ($i=0; $i -lt $audioCount; $i++) { $ffArgs += "-map", "0:a:$i", "-c:a:$i", "copy" }
        
        # Inject Surround-Aware TV Track
        $tvIdx = $audioCount
        $audioFilter = "[0:a:0]pan=stereo|c0=c0+0.707*c2+0.5*c4|c1=c1+0.707*c2+0.5*c5,loudnorm=I=-16:TP=-1.5:LRA=11[tvout]"
        $ffArgs += "-filter_complex", $audioFilter
        $ffArgs += "-map", "[tvout]", "-c:a:$tvIdx", "aac", "-b:a:$tvIdx", "160k", "-metadata:s:a:$tvIdx", "title=TV Optimized"
        
        # Default the TV track for set-top box compatibility
        $ffArgs += "-disposition:a", "0", "-disposition:a:$tvIdx", "default"
    }

    # Pass-through subtitles and metadata
    $ffArgs += "-map", "0:s?", "-c:s", "copy", "-map_metadata", "0", $outputPath

    # 3. Execution (This will be limited only by your Disk I/O speed)
    & $ffmpegPath @ffArgs

    # 4. Integrity Check
    if ($LASTEXITCODE -eq 0) {
        $newDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $outputPath
        if ([Math]::Abs([double]$origDuration - [double]$newDuration) -lt 1.0) {
            Write-Host "SUCCESS: Library Standardized." -ForegroundColor Green
        } else {
            Write-Host "WARNING: Duration mismatch on copy!" -ForegroundColor Red
        }
    }
    Write-Host "-----------------------------------------------------"
}
