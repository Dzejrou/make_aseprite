# import/export for Pixellab Aseprite workflows

This repository contains an importer and exporter for `.aseprite` files built around character directories exported from [pixellab.ai](https://pixellab.ai/).

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

## Import Output Structure

The generated `.aseprite` file contains:

- a `base` layer with the rotation images as frames in this order:
  `south`, `south-east`, `east`, `north-east`, `north`, `north-west`, `west`, `south-west`
- one layer group per animation directory
- inside each animation group, one layer per available direction
- each direction layer populated with that direction's animation frames

## Files

- `import`: shell wrapper that imports a Pixellab-style character directory into an `.aseprite` file
- `import.lua`: Aseprite Lua script used by the importer
- `export`: shell wrapper that exports a matching `.aseprite` file back into directories and PNG frames
- `export.lua`: Aseprite Lua script used by the exporter
- `lib.lua`: shared Aseprite Lua helpers used by both tools

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

### Import wrapper

From this repository:

```bash
./import --in /path/to/character --out /path/to/character/out.aseprite
```

Examples:

```bash
./import --in characters/ranger_v2 --out characters/ranger_v2/ranger.aseprite
./import --in characters/wolf --out characters/wolf/wolf.aseprite
```

If you omit arguments:

- `--in` defaults to the current directory
- `--out` defaults to `out.aseprite`

### Import Lua script directly through Aseprite

If you want to call Aseprite yourself instead of using the wrapper, run the Lua script with `--script-param` values:

```bash
aseprite --batch \
  --script-param in=/path/to/character \
  --script-param out=/path/to/character/out.aseprite \
  --script ./import.lua
```

Example:

```bash
aseprite --batch \
  --script-param in=characters/ranger_v2 \
  --script-param out=characters/ranger_v2/ranger.aseprite \
  --script scripts/import.lua
```

Notes:

- `--script-param in=...` sets the input character directory
- `--script-param out=...` sets the output `.aseprite` file
- if omitted, the import Lua script defaults to the current directory for input and `out.aseprite` for output
- the parameters should be passed before `--script`

### Export wrapper

The exporter writes top-level image layers and top-level layer groups directly under the output directory:

```text
output/
├── base/
│   ├── south.png
│   ├── east.png
│   └── ...
├── idle/
│   ├── south/
│   │   ├── frame_000.png
│   │   └── ...
│   └── east/
└── attack/
```

Usage:

```bash
./export --in /path/to/character.aseprite --out /path/to/output
```

Examples:

```bash
./export --in characters/ranger_v2/ranger.aseprite --out /tmp/ranger_export
./export --in characters/ranger_v2/ranger.aseprite --out /tmp/ranger_filtered --export base --export_group attack
```

Exporter flags:

- `--replace` overwrites files written by the current export
- `--replace-all` deletes exported top-level layer/group directories before exporting
- `--export <layer>` filters to named top-level image layers; repeatable
- `--export_group <group>` filters to named top-level layer groups; repeatable

### Export Lua script directly through Aseprite

```bash
aseprite --batch \
  --script-param in=/path/to/character.aseprite \
  --script-param out=/path/to/output \
  --script-param replace=1 \
  --script-param export=base \
  --script-param export_group=attack \
  --script ./export.lua
```

Notes:

- `--script-param in=...` points to the input `.aseprite` file
- `--script-param out=...` points to the output directory
- `--script-param replace=1` enables overwrite mode
- `--script-param replace_all=1` removes exported top-level directories before export
- `--script-param export=...` and `--script-param export_group=...` accept comma-separated names
- if no `export` / `export_group` filters are provided, the exporter writes all top-level image layers and groups

## Notes

- The wrappers translate their CLI flags into Aseprite `--script-param` values.
- The import Lua script uses the largest discovered input image size as the canvas size.
- Rotation frames and animation frames can coexist even when a character has 4-direction animations but 8-direction base rotations.
