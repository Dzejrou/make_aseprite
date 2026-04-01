-- Inspect an .aseprite file and report top-level layers/groups with non-empty counts.
--
-- Practical invocation:
--   aseprite --batch \
--     --script-param in=characters/ranger_v2/ranger.aseprite \
--     --script-param json=1 \
--     --script inspect.lua
--
-- Parameters:
--   in:     input .aseprite file (required)
--   json:   emit JSON instead of text
--   layer:  comma-separated top-level image layer names to inspect
--   group:  comma-separated top-level layer group names to inspect

local SCRIPT_NAME = "inspect.lua"

local function current_script_dir()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  if string.sub(source, 1, 1) == "@" then
    source = string.sub(source, 2)
  end
  return app.fs.filePath(source)
end

local lib = dofile(app.fs.joinPath(current_script_dir(), "lib.lua"))

local function fail(message)
  lib.fail(SCRIPT_NAME, message)
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

local function count_non_empty_frames(sprite, layer)
  local count = 0

  for frame_number = 1, #sprite.frames do
    local cel = layer:cel(frame_number)
    if cel ~= nil and not cel.image:isEmpty() then
      count = count + 1
    end
  end

  return count
end

local function inspect_layer(sprite, layer)
  return {
    type = "layer",
    name = layer.name,
    non_empty_frames = count_non_empty_frames(sprite, layer),
  }
end

local function inspect_group(sprite, group)
  local children = {}
  local total_non_empty_cels = 0

  for _, child in ipairs(group.layers) do
    local item = nil

    if child.isImage then
      item = inspect_layer(sprite, child)
      total_non_empty_cels = total_non_empty_cels + item.non_empty_frames
    elseif child.isGroup then
      item = inspect_group(sprite, child)
      total_non_empty_cels = total_non_empty_cels + item.total_non_empty_cels
    end

    if item ~= nil then
      children[#children + 1] = item
    end
  end

  return {
    type = "group",
    name = group.name,
    total_non_empty_cels = total_non_empty_cels,
    children = children,
  }
end

local function json_escape(value)
  local replacements = {
    ['\\'] = '\\\\',
    ['"'] = '\\"',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
  }

  return string.gsub(value, '[%z\1-\31\\"]', function(char)
    return replacements[char] or string.format("\\u%04x", string.byte(char))
  end)
end

local function is_array(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      return false
    end
    count = count + 1
  end

  return count == #value
end

local function encode_json(value)
  local value_type = type(value)

  if value_type == "nil" then
    return "null"
  elseif value_type == "boolean" then
    return value and "true" or "false"
  elseif value_type == "number" then
    return tostring(value)
  elseif value_type == "string" then
    return '"' .. json_escape(value) .. '"'
  elseif value_type == "table" then
    if is_array(value) then
      local parts = {}
      for i = 1, #value do
        parts[#parts + 1] = encode_json(value[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end

    local keys = {}
    for key, _ in pairs(value) do
      keys[#keys + 1] = key
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
      parts[#parts + 1] = encode_json(tostring(key)) .. ":" .. encode_json(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end

  fail("cannot encode value of type " .. value_type .. " as JSON")
end

local function print_item(item, indent)
  local prefix = string.rep("  ", indent)

  if item.type == "layer" then
    print(prefix .. "- " .. item.name .. " [layer]: " .. item.non_empty_frames .. " non-empty frames")
    return
  end

  print(prefix .. "- " .. item.name .. " [group]: " .. item.total_non_empty_cels .. " total non-empty child cels")
  for _, child in ipairs(item.children) do
    print_item(child, indent + 1)
  end
end

local input_param = app.params["in"]
if input_param == nil or input_param == "" then
  fail("--in is required")
end

local input_path = lib.resolve_path(input_param, nil)
local json_output = lib.parse_bool(app.params["json"])
local selected_layers = parse_name_list(app.params["layer"])
local selected_groups = parse_name_list(app.params["group"])

if not app.fs.isFile(input_path) then
  fail("input file does not exist: " .. tostring(input_path))
end

local sprite = Sprite { fromFile = input_path }
local total_frames = #sprite.frames
local items = {}
local matched_layers = {}
local matched_groups = {}

for _, layer in ipairs(sprite.layers) do
  if layer.isImage and is_selected(layer.name, selected_layers) then
    items[#items + 1] = inspect_layer(sprite, layer)
    matched_layers[layer.name] = true
  elseif layer.isGroup and is_selected(layer.name, selected_groups) then
    items[#items + 1] = inspect_group(sprite, layer)
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

if #items == 0 then
  fail("no matching top-level image layers or groups found")
end

local result = {
  input = input_path,
  total_frames = total_frames,
  items = items,
}

if json_output then
  print(encode_json(result))
else
  print("Sprite: " .. input_path)
  print("Frames: " .. result.total_frames)
  for _, item in ipairs(items) do
    print_item(item, 0)
  end
end
