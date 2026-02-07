$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source }
              elseif (Test-Path "C:\Program Files\Jellyfin\Server\ffmpeg.exe") { "C:\Program Files\Jellyfin\Server\ffmpeg.exe" }
              else { Write-Error "FFmpeg not found!"; break }

#$ffprobePath = $ffmpegPath.Replace("ffmpeg.exe", "ffprobe.exe")
$ffprobePath = Join-Path (Split-Path $ffmpegPath) "ffprobe.exe"

# --- 2. Reliable Hardware Check (CPU & GPU) ---
# Direct hardware interrogation via WMI/CIM is more reliable than software tests
$cpuFeatures = Get-CimInstance Win32_Processor | Select-Object -ExpandProperty Caption
# Note: Since PowerShell doesn't always expose SIMD flags easily, we use a more robust FFmpeg '-cpuflags' probe
$ffmpegCpuInfo = & $ffmpegPath -cpuflags 2>&1

$isAVX512 = $ffmpegCpuInfo -match "avx512"
$isAVX2   = $ffmpegCpuInfo -match "avx2"

# Detect HW Accelerators
$hwEncoders = & $ffmpegPath -encoders
$hasNVENC = $hwEncoders -match "hevc_nvenc"
$hasAMF   = $hwEncoders -match "hevc_amf"
$hasQSV   = $hwEncoders -match "hevc_qsv"

$gpuEncoder = $null
if ($hasNVENC) { $gpuEncoder = "hevc_nvenc" }
elseif ($hasQSV) { $gpuEncoder = "hevc_qsv" }
elseif ($hasAMF) { $gpuEncoder = "hevc_amf" }

# --- 3. User Prompt ---
Clear-Host
Write-Host "================ ENCODER SELECTION ================" -ForegroundColor Cyan
Write-Host "CPU MODEL       : $((Get-CimInstance Win32_Processor).Name)"
Write-Host "AVX-512 Support : $(if($isAVX512){'YES'}else{'NO'})" -ForegroundColor $(if($isAVX512){'Green'}else{'Gray'})
Write-Host "AVX2 Support    : $(if($isAVX2){'YES'}else{'NO'})" -ForegroundColor $(if($isAVX2){'Green'}else{'Gray'})
Write-Host "GPU Accelerator : $(if($gpuEncoder){$gpuEncoder}else{'NONE DETECTED'})"
Write-Host "---------------------------------------------------"

$choice = "S"
if ($gpuEncoder) {
    Write-Host "Choose your engine:"
    Write-Host "[G] GPU Hardware Encoding (Ultra Fast, Larger Files)" -ForegroundColor Green
    Write-Host "[S] Software Encoding (Slower, Smaller Files)" -ForegroundColor Yellow
    $userInput = Read-Host "Selection (G/S)"
    if ($userInput -eq "G") { $choice = "G" }
}

# pmode=1 is only beneficial if you have high core counts AND AVX-512
$x265Asm = if ($isAVX512) { "asm=avx512:pmode=1" } else { "auto" }

# --- 4. Stats Tracking ---
$startTime = Get-Date
$totalOriginalSize = 0
$totalNewSize = 0
$filesProcessed = 0

Clear-Host
Write-Host "================ TRANSCODER v1.6 ================" -ForegroundColor Cyan
Write-Host "MODE           : $(if($choice -eq 'G'){'GPU ACCELERATED ('+$gpuEncoder+')'}else{'SOFTWARE (x265)'})" -ForegroundColor Magenta
Write-Host "INSTRUCTION SET: $(if($isAVX512){'AVX-512'}elseif($isAVX2){'AVX2'}else{'AVX/SSE Fallback'})" -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Cyan

$files = Get-ChildItem -File | Where-Object { $_.Extension -match "mp4|mkv|avi|mov" -and $_.Name -notlike "*_x265*" }

foreach ($file in $files) {
    $vInfo = & $ffprobePath -v error -select_streams v:0 -show_entries stream=codec_name,height -of csv=p=0 $file.FullName
    if (-not $vInfo) { continue }

    $codec = $vInfo.Split(',')[0]
    $height = [int]$vInfo.Split(',')[1]
    
    if ($codec -eq "hevc") {
        Write-Host "SKIPPING: $($file.Name) (Already HEVC)" -ForegroundColor Gray
        continue
    }

    $targetCRF = 28 
    $resLabel = "1080p"
    if ($height -ge 2160) { $targetCRF = 31; $resLabel = "4K UHD" } 
    elseif ($height -le 576) { $targetCRF = 22; $resLabel = "SD/480p" } 
    elseif ($height -le 720) { $targetCRF = 24; $resLabel = "720p" }

    $newName = $file.BaseName + "_x265.mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    if (Test-Path $outputPath) { continue }

    Write-Host "`nPROCESING: $($file.Name)" -ForegroundColor Cyan
    Write-Host "PROFILE    : $resLabel Detected -> Using Target Value $targetCRF" -ForegroundColor Yellow
    
    if ($choice -eq "G") {
        & $ffmpegPath -i "$($file.FullName)" `
            -map 0:v:0 -c:v:0 $gpuEncoder -rc vbr -cq $targetCRF -preset p4 -pix_fmt p010le `
            -map 0:a? -c:a copy `
            -map 0:s? -c:s copy `
            -map_metadata 0 `
            -stats "$outputPath"
    } else {
        & $ffmpegPath -i "$($file.FullName)" `
            -map 0:v:0 -c:v:0 libx265 -crf $targetCRF -preset medium -x265-params "$($x265Asm):log-level=info" -pix_fmt yuv420p10le `
            -map 0:a? -c:a copy `
            -map 0:s? -c:s copy `
            -map_metadata 0 `
            -stats "$outputPath"
    }

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
