# make_aseprite

`make_aseprite` builds an `.aseprite` file from a character directory exported from [pixellab.ai](https://pixellab.ai/).

It is meant for folders that look like Pixellab character exports, with:

- a `rotations/` directory containing directional PNGs
- an `animations/` directory containing one subdirectory per animation
- animation subdirectories containing one subdirectory per direction
- directional animation directories containing `frame_###.png` files

## Expected Input Layout

```text
character/
├── rotations/
│   ├── south.png
│   ├── south-east.png
│   ├── east.png
│   ├── north-east.png
│   ├── north.png
│   ├── north-west.png
│   ├── west.png
│   └── south-west.png
└── animations/
    ├── idle/
    │   ├── south/
    │   │   ├── frame_000.png
    │   │   └── ...
    │   ├── east/
    │   └── ...
    ├── walk/
    └── attack/
```

Only existing directions are used. Missing directions are ignored.

## Output Structure

The generated `.aseprite` file contains:

- a `base` layer with the rotation images as frames in this order:
  `south`, `south-east`, `east`, `north-east`, `north`, `north-west`, `west`, `south-west`
- one layer group per animation directory
- inside each animation group, one layer per available direction
- each direction layer populated with that direction's animation frames

## Files

- `make_aseprite`: shell wrapper that finds the Aseprite binary and passes arguments through to the Lua script
- `make_aseprite.lua`: Aseprite Lua script that constructs the sprite and layers

## Requirements

- [Aseprite](https://www.aseprite.org/) with scripting support
- a Pixellab-style character export directory

The wrapper looks for Aseprite in this order:

1. `ASEPRITE_BIN`
2. `aseprite` on `PATH`
3. `$HOME/Applications/Aseprite.app/Contents/MacOS/aseprite`
4. `/Applications/Aseprite.app/Contents/MacOS/aseprite`
5. `/Applications/Aseprite.app/Contents/MacOS/Aseprite`

## Usage

From this repository:

```bash
./make_aseprite --in /path/to/character --out /path/to/character/out.aseprite
```

Examples:

```bash
./make_aseprite --in characters/ranger_v2 --out characters/ranger_v2/ranger.aseprite
./make_aseprite --in characters/wolf --out characters/wolf/wolf.aseprite
```

If you omit arguments:

- `--in` defaults to the current directory
- `--out` defaults to `out.aseprite`

## Notes

- The wrapper translates `--in` and `--out` into Aseprite `--script-param` values.
- The Lua script uses the largest discovered input image size as the canvas size.
- Rotation frames and animation frames can coexist even when a character has 4-direction animations but 8-direction base rotations.
