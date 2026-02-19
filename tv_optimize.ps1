# =========================================================
# 1. ROBUST PATH DETECTION
# =========================================================
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source }
              elseif (Test-Path "C:\Program Files\Jellyfin\Server\ffmpeg.exe") { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
              else { Write-Error "FFmpeg not found!"; break }

$ffprobePath = Join-Path (Split-Path $ffmpegPath) "ffprobe.exe"

Write-Host "================ LIBRARY STANDARDIZER v3.6 ================" -ForegroundColor Cyan
Write-Host "MODE    : EN/CH Optimization + v3.0 Core + Silent Analytics"
Write-Host "===========================================================" -ForegroundColor Cyan

# =========================================================
# 2. TARGET SELECTION (Frozen in Memory - Prevents Reruns)
# =========================================================
$files = @(Get-ChildItem -File | Where-Object { 
    $_.Extension -eq ".mkv" -and $_.Name -notlike "*_standardized*" 
})

foreach ($file in $files) {
    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_standardized.mkv")
    
    if (Test-Path $outputPath) {
        Write-Host "SKIPPING: $($file.Name) (Already Standardized)" -ForegroundColor Gray
        continue
    }

    # Gather all data in one clean, v3.0-style probe to avoid specifier errors
    $origDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$($file.FullName)"
    $streamData = @(& $ffprobePath -v error -show_entries stream=index,codec_type,channels,bit_rate:stream_tags=language -of csv=p=0 "$($file.FullName)")
    
    $engPattern = "eng"
    $chiPatterns = @("chi", "zho", "zh", "zh-cn", "zh-tw", "cmn")

    $allAudio = @($streamData | Where-Object { $_ -like "*,audio,*" })
    $allSubs  = @($streamData | Where-Object { $_ -like "*,subtitle,*" })

    $keepAudioIdx = @()
    $optimizeJobs = @()

    # Audio logic using the multi-column CSV
    # Column mapping: 0:index, 1:codec_type, 2:channels, 3:bit_rate, 4:language
    $engAudioLines = @($allAudio | Where-Object { $_ -like "*,$engPattern*" })
    if ($engAudioLines.Count -gt 0) {
        foreach ($line in $engAudioLines) { $keepAudioIdx += $line.Split(',')[0] }
        $p = $engAudioLines[0].Split(',')
        $optimizeJobs += [PSCustomObject]@{ index = $p[0]; lang = "eng"; channels = $p[2]; bitrate = $p[3]; label = "English" }
    }

    $chiAudioLines = @($allAudio | Where-Object { 
        $line = $_; $found = $false
        foreach ($p in $chiPatterns) { if ($line -like "*,$p*") { $found = $true } }; $found
    })
    if ($chiAudioLines.Count -gt 0) {
        foreach ($line in $chiAudioLines) { $keepAudioIdx += $line.Split(',')[0] }
        $p = $chiAudioLines[0].Split(',')
        $optimizeJobs += [PSCustomObject]@{ index = $p[0]; lang = "chi"; channels = $p[2]; bitrate = $p[3]; label = "Chinese" }
    }

    if ($optimizeJobs.Count -eq 0 -and $allAudio.Count -gt 0) {
        $p = $allAudio[0].Split(',')
        $optimizeJobs += [PSCustomObject]@{ index = $p[0]; lang = "und"; channels = $p[2]; bitrate = $p[3]; label = "Primary" }
        $keepAudioIdx += $p[0]
    }

    # --- CALCULATE SAVINGS BEFORE STARTING ---
    $removedBytes = 0
    $sourceOptimizedBytes = 0
    foreach ($line in $allAudio) {
        $p = $line.Split(',')
        if ([double]::TryParse($p[3], [ref]0)) {
            $size = ([double]$p[3] * [double]$origDuration) / 8
            if ($p[0] -notin $keepAudioIdx) { $removedBytes += $size }
            foreach ($job in $optimizeJobs) { if ($job.index -eq $p[0]) { $sourceOptimizedBytes += $size } }
        }
    }

    $keepSubIdx = @($allSubs | Where-Object {
        $line = $_; $match = ($line -like "*,$engPattern*")
        foreach ($p in $chiPatterns) { if ($line -like "*,$p*") { $match = $true } }; $match
    } | ForEach-Object { $_.Split(',')[0] })

    # =========================================================
    # 3. CONSTRUCT ARGUMENTS (REVERTED TO WORKING v3.0 LOGIC)
    # =========================================================
    $ffArgs = @("-hide_banner", "-loglevel", "error", "-stats", "-y", "-i", "$($file.FullName)")
    $ffArgs += "-map", "0:v:0", "-c:v", "copy"

    $outIdx = 0
    foreach ($idx in $keepAudioIdx) {
        $ffArgs += "-map", "0:$idx", "-c:a:$outIdx", "copy"
        $outIdx++
    }

    $filterStrings = @()
    foreach ($job in $optimizeJobs) {
        $tag = "tv_$($job.lang)"
        $norm = "loudnorm=I=-16:TP=-1.5:LRA=11[$tag]"
        # Use the channel count we already gathered in the first probe
        if ([int]$job.channels -ge 6) {
            $filterStrings += "[0:$($job.index)]pan=stereo|c0<c0+0.707*c2+0.5*c4|c1<c1+0.707*c2+0.5*c5,$norm"
        } else {
            $filterStrings += "[0:$($job.index)]$norm"
        }
    }
    
    if ($filterStrings.Count -gt 0) {
        $ffArgs += "-filter_complex", ($filterStrings -join ";")
        foreach ($job in $optimizeJobs) {
            $tag = "tv_$($job.lang)"
            $ffArgs += "-map", "[$tag]", "-c:a:$outIdx", "aac", "-b:a:$outIdx", "192k"
            $ffArgs += "-metadata:s:a:$outIdx", "title=TV Optimized ($($job.label))", "-metadata:s:a:$outIdx", "language=$($job.lang)"
            $outIdx++
        }
    }

    $ffArgs += "-disposition:a", "0" 
    $defaultTrackIdx = $null
    foreach ($job in $optimizeJobs) {
        if ($job.lang -eq "eng") { $defaultTrackIdx = ($keepAudioIdx.Count + $optimizeJobs.IndexOf($job)) }
    }
    if ($null -eq $defaultTrackIdx -and $optimizeJobs.Count -gt 0) { $defaultTrackIdx = $keepAudioIdx.Count }
    if ($null -ne $defaultTrackIdx) { $ffArgs += "-disposition:a:$defaultTrackIdx", "default" }

    foreach ($idx in $keepSubIdx) { $ffArgs += "-map", "0:$idx", "-c:s", "copy" }
    $ffArgs += "-map_metadata", "0", "$outputPath"

    # =========================================================
    # 4. EXECUTION
    # =========================================================
    Write-Host "Standardizing: $($file.Name)" -ForegroundColor Cyan
    Write-Host "Found: $($engAudioLines.Count) English, $($chiAudioLines.Count) Chinese tracks." -ForegroundColor Gray
    foreach ($job in $optimizeJobs) {
        Write-Host " >> Optimizing $($job.label): Stream $($job.index) [$($job.channels)ch Detected]" -ForegroundColor Yellow
    }

    & $ffmpegPath @ffArgs

    if ($LASTEXITCODE -eq 0) {
        $removedMB = [Math]::Round($removedBytes / 1MB, 2)
        $sourceMB  = [Math]::Round($sourceOptimizedBytes / 1MB, 2)
        $addedMB   = [Math]::Round(($optimizeJobs.Count * 192000 * [double]$origDuration) / 8 / 1MB, 2)
        $optSaved  = [Math]::Round($sourceMB - $addedMB, 2)

        Write-Host "SUCCESS: Saved standardized file." -ForegroundColor Green
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host "TRIMMED  : Removed Unused Tracks      : -$($removedMB) MB" -ForegroundColor Red
        Write-Host "CRUNCHED : Original -> TV Optimized    : $($sourceMB) MB -> $($addedMB) MB (-$($optSaved) MB)" -ForegroundColor Blue
        Write-Host "TOTAL AUDIO SPACE RECLAIMED            : $([Math]::Round($removedMB + $optSaved, 2)) MB" -ForegroundColor Green
        Write-Host "-------------------------------------------------------`n" -ForegroundColor Gray
    }
}
