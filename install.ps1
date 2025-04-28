# Installer script for almd on Windows (PowerShell)
# Copies src/ to $env:USERPROFILE\.almd and wrapper to $env:LOCALAPPDATA\Programs\almd

$AppHome = "$env:USERPROFILE\.almd"
$WrapperDir = "$env:LOCALAPPDATA\Programs\almd"

Write-Host "Installing almd to $AppHome ..."
New-Item -ItemType Directory -Path $AppHome -Force | Out-Null
Copy-Item -Path ".\src\*" -Destination $AppHome -Recurse -Force

Write-Host "Installing wrapper script to $WrapperDir ..."
New-Item -ItemType Directory -Path $WrapperDir -Force | Out-Null
Copy-Item -Path ".\install\almd.ps1" -Destination (Join-Path $WrapperDir "almd.ps1") -Force

Write-Host "\nInstallation complete!"
Write-Host "Make sure $WrapperDir is in your Path environment variable. You may need to restart your terminal or system."
