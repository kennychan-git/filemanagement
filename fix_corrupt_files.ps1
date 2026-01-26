# Add reference for Recycle Bin support
Add-Type -AssemblyName Microsoft.VisualBasic

$ffmpegPath = "C:\Program Files\Jellyfin\Server\ffmpeg.exe"
$corruptList = "corrupt_files.txt"
$logFile = "repair_results.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logEntry
    Write-Host $Message -ForegroundColor $Color
}

function Move-ToRecycleBin {
    param([string]$FilePath)
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($FilePath, 'OnlyErrorDialogs', 'SendToRecycleBin')
}

if (-not (Test-Path $corruptList)) {
    Write-Error "No corrupt_files.txt found!"
    return
}

$filesToFix = Get-Content $corruptList | ForEach-Object { $_.Trim() }

Write-Log "--- Starting Repair Session with Recycle Bin Safety ---" -Color Cyan

foreach ($filePath in $filesToFix) {
    $cleanPath = $filePath -replace "^CORRUPT:\s*", ""
    
    if (Test-Path -LiteralPath $cleanPath) {
        $fileItem = Get-Item -LiteralPath $cleanPath
        $dir = $fileItem.DirectoryName
        
        # Temporary file naming
        $tempFile = Join-Path $dir "$($fileItem.BaseName).tmp_repair.mkv"
        $finalTarget = [System.IO.Path]::ChangeExtension($cleanPath, ".mkv")
        
        Write-Log "Processing: $($fileItem.Name)" -Color Yellow
        
        # Execute FFmpeg Repair
        & $ffmpegPath -err_detect ignore_err -i "$cleanPath" -c copy -map 0 -ignore_unknown "$tempFile" -y -loglevel error
        
        if ($lastExitCode -eq 0 -and (Test-Path -LiteralPath $tempFile)) {
            $tempSize = (Get-Item -LiteralPath $tempFile).Length
            
            if ($tempSize -gt 100kb) {
                Write-Log "Repair successful. Moving original to Recycle Bin..." -Color Gray
                
                # Use the custom Recycle Bin function instead of Remove-Item
                Move-ToRecycleBin -FilePath $cleanPath
                
                # Rename the fixed file to the original name (standardized to .mkv)
                Move-Item -LiteralPath $tempFile -Destination $finalTarget -Force
                Write-Log "SUCCESS: Created $($finalTarget)" -Color Green
            } else {
                Write-Log "FAILED: Resulting file was too small ($($tempSize) bytes). Keeping original." -Color Red
                if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile }
            }
        } else {
            Write-Log "ERROR: FFmpeg failed to process $($fileItem.Name)" -Color Red
            if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile }
        }
    } else {
        Write-Log "NOT FOUND: $cleanPath" -Color Magenta
    }
}

Write-Log "--- Session Complete ---" -Color Cyan
