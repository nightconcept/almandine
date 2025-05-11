# Installer script for almd on Windows (PowerShell)
# Fetches and installs almd CLI from the latest (or specified) GitHub release, or locally with -local

$Repo = "nightconcept/almandine"
$AppHome = "$env:USERPROFILE\.almd"
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
  New-Item -ItemType Directory -Path $AppHome -Force | Out-Null
  New-Item -ItemType Directory -Path $WrapperDir -Force | Out-Null
  Copy-Item -Path ./build/almd.exe -Destination (Join-Path $WrapperDir 'almd.exe') -Force
  Write-Host "[DEV] Local installation complete!"
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

$VersionForAsset = if ($Tag.StartsWith("v")) { $Tag.Substring(1) } else { $Tag }
$AssetFilename = "almd_$($VersionForAsset)_windows_amd64.zip"
$ArchiveUrl = "https://github.com/$Repo/releases/download/$Tag/$AssetFilename"
$ArchiveName = $AssetFilename # Use the actual asset filename

Write-Host "Downloading Almandine release asset for tag $Tag ($AssetFilename) ..."
$ZipPath = Join-Path $TmpDir $ArchiveName
Download $ArchiveUrl $ZipPath

Write-Host "Extracting Almandine ..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Extract almd.exe directly to the TmpDir, assuming it's at the root of the zip
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $TmpDir)

# almd.exe should now be directly in $TmpDir
$AlmdExePathInTmp = Join-Path $TmpDir "almd.exe"
if (!(Test-Path $AlmdExePathInTmp)) {
    Write-Error "Could not find almd.exe in the extracted archive at $AlmdExePathInTmp."
    # List files in TmpDir for debugging
    Write-Host "Contents of ${TmpDir}:"
    Get-ChildItem -Path $TmpDir | ForEach-Object { Write-Host $_.Name }
    exit 1
}

Write-Host "Installing Almandine ..."
# Check for previous install and warn if present
if (Test-Path $AppHome) {
  Write-Host ""
  Write-Host "⚠️  WARNING: Previous Almandine install detected at $AppHome. It will be OVERWRITTEN! ⚠️" -ForegroundColor Yellow
  Write-Host ""
}
New-Item -ItemType Directory -Path $AppHome -Force | Out-Null
New-Item -ItemType Directory -Path $WrapperDir -Force | Out-Null

# Copy the binary to the wrapper directory
Copy-Item -Path $AlmdExePathInTmp -Destination (Join-Path $WrapperDir 'almd.exe') -Force

Write-Host "Installation complete!"
Write-Host "Make sure $WrapperDir is in your Path environment variable. You may need to restart your terminal or system."

Remove-Item -Recurse -Force $TmpDir
