# Define the path to Jellyfin's internal FFmpeg
$ffmpegPath = "C:\Program Files\Jellyfin\Server\ffmpeg.exe"

# If you installed Jellyfin in a custom location, update the path above.
if (-not (Test-Path $ffmpegPath)) {
    Write-Error "FFmpeg not found at $ffmpegPath. Please check your Jellyfin install folder."
    return
}

Get-ChildItem -Recurse -Filter *.mkv | ForEach-Object {
    $file = $_
    Write-Host "Scanning: $($file.Name)" -ForegroundColor Cyan
    
    # We run a 'null' render to force FFmpeg to read every packet for errors
    $check = & $ffmpegPath -v error -i $file.FullName -f null - 2>&1
    
    if ($check -match "invalid as first byte" -or $check -match "Error" -or $check -match "out of range") {
        Add-Content -Path "corrupt_files.txt" -Value $file.FullName
        Write-Host "[!] Found Corruption: $($file.Name)" -ForegroundColor Red
    }
}
