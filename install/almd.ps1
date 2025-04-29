# PowerShell wrapper for launching the almd Lua application
# Finds a suitable Lua interpreter and runs src/main.lua with all arguments.

# Deferred self-update logic (Windows PowerShell)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$UpdatePending = Join-Path $ScriptDir 'update_pending'
$NextDir = Join-Path $ScriptDir 'next'
if ((Test-Path $UpdatePending -PathType Leaf -ErrorAction SilentlyContinue) -and (Test-Path $NextDir -PathType Container -ErrorAction SilentlyContinue)) {
  Remove-Item -Recurse -Force (Join-Path $ScriptDir 'src') -ErrorAction SilentlyContinue
  $srcPath = Join-Path $NextDir 'src'
  $almdPath = Join-Path $NextDir 'install/almd'
  $almdPs1Path = Join-Path $NextDir 'install/almd.ps1'
  Copy-Item -Recurse -Force $srcPath $ScriptDir -ErrorAction SilentlyContinue
  if (Test-Path $almdPath) {
    Remove-Item -Force (Join-Path $ScriptDir 'almd') -ErrorAction SilentlyContinue
    Copy-Item -Force $almdPath $ScriptDir -ErrorAction SilentlyContinue
  }
  if (Test-Path $almdPs1Path) {
    Remove-Item -Force (Join-Path $ScriptDir 'almd.ps1') -ErrorAction SilentlyContinue
    Copy-Item -Force $almdPs1Path $ScriptDir -ErrorAction SilentlyContinue
  }
  Remove-Item -Recurse -Force $NextDir -ErrorAction SilentlyContinue
  Remove-Item -Force $UpdatePending -ErrorAction SilentlyContinue
}

function Find-Lua {
  $candidates = @('lua.exe', 'lua5.4.exe', 'lua5.3.exe', 'lua5.2.exe', 'lua5.1.exe', 'luajit.exe')
  foreach ($cmd in $candidates) {
    $path = (Get-Command $cmd -ErrorAction SilentlyContinue)?.Source
    if ($path) { return $cmd }
  }
  return $null
}

$LUA_BIN = Find-Lua
if (-not $LUA_BIN) {
  Write-Error 'No suitable Lua interpreter found (lua, lua5.4, lua5.3, lua5.2, lua5.1, or luajit required).'
  exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Main = Join-Path $ScriptDir 'src/main.lua'

# Construct module paths
$luaPathPrefix = "$ScriptDir/src/?.lua;$ScriptDir/src/lib/?.lua;"
$luaCPathPrefix = "$ScriptDir/src/?.dll;$ScriptDir/src/lib/?.dll;"

# Prepend to LUA_PATH if set, else set default
if ($env:LUA_PATH) {
  $env:LUA_PATH = "$luaPathPrefix$env:LUA_PATH"
} else {
  $env:LUA_PATH = "$luaPathPrefix;"
}

# Prepend to LUA_CPATH if set, else set default
if ($env:LUA_CPATH) {
  $env:LUA_CPATH = "$luaCPathPrefix$env:LUA_CPATH"
} else {
  $env:LUA_CPATH = "$luaCPathPrefix;"
}

& $LUA_BIN $Main @args
exit $LASTEXITCODE
