# 1. Physical Hardware Interrogation
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

$gpuInfo = Get-PnpDevice -PresentOnly | Where-Object { $_.Class -eq "Display" -and $_.FriendlyName -notmatch "Remote|Microsoft" } | Select-Object -First 1
$gpuName = $gpuInfo.FriendlyName

# TRUE VRAM DETECTION (Registry Lookup for RDP/WMI Bypass)
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\000*"
$vramBytes = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.HardwareInformation.AdapterString -match "NVIDIA|AMD|Radeon" } | Select-Object -ExpandProperty HardwareInformation.MemorySize -First 1
if (!$vramBytes) { $vramBytes = 4GB }
$vramGB = [math]::Round([double]$vramBytes / 1GB)

# Engine Selection
$selectedEngine = "none"
if ($gpuName -match "NVIDIA") { $selectedEngine = "cuda" }
elseif ($gpuName -match "AMD|Radeon") { $selectedEngine = "d3d11va" }
elseif ($gpuName -match "Intel") { $selectedEngine = "qsv" }

# 2. Bimodal Governor (Safety/Perf Split)
if ($selectedEngine -eq "qsv") {
    $maxThreads = 8
    $modeLabel = "Intel QSV Standard"
} else {
    if ($vramGB -le 4) {
        $maxThreads = 2 # Hard-locked safety for A2000
        $modeLabel = "Safety (4GB Limited)"
    } else {
        $maxThreads = [math]::Min(8, [math]::Max(2, [math]::Floor($vramGB / 1.1)))
        $modeLabel = "High-Performance (Desktop)"
    }
}

# 3. UI Header
Clear-Host
Write-Host "================ UNIVERSAL FLEET AUDITOR v10.8 ================" -ForegroundColor Cyan
Write-Host "MACHINE   : $env:COMPUTERNAME"
Write-Host "PHYSICAL  : $gpuName ($vramGB GB VRAM)" -ForegroundColor Yellow
Write-Host "GOVERNOR  : $modeLabel -> $maxThreads Threads" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Cyan

$allFiles = Get-ChildItem -Recurse -Include *.mkv, *.mp4 | Where-Object { $_.Length -gt 1mb }
$totalFiles = $allFiles.Count
$globalWatch = [System.Diagnostics.Stopwatch]::StartNew()

# 4. Execution Loop
$results = $allFiles | ForEach-Object -ThrottleLimit $maxThreads -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $engine = $using:selectedEngine
    
    # Attempt HW Decode
    $hwErr = & $ffexe -hwaccel $engine -v error -i $file.FullName -f null - 2>&1
    
    $status = "PASSED"
    if ($hwErr) {
        # Simple Fallback Check
        $swErr = & $ffexe -v error -i $file.FullName -f null - 2>&1
        if ($swErr) { $status = "FAILED" }
        else { $status = "SOFT-PASS" }
    }

    $label = switch($status) {
        "PASSED"    { $engine.ToUpper().PadRight(9) }
        "SOFT-PASS" { "SW-DECODE" }
        "FAILED"    { "FAILED   " }
    }
    
    $color = switch($status) {
        "PASSED"    { "Green" }
        "SOFT-PASS" { "Yellow" }
        "FAILED"    { "Red" }
    }
    
    Write-Host "$label | $($file.Name)" -ForegroundColor $color
    [PSCustomObject]@{ Status = $status; Path = $file.FullName; Size = $file.Length }
}

# 5. Final Summary
$globalWatch.Stop()
$passCount = ($results | Where-Object { $_.Status -eq "PASSED" }).Count
$softCount = ($results | Where-Object { $_.Status -eq "SOFT-PASS" }).Count
$failFiles = $results | Where-Object { $_.Status -eq "FAILED" }

if ($failFiles) { $failFiles.Path | Out-File "failed_audit.txt" -Encoding utf8 }

Write-Host "`n======================= SCAN COMPLETE =========================" -ForegroundColor Cyan
$totalSizeMB = [math]::Round(($results | Measure-Object -Property Size -Sum).Sum / 1MB, 2)
$efficiency = if ($globalWatch.Elapsed.TotalSeconds -gt 0) { [math]::Round($totalSizeMB / $globalWatch.Elapsed.TotalSeconds, 2) } else { 0 }

Write-Host "Final Efficiency : $efficiency MB/s"
Write-Host "Hardware Pass    : $passCount" -ForegroundColor Green
Write-Host "Software Pass    : $softCount" -ForegroundColor Yellow
Write-Host "Total Failures   : $($failFiles.Count) (See failed_audit.txt)" -ForegroundColor Red
Write-Host "Total Time       : $($globalWatch.Elapsed.ToString('hh\:mm\:ss'))"
Write-Host "===============================================================" -ForegroundColor Cyan
