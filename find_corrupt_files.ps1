# 1. v10.2 Hardware Discovery Core (The "Last Known Best")
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }

# Find the physical GPU Name
$gpuInfo = Get-PnpDevice -PresentOnly | Where-Object { $_.Class -eq "Display" -and $_.FriendlyName -notmatch "Remote|Microsoft" } | Select-Object -First 1
$gpuName = $gpuInfo.FriendlyName

# RE-IMPLEMENTED v10.2 VRAM Logic
try {
    # Using the Registry Hardware Key that worked in v10.2
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\000*"
    $vramBytes = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.HardwareInformation.AdapterString -match "NVIDIA|AMD|Radeon" } | Select-Object -ExpandProperty HardwareInformation.MemorySize -First 1
    
    if (!$vramBytes) { 
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

# 2. Governor (v10.2 Calibration)
$maxThreads = if ($selectedEngine -eq "qsv") { 8 } 
              else { [math]::Min(8, [math]::Max(2, [math]::Floor($vramGB / 1.1))) }

# 3. UI Header
Clear-Host
Write-Host "================ UNIVERSAL HYBRID SCANNER v10.5 ===============" -ForegroundColor Cyan
Write-Host "MACHINE   : $env:COMPUTERNAME"
Write-Host "PHYSICAL  : $gpuName" -ForegroundColor Yellow
Write-Host "TRUE VRAM : $vramGB GB Detected" -ForegroundColor Yellow
Write-Host "STRATEGY  : $selectedEngine Engine - $maxThreads Threads" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Cyan

$allFiles = Get-ChildItem -Recurse -Include *.mkv, *.mp4 | Where-Object { $_.Length -gt 1mb -and $_.Name -like "*_standardized*"}
$totalFiles = $allFiles.Count
$globalWatch = [System.Diagnostics.Stopwatch]::StartNew()

# 4. Execution Loop (v10.3 Refined Auditor)
$results = $allFiles | ForEach-Object -ThrottleLimit $maxThreads -Parallel {
    $ffexe = $using:ffmpegPath
    $file = $_
    $engine = $using:selectedEngine
    
    # 1. Probing with Hardware Acceleration
    # We filter out the "non monotonically increasing dts" warnings which are common in DVD rips
    $hwRaw = & $ffexe -hwaccel $engine -v error -i $file.FullName -f null - 2>&1
    $hwErr = $hwRaw | Where-Object { 
        $_ -notmatch "monotonically increasing dts" -and 
        $_ -notmatch "buffer underflow" -and
        $_ -notmatch "Metadata update"
    }
    
    $status = "Success"
    if ($hwErr) {
        # 2. If HW fails, check with Software Decode (CPU)
        $swRaw = & $ffexe -v error -i $file.FullName -f null - 2>&1
        $swErr = $swRaw | Where-Object { $_ -notmatch "monotonically increasing dts" }

        if ($swErr) {
            $msg = ($swErr | Out-String).ToLower()
            # Distinguish between "Hardware can't do it" and "File is broken"
            if ($msg -match "decoder|not implemented|unsupported|no pixel format") {
                $status = "Incompatible"
            } else {
                $status = "Error"
            }
        } else {
            # If software passes but hardware failed, it's a Fallback (usually 10-bit H.264)
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
        "Success"      { "Green" }
        "Fallback"     { "Yellow" }
        "Incompatible" { "Magenta" }
        "Error"        { "Red" }
    }

    Write-Host "$label | $($file.Name)" -ForegroundColor $color
    [PSCustomObject]@{ Status = $status; Path = $file.FullName; Size = $file.Length }
}

# 5. Final Summary
$globalWatch.Stop()
$successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
Write-Host "`n======================= SCAN COMPLETE =========================" -ForegroundColor Cyan
$totalSizeMB = [math]::Round(($results | Measure-Object -Property Size -Sum).Sum / 1MB, 2)
$efficiency = if ($globalWatch.Elapsed.TotalSeconds -gt 0) { [math]::Round($totalSizeMB / $globalWatch.Elapsed.TotalSeconds, 2) } else { 0 }
Write-Host "Total Efficiency : $efficiency MB/s"
Write-Host "Hardware Success : $successCount" -ForegroundColor Green
Write-Host "Total Time       : $($globalWatch.Elapsed.ToString('hh\:mm\:ss'))"
Write-Host "===============================================================" -ForegroundColor Cyan

# --- 6. Interactive Production Promotion ---
Write-Host "`n"
$standardizedFiles = Get-ChildItem -Recurse | Where-Object { $_.Name -match "_standardized\.(mkv|mp4)$" }

if ($standardizedFiles.Count -gt 0) {
    Write-Host "FOUND: $($standardizedFiles.Count) standardized versions ready for promotion." -ForegroundColor Cyan
    $promoteChoice = Read-Host "Promote standardized files to Production and rename originals to _ori? (Y/N)"

    if ($promoteChoice -eq "Y") {
        Write-Host "`nStarting Promotion & Backup..." -ForegroundColor Green
        $processedCount = 0

        foreach ($pfile in $standardizedFiles) {
            # Define the target Production Name (no suffix) and the Backup Name (_ori)
            $productionName = $pfile.Name -replace "_standardized", ""
            $productionPath = Join-Path $pfile.DirectoryName $productionName
            
            $extension = $pfile.Extension
            $baseName = $pfile.BaseName -replace "_standardized", ""
            $backupPath = Join-Path $pfile.DirectoryName "$($baseName)_ori$($extension)"

            if (Test-Path $productionPath) {
                try {
                    # 1. Sanity Check: Ensure standardized file isn't an empty/tiny husk
                    if ($pfile.Length -gt 1mb) {
                        
                        # 2. Rename Original to _ori (The Backup)
                        # If a backup already exists, we overwrite it to prevent script hang
                        Move-Item $productionPath $backupPath -Force -ErrorAction Stop
                        
                        # 3. Rename Standardized to Production (The Swap)
                        Move-Item $pfile.FullName $productionPath -Force -ErrorAction Stop
                        
                        Write-Host "PROMOTED: $productionName (Original saved as _ori)" -ForegroundColor Gray
                        $processedCount++
                    }
                } catch {
                    Write-Host "ERROR: Failed to process $productionName - $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                # Handle cases where standardized exists but the "original" is already gone/renamed
                Write-Host "NOTICE: Original source for $($pfile.Name) not found. Renaming to production." -ForegroundColor Yellow
                Rename-Item $pfile.FullName $productionName -Force
            }
        }
        Write-Host "`nPromotion Complete. $processedCount files updated." -ForegroundColor Green
        Write-Host "You can now manually delete all '*_ori$extension' files after verification." -ForegroundColor Cyan
    } else {
        Write-Host "`nProcess cancelled." -ForegroundColor Yellow
    }
} else {
    Write-Host "No standardized files found to promote." -ForegroundColor Gray
}
