--[[
  Install Command Module

  Provides functionality to install dependencies based on the lockfile (`almd-lock.lua`).
  If the lockfile doesn't exist or is outdated compared to `project.lua`, it will be generated/updated first.
]]
--

-- REMOVED: Unused top-level requires, use versions passed in deps
-- local url_utils = require("utils.url")
-- local filesystem_utils = require("utils.filesystem")
-- local lockfile = require("utils.lockfile") -- REMOVED: Use the one passed in deps

---
-- Installs dependencies based primarily on the lockfile.
-- Generates or updates the lockfile if necessary based on the manifest.
-- If dep_name is provided, only installs that specific dependency after ensuring the lockfile is up-to-date.
--
-- @param dep_name string|nil Dependency name to install (or all if nil).
-- @param deps table A table containing required dependencies:
--   - load_manifest function: Function to load the project manifest.
--   - ensure_lib_dir function: Function to ensure the library directory exists.
--   - downloader table: The downloader module.
--   - lockfile table: The lockfile utility module.
--   - hash_utils table: The hash utility module (optional, primarily for future verification).
--   - filesystem table: The filesystem utility module.
--   - url_utils table: The URL utility module.
local function install_dependencies(dep_name, deps)
  local load_manifest = deps.load_manifest
  local ensure_lib_dir = deps.ensure_lib_dir
  local effective_downloader = deps.downloader
  local lockfile_utils = deps.lockfile -- Use the passed-in lockfile utility
  local fs_utils = deps.filesystem -- Use the passed-in filesystem utility
  local url_utils = deps.url_utils -- Use the passed-in url utility
  local hash_utils = deps.hash_utils -- Use the passed-in hash utility

  ensure_lib_dir() -- Ensure base lib directory exists

  -- 1. Load Manifest
  local manifest, err_load = load_manifest()
  if not manifest then
    print("Failed to load manifest (project.lua): " .. tostring(err_load))
    return false, "Manifest load failed"
  end
  local manifest_deps = manifest.dependencies or {}

  -- 2. Load Lockfile (if exists)
  local existing_lock_data, err_lock_load = lockfile_utils.load_lockfile()
  if err_lock_load then
    print("Warning: Could not load existing lockfile: " .. tostring(err_lock_load))
    existing_lock_data = { package = {} } -- Treat as empty, ensuring .package exists
  end
  local existing_lock_deps = existing_lock_data.package or {} -- Ensure it's a table

  -- 3. Reconcile Manifest with Lockfile & Build Target Lockfile Data
  local target_lock_deps = {}
  local lockfile_updated = false
  local needs_content_hash = {} -- Keep track of deps needing post-download hash verification/calculation

  print("Checking project.lua dependencies against lockfile...")
  for name, dep_info in pairs(manifest_deps) do
    -- Validate manifest entry format (must be table with url and path)
    if type(dep_info) == "table" and dep_info.url and dep_info.path then
      -- Try to extract commit hash from URL for github: prefix
      local _, extracted_commit_hash = url_utils.normalize_github_url(dep_info.url, nil)

      local manifest_entry = {
        source = dep_info.url, -- Store the original source URL
        path = dep_info.path,
        -- hash = nil -- Set below
      }

      -- Determine the hash type and value for the lockfile
      if extracted_commit_hash then
        manifest_entry.hash = "github:" .. extracted_commit_hash
      else
        -- No extractable GitHub hash, mark for SHA512 content hash
        needs_content_hash[name] = true
        -- manifest_entry.hash will be set after download if needed
      end

      local existing_entry = existing_lock_deps[name]

      -- Determine if update is needed
      local needs_update = false
      if not existing_entry then
        needs_update = true
        print(string.format("Adding new lockfile entry for %s.", name))
      elseif existing_entry.source ~= manifest_entry.source or existing_entry.path ~= manifest_entry.path then
        needs_update = true
        print(string.format("Updating lockfile entry for %s (source/path changed).", name))
      elseif manifest_entry.hash and existing_entry.hash ~= manifest_entry.hash then
        -- If we determined a github: hash and it differs from existing
        needs_update = true
        print(
          string.format(
            "Updating lockfile entry for %s (hash changed: %s -> %s).",
            name,
            existing_entry.hash or "N/A",
            manifest_entry.hash
          )
        )
      elseif needs_content_hash[name] and (not existing_entry.hash or not existing_entry.hash:find("^sha512:")) then
        -- If we need a content hash, but existing doesn't have one (or it's not sha512)
        needs_update = true
        print(string.format("Marking lockfile entry for %s for SHA512 hash update.", name))
      end

      if needs_update then
        target_lock_deps[name] = manifest_entry -- Store the entry derived from manifest
        lockfile_updated = true -- Mark lockfile as needing save
      else
        -- Entry exists and matches (or SHA512 will be verified later), copy it
        target_lock_deps[name] = existing_entry
        -- If existing entry needs content hash check, mark it
        if existing_entry.hash and existing_entry.hash:find("^sha512:") then
          needs_content_hash[name] = true -- Mark for verification after download
        end
      end
    else
      -- Invalid entry format, print message and skip
      print(string.format("Skipping %s: Invalid entry in project.lua. Requires at least url and path.", name))
    end
  end

  -- Stale entry removal logic remains implicitly handled

  -- 4. Pre-Save Lockfile
  local lock_data_to_save = {
    api_version = existing_lock_data.api_version or "1",
    package = target_lock_deps,
  }

  -- Remove commit field before saving (if it accidentally exists)
  for _, entry in pairs(lock_data_to_save.package) do
    entry.commit = nil
  end

  if lockfile_updated or fs_utils.get_path_type("almd-lock.lua") ~= "file" then
    print("Updating almd-lock.lua...")
    local ok_save, err_save = lockfile_utils.write_lockfile(lock_data_to_save)
    if not ok_save then
      print("Failed to save lockfile: " .. tostring(err_save))
      print("Warning: Proceeding with installation despite lockfile save failure.")
    else
      print("Lockfile updated.")
    end
  else
    print("Lockfile is up-to-date.")
  end

  -- 5. Install Dependencies from the Target Lockfile Data
  print("Installing dependencies from lockfile...")
  local install_count = 0
  local fail_count = 0
  local content_hashes_verified_or_calculated = false -- Flag if SHA512 logic ran

  for name, lock_entry in pairs(target_lock_deps) do
    -- Check if we should process this dependency (either all deps or the specific one)
    local should_process = (not dep_name) or (dep_name == name)

    if should_process then
      -- Validate the lock entry format
      if type(lock_entry) == "table" and lock_entry.source and lock_entry.path and lock_entry.hash then
        -- ### Start of main processing logic for valid entry ###
        local source_url = lock_entry.source
        local target_path = lock_entry.path
        local expected_hash = lock_entry.hash

        -- Get the raw download URL, preferring normalized version
        local _, _, normalized_download_url, norm_err = url_utils.normalize_github_url(source_url, nil)
        local download_url = normalized_download_url or source_url -- Fallback to original source if normalization fails
        if norm_err and normalized_download_url then
          print(string.format("Warning: Using potentially non-raw URL for %s. Normalization error: %s", name, norm_err))
        end

        local target_dir = target_path:match("(.+)[\\/]")
        if target_dir then
          fs_utils.ensure_dir_exists(target_dir)
        end

        local display_hash = expected_hash:match("^github:(.+)$")
        local display_name = name .. (display_hash and ("@" .. display_hash:sub(1, 7)) or "")
        print(string.format("Downloading %s from %s to %s...", display_name, download_url, target_path))
        local ok, err_download = effective_downloader.download(download_url, target_path)

        if ok then
          print(string.format("Downloaded %s to %s", name, target_path))
          install_count = install_count + 1

          -- Verify or Calculate SHA512 hash if needed
          if needs_content_hash[name] then
            content_hashes_verified_or_calculated = true -- Mark that we ran this logic
            print(string.format("Calculating/Verifying SHA512 hash for %s...", name))
            local calculated_hash, hash_err = hash_utils.calculate_sha512(target_path)

            if calculated_hash then
              local calculated_hash_str = "sha512:" .. calculated_hash
              if expected_hash:find("^sha512:") then -- Verify existing SHA512 hash
                if expected_hash == calculated_hash_str then
                  print(string.format("  -> SHA512 Verified: %s", calculated_hash_str))
                else
                  print(
                    string.format(
                      "Error: SHA512 Mismatch for %s! Expected %s, got %s",
                      name,
                      expected_hash,
                      calculated_hash_str
                    )
                  )
                  print("  -> This may indicate corrupted download or lockfile tampering.")
                  fail_count = fail_count + 1 -- Count as failure due to mismatch
                end
              else -- Calculate and store new SHA512 hash
                lock_entry.hash = calculated_hash_str
                print(string.format("  -> SHA512 Calculated: %s", lock_entry.hash))
                lockfile_updated = true -- Mark that we need to re-save the lockfile
              end
            else
              print(string.format("Warning: Failed to calculate hash for %s: %s", name, hash_err or "Unknown error"))
            end
          end
        else
          print(string.format("Failed to download %s: %s", name, err_download))
          fail_count = fail_count + 1
        end
        -- ### End of main processing logic for valid entry ###
      else
        -- Invalid lock entry format
        print(string.format("Skipping %s: Invalid lock entry format (missing source, path, or hash).", name))
        fail_count = fail_count + 1
      end
    end -- end if should_process
  end

  -- 6. Re-save Lockfile if hashes were calculated/updated
  if lockfile_updated and content_hashes_verified_or_calculated then
    print("Saving updated lockfile with content hashes...")
    -- Ensure commit field is definitely gone before final save
    for _, entry in pairs(target_lock_deps) do
      entry.commit = nil
    end
    local final_lock_data = { api_version = lock_data_to_save.api_version, package = target_lock_deps }
    local ok_resave, err_resave = lockfile_utils.write_lockfile(final_lock_data)
    if not ok_resave then
      print("Warning: Failed to re-save lockfile with calculated/verified content hashes: " .. tostring(err_resave))
    else
      print("Lockfile updated with content hashes.")
    end
  end

  print(string.format("Installation finished. %d dependencies installed, %d failed.", install_count, fail_count))
  if fail_count > 0 then
    return false, "Some dependencies failed to install or verify"
  end
  return true -- Indicate success
end

-- Keep lockfile require accessible if needed by other parts (though unlikely now)
-- local lockfile = require("utils.lockfile") -- Already required at the top

local function help_info()
  print([[
Usage: almd install [<dep_name>]

Installs dependencies based on almd-lock.lua.
If almd-lock.lua is missing or outdated compared to project.lua, it will be
generated or updated before installation.

If <dep_name> is specified, only that dependency will be installed after
ensuring the lockfile is up-to-date.

Examples:
  almd install          # Install all dependencies from lockfile (update if needed)
  almd install my_lib   # Install only 'my_lib' from lockfile (update if needed)
]])
end

return {
  install_dependencies = install_dependencies,
  -- lockfile = lockfile, -- No longer need to export lockfile module itself
  help_info = help_info,
}
