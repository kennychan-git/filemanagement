# =========================================================
# 1. ROBUST PATH DETECTION
# =========================================================
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source }
              elseif (Test-Path "C:\Program Files\Jellyfin\Server\ffmpeg.exe") { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
              else { Write-Error "FFmpeg not found!"; break }

$ffprobePath = Join-Path (Split-Path $ffmpegPath) "ffprobe.exe"

Write-Host "================ LIBRARY STANDARDIZER v2.9 ================" -ForegroundColor Cyan
Write-Host "MODE    : EN/CH Optimization + Robust Array Logic"
Write-Host "===========================================================" -ForegroundColor Cyan

# =========================================================
# 2. TARGET SELECTION
# =========================================================
$files = Get-ChildItem -File | Where-Object { 
    $_.Extension -eq ".mkv" -and $_.Name -notlike "*_standardized*" 
}

foreach ($file in $files) {
    $origDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName
    
    # Get all stream info: index, type, channels, and language tag
    $streamData = @(& $ffprobePath -v error -show_entries stream=index,codec_type,channels:stream_tags=language -of csv=p=0 $file.FullName)
    
    # Define expanded language patterns
    $engPattern = "eng"
    $chiPatterns = @("chi", "zho", "zh", "zh-cn", "zh-tw", "cmn")

    # Filter Audio and Subtitles (Force Array)
    $allAudio = @($streamData | Where-Object { $_ -like "*,audio,*" })
    $allSubs  = @($streamData | Where-Object { $_ -like "*,subtitle,*" })

    $engAudioLines = @($allAudio | Where-Object { $_ -like "*,$engPattern*" })
    $chiAudioLines = @($allAudio | Where-Object { 
        $line = $_
        $found = $false
        foreach ($p in $chiPatterns) { if ($line -like "*,$p*") { $found = $true } }
        $found
    })

    $keepAudioIdx = @()
    $optimizeJobs = @()

    # Process English detection
    if ($engAudioLines.Count -gt 0) {
        foreach ($line in $engAudioLines) { $keepAudioIdx += $line.Split(',')[0] }
        $firstEng = $engAudioLines[0].Split(',')
        $optimizeJobs += [PSCustomObject]@{ index = $firstEng[0]; lang = "eng"; channels = $firstEng[2]; label = "English" }
    }

    # Process Chinese detection (Fixed Split logic)
    if ($chiAudioLines.Count -gt 0) {
        foreach ($line in $chiAudioLines) { $keepAudioIdx += $line.Split(',')[0] }
        $firstChi = $chiAudioLines[0].Split(',')
        $optimizeJobs += [PSCustomObject]@{ index = $firstChi[0]; lang = "chi"; channels = $firstChi[2]; label = "Chinese" }
    }

    # FALLBACK: If NO tagged tracks found, pick the first audio track
    if ($optimizeJobs.Count -eq 0) {
        $firstAny = $allAudio | Select-Object -First 1
        if ($firstAny) {
            $parts = $firstAny.Split(',')
            $optimizeJobs += [PSCustomObject]@{ index = $parts[0]; lang = "und"; channels = $parts[2]; label = "Primary" }
            $keepAudioIdx += $parts[0]
        }
    }

    # Subtitle selection
    $keepSubIdx = @($allSubs | Where-Object {
        $line = $_
        $match = ($line -like "*,$engPattern*")
        foreach ($p in $chiPatterns) { if ($line -like "*,$p*") { $match = $true } }
        $match
    } | ForEach-Object { $_.Split(',')[0] })

    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_standardized.mkv")
    
    Write-Host "Standardizing: $($file.Name)" -ForegroundColor Cyan
    Write-Host "Found: $($engAudioLines.Count) English, $($chiAudioLines.Count) Chinese tracks." -ForegroundColor Gray
    foreach ($job in $optimizeJobs) {
        Write-Host " >> Optimizing $($job.label): Stream $($job.index) [$($job.channels)ch Detected]" -ForegroundColor Yellow
    }

    # =========================================================
    # 3. CONSTRUCT ARGUMENTS
    # =========================================================
    $ffArgs = @("-hide_banner", "-loglevel", "error", "-stats", "-i", $file.FullName)
    $ffArgs += "-map", "0:v:0", "-c:v", "copy"

    # Map Original Audio Tracks
    $outIdx = 0
    foreach ($idx in $keepAudioIdx) {
        $ffArgs += "-map", "0:$idx", "-c:a:$outIdx", "copy"
        $outIdx++
    }

    # Build Filter Complex
    $filterStrings = @()
    foreach ($job in $optimizeJobs) {
        $tag = "tv_$($job.lang)"
        $norm = "loudnorm=I=-16:TP=-1.5:LRA=11[$tag]"
        if ([int]$job.channels -ge 6) {
            $filterStrings += "[0:$($job.index)]pan=stereo|c0<c0+0.707*c2+0.5*c4|c1<c1+0.707*c2+0.5*c5,$norm"
        } else {
            $filterStrings += "[0:$($job.index)]$norm"
        }
    }
    $ffArgs += "-filter_complex", ($filterStrings -join ";")

    # Map Optimized Tracks
    $defaultTrackIdx = $null
    foreach ($job in $optimizeJobs) {
        $tag = "tv_$($job.lang)"
        $ffArgs += "-map", "[$tag]", "-c:a:$outIdx", "aac", "-b:a:$outIdx", "192k"
        $ffArgs += "-metadata:s:a:$outIdx", "title=TV Optimized ($($job.label))", "-metadata:s:a:$outIdx", "language=$($job.lang)"
        
        if ($job.lang -eq "eng") { $defaultTrackIdx = $outIdx }
        elseif ($null -eq $defaultTrackIdx) { $defaultTrackIdx = $outIdx }
        $outIdx++
    }

    $ffArgs += "-disposition:a", "0" 
    if ($null -ne $defaultTrackIdx) { $ffArgs += "-disposition:a:$defaultTrackIdx", "default" }

    # Map Subtitles
    foreach ($idx in $keepSubIdx) { $ffArgs += "-map", "0:$idx", "-c:s", "copy" }

    $ffArgs += "-map_metadata", "0", $outputPath

    # =========================================================
    # 4. EXECUTION
    # =========================================================
    & $ffmpegPath @ffArgs

    if ($LASTEXITCODE -eq 0) {
        $newDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $outputPath
        if ([Math]::Abs([double]$origDuration - [double]$newDuration) -lt 0.5) {
            Write-Host "SUCCESS: Saved standardized file." -ForegroundColor Green
        }
    }
}# =========================================================
# 1. ROBUST PATH DETECTION
# =========================================================
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source }
              elseif (Test-Path "C:\Program Files\Jellyfin\Server\ffmpeg.exe") { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
              else { Write-Error "FFmpeg not found!"; break }

$ffprobePath = Join-Path (Split-Path $ffmpegPath) "ffprobe.exe"

Write-Host "================ LIBRARY STANDARDIZER v2.9 ================" -ForegroundColor Cyan
Write-Host "MODE    : EN/CH Optimization + Robust Array Logic"
Write-Host "===========================================================" -ForegroundColor Cyan

# =========================================================
# 2. TARGET SELECTION
# =========================================================
$files = Get-ChildItem -File | Where-Object { 
    $_.Extension -eq ".mkv" -and $_.Name -notlike "*_standardized*" 
}

foreach ($file in $files) {
    $origDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName
    
    # Get all stream info: index, type, channels, and language tag
    $streamData = @(& $ffprobePath -v error -show_entries stream=index,codec_type,channels:stream_tags=language -of csv=p=0 $file.FullName)
    
    # Define expanded language patterns
    $engPattern = "eng"
    $chiPatterns = @("chi", "zho", "zh", "zh-cn", "zh-tw", "cmn")

    # Filter Audio and Subtitles (Force Array)
    $allAudio = @($streamData | Where-Object { $_ -like "*,audio,*" })
    $allSubs  = @($streamData | Where-Object { $_ -like "*,subtitle,*" })

    $engAudioLines = @($allAudio | Where-Object { $_ -like "*,$engPattern*" })
    $chiAudioLines = @($allAudio | Where-Object { 
        $line = $_
        $found = $false
        foreach ($p in $chiPatterns) { if ($line -like "*,$p*") { $found = $true } }
        $found
    })

    $keepAudioIdx = @()
    $optimizeJobs = @()

    # Process English detection
    if ($engAudioLines.Count -gt 0) {
        foreach ($line in $engAudioLines) { $keepAudioIdx += $line.Split(',')[0] }
        $firstEng = $engAudioLines[0].Split(',')
        $optimizeJobs += [PSCustomObject]@{ index = $firstEng[0]; lang = "eng"; channels = $firstEng[2]; label = "English" }
    }

    # Process Chinese detection (Fixed Split logic)
    if ($chiAudioLines.Count -gt 0) {
        foreach ($line in $chiAudioLines) { $keepAudioIdx += $line.Split(',')[0] }
        $firstChi = $chiAudioLines[0].Split(',')
        $optimizeJobs += [PSCustomObject]@{ index = $firstChi[0]; lang = "chi"; channels = $firstChi[2]; label = "Chinese" }
    }

    # FALLBACK: If NO tagged tracks found, pick the first audio track
    if ($optimizeJobs.Count -eq 0) {
        $firstAny = $allAudio | Select-Object -First 1
        if ($firstAny) {
            $parts = $firstAny.Split(',')
            $optimizeJobs += [PSCustomObject]@{ index = $parts[0]; lang = "und"; channels = $parts[2]; label = "Primary" }
            $keepAudioIdx += $parts[0]
        }
    }

    # Subtitle selection
    $keepSubIdx = @($allSubs | Where-Object {
        $line = $_
        $match = ($line -like "*,$engPattern*")
        foreach ($p in $chiPatterns) { if ($line -like "*,$p*") { $match = $true } }
        $match
    } | ForEach-Object { $_.Split(',')[0] })

    $outputPath = Join-Path $file.DirectoryName ($file.BaseName + "_standardized.mkv")
    
    Write-Host "Standardizing: $($file.Name)" -ForegroundColor Cyan
    Write-Host "Found: $($engAudioLines.Count) English, $($chiAudioLines.Count) Chinese tracks." -ForegroundColor Gray
    foreach ($job in $optimizeJobs) {
        Write-Host " >> Optimizing $($job.label): Stream $($job.index) [$($job.channels)ch Detected]" -ForegroundColor Yellow
    }

    # =========================================================
    # 3. CONSTRUCT ARGUMENTS
    # =========================================================
    $ffArgs = @("-hide_banner", "-loglevel", "error", "-stats", "-i", $file.FullName)
    $ffArgs += "-map", "0:v:0", "-c:v", "copy"

    # Map Original Audio Tracks
    $outIdx = 0
    foreach ($idx in $keepAudioIdx) {
        $ffArgs += "-map", "0:$idx", "-c:a:$outIdx", "copy"
        $outIdx++
    }

    # Build Filter Complex
    $filterStrings = @()
    foreach ($job in $optimizeJobs) {
        $tag = "tv_$($job.lang)"
        $norm = "loudnorm=I=-16:TP=-1.5:LRA=11[$tag]"
        if ([int]$job.channels -ge 6) {
            $filterStrings += "[0:$($job.index)]pan=stereo|c0<c0+0.707*c2+0.5*c4|c1<c1+0.707*c2+0.5*c5,$norm"
        } else {
            $filterStrings += "[0:$($job.index)]$norm"
        }
    }
    $ffArgs += "-filter_complex", ($filterStrings -join ";")

    # Map Optimized Tracks
    $defaultTrackIdx = $null
    foreach ($job in $optimizeJobs) {
        $tag = "tv_$($job.lang)"
        $ffArgs += "-map", "[$tag]", "-c:a:$outIdx", "aac", "-b:a:$outIdx", "192k"
        $ffArgs += "-metadata:s:a:$outIdx", "title=TV Optimized ($($job.label))", "-metadata:s:a:$outIdx", "language=$($job.lang)"
        
        if ($job.lang -eq "eng") { $defaultTrackIdx = $outIdx }
        elseif ($null -eq $defaultTrackIdx) { $defaultTrackIdx = $outIdx }
        $outIdx++
    }

    $ffArgs += "-disposition:a", "0" 
    if ($null -ne $defaultTrackIdx) { $ffArgs += "-disposition:a:$defaultTrackIdx", "default" }

    # Map Subtitles
    foreach ($idx in $keepSubIdx) { $ffArgs += "-map", "0:$idx", "-c:s", "copy" }

    $ffArgs += "-map_metadata", "0", $outputPath

    # =========================================================
    # 4. EXECUTION
    # =========================================================
    & $ffmpegPath @ffArgs

    if ($LASTEXITCODE -eq 0) {
        $newDuration = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $outputPath
        if ([Math]::Abs([double]$origDuration - [double]$newDuration) -lt 0.5) {
            Write-Host "SUCCESS: Saved standardized file." -ForegroundColor Green
        }
    }
}
