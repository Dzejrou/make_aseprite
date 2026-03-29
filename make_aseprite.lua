-- Build an .aseprite file from a character asset directory.
--
-- Official Aseprite CLI exposes script arguments through --script-param and
-- app.params, so the practical invocation is:
--   aseprite --batch --script scripts/make_aseprite.lua \
--     --script-param in=characters/warlock \
--     --script-param out=characters/warlock_v2/warlock.aseprite
--
-- Parameters:
--   in:  input directory, defaults to the launch directory
--   out: output .aseprite path, defaults to out.aseprite in the launch directory

local DIRECTION_ORDER = {
  "south",
  "south-east",
  "east",
  "north-east",
  "north",
  "north-west",
  "west",
  "south-west",
}

local function fail(message)
  error("make_aseprite.lua: " .. message, 0)
end

local function lower(value)
  return string.lower(value)
end

local function is_absolute_path(path)
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

local function resolve_path(path, default_path)
  local raw = path
  if raw == nil or raw == "" then
    raw = default_path
  end

  if is_absolute_path(raw) then
    return app.fs.normalizePath(raw)
  end

  return app.fs.normalizePath(app.fs.joinPath(app.fs.currentPath, raw))
end

local function sorted_entries(path)
  if not app.fs.isDirectory(path) then
    return {}
  end

  local entries = app.fs.listFiles(path)
  table.sort(entries)
  return entries
end

local function list_png_files(path)
  local files = {}

  for _, entry in ipairs(sorted_entries(path)) do
    local full_path = app.fs.joinPath(path, entry)
    if app.fs.isFile(full_path) and lower(app.fs.fileExtension(entry)) == "png" then
      files[#files + 1] = full_path
    end
  end

  return files
end

local function load_image(path)
  return Image { fromFile = path }
end

local function collect_rotation_paths(input_dir)
  local rotation_dir = app.fs.joinPath(input_dir, "rotations")
  local paths = {}

  for _, direction in ipairs(DIRECTION_ORDER) do
    local image_path = app.fs.joinPath(rotation_dir, direction .. ".png")
    if app.fs.isFile(image_path) then
      paths[#paths + 1] = image_path
    end
  end

  return paths
end

local function collect_animations(input_dir)
  local animations_dir = app.fs.joinPath(input_dir, "animations")
  local animations = {}

  for _, animation_name in ipairs(sorted_entries(animations_dir)) do
    local animation_path = app.fs.joinPath(animations_dir, animation_name)
    if app.fs.isDirectory(animation_path) then
      local directions = {}

      for _, direction in ipairs(DIRECTION_ORDER) do
        local direction_path = app.fs.joinPath(animation_path, direction)
        if app.fs.isDirectory(direction_path) then
          local frames = list_png_files(direction_path)
          if #frames > 0 then
            directions[#directions + 1] = {
              name = direction,
              frames = frames,
            }
          end
        end
      end

      if #directions > 0 then
        animations[#animations + 1] = {
          name = animation_name,
          directions = directions,
        }
      end
    end
  end

  return animations
end

local function gather_image_paths(rotation_paths, animations)
  local image_paths = {}

  for _, path in ipairs(rotation_paths) do
    image_paths[#image_paths + 1] = path
  end

  for _, animation in ipairs(animations) do
    for _, direction in ipairs(animation.directions) do
      for _, frame_path in ipairs(direction.frames) do
        image_paths[#image_paths + 1] = frame_path
      end
    end
  end

  return image_paths
end

local function create_sprite_from_images(image_paths)
  if #image_paths == 0 then
    fail("no PNG inputs found in rotations/ or animations/")
  end

  local first_image = load_image(image_paths[1])
  local spec = ImageSpec(first_image.spec)
  local max_width = first_image.width
  local max_height = first_image.height

  for i = 2, #image_paths do
    local image = load_image(image_paths[i])
    if image.width > max_width then
      max_width = image.width
    end
    if image.height > max_height then
      max_height = image.height
    end
  end

  spec.width = max_width
  spec.height = max_height

  local sprite = Sprite(spec)

  if sprite.colorMode == ColorMode.INDEXED then
    local palette_sprite = Sprite { fromFile = image_paths[1], oneFrame = true }
    sprite:setPalette(palette_sprite.palettes[1])
    sprite.transparentColor = palette_sprite.transparentColor
    palette_sprite:close()
  end

  while #sprite.layers > 0 do
    sprite:deleteLayer(sprite.layers[1])
  end

  return sprite
end

local function ensure_frame_count(sprite, count)
  while #sprite.frames < count do
    sprite:newEmptyFrame(#sprite.frames + 1)
  end
end

local function populate_base_layer(sprite, rotation_paths)
  local layer = sprite:newLayer()
  layer.name = "base"
  layer.stackIndex = 1

  ensure_frame_count(sprite, #rotation_paths)

  for frame_number, image_path in ipairs(rotation_paths) do
    local image = load_image(image_path)
    sprite:newCel(layer, frame_number, image)
  end
end

local function populate_animation_group(sprite, animation)
  local group = sprite:newGroup()
  group.name = animation.name

  for _, direction in ipairs(animation.directions) do
    local layer = sprite:newLayer()
    layer.name = direction.name
    layer.parent = group

    ensure_frame_count(sprite, #direction.frames)

    for frame_number, image_path in ipairs(direction.frames) do
      local image = load_image(image_path)
      sprite:newCel(layer, frame_number, image)
    end
  end
end

local function make_output_directory(output_path)
  local output_dir = app.fs.filePath(output_path)
  if output_dir ~= "" and not app.fs.isDirectory(output_dir) then
    local ok = app.fs.makeAllDirectories(output_dir)
    if not ok then
      fail("could not create output directory: " .. output_dir)
    end
  end
end

local input_dir = resolve_path(app.params["in"], app.fs.currentPath)
local output_path = resolve_path(app.params["out"], "out.aseprite")

if not app.fs.isDirectory(input_dir) then
  fail("input directory does not exist: " .. input_dir)
end

local rotation_paths = collect_rotation_paths(input_dir)
local animations = collect_animations(input_dir)
local image_paths = gather_image_paths(rotation_paths, animations)

local sprite = create_sprite_from_images(image_paths)

populate_base_layer(sprite, rotation_paths)

for _, animation in ipairs(animations) do
  populate_animation_group(sprite, animation)
end

make_output_directory(output_path)
sprite:saveAs(output_path)
sprite:close()
print("Saved " .. output_path)
