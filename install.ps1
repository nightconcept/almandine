# Installer script for almd on Windows (PowerShell)
# Fetches and installs almd CLI from the latest (or specified) GitHub release

$Repo = "nightconcept/almandine"
$Asset = "almd-release.zip"
$AppHome = "$env:USERPROFILE\.almd"
$WrapperDir = "$env:LOCALAPPDATA\Programs\almd"
$TmpDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString())
$Version = $null

if ($args.Count -gt 0) {
  $Version = $args[0]
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

if (!(Test-Path $TmpDir)) { New-Item -ItemType Directory -Path $TmpDir | Out-Null }

if ($Version) {
  $ApiUrl = "https://api.github.com/repos/$Repo/releases/tags/$Version"
} else {
  $ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
}

Write-Host "Fetching release info ..."
$Release = GithubApi $ApiUrl

$ZipUrl = $null
foreach ($asset in $Release.assets) {
  if ($asset.name -eq $Asset) {
    $ZipUrl = $asset.browser_download_url
    break
  }
}

if (-not $ZipUrl) {
  Write-Error "Could not find $Asset in release. Check version or release status."
  exit 1
}

Write-Host "Downloading $Asset ..."
$ZipPath = Join-Path $TmpDir $Asset
Download $ZipUrl $ZipPath

Write-Host "Extracting CLI ..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $TmpDir)

Write-Host "Installing CLI to $AppHome ..."
New-Item -ItemType Directory -Path $AppHome -Force | Out-Null
Copy-Item -Path (Join-Path $TmpDir 'release/src') -Destination $AppHome -Recurse -Force

Write-Host "Installing wrapper script to $WrapperDir ..."
New-Item -ItemType Directory -Path $WrapperDir -Force | Out-Null
Copy-Item -Path (Join-Path $TmpDir 'release/install/almd.ps1') -Destination (Join-Path $WrapperDir 'almd.ps1') -Force

Write-Host "\nInstallation complete!"
Write-Host "Make sure $WrapperDir is in your Path environment variable. You may need to restart your terminal or system."

Remove-Item -Recurse -Force $TmpDir
