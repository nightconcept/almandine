--[[
  Add Module Specification

  Tests src/modules/add.lua
]]
--

--- Add module specification for Busted.
-- @module add_spec

local add_mod = require("modules.add")

return function()
  local describe = require("busted").describe
  local it = require("busted").it
  local assert = require("luassert")
  local stub = require("luassert.stub")

  describe("add_module", function()
    -- Helper functions
    local function make_fake_manifest()
      return {
        name = "test-project",
        type = "application",
        version = "0.0.1",
        license = "MIT",
        description = "Test manifest",
        scripts = {},
        dependencies = {},
      }
    end

    local function make_test_deps(manifest, save_manifest_fn, downloader_fn)
      local saved_manifest, save_called
      local saved_lockfile
      local deps = {
        load_manifest = function()
          return manifest, nil
        end,
        save_manifest = save_manifest_fn or function(m)
          saved_manifest = m
          save_called = true
          return true, nil
        end,
        ensure_lib_dir = function() end,
        downloader = {
          download = downloader_fn or function(_, _)
            return true, nil
          end,
        },
        hash_utils = {
          hash_dependency = function(dep)
            -- Extract hash from GitHub URL if present
            local url = type(dep) == "string" and dep or dep.url
            if url:match("github.com") then
              local hash = url:match("/blob/([0-9a-f]+)/")
              if hash then
                return hash, nil
              end
            end
            return "no_hash_found", "URL does not contain a commit hash"
          end,
        },
        lockfile = {
          generate_lockfile_table = function(deps)
            return { package = deps }
          end,
          write_lockfile = function(table)
            saved_lockfile = table
            return true, nil
          end,
        },
      }
      return deps,
        function()
          return saved_manifest
        end,
        function()
          return save_called
        end,
        function()
          return saved_lockfile
        end
    end

    -- Help info output
    it("help_info returns correct usage string", function()
      local help = add_mod.help_info()
      assert.is_true(type(help) == "string")
      assert.are.same(
        help,
        [[
Usage: almd add <source> [-d <dir>] [-n <dep_name>]

Options:
  -d <dir>     Destination directory for the installed file
  -n <name>    Name of the dependency (optional, inferred from URL if not provided)

Example:
  almd add https://example.com/lib.lua
  almd add https://example.com/lib.lua -d src/lib/custom
  almd add https://example.com/lib.lua -n mylib
]]
      )
    end)

    -- add_dependency functionality
    it("returns true when adding dependency successfully", function()
      local printed = {}
      local print_stub = stub(_G, "print", function(msg)
        table.insert(printed, tostring(msg))
      end)

      -- Mock dependencies
      local manifest = make_fake_manifest()
      local deps, _, get_save_called = make_test_deps(manifest)
      local success, err = add_mod.add_dependency("testdep", "http://example.com/test.lua", nil, deps)

      assert.is_true(success)
      assert.are.same(err, nil)
      assert.is_true(get_save_called())
      assert.are.same(#printed, 4)
      print_stub:revert()
    end)

    it("handles GitHub blob URLs by converting to raw URLs", function()
      local manifest = make_fake_manifest()
      local deps, get_saved_manifest, _, _ = make_test_deps(manifest)
      local ensure_lib_dir_called = false
      local downloader_called = false
      local download_url

      deps.ensure_lib_dir = function()
        ensure_lib_dir_called = true
      end

      deps.downloader.download = function(url, _)
        downloader_called = true
        download_url = url
        return true, nil
      end

      local blob_url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
      local success, err = add_mod.add_dependency("shove", blob_url, nil, deps)

      assert.is_true(success)
      assert.are.same(err, nil)
      assert.is_true(ensure_lib_dir_called)
      assert.is_true(downloader_called)
      local expected_raw_url = "https://raw.githubusercontent.com/Oval-Tutu/shove/"
        .. "81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
      assert.are.same(download_url, expected_raw_url)

      -- Verify manifest stores the blob URL
      local saved_manifest = get_saved_manifest()
      assert.are.same(saved_manifest.dependencies.shove, blob_url)
    end)

    it("handles GitHub raw URLs directly", function()
      local manifest = make_fake_manifest()
      local deps, get_saved_manifest, _ = make_test_deps(manifest)
      local ensure_lib_dir_called = false
      local downloader_called = false
      local download_url

      deps.ensure_lib_dir = function()
        ensure_lib_dir_called = true
      end

      deps.downloader.download = function(url, _)
        downloader_called = true
        download_url = url
        return true, nil
      end

      local raw_url = "https://raw.githubusercontent.com/Oval-Tutu/shove/"
        .. "81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
      local success, err = add_mod.add_dependency("shove", raw_url, nil, deps)

      assert.is_true(success)
      assert.are.same(err, nil)
      assert.is_true(ensure_lib_dir_called)
      assert.is_true(downloader_called)
      assert.are.same(download_url, raw_url)

      -- Verify manifest stores the raw URL
      local saved_manifest = get_saved_manifest()
      assert.are.same(saved_manifest.dependencies.shove, raw_url)
    end)

    it("adds a simple dependency and stores git hash in lockfile", function()
      local manifest = make_fake_manifest()
      local deps, get_saved_manifest, get_save_called, get_saved_lockfile = make_test_deps(manifest)
      local ensure_lib_dir_called = false
      local downloader_called = false
      local downloader_args = {}
      deps.downloader.download = function(url, out_path)
        downloader_called = true
        downloader_args.url = url
        downloader_args.out_path = out_path
        return true, nil
      end
      deps.ensure_lib_dir = function()
        ensure_lib_dir_called = true
      end

      local dep_name = "shove"
      local dep_url = "https://github.com/Oval-Tutu/shove/blob/81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
      local _, _ = add_mod.add_dependency(dep_name, dep_url, nil, deps)

      -- Verify manifest updates
      assert.is_true(get_save_called())
      assert.are.same(get_saved_manifest().dependencies[dep_name], dep_url)
      assert.is_true(ensure_lib_dir_called)
      assert.is_true(downloader_called)
      local expected_raw_url = "https://raw.githubusercontent.com/Oval-Tutu/shove/"
        .. "81f7f879a812e4479493a88e646831d0f0409560/shove.lua"
      assert.are.same(downloader_args.url, expected_raw_url)
      assert.are.same(downloader_args.out_path, "shove.lua")

      -- Verify lockfile
      assert.is_true(get_saved_lockfile() ~= nil)
      assert.are.same(get_saved_lockfile().package[dep_name].hash, "81f7f879a812e4479493a88e646831d0f0409560")
    end)

    it("adds a dependency from a table source", function()
      local manifest = make_fake_manifest()
      local deps, get_saved_manifest = make_test_deps(manifest)
      local downloader_args = {}
      deps.downloader.download = function(url, out_path)
        downloader_args.url = url
        downloader_args.out_path = out_path
        return true, nil
      end

      local dep_name = "bar"
      local dep_source = {
        url = "https://github.com/owner/repo/blob/abcdef1234567890/bar.lua",
        path = "custom/bar.lua",
      }
      local _, _ = add_mod.add_dependency(dep_name, dep_source, nil, deps)

      assert.are.same(get_saved_manifest().dependencies[dep_name], dep_source)
      assert.are.equal(downloader_args.url, dep_source.url)
      assert.are.equal(downloader_args.out_path, "custom/bar.lua")
    end)

    it("infers name from URL if not provided", function()
      local manifest = make_fake_manifest()
      local deps, get_saved_manifest, get_save_called = make_test_deps(manifest)
      local ensure_lib_dir_called = false
      local downloader_called = false
      local downloader_args = {}
      deps.downloader.download = function(url, out_path)
        downloader_called = true
        downloader_args.url = url
        downloader_args.out_path = out_path
        return true, nil
      end
      deps.ensure_lib_dir = function()
        ensure_lib_dir_called = true
      end

      local dep_url = "https://github.com/owner/repo/blob/abcdef1234567890/baz.lua"
      local _, _ = add_mod.add_dependency(nil, dep_url, nil, deps)

      assert.is_true(get_save_called())
      assert.are.equal(get_saved_manifest().dependencies["baz"], dep_url)
      assert.is_true(ensure_lib_dir_called)
      assert.is_true(downloader_called)
      local expected_raw_url = "https://raw.githubusercontent.com/owner/repo/abcdef1234567890/baz.lua"
      assert.are.equal(downloader_args.url, expected_raw_url)
      assert.are.equal(downloader_args.out_path, "baz.lua")
    end)

    it("prints error and returns if manifest fails to load", function()
      local deps = {
        load_manifest = function()
          return nil, "manifest load error"
        end,
        save_manifest = function()
          return true, nil
        end,
        ensure_lib_dir = function() end,
        downloader = {
          download = function()
            return true, nil
          end,
        },
        hash_utils = {
          hash_dependency = function()
            return "hash123", nil
          end,
        },
        lockfile = {
          generate_lockfile_table = function()
            return {}
          end,
          write_lockfile = function()
            return true, nil
          end,
        },
      }

      local printed = {}
      stub(_G, "print", function(msg)
        table.insert(printed, tostring(msg))
      end)
      assert.has_no.errors(function()
        add_mod.add_dependency("testdep", "http://example.com/test.lua", nil, deps)
      end)
      assert.is_true(table.concat(printed, "\n"):match("manifest load error") ~= nil)
    end)

    it("prints error and returns if dep_name cannot be inferred from bad URL", function()
      local manifest = { dependencies = {} }
      local deps = make_test_deps(manifest)
      local save_manifest_called = false
      deps.save_manifest = function()
        save_manifest_called = true
      end

      local printed = {}
      stub(_G, "print", function(msg)
        table.insert(printed, tostring(msg))
      end)
      assert.has_no.errors(function()
        add_mod.add_dependency(nil, "https://example.com/", nil, deps)
      end)
      assert.is_true(table.concat(printed, "\n"):match("Could not infer dependency name") ~= nil)
      assert.is_false(save_manifest_called)
    end)

    it("prints error and returns if save_manifest fails", function()
      local manifest = { dependencies = {} }
      local deps = make_test_deps(manifest, function()
        return false, "save failed"
      end)

      local printed = {}
      stub(_G, "print", function(msg)
        table.insert(printed, tostring(msg))
      end)
      assert.has_no.errors(function()
        add_mod.add_dependency("foo", "url", nil, deps)
      end)
      assert.is_true(table.concat(printed, "\n"):match("save failed") ~= nil)
    end)

    it("prints error if downloader fails", function()
      local manifest = { dependencies = {} }
      local deps = make_test_deps(manifest, nil, function()
        return false, "download failed"
      end)

      local printed = {}
      stub(_G, "print", function(msg)
        table.insert(printed, tostring(msg))
      end)
      assert.has_no.errors(function()
        add_mod.add_dependency("foo", "url", nil, deps)
      end)
      local output = table.concat(printed, "\n")
      assert.is_true(output:match("Failed to download") ~= nil)
      assert.is_true(output:match("download failed") ~= nil)
    end)

    it("does not fail when no dependency is given", function()
      local manifest = make_fake_manifest()
      local deps = make_test_deps(manifest, function()
        error("Should not be called")
      end)

      assert.has_no.errors(function()
        add_mod.add_dependency(nil, nil, nil, deps)
      end)
    end)
  end)
end
