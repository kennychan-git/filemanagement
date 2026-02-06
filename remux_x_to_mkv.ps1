# --- 1. Hardware Interrogation & Selection ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

$gpus = Get-PnpDevice -PresentOnly | Where-Object { $_.Class -eq "Display" -and $_.FriendlyName -notmatch "Remote|Microsoft" }
$engines = @()
foreach ($gpu in $gpus) {
    if ($gpu.FriendlyName -match "NVIDIA") { $engines += [PSCustomObject]@{ Name = "NVIDIA (CUDA)"; Engine = "cuda" } }
    elseif ($gpu.FriendlyName -match "Intel") { $engines += [PSCustomObject]@{ Name = "Intel (QuickSync)"; Engine = "qsv" } }
}

$selectedEngine = "none"
if ($engines.Count -gt 1) {
    Write-Host "`nHardware Engines Detected:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $engines.Count; $i++) { Write-Host " [$i] $($engines[$i].Name)" }
    Write-Host " [S] Software (CPU Only)"
    $choice = Read-Host "`nSelect Engine"
    if ($choice -match '^\d$' -and [int]$choice -lt $engines.Count) { $selectedEngine = $engines[[int]$choice].Engine }
} elseif ($engines.Count -eq 1) { $selectedEngine = $engines[0].Engine }

# --- 2. Processing ---
$files = Get-ChildItem -File | Where-Object { $_.Extension -match "mp4|mov|avi" }
$startTime = Get-Date
$totalFrames = 0
$totalAuditTime = 0
$filesProcessed = 0

Clear-Host
Write-Host "================ UNIVERSAL REMUXER v2.9 ================" -ForegroundColor Cyan
Write-Host "ACTIVE ENGINE : $(if($selectedEngine -eq 'none') { 'SOFTWARE' } else { $selectedEngine.ToUpper() })" -ForegroundColor Yellow
Write-Host "STABILITY     : Silent-Safe Mapping Enabled" -ForegroundColor Gray
Write-Host "========================================================" -ForegroundColor Cyan

foreach ($file in $files) {
    $newName = $file.BaseName + ".mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    if (Test-Path $outputPath) { continue }

    $externalSub = Get-ChildItem -Path $file.DirectoryName -Filter ($file.BaseName + "*.srt") | Select-Object -First 1

    Write-Host "`n[1/2] Remuxing: $($file.Name)" -ForegroundColor Cyan
    Write-Host "       Target : $newName" -ForegroundColor Gray
    
    # FIXED MAPPING: Added '?' to audio/subtitle maps to prevent crashes on silent or sub-less files.
    if ($externalSub) {
        Write-Host "       SUBS   : Found External -> $($externalSub.Name)" -ForegroundColor Magenta
        & $ffmpegPath -i $file.FullName -i $externalSub.FullName `
            -map 0:v -map 0:a? -map 1:s? -map 0:s? `
            -c:v copy -c:a copy -c:s srt `
            -metadata:s:s:0 title="External Injected" -disposition:s:0 default `
            -map_metadata 0 -v error $outputPath
    } else {
        & $ffmpegPath -i $file.FullName `
            -map 0:v -map 0:a? -map 0:s? `
            -c:v copy -c:a copy -c:s srt `
            -map_metadata 0 -v error $outputPath
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[2/2] Auditing with $selectedEngine..." -ForegroundColor Gray
        $hwArgs = if ($selectedEngine -ne "none") { @("-hwaccel", $selectedEngine) } else { @() }
        
        $auditTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $log = & $ffmpegPath $hwArgs -i $outputPath -f null -benchmark - 2>&1
        $auditTimer.Stop()

        $logString = $log -join "`n"
        if ($logString -match 'frame=\s*(\d+)') {
            $frames = [int]$matches[1]
            $sec = $auditTimer.Elapsed.TotalSeconds
            $fps = [math]::Round($frames / $sec, 2)
            $totalFrames += $frames
            $totalAuditTime += $sec
            
            $subCheck = & $ffprobePath -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 $outputPath
            $subStatus = if($subCheck) { "SUBS: OK ($($subCheck -join ','))" } else { "SUBS: NONE" }

            # TUNED PERFORMANCE TELEMETRY: Focus on Decoder Throughput
            if ($fps -lt 2.0 -and $selectedEngine -ne "none") {
                Write-Host "VERIFIED: $frames frames @ $fps FPS (DECODER BOTTLE NECK: Critical Low)" -ForegroundColor Red
            } elseif ($fps -lt 15.0 -and $selectedEngine -ne "none") {
                Write-Host "VERIFIED: $frames frames @ $fps FPS (LOW THROUGHPUT: Non-Native HW Profile)" -ForegroundColor Yellow
            } else {
                Write-Host "VERIFIED: $frames frames @ $fps FPS (OPTIMAL)" -ForegroundColor Green
            }
            Write-Host "       $subStatus" -ForegroundColor Gray
        }
        $filesProcessed++
    }
}

# --- 3. Final Report ---
$totalTime = (Get-Date) - $startTime
Write-Host "`n======================= REPORT =========================" -ForegroundColor Magenta
Write-Host "Total Files      : $filesProcessed"
if ($totalAuditTime -gt 0) {
    $avgFps = [math]::Round($totalFrames / $totalAuditTime, 2)
    Write-Host "Average Perf     : $avgFps FPS" -ForegroundColor Yellow
}
Write-Host "Total Duration   : $($totalTime.ToString('hh\:mm\:ss'))"
Write-Host "========================================================" -ForegroundColor Magenta
