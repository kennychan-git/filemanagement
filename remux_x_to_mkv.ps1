# --- 1. Path Discovery ---
$ffmpegPath = if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { (Get-Command ffmpeg).Source } 
              else { "C:\Users\me\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe" }

# --- 2. Stats Tracking ---
$startTime = Get-Date
$filesProcessed = 0
$failedFiles = @()

Write-Host "Mode: Ultra-Fast Remux + Integrity Check (Pro Data Stripped)" -ForegroundColor Green

# --- 3. Processing ---
$files = Get-ChildItem -Path "." -Filter "*.mp4"

foreach ($file in $files) {
    # Define output filename: OriginalName.mkv
    $newName = $file.BaseName + ".mkv"
    $outputPath = Join-Path $file.DirectoryName $newName
    
    # Skip if output already exists
    if (Test-Path $outputPath) { 
        Write-Host "SKIPPING: $($newName) already exists." -ForegroundColor Yellow
        continue 
    }

    Write-Host "`nStep 1: Remuxing $($file.Name)..." -ForegroundColor Cyan
    
    # -map 0      -> Include all streams (Video, Audio, Subs)
    # -map -0:d   -> EXCLUDE data/timecode streams (Fixes Canon/Apple errors)
    # -c copy     -> Copy streams without re-encoding (Zero quality loss)
    & $ffmpegPath -i $file.FullName -map 0 -map -0:d -c copy -map_metadata 0 -v error $outputPath

    if ($LASTEXITCODE -eq 0 -and (Test-Path $outputPath)) {
        Write-Host "Step 2: Verifying Integrity..." -ForegroundColor Gray
        
        # Verification: Read through the file to ensure no packet corruption
        & $ffmpegPath -v error -i $outputPath -f null - 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "VERIFIED: $($newName) is healthy." -ForegroundColor Green
            $filesProcessed++
        } else {
            Write-Host "FAILURE: $($newName) failed integrity check!" -ForegroundColor Red
            $failedFiles += $newName
            # Rename failed file to prevent Jellyfin from trying to scan it
            Rename-Item $outputPath ($newName + ".CORRUPT")
        }
    } else {
        Write-Host "ERROR: FFmpeg failed during remux of $($file.Name)" -ForegroundColor Red
        $failedFiles += $file.Name
    }
}

# --- 4. Final Summary ---
$endTime = Get-Date
$duration = $endTime - $startTime
Write-Host "`n================================================" -ForegroundColor Magenta
Write-Host "            REMUX & VERIFY REPORT"
Write-Host "================================================" -ForegroundColor Magenta
Write-Host "Files Successfully Remuxed: $filesProcessed"
Write-Host "Total Time:                 $($duration.ToString("hh\:mm\:ss"))"

if ($failedFiles.Count -gt 0) {
    Write-Host "Warning: $($failedFiles.Count) files failed or had errors." -ForegroundColor Red
    foreach ($f in $failedFiles) { Write-Host " - $f" }
}
Write-Host "================================================" -ForegroundColor Magenta
