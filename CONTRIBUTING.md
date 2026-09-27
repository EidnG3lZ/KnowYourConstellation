# Building and verification

Use Python 3 and the non-GC64 Windows x64 LuaJIT commit in dependencies.json.
Set HD2_LUAJIT to that compiler. Set HD2_GAME_ROOT if the game is not in the
standard Steam installation directory.

Run `python scripts/build.py`. The build verifies the supported game hashes,
runs the shared offline suites, compiles stripped bytecode, verifies the runtime
against the tested v3.12 hash, and creates the release ZIP.
Run `python scripts/privacy_audit.py --zip releases/Know-Your-Constellation-v3.12.zip`.
Nested workspace projects may share their parent's releases directory.

Run `python scripts/build.py --rows` to build the separate static rows variant.
See [Static rows variant](docs/ROWS.md) for layout and verification details.

Localized builds are supported end to end: Lua sources are read and written as
UTF-8, so display tables such as `src/catalogue.lua` may carry any script the
active locale's native body font covers. Keep display text free of ASCII
semicolons and control codes. Translating display text changes the runtime hash,
so build it with `--allow-untested` until an in-game check promotes the payload.
The Simplified Chinese fork documents its text inventory, terminology, glyph
availability and re-localization procedure in
[the localization playbook](docs/LOCALIZATION-zh-CN.md).

The shipped chunk is a non-GC64 (`-W`) dump for the game's loader. When
HD2_LUAJIT is a GC64 build, the local package test loads an equivalent GC64 dump
of the same wrapper instead; the packaged bytes are unaffected.

Use synthetic fixtures in public tests. Do not commit memory captures,
session packets, screenshots, local paths, extracted game files or logs.
Keep publication-files.json synchronized with the intended public files.
Run the privacy audit with `--git` after staging to include index and history.
