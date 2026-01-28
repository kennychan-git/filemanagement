# 1. Physical Hardware Interrogation (Bypasses 4GB WMI Cap)
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

# Find the physical GPU Name
$gpuInfo = Get-PnpDevice -PresentOnly | Where-Object { $_.Class -eq "Display" -and $_.FriendlyName -notmatch "Remote|Microsoft" } | Select-Object -First 1
$gpuName = $gpuInfo.FriendlyName

# TRUE VRAM DETECTION: Using Performance Counters (Bypasses WMI 4GB limit)
try {
    $perfVram = (Get-Counter "\GPU Process Memory(pid_*)\Dedicated Usage").CounterSamples | Measure-Object -Property CookedValue -Sum
    # If counters are empty (common in fresh RDP), use the Registry Hardware Key
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\000*"
    $vramBytes = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.HardwareInformation.AdapterString -match "NVIDIA|AMD|Radeon" } | Select-Object -ExpandProperty HardwareInformation.MemorySize -First 1
    
    if (!$vramBytes) { 
        # Final Fallback for 1660S/RX580 logic
        if ($gpuName -match "1660") { $vramBytes = 6GB }
        elseif ($gpuName -match "580|570|590") { $vramBytes = 8GB }
        else { $vramBytes = 4GB }
    }
} catch { $vramBytes = 4GB }

$vramGB = [math]::Round([double]$vramBytes / 1GB)

# Engine Selection
$selectedEngine = "none"
if ($gpuName -match "NVIDIA") { $selectedEngine = "cuda" }
elseif ($gpuName -match "AMD|Radeon") { $selectedEngine = "d3d11va" }
elseif ($gpuName -match "Intel") { $selectedEngine = "qsv" }

# 2. Dynamic Governor v3.0 (Aggressive Desktop Mode)
# 1.2GB per thread floor for 6GB+ cards
$maxThreads = if ($selectedEngine -eq "qsv") { 8 } 
              else { [math]::Min(8, [math]::Max(2, [math]::Floor($vramGB / 1.1))) }

# 3. UI Header
Clear-Host
Write-Host "================ UNIVERSAL HYBRID SCANNER v10.2 ===============" -ForegroundColor Cyan
Write-Host "MACHINE   : $env:COMPUTERNAME (Hardware Audit)"
Write-Host "PHYSICAL  : $gpuName" -ForegroundColor Yellow
Write-Host "TRUE VRAM : $vramGB GB Detected" -ForegroundColor Yellow
Write-Host "STRATEGY  : $selectedEngine Engine - $maxThreads Threads" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Cyan

$allFiles = Get-ChildItem -Recurse -Include *.mkv, *.mp4 | Where-Object { $_.Length -gt 1mb }
$totalFiles = $allFiles.Count
$totalSizeMB = [math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
$globalWatch = [System.Diagnostics.Stopwatch]::StartNew()

# 4. Execution Loop
$results = $allFiles | ForEach-Object -ThrottleLimit $maxThreads -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $engine = $using:selectedEngine
    
    $hwErr = & $ffexe -hwaccel $engine -v error -i $file.FullName -f null - 2>&1
    
    $status = "Success"
    if ($hwErr) {
        $swErr = & $ffexe -v error -i $file.FullName -f null - 2>&1
        if ($swErr) {
            $msg = ($swErr | Out-String).ToLower()
            $status = if ($msg -match "decoder|not implemented|unsupported") { "Incompatible" } else { "Error" }
        } else { $status = "Fallback" }
    }

    $label = switch($status) {
        "Success"      { $engine.ToUpper().PadRight(9) }
        "Fallback"     { "SW-DECODE" }
        "Incompatible" { "UNSUPPORT " }
        "Error"        { "CORRUPT   " }
    }
    Write-Host "$label | $($file.Name)" -ForegroundColor $(switch($status){"Success"{"Green"};"Fallback"{"Yellow"};"Incompatible"{"Magenta"};"Error"{"Red"}})
    [PSCustomObject]@{ Status = $status; Path = $file.FullName }
}

# 5. Final Summary (Fixed .Count bug)
$globalWatch.Stop()
$successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
Write-Host "`n======================= SCAN COMPLETE =========================" -ForegroundColor Cyan
$efficiency = if ($globalWatch.Elapsed.TotalSeconds -gt 0) { [math]::Round($totalSizeMB / $globalWatch.Elapsed.TotalSeconds, 2) } else { 0 }
Write-Host "Total Efficiency : $efficiency MB/s"
Write-Host "Hardware Success : $successCount" -ForegroundColor Green
Write-Host "Total Time       : $($globalWatch.Elapsed.ToString('hh\:mm\:ss'))"
Write-Host "===============================================================" -ForegroundColor Cyan
