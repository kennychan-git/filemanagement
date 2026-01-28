# 1. Targeted dGPU Selection
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

$gpuSearch = Get-CimInstance Win32_VideoController | Where-Object { $_.Caption -notmatch "Remote|Microsoft|Basic" }
$selectedEngine = "none"; $gpuBrand = "None"; $vramBytes = 0

foreach ($gpu in $gpuSearch) {
    if ($gpu.Caption -match "NVIDIA") { 
        $selectedEngine = "cuda"; $gpuBrand = "NVIDIA"; $vramBytes = $gpu.AdapterRAM; break 
    }
    elseif ($gpu.Caption -match "AMD|Radeon") { 
        $selectedEngine = "d3d11va"; $gpuBrand = "AMD"; $vramBytes = $gpu.AdapterRAM; break 
    }
}
if ($selectedEngine -eq "none" -and ($gpuSearch.Caption -match "Intel")) {
    $selectedEngine = "qsv"; $gpuBrand = "Intel (iGPU)"
}

# 2. Refined Governor (Safety: 1.5GB/Thread)
$vramGB = if ($vramBytes) { [math]::Round($vramBytes / 1GB) } else { 0 }
$maxThreads = if ($selectedEngine -eq "qsv") { 8 } else { [math]::Min(8, [math]::Max(2, [math]::Floor($vramGB / 1.5))) }

# 3. UI Header
Clear-Host
Write-Host "================ UNIVERSAL HYBRID SCANNER v9.9 ================" -ForegroundColor Cyan
Write-Host "MACHINE   : $env:COMPUTERNAME"
Write-Host "TARGET    : $gpuBrand ($vramGB GB VRAM)" -ForegroundColor Yellow
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
    
    # Direct execution with error capture
    $hwErr = & $ffexe -hwaccel $engine -v error -i $file.FullName -f null - 2>&1
    
    $status = "Success"
    $isFallback = $false

    if ($hwErr) {
        $isFallback = $true
        $swErr = & $ffexe -v error -i $file.FullName -f null - 2>&1
        
        if ($swErr) {
            $msg = ($swErr | Out-String).ToLower()
            if ($msg -match "decoder|not implemented|unsupported|protocol") { $status = "Incompatible" }
            else { $status = "Error" }
        } else {
            $status = "Fallback"
        }
    }

    $label = switch($status) {
        "Success"      { $engine.ToUpper().PadRight(9) }
        "Fallback"     { "SW-DECODE" }
        "Incompatible" { "UNSUPPORT " }
        "Error"        { "CORRUPT   " }
    }
    $color = switch($status) {
        "Success" { "Green" }
        "Fallback" { "Yellow" }
        "Incompatible" { "Magenta" }
        "Error" { "Red" }
    }
    Write-Host "$label | $($file.Name)" -ForegroundColor $color
    [PSCustomObject]@{ Status = $status; Path = $file.FullName }
}

# 5. Final Summary
$globalWatch.Stop()
$hwCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
$swCount = ($results | Where-Object { $_.Status -eq "Fallback" }).Count
$incCount = ($results | Where-Object { $_.Status -eq "Incompatible" }).Count
$errCount = ($results | Where-Object { $_.Status -eq "Error" }).Count

Write-Host "`n======================= SCAN COMPLETE =========================" -ForegroundColor Cyan
$efficiency = if ($globalWatch.Elapsed.TotalSeconds -gt 0) { [math]::Round($totalSizeMB / $globalWatch.Elapsed.TotalSeconds, 2) } else { 0 }
Write-Host "Total Efficiency : $efficiency MB/s"
Write-Host "Hardware Success : $hwCount" -ForegroundColor Green
Write-Host "Software Fallback: $swCount" -ForegroundColor Yellow
Write-Host "HW Incompatible  : $incCount" -ForegroundColor Magenta
Write-Host "TRULY CORRUPT    : $errCount" -ForegroundColor Red
Write-Host "===============================================================" -ForegroundColor Cyan
