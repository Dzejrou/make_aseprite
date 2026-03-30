local M = {}

M.DIRECTION_ORDER = {
  "south",
  "south-east",
  "east",
  "north-east",
  "north",
  "north-west",
  "west",
  "south-west",
}

function M.fail(script_name, message)
  error(script_name .. ": " .. message, 0)
end

function M.lower(value)
  return string.lower(value)
end

function M.is_absolute_path(path)
  if path == nil or path == "" then
    return false
  end

  if string.sub(path, 1, 1) == "/" then
    return true
  end

  if string.match(path, "^%a:[/\\]") then
    return true
  end

  return string.sub(path, 1, 2) == "\\\\"
end

function M.resolve_path(path, default_path)
  local raw = path
  if raw == nil or raw == "" then
    raw = default_path
  end

  if raw == nil or raw == "" then
    return nil
  end

  if M.is_absolute_path(raw) then
    return app.fs.normalizePath(raw)
  end

  return app.fs.normalizePath(app.fs.joinPath(app.fs.currentPath, raw))
end

function M.sorted_entries(path)
  if not app.fs.isDirectory(path) then
    return {}
  end

  local entries = app.fs.listFiles(path)
  table.sort(entries)
  return entries
end

function M.list_png_files(path)
  local files = {}

  for _, entry in ipairs(M.sorted_entries(path)) do
    local full_path = app.fs.joinPath(path, entry)
    if app.fs.isFile(full_path) and M.lower(app.fs.fileExtension(entry)) == "png" then
      files[#files + 1] = full_path
    end
  end

  return files
end

function M.parse_bool(value)
  if value == nil then
    return false
  end

  local normalized = M.lower(tostring(value))
  return normalized == "1"
    or normalized == "true"
    or normalized == "yes"
    or normalized == "on"
end

function M.make_all_directories(path, script_name)
  if path == nil or path == "" or app.fs.isDirectory(path) then
    return
  end

  local ok = app.fs.makeAllDirectories(path)
  if not ok and not app.fs.isDirectory(path) then
    M.fail(script_name, "could not create directory: " .. path)
  end
end

function M.ensure_parent_directory(path, script_name)
  local parent = app.fs.filePath(path)
  if parent ~= "" then
    M.make_all_directories(parent, script_name)
  end
end

function M.save_image(image, filename, sprite)
  if sprite.colorMode == ColorMode.INDEXED then
    image:saveAs {
      filename = filename,
      palette = sprite.palettes[1],
    }
  else
    image:saveAs(filename)
  end
end

function M.remove_tree(path, script_name)
  if app.fs.isFile(path) then
    local ok = os.remove(path)
    if not ok and app.fs.isFile(path) then
      M.fail(script_name, "could not remove file: " .. path)
    end
    return
  end

  if not app.fs.isDirectory(path) then
    return
  end

  for _, entry in ipairs(M.sorted_entries(path)) do
    local full_path = app.fs.joinPath(path, entry)
    if app.fs.isDirectory(full_path) then
      M.remove_tree(full_path, script_name)
    else
      local ok = os.remove(full_path)
      if not ok and app.fs.isFile(full_path) then
        M.fail(script_name, "could not remove file: " .. full_path)
      end
    end
  end

  local ok = app.fs.removeDirectory(path)
  if not ok and app.fs.isDirectory(path) then
    M.fail(script_name, "could not remove directory: " .. path)
  end
end

return M
