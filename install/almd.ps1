# PowerShell wrapper for launching the almd Lua application
# Finds a suitable Lua interpreter and runs src/main.lua with all arguments.

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

& $LUA_BIN $Main @args
exit $LASTEXITCODE
