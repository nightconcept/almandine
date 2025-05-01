# Installer script for almd on Windows (PowerShell)
# Fetches and installs almd CLI from the latest (or specified) GitHub release, or locally with -local

$Repo = "nightconcept/almandine"
$WrapperDir = "$env:LOCALAPPDATA\Programs\almd"
$TmpDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString())
$Version = $null
$LocalMode = $false

# Usage: install.ps1 [-local] [version]
foreach ($arg in $args) {
  if ($arg -eq '--local') {
    $LocalMode = $true
  } elseif (-not $Version) {
    $Version = $arg
  }
}

function Download($url, $dest) {
  if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
  } elseif (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    curl.exe -L $url -o $dest
  } elseif (Get-Command wget.exe -ErrorAction SilentlyContinue) {
    wget.exe $url -O $dest
  } else {
    Write-Error "Neither Invoke-WebRequest, curl, nor wget found. Please install one and re-run."
    exit 1
  }
}

function GithubApi($url) {
  if (Get-Command Invoke-RestMethod -ErrorAction SilentlyContinue) {
    return Invoke-RestMethod -Uri $url -UseBasicParsing
  } elseif (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    $json = curl.exe -s $url
    return $json | ConvertFrom-Json
  } elseif (Get-Command wget.exe -ErrorAction SilentlyContinue) {
    $json = wget.exe -qO- $url
    return $json | ConvertFrom-Json
  } else {
    Write-Error "Neither Invoke-RestMethod, curl, nor wget found. Please install one and re-run."
    exit 1
  }
}

if ($LocalMode) {
  Write-Host "[DEV] Installing from local repository ..."
  New-Item -ItemType Directory -Path $WrapperDir -Force | Out-Null
  Copy-Item -Path ./src -Destination (Join-Path $WrapperDir 'src') -Recurse -Force
  Copy-Item -Path ./install/almd.ps1 -Destination (Join-Path $WrapperDir 'almd.ps1') -Force
  Write-Host "\n[DEV] Local installation complete!"
  Write-Host "Make sure $WrapperDir is in your Path environment variable. You may need to restart your terminal or system."
  exit 0
}

if (!(Test-Path $TmpDir)) { New-Item -ItemType Directory -Path $TmpDir | Out-Null }

# Fetch latest tag from GitHub if version not specified
if ($Version) {
  $Tag = $Version
} else {
  Write-Host "Fetching Almandine version info ..."
  $TagsApiUrl = "https://api.github.com/repos/$Repo/tags?per_page=1"
  $Tags = GithubApi $TagsApiUrl
  if ($Tags -is [System.Array] -and $Tags.Count -gt 0) {
    $Tag = $Tags[0].name
  } elseif ($Tags.name) {
    $Tag = $Tags.name
  } else {
    Write-Error "Could not determine latest tag from GitHub."
    exit 1
  }
}

$ArchiveUrl = "https://github.com/$Repo/archive/refs/tags/$Tag.zip"
$ArchiveName = "$Repo-$Tag.zip" -replace "/", "-"

Write-Host "Downloading Almandine archive for tag $Tag ..."
$ZipPath = Join-Path $TmpDir $ArchiveName
Download $ArchiveUrl $ZipPath

Write-Host "Extracting Almandine ..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $TmpDir)

# Find extracted folder (name format: almandine-<tag>)
$ExtractedDir = Join-Path $TmpDir "almandine-$Tag"
if (!(Test-Path $ExtractedDir)) {
  # Try with v prefix (e.g., v0.1.0)
  $ExtractedDir = Join-Path $TmpDir "almandine-v$Tag"
  if (!(Test-Path $ExtractedDir)) {
    Write-Error "Could not find extracted directory for tag $Tag."
    exit 1
  }
}

Write-Host "Installing Almandine to $WrapperDir ..."
# Check for previous install and warn if present
if (Test-Path $WrapperDir) {
  Write-Host ""
  Write-Host "⚠️  WARNING: Previous Almandine install detected at $WrapperDir. It will be OVERWRITTEN! ⚠️" -ForegroundColor Yellow
  Write-Host ""
}
New-Item -ItemType Directory -Path $WrapperDir -Force | Out-Null
Copy-Item -Path (Join-Path $ExtractedDir 'src') -Destination (Join-Path $WrapperDir 'src') -Recurse -Force
Copy-Item -Path (Join-Path $ExtractedDir 'src/install/almd.ps1') -Destination (Join-Path $WrapperDir 'almd.ps1') -Force

Write-Host "\nInstallation complete!"
Write-Host "Make sure $WrapperDir is in your Path environment variable. You may need to restart your terminal or system."

Remove-Item -Recurse -Force $TmpDir
