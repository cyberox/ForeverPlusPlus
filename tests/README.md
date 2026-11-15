# Tests

Offline tests for Forever++, in plain Lua 5.1 with no WoW client. From the repo root:

```sh
lua5.1 tests/run.lua              # every spec
lua5.1 tests/run.lua store text   # only specs with one of these in their name
lua5.1 tests/run.lua -v           # print every check, not only failures
```

On Windows: `"C:\Program Files (x86)\Lua\5.1\lua.exe" tests/run.lua`. CI runs `lua5.1 tests/run.lua` on every push. The exit code is 0 only when every check passes and no spec errors.

## Layout

| Path | What |
| --- | --- |
| `run.lua` | The runner. It finds every file in `spec/`, runs them in name order, and prints a line per spec and the totals. |
| `lib/env.lua` | A fresh copy of the addon for each spec: stubbed WoW globals, an `ns`, the enUS Core and Map strings, the `Data/` files those need, and the pure-logic `Lib/` files. |
| `lib/standin.lua` | The whole addon loaded offline, every file in the TOC, against a stand-in for each WoW global that isn't stubbed, for the `modules` and `migrations` specs (`T.Whole`). |
| `lib/harness.lua` | The checks: `eq`, `same`, `near`, `ok`, `raises`. |
| `lib/bytecode.lua` | The globals a file reads and writes, with their lines, and the strings in its code, from its Lua 5.1 bytecode (what `luac -l` lists as GETGLOBAL and SETGLOBAL), for the `globals` and `rules` specs. |
| `lib/core.lua` | A fresh loaded Core for a spec, as `T.Core()`: the real `Core.lua` on stub frames and a stub clock (see The real Core). |
| `spec/*.lua` | One spec per area: a Lib file (`text`, `store`, `prices`, `cvars`, `units`, ...), Core by area (the `core_*` specs), the public API (`api`), what a plugin's module is handed (`plugins`), and checks across the addon (`docs`, `globals`, `locales`, `modules`, `release`, `rules`). |

## A spec

Each spec runs in its own environment: globals it sets (`C_Map = {...}`) and globals the addon sets stay in that spec, so specs can't depend on each other or on order. A spec that errors counts as broken, and the run goes on to the next one. One that makes no checks counts as broken too.

```lua
-- Taxi: the open flight master's nodes, read once a frame.
local T = ...
local ns, eq, game = T.ns, T.eq, T.game

C_TaxiMap = { GetAllTaxiNodes = function() return {} end }
eq(#ns.Taxi.Nodes(), 0, "taxi: no nodes")
```

What `T` holds:

- `T.ns`: the addon's `ns`, with the Lib files in `lib/env.lua`'s `LIBS` loaded.
- `T.player` and `T.game`: tables the stubs read. The Lib files cache functions like `UnitLevel` at load, so change `T.player.level` rather than the function.
- `T.load(path, into)`: loads one of the addon's files (`"Lib/Players"`, `"API"`) into `into` (`T.ns` by default), in this spec's environment. Use it for a file that needs stubs set first, or to load one again after changing a stub it caches.
- `T.Whole(before, around)`: every file in the TOC but `Init.lua`, loaded into an `ns` of its own against a stand-in client; returns that `ns`, its globals, and a line for each file that didn't load. `before(env, stub)` sets the globals the spec's checks need first, since files keep them at load. `around(path, ns, loaded)`, if given, runs before each file (`loaded` nil) and after it (true or false). Loading is all it does: no module is turned on. For a spec that needs the module files themselves, like a migration step.
- `T.Toc()`, `T.Read(path)`: the TOC's fields and file list, and a file's text.
- Checks. Each takes a short name, prefixed with the area (`"taxi: no nodes"`). A failure prints the spec's file and line, the name, and what it got.
  - `eq(got, want, what)`: equal with `==`.
  - `same(got, want, what)`: equal looking inside tables, and says where they differ.
  - `near(got, want, what, within)`: a number within `within` (default `1e-9`).
  - `ok(value, what)`: anything but `nil` or `false`.
  - `raises(fn, pattern, what)`: `fn` errors, with `pattern` in the message.

## The real Core

`T.ns` has no Core: a Lib spec stubs the one or two `ns` functions its file calls. A spec that tests Core itself, or needs a real one, calls `T.Core()` (`lib/core.lua`). Each call loads the real `Core.lua`, `Commands.lua`, and the Lib files Core needs into an `ns` of its own, against stub frames and a clock for `C_Timer`. `lua5.1 tests/run.lua core` runs every Core spec:

| Spec | What |
| --- | --- |
| `core_modules` | Modules and parts turning on and off, `OnWhile`, `PartOn`, a locked module. |
| `core_frames` | A window's saved size, and timers a module or part owns (`Lib/Frames.lua`). |
| `core_hooks` | A module's tooltip hooks. |
| `core_settings` | A choice staying saved until a reset, and a `cvar` checkbox in and out of combat. |
| `core_commands` | `/fpp set` and `toggle`, Defaults, a command whose module is off. |
| `core_profiles` | Switching profiles live, and `ns.switching`. |
| `core_presets` | A profile based on a preset. |
| `core_plugins` | Another addon's module through `Lib/Plugins.lua`. |
| `core_pluginkit` | What a plugin shares with our modules: renamed settings, unit events, tooltip lines, the shared options, a map layer's filter entry, marks on items, and a frame in Edit Mode, against stand-ins for the libraries behind them. |

```lua
local T = ...
local eq = T.eq
local c = T.Core()
local core = c.ns
local m = c.Modules()   -- the usual test modules, or make your own with core.NewModule
c.Login()               -- or c.Login(savedDB)

core.SetOption("Plain", "loud", true)
eq(c.registered("PLAYER_MONEY"), true, "lifecycle: checkbox on: listened")
```

What `c` holds:

- `c.ns`: the loaded `ns`. Nothing has logged in until `c.Login(db)`, which sets `ForeverPlusPlusDB` to `db` (nothing by default) and calls `ns.Start()`. Make modules before it.
- `c.fire(event, ...)` fires an event on the stub frames, and `c.registered(event)` says whether any frame listens for it.
- `c.wait(seconds)` moves the clock on and runs the timers that came due.
- `c.inCombat`: set it to change what `InCombatLockdown` answers, then `c.fire("PLAYER_REGEN_ENABLED")` to end combat.
- `c.cvars` and `c.refuse`: the client's CVars by name, and the ones it won't set.
- `c.refreshed`: the module names Settings was asked to redraw. Set a new table to start over.
- `c.count(key)` gives a handler that counts its calls in `c.heard[key]`.
- `c.Modules()` makes the modules most Core specs act on and returns them by name: `plain` (a checkbox `loud` and a dropdown `mode`, each with `OnWhile` events), `host` with its parts `check`, `drop`, and `side`, `coords` (a `cvar` checkbox), `locked`, and `tool` (always on), with their timers and what their callbacks recorded. `lib/core.lua` says what each is for.

A Core spec starts from a fresh login and builds the state its checks need, so one that fails doesn't take the others with it.

## wowlua-ls

CI also runs [wowlua-ls](https://github.com/TradeSkillMaster/wowlua-ls) (the version is pinned in `.github/workflows/check.yml`; the repo root's `.wowluarc.json` sets the Forever flavor) and hands its output to `wowlua.lua`, which fails on any finding `wowlua-baseline.txt` doesn't list, and on one the baseline lists but that's gone. A finding there is its file, code, and message, with how many times it's there, without lines, so moving code doesn't count as new. The baseline's findings sit in groups under a comment saying why they stay; `--update` keeps the comments, drops a group with nothing left in it, and puts a new finding in a "Not sorted yet" group at the end, to move under the comment that fits. Locally, with a release binary:

```sh
wowlua_ls check . > out.txt 2>&1
lua5.1 tests/wowlua.lua out.txt            # compare
lua5.1 tests/wowlua.lua out.txt --update   # rewrite the baseline after a fix, or for the checker's own mistake
```

## What to test

Test pure logic: anything in `Lib/` with no frames, and Core's module lifecycle on the stub frames of the `core_*` specs. Add a check when you change or add that logic, and a spec when you add a Lib file. Don't test frame or UI code; it needs the client.

These specs check the whole addon:

- `docs`: every Lib file has a row in AGENTS.md's Lib tables and a place in `docs/architecture.md`, and every click hint in the enUS strings is written as Blizzard's are.
- `globals`: no file in the TOC writes a global AGENTS.md doesn't allow (a missing `local` leaks one), plainly or through `_G.Name =` and `_G[...] =` (a name worked out at run time is listed in `DYNAMIC`), and every global a file reads is Lua 5.1's own (as the game has it: no `io`, `os`, or `require`) or listed in `.luarc.json`, so a typo like `fromat` fails here. When it flags a real client global, add that to `.luarc.json`; when a new allowed global appears in AGENTS.md, add it to `WRITES` in `spec/globals.lua`.
- `locales`: every `L.KEY` the code uses is defined, and none twice; another language sets only keys enUS has, with the same placeholders.
- `modules`: every file in the TOC loads offline, against a stand-in for any WoW global it reads, and makes no frame, hook, timer, or event listener as it loads (but for the few in its `ALLOWED`). No migration step is for a version past `Store.VERSION`. Every module's settings are well formed: a title, a category, and options with a name, a description, and a default that fits them. A dropdown's default must be one of its choices, and a slider's must be in its range. Every `requires`, `slider`, and `conflicts` must name an option the module has, and `module.presets` only presets `Lib/Presets.lua` registers, with `enabled` a boolean and option values that fit their options. When a file fails to load here, it's usually a new global the stand-in can't fake (a color, a string, a function whose answer the file uses at load). Stub that one in `spec/modules.lua`.
- `release`: the TOC's version and both changelogs agree, every file the TOC loads is there (`Init.lua` last), and every `.lua` file in the addon folder is in the TOC.
- `rules`: the AGENTS.md rules a machine can check exactly. Every file starts with its addon's `ns` line (after comments); none calls a Classic global the client doesn't have (docs/forever-api.md's list, kept out of `.luarc.json` too; `C_Item.GetItemInfo` is fine); none uses `COMBAT_LOG_EVENT_UNFILTERED`; only the files in `ONLY` read `WOW_PROJECT_ID`, `print`, or `IsInInstance`; and no line is indented with tabs or ends in spaces. A real exception goes in the spec's list, with why.
