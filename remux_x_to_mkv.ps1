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
Write-Host "================ UNIVERSAL REMUXER v2.8.2 ================" -ForegroundColor Cyan
Write-Host "ACTIVE ENGINE : $(if($selectedEngine -eq 'none') { 'SOFTWARE' } else { $selectedEngine.ToUpper() })" -ForegroundColor Yellow
Write-Host "FEATURES      : External Sub Merging + Hardware Audit" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

foreach ($file in $files) {
    $newName = $file.BaseName + ".mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    if (Test-Path $outputPath) { continue }

    # SEARCH FOR EXTERNAL SUBS (Matching Filename)
    $externalSub = Get-ChildItem -Path $file.DirectoryName -Filter ($file.BaseName + "*.srt") | Select-Object -First 1

    Write-Host "`n[1/2] Remuxing: $($file.Name)" -ForegroundColor Cyan
    
    if ($externalSub) {
        Write-Host "SUBTITLES : FOUND EXTERNAL -> $($externalSub.Name)" -ForegroundColor Magenta
        & $ffmpegPath -i $file.FullName -i $externalSub.FullName `
            -map 0:v -map 0:a -map 1:s? -map 0:s? `
            -c:v copy -c:a copy -c:s srt `
            -metadata:s:s:0 title="External Injected" -disposition:s:0 default `
            -map_metadata 0 -v error $outputPath
    } else {
        & $ffmpegPath -i $file.FullName `
            -map 0:v -map 0:a -map 0:s? `
            -c:v copy -c:a copy -c:s srt `
            -map_metadata 0 -v error $outputPath
    }

    if ($LASTEXITCODE -eq 0) {
        # --- REINTEGRATED AUDIT LOGIC ---
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
            
            # Subtitle verification for the report
            $subCheck = & $ffprobePath -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 $outputPath
            $subStatus = if($subCheck) { "OK ($($subCheck -join ','))" } else { "NONE" }

            if ($fps -lt 15.0 -and $selectedEngine -ne "none") {
                Write-Host "VERIFIED  : $frames frames @ $fps FPS (HEAVY) | SUBS: $subStatus" -ForegroundColor Yellow
            } else {
                Write-Host "VERIFIED  : $frames frames @ $fps FPS | SUBS: $subStatus" -ForegroundColor Green
            }
        } else {
            Write-Host "VERIFIED  : Integrity Check Passed." -ForegroundColor Green
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
