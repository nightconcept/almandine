---
--- Printer Utility
---
-- Provides functions for writing to standard output and standard error.
---

local M = {}

--- Writes the given arguments to standard output, followed by a newline.
--- Converts arguments to strings before writing.
---@vararg any The values to write.
function M.stdout(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  io.stdout:write(table.concat(parts, "\t"), "\n")
  io.stdout:flush() -- Ensure output is immediate
end

--- Writes the given arguments to standard error, followed by a newline.
--- Converts arguments to strings before writing.
---@vararg any The values to write.
function M.stderr(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  io.stderr:write(table.concat(parts, "\t"), "\n")
  io.stderr:flush() -- Ensure output is immediate
end

return M 