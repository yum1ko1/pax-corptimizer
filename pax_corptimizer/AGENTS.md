# Instructions for AI coding assistants (Claude Code, Cursor, Copilot, Codex…)

This folder is a **Pax Universe mod** — a 3D space strategy about restoring Earth after a nuclear war,
built on **Godot 4.7** with **GDScript**. Read this whole file before writing anything.

## Where things are

| What | Where |
|---|---|
| Mod manifest | `mod.json` (schema: `docs/modding/schemas/mod.schema.json` in the game folder) |
| Mod code entry | `main.gd` — must start with `extends PaxMod` |
| Changes to game data | `data/<file>.patch.json` — mirrors the game's `data/<file>.json` |
| Translations | `data/lang/<code>.json` — merged into the game dictionary |
| Your assets | anywhere in the mod; address them as `res://mods/<id>/…` or `path("…")` in code |
| Full guide | `docs/modding/en/README.md` (RU: `docs/modding/ru/README.md`) |
| API reference | `docs/modding/en/api-reference.md` (generated from code — trust it) |
| Working examples | `mods/example_theia` (planet + UI + save), `mods/example_alpha_centauri` (star system + arks) |

If the game folder is not open next to the mod, ask the user where the game is installed: the docs,
schemas and the game's own `data/*.json` (the source of truth for field names) are there.

## Code layout (keep it)

- `main.gd` only **registers**: preloads, modules, shared state, one-line entry points (the game's callbacks,
  `api.call` names, console). No logic and no inner classes in it.
- `src/` is split **by feature**: one folder per thing the mod does, holding its logic, its part of `main.gd`
  (`*_ctl.gd`: `extends RefCounted`, `const Host := preload(main.gd)`, `var app: Host`, made in `main.gd` as
  `var x_ctl: XCtl = XCtl.new(self)`) and its windows together. A new feature gets its own folder; never put files
  flat in `src/`.
- `src/shared/` — files shared by the Pax CorpInc mods (`whatsnew.gd`, `wheel_guard.gd`, `feedback.gd`): edit them
  only in `pax_corporations_dev/shared/` and run `python pax_corporations_dev/shared/sync.py`.

| Folder | Feature |
|---|---|
| `core/` | the life cycle |
| `profiler/` | profiler and frame timeline |
| `map/` | map tuner, switchable layers, hidden armies |
| `skip/` | the cover over a time skip |
| `enterprises/` | the switches over the game's enterprises (manager, its part of main.gd, the window «Предприятия») |
| `settings/` | the ⚙ panel and applying it |
| `shared/` | shared files of the series |

## Hard rules

1. **Never copy a whole game data file** into the mod. Use `*.patch.json` with `$append`, `$edit` + `$match`,
   `$remove`, `$insert_after`, `$replace`, or plain object merge (`null` deletes a key). Otherwise mods conflict.
2. **Game data keys are Russian** (`"тела"`, `"имя"`, `"род"`, `"параметры"`). Copy them exactly from the game's
   `data/*.json`. Do not translate keys. Body names (`"Земля"`, `"Марс"`) are ids — also exact.
3. **No player-visible text in code.** Put it into `data/lang/en.json` and `data/lang/ru.json` (at least these two)
   and read with `tr_key("key")`. Prefix keys with the mod id to avoid collisions.
4. **GDScript is strict here**: inferring a type from an untyped value is a compile error.
   Write `var x: float = dict["a"]`, not `var x := dict["a"]`. Same for results of untyped calls.
5. Use the **stable API** (`PaxGame` methods, `Pax` signals, `PaxMod` callbacks). `game.main`, `game.sim`,
   `game.world`, `game.stock` are raw internals with Russian identifiers — allowed, but may change between versions.
6. Save state only through `_save_state` → `_game_loaded` (JSON types only: no Vector3, no Objects).
7. Textures, sounds and models from the mod load at runtime without Godot import: use `texture()`, `sound()`,
   `model()`, `shader()` helpers (or `Pax.texture(path)`), never `load()` for png/jpg/ogg/glb.

8. **Sandbox — the game refuses to run a mod that breaks these** (checked before loading, shown with file:line):
   - no `OS.execute`/`create_process`/`shell_open`/environment/system paths; no network classes (`HTTPRequest`,
     `HTTPClient`, sockets, WebSocket, UPNP…); no `FileAccess`/`DirAccess`/`ConfigFile`/`ResourceSaver`, no
     `user://`, drive letters or `..` in paths; no `Expression`, `ClassDB`, `GDScript`, `set_script`,
     `Engine.get_singleton`, `str_to_var`; no `res://scripts/…` game scripts, scene changes or `get_tree().quit()`;
     no `.dll/.exe/.pck/.scn/.res` files and no GDScript embedded in `.tscn`.
   - `load()`/`preload()` only with a literal `"res://mods/<id>/…"` path. Everything else — the safe `PaxMod` API:
     `load_resource("x.tscn")`, `read_text("notes.txt")`, `read_bytes()`, `list_files("folder")`,
     `save_data("name", value)` / `load_data("name", default)`, `open_link("https://…")`, `texture()`, `sound()`,
     `model()`, `shader()`, `scene()`, `load_json()`, `get_setting()/set_setting()`.

## When the game reads what the mod writes (days_passed and enterprises)

- `_days_passed` comes **after** all the game's steps for the period: `_pax("_дни_прошли")` is called at the very end
  of `_start_period` (Main227:73). Whatever the mod changes there, the game sees only on its next step.
- Entries in `enterprises` take effect only **from the game's next step**.
- So the switches — `set_active`, `set_throttle`, `set_priority`, modernization — write into the live entry
  **immediately** through `manager.apply_now(body)`. Never leave them for the weekly tick.
- Inside `days_passed` the mutations (construction, `econ_add`) go **before** the manager's sync. Otherwise a new
  object shows up in the mirror one step late.
- Implemented in `src/enterprises/manager.gd` (`apply_now`, `days_passed` → queued builds → `sync_all`); keep new
  switches the same way.

## Verify your work — always

```
godot --headless --path <game folder> -- --check-mods <mod id>
```
Exit code 0 = no errors. Fix every ERROR and read every WARNING. In the running game press **F8** for the dev
console: `check <id>`, `json res://data/bodies.json` (final data after all patches), `eval game.body_names()`,
`reload` (re-read JSON/text/images without restarting). In the game **F6** reloads mod code and texts.

Enable/disable mods in the launcher → **Mods** (restart applies). Package for sharing: `--pack-mod <id>`.
