# FFmpeg x265 Batch Transcoder v4.7
# Logic: AVX-512 Auto-Logic | 10-Bit HEVC | Surround-Aware TV Downmix | Duration Audit

$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Users\me\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe" }
$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

# --- 1. AVX-512 Detection ---
$isAVX512 = $false
try {
    $test = & $ffmpegPath -f lavfi -i color=c=black:s=16x16:d=0.1 -c:v libx265 -x265-params "asm=avx512:log-level=error" -f null - 2>&1
    if ($test -notmatch "invalid|error|not found") { $isAVX512 = $true }
} catch { $isAVX512 = $false }
$x265Asm = $isAVX512 ? "asm=avx512" : "asm=avx2"

Write-Host "================ TRANSCODER v4.7 ================" -ForegroundColor Cyan
Write-Host "ENGINE : libx265 [$x265Asm]" -ForegroundColor Yellow
Write-Host "STAGE  : Optimized x264 -> x265 Conversion"
Write-Host "=================================================" -ForegroundColor Cyan

# Grab files (Assumes you've already run your Remuxer to get MKVs)
$files = Get-ChildItem -File | Where-Object { $_.Extension -eq ".mkv" -and $_.Name -notlike "*_x265*" }
$totalSavedBytes = 0

foreach ($file in $files) {
    # 2. Pre-Flight Check: Get Duration & Codec
    $origDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName
    $vCodec = & $ffprobePath -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $file.FullName
    
    if ($vCodec -eq "hevc") { 
        Write-Host "Skipping: $($file.Name) (Already HEVC)" -ForegroundColor Gray
        continue 
    }

    $audioCount = (& $ffprobePath -v error -select_streams a -show_entries stream=index -of csv=p=0 $file.FullName | Measure-Object).Count
    $subCount = (& $ffprobePath -v error -select_streams s -show_entries stream=index -of csv=p=0 $file.FullName | Measure-Object).Count
    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_x265.mkv")

    Write-Host "`nProcessing: $($file.Name)" -ForegroundColor Cyan
    
    # 3. Argument Construction
    $ffArgs = @("-hide_banner", "-loglevel", "error", "-stats", "-i", $file.FullName, 
                "-map", "0:v:0", "-c:v", "libx265", "-crf", "28", "-preset", "medium", 
                "-x265-params", "$($x265Asm):log-level=error", "-pix_fmt", "yuv420p10le")

    if ($audioCount -gt 0) {
        # Map all original tracks (Copy)
        for ($i=0; $i -lt $audioCount; $i++) { $ffArgs += "-map", "0:a:$i", "-c:a:$i", "copy" }
        
        # Add TV-Optimized Track (Surround-Aware Downmix + Loudnorm)
        $tvIdx = $audioCount
        # Formula: FL=FL+0.7C+0.5SL | FR=FR+0.7C+0.5SR | Normalized to -16 LUFS
        $audioFilter = "[0:a:0]pan=stereo|c0=c0+0.707*c2+0.5*c4|c1=c1+0.707*c2+0.5*c5,loudnorm=I=-16:TP=-1.5:LRA=11[tvout]"
        
        $ffArgs += "-filter_complex", $audioFilter
        $ffArgs += "-map", "[tvout]", "-c:a:$tvIdx", "aac", "-b:a:$tvIdx", "160k", "-metadata:s:a:$tvIdx", "title=TV Optimized"
        $ffArgs += "-disposition:a", "0", "-disposition:a:$tvIdx", "default"
    }

    if ($subCount -gt 0) { $ffArgs += "-map", "0:s?", "-c:s", "copy" }
    $ffArgs += "-map_metadata", "0", $outputPath

    # 4. Transcode
    & $ffmpegPath @ffArgs

    # 5. Modular Quality Control: Duration Match Check
    if ($LASTEXITCODE -eq 0) {
        $newDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $outputPath
        $diff = [Math]::Abs([double]$origDuration - [double]$newDuration)
        
        if ($diff -lt 1.0) {
            $oldSize = $file.Length
            $newSize = (Get-Item $outputPath).Length
            $saved = $oldSize - $newSize
            $totalSavedBytes += $saved
            Write-Host "VALIDATED: Time Match [Diff: $([Math]::Round($diff,3))s] | Saved: $([Math]::Round($saved/1MB,2)) MB" -ForegroundColor Green
        } else {
            Write-Host "CRITICAL: Duration Mismatch! (Diff: $([Math]::Round($diff,2))s)" -ForegroundColor Red
            Rename-Item $outputPath ($outputPath + ".mismatch")
        }
    }
}

Write-Host "`nStage 2 Complete. Reclaimed: $([Math]::Round($totalSavedBytes/1GB,2)) GB" -ForegroundColor Magenta
Write-Host "Proceed to Stage 3: Fleet Auditor." -ForegroundColor Cyan
