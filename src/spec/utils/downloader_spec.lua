--[[
  Spec for downloader utility

  Ensures all code paths and error handling in src/utils/downloader.lua are covered.
  Uses dependency injection for os.execute and package.config.
]]--

local downloader = require("src.utils.downloader")

describe("downloader utility", function()
  local orig_os_execute, orig_package_config

  before_each(function()
    orig_os_execute = nil
    orig_package_config = nil
  end)

  after_each(function()
    downloader._set_test_env(orig_os_execute, orig_package_config)
  end)

  it("returns true when wget succeeds", function()
    downloader._set_test_env(function(cmd)
      if cmd == "command -v wget >/dev/null 2>&1" then return 0 end
      if cmd:match('wget %-O') then return 0 end
      return false
    end, "/")
    local ok, err = downloader.download("http://example.com/file", "file.txt")
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("returns error when wget fails", function()
    downloader._set_test_env(function(cmd)
      if cmd == "command -v wget >/dev/null 2>&1" then return 0 end
      if cmd:match('wget %-O') then return 1 end
      return false
    end, "/")
    local ok, err = downloader.download("http://example.com/file", "file.txt")
    assert.is_false(ok)
    assert.matches("wget failed", err)
  end)

  it("falls back to curl when wget missing and curl succeeds", function()
    downloader._set_test_env(function(cmd)
      if cmd == "command -v wget >/dev/null 2>&1" then return false end
      if cmd == "command -v curl >/dev/null 2>&1" then return 0 end
      if cmd:match('curl %-fSL %-o') then return 0 end
      return false
    end, "/")
    local ok, err = downloader.download("http://example.com/file", "file.txt")
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("returns error when curl fails", function()
    downloader._set_test_env(function(cmd)
      if cmd == "command -v wget >/dev/null 2>&1" then return false end
      if cmd == "command -v curl >/dev/null 2>&1" then return 0 end
      if cmd:match('curl %-fSL %-o') then return 1 end
      return false
    end, "/")
    local ok, err = downloader.download("http://example.com/file", "file.txt")
    assert.is_false(ok)
    assert.matches("curl failed", err)
  end)

  it("returns error if neither wget nor curl is available", function()
    downloader._set_test_env(function(cmd)
      if cmd == "command -v wget >/dev/null 2>&1" or cmd == "command -v curl >/dev/null 2>&1" then return false end
      return false
    end, "/")
    local ok, err = downloader.download("http://example.com/file", "file.txt")
    assert.is_false(ok)
    assert.matches("Neither wget nor curl", err)
  end)

  it("checks for wget/curl using Windows syntax", function()
    downloader._set_test_env(function(cmd)
      if cmd == "where wget>NUL 2>NUL" then return 0 end
      if cmd == "where curl>NUL 2>NUL" then return 0 end
      if cmd:match('wget %-O') then return 0 end
      if cmd:match('curl %-fSL %-o') then return 0 end
      return false
    end, "\\")
    local ok, err = downloader.download("http://example.com/file", "file.txt")
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("returns error if wget and curl missing on Windows", function()
    downloader._set_test_env(function(cmd)
      if cmd == "where wget>NUL 2>NUL" or cmd == "where curl>NUL 2>NUL" then return false end
      return false
    end, "\\")
    local ok, err = downloader.download("http://example.com/file", "file.txt")
    assert.is_false(ok)
    assert.matches("Neither wget nor curl", err)
  end)
end)
