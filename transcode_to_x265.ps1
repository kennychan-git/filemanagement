# --- 1. Robust Path Discovery ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Users\me\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe" }
$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")

# --- 2. Reliable AVX-512 Hardware Check ---
$isAVX512 = $false
try {
    # Testing for AVX-512 instruction set support in the x265 library
    $test = & $ffmpegPath -f lavfi -i color=c=black:s=16x16:d=0.1 -c:v libx265 -x265-params "asm=avx512" -f null - 2>&1
    if ($test -notmatch "invalid|error|not found") { $isAVX512 = $true }
} catch { $isAVX512 = $false }

# pmode=1 is essential for 4K performance on high-core-count CPUs
$x265Asm = if ($isAVX512) { "asm=avx512:pmode=1" } else { "auto" }

# --- 3. Stats Tracking ---
$startTime = Get-Date
$totalOriginalSize = 0
$totalNewSize = 0
$filesProcessed = 0

Clear-Host
Write-Host "================ AVX-512 TRANSCODER v1.4 ================" -ForegroundColor Cyan
Write-Host "AVX-512 STATUS : $(if($isAVX512){'ENABLED'}else{'FALLBACK'})" -ForegroundColor $(if($isAVX512){'Yellow'}else{'Red'})
Write-Host "ENHANCEMENT    : Resolution-Adaptive CRF (4K UHD Optimized)" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan

# Target all potential sources that aren't already x265-marked children
$files = Get-ChildItem -File | Where-Object { $_.Extension -match "mp4|mkv|avi|mov" -and $_.Name -notlike "*_x265*" }

foreach ($file in $files) {
    # Inspect Primary Video Stream
    $vInfo = & $ffprobePath -v error -select_streams v:0 -show_entries stream=codec_name,height -of csv=p=0 $file.FullName
    if (-not $vInfo) { continue }

    $codec = $vInfo.Split(',')[0]
    $height = [int]$vInfo.Split(',')[1]
    
    # Do not re-transcode if the codec is already HEVC
    if ($codec -eq "hevc") {
        Write-Host "SKIPPING: $($file.Name) (Already HEVC)" -ForegroundColor Gray
        continue
    }

    # --- 4. Resolution-Proportional CRF Logic ---
    # Higher pixel density (4K) allows for higher CRF with no perceived loss
    $targetCRF = 28 # Baseline for 1080p
    $resLabel = "1080p"

    if ($height -ge 2160) { 
        $targetCRF = 31      # 4K: High density hides compression mathematically
        $resLabel  = "4K UHD" 
    } 
    elseif ($height -le 576) { 
        $targetCRF = 22      # SD: Needs lower CRF to prevent blockiness
        $resLabel  = "SD/480p" 
    } 
    elseif ($height -le 720) { 
        $targetCRF = 24      # 720p: Sweet spot
        $resLabel  = "720p" 
    }

    $newName = $file.BaseName + "_x265.mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    
    if (Test-Path $outputPath) { continue }

    Write-Host "`nPROCESING: $($file.Name)" -ForegroundColor Cyan
    Write-Host "PROFILE    : $resLabel Detected -> Using CRF $targetCRF" -ForegroundColor Yellow
    
    # --- 5. Execution ---
    # Using Main 10 profile (yuv420p10le) for superior efficiency/banding prevention
    & $ffmpegPath -i "$($file.FullName)" `
             -map 0:v:0 -c:v:0 libx265 -crf $targetCRF -preset medium -x265-params "$($x265Asm):log-level=info" -pix_fmt yuv420p10le `
             -map 0:a? -c:a copy `
             -map 0:s? -c:s copy `
             -map_metadata 0 `
             -stats "$outputPath"

    # Post-process stats
    if (Test-Path $outputPath) {
        $totalOriginalSize += $file.Length
        $totalNewSize += (Get-Item $outputPath).Length
        $filesProcessed++
    }
}

# --- 6. Final Summary ---
if ($filesProcessed -gt 0) {
    $duration = (Get-Date) - $startTime
    $savedBytes = $totalOriginalSize - $totalNewSize
    $percent = [math]::Round(($savedBytes / $totalOriginalSize) * 100, 2)
    
    Write-Host "`n======================= REPORT =========================" -ForegroundColor Magenta
    Write-Host "Total Files      : $filesProcessed"
    Write-Host "Total Time       : $($duration.ToString('hh\:mm\:ss'))"
    Write-Host "Total In         : $([math]::Round($totalOriginalSize/1GB, 3)) GB"
    Write-Host "Total Out        : $([math]::Round($totalNewSize/1GB, 3)) GB"
    Write-Host "Space Saved      : $([math]::Round($savedBytes/1GB, 3)) GB ($percent%)" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Magenta
}
