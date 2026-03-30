-- Export a Pixellab-style directory structure from an .aseprite file.
--
-- Practical invocation:
--   aseprite --batch \
--     --script-param in=characters/ranger_v2/ranger.aseprite \
--     --script-param out=/tmp/ranger_export \
--     --script-param replace=1 \
--     --script export.lua
--
-- Parameters:
--   in:          input .aseprite file (required)
--   out:         output directory, defaults to the launch directory
--   replace:     overwrite files that this export writes
--   replace_all: delete exported top-level layer and group directories before export
--   export:      comma-separated top-level image layer names to export
--   export_group: comma-separated top-level layer group names to export

local SCRIPT_NAME = "export.lua"

local function current_script_dir()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  if string.sub(source, 1, 1) == "@" then
    source = string.sub(source, 2)
  end
  return app.fs.filePath(source)
end

local lib = dofile(app.fs.joinPath(current_script_dir(), "lib.lua"))
local DIRECTION_ORDER = lib.DIRECTION_ORDER

local function fail(message)
  lib.fail(SCRIPT_NAME, message)
end

local function render_cel_on_canvas(sprite, cel)
  local image = Image(sprite.spec)
  image:drawImage(cel.image, cel.position, cel.opacity)
  return image
end

local function write_image(sprite, image, target_path, replace)
  if app.fs.isFile(target_path) and not replace then
    fail("refusing to overwrite existing file: " .. target_path .. " (use --replace or --replace-all)")
  end

  lib.ensure_parent_directory(target_path, SCRIPT_NAME)
  lib.save_image(image, target_path, sprite)
end

local function write_cel(sprite, cel, target_path, replace)
  local image = render_cel_on_canvas(sprite, cel)
  write_image(sprite, image, target_path, replace)
end

local function frame_filename(frame_number)
  return string.format("frame_%03d.png", frame_number - 1)
end

local function parse_name_list(value)
  local names = {}

  if value == nil or value == "" then
    return names
  end

  for name in string.gmatch(value, "([^,]+)") do
    names[name] = false
  end

  return names
end

local function is_selected(name, selected_names)
  return next(selected_names) == nil or selected_names[name] ~= nil
end

local function find_named_child_layer(group, name)
  for _, layer in ipairs(group.layers) do
    if layer.name == name then
      return layer
    end
  end
  return nil
end

local function export_direction_layer(sprite, layer, output_dir, replace)
  local exported = 0

  for index, direction in ipairs(DIRECTION_ORDER) do
    local cel = layer:cel(index)
    if cel ~= nil and not cel.image:isEmpty() then
      local target = app.fs.joinPath(output_dir, layer.name, direction .. ".png")
      write_cel(sprite, cel, target, replace)
      exported = exported + 1
    end
  end

  for frame_number = #DIRECTION_ORDER + 1, #sprite.frames do
    local cel = layer:cel(frame_number)
    if cel ~= nil and not cel.image:isEmpty() then
      print("Warning: ignoring extra non-empty frame " .. frame_number .. " in layer '" .. layer.name .. "'")
    end
  end

  return exported
end

local function export_animation_group(sprite, group, output_dir, replace)
  local exported = 0

  for _, direction in ipairs(DIRECTION_ORDER) do
    local layer = find_named_child_layer(group, direction)
    if layer ~= nil then
      if not layer.isImage then
        fail("layer '" .. direction .. "' in group '" .. group.name .. "' must be an image layer")
      end

      for frame_number = 1, #sprite.frames do
        local cel = layer:cel(frame_number)
        if cel ~= nil and not cel.image:isEmpty() then
          local target = app.fs.joinPath(
            output_dir,
            group.name,
            direction,
            frame_filename(frame_number)
          )
          write_cel(sprite, cel, target, replace)
          exported = exported + 1
        end
      end
    end
  end

  return exported
end

local input_param = app.params["in"]
if input_param == nil or input_param == "" then
  fail("--in is required")
end

local input_path = lib.resolve_path(input_param, nil)
local output_dir = lib.resolve_path(app.params["out"], app.fs.currentPath)
local replace = lib.parse_bool(app.params["replace"])
local replace_all = lib.parse_bool(app.params["replace_all"])
local selected_layers = parse_name_list(app.params["export"])
local selected_groups = parse_name_list(app.params["export_group"])

if replace_all then
  replace = true
end

if not app.fs.isFile(input_path) then
  fail("input file does not exist: " .. tostring(input_path))
end

if app.fs.isFile(output_dir) then
  fail("output path is a file, expected a directory: " .. output_dir)
end

local sprite = Sprite { fromFile = input_path }
local exported = 0
local matched_layers = {}
local matched_groups = {}

if replace_all then
  for _, layer in ipairs(sprite.layers) do
    if layer.isImage then
      lib.remove_tree(app.fs.joinPath(output_dir, layer.name), SCRIPT_NAME)
    elseif layer.isGroup then
      lib.remove_tree(app.fs.joinPath(output_dir, layer.name), SCRIPT_NAME)
    end
  end
end

lib.make_all_directories(output_dir, SCRIPT_NAME)

for _, layer in ipairs(sprite.layers) do
  if layer.isImage and is_selected(layer.name, selected_layers) then
    exported = exported + export_direction_layer(sprite, layer, output_dir, replace)
    matched_layers[layer.name] = true
  elseif layer.isGroup and is_selected(layer.name, selected_groups) then
    exported = exported + export_animation_group(sprite, layer, output_dir, replace)
    matched_groups[layer.name] = true
  end
end

sprite:close()

for name, _ in pairs(selected_layers) do
  if not matched_layers[name] then
    fail("requested layer not found: " .. name)
  end
end

for name, _ in pairs(selected_groups) do
  if not matched_groups[name] then
    fail("requested layer group not found: " .. name)
  end
end

if exported == 0 then
  fail("no exportable top-level image layers or animation groups found")
end

print("Exported " .. exported .. " images to " .. output_dir)
