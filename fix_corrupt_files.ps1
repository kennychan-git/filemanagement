$ffmpegPath = "C:\Program Files\Jellyfin\Server\ffmpeg.exe"
$corruptList = "corrupt_files.txt"

if (-not (Test-Path $corruptList)) {
    Write-Error "No corrupt_files.txt found!"
    return
}

# Read the list and trim any invisible characters/spaces
$filesToFix = Get-Content $corruptList | ForEach-Object { $_.Trim() }

foreach ($filePath in $filesToFix) {
    # Specifically handling the "CORRUPT: " prefix if present
    $cleanPath = $filePath -replace "^CORRUPT:\s*", ""
    
    # Use -LiteralPath to handle brackets [ ] and special characters correctly
    if (Test-Path -LiteralPath $cleanPath) {
        $fileItem = Get-Item -LiteralPath $cleanPath
        $tempFile = $cleanPath + ".fixed.mkv"
        
        Write-Host "Repairing: $($fileItem.Name)" -ForegroundColor Yellow
        
        # We use quotes around the paths to handle spaces
        & $ffmpegPath -err_detect ignore_err -i "$cleanPath" -c copy -map 0 -ignore_unknown "$tempFile" -y
        
        if ($lastExitCode -eq 0 -and (Test-Path -LiteralPath $tempFile)) {
            Write-Host "Success! Replacing original..." -ForegroundColor Green
            # Remove and Move also need to be careful with literal paths
            Remove-Item -LiteralPath $cleanPath
            Move-Item -LiteralPath $tempFile -Destination $cleanPath
        } else {
            Write-Host "Failed to repair $($fileItem.Name)" -ForegroundColor Red
        }
    } else {
        # Debugging output to see exactly what path the script is failing on
        Write-Host "Still can't find: $cleanPath" -ForegroundColor Magenta
    }
}
Write-Host "Task complete." -ForegroundColor Cyan
