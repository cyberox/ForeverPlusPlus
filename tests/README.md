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
| `lib/env.lua` | A fresh copy of the addon for each spec: stubbed WoW globals, an `ns`, the enUS Core and Map strings, and the pure-logic `Lib/` files. |
| `lib/harness.lua` | The checks: `eq`, `same`, `near`, `ok`, `raises`. |
| `lib/bytecode.lua` | The globals a file reads and writes, with their lines, and the strings in its code, from its Lua 5.1 bytecode (what `luac -l` lists as GETGLOBAL and SETGLOBAL), for the `globals` and `rules` specs. |
| `spec/*.lua` | One spec per area: a Lib file (`text`, `store`, `prices`, `cvars`, `units`, ...), Core's module lifecycle (`core`), the public API (`api`), and checks across the addon (`globals`, `locales`, `modules`, `release`, `rules`). |

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
- `T.Toc()`, `T.Read(path)`: the TOC's fields and file list, and a file's text.
- Checks. Each takes a short name, prefixed with the area (`"taxi: no nodes"`). A failure prints the spec's file and line, the name, and what it got.
  - `eq(got, want, what)`: equal with `==`.
  - `same(got, want, what)`: equal looking inside tables, and says where they differ.
  - `near(got, want, what, within)`: a number within `within` (default `1e-9`).
  - `ok(value, what)`: anything but `nil` or `false`.
  - `raises(fn, pattern, what)`: `fn` errors, with `pattern` in the message.

## wowlua-ls

CI also runs [wowlua-ls](https://github.com/TradeSkillMaster/wowlua-ls) (the version is pinned in `.github/workflows/check.yml`; the repo root's `.wowluarc.json` sets the Forever flavor) and hands its output to `wowlua.lua`, which fails on any finding `wowlua-baseline.txt` doesn't list, and on one the baseline lists but that's gone. A finding there is its file, code, and message, with how many times it's there, without lines, so moving code doesn't count as new. Locally, with a release binary:

```sh
wowlua_ls check . > out.txt 2>&1
lua5.1 tests/wowlua.lua out.txt            # compare
lua5.1 tests/wowlua.lua out.txt --update   # rewrite the baseline after a fix, or for the checker's own mistake
```

## What to test

Test pure logic: anything in `Lib/` with no frames, and Core's module lifecycle on the stub frames in `spec/core.lua`. Add a check when you change or add that logic, and a spec when you add a Lib file. Don't test frame or UI code; it needs the client.

These specs check the whole addon:

- `globals`: no file in either addon's TOC writes a global AGENTS.md doesn't allow (a missing `local` leaks one), plainly or through `_G.Name =` and `_G[...] =` (a name worked out at run time is listed in `DYNAMIC`), and every global a file reads is Lua 5.1's own (as the game has it: no `io`, `os`, or `require`) or listed in `.luarc.json`, so a typo like `fromat` fails here. When it flags a real client global, add that to `.luarc.json`; when a new allowed global appears in AGENTS.md, add it to `WRITES` in `spec/globals.lua`.
- `locales`: every `L.KEY` the code uses is defined, and none twice.
- `modules`: every file in the TOC loads offline, against a stand-in for any WoW global it reads. Every module's settings are well formed: a title, a category, and options with a name, a description, and a default that fits them. A dropdown's default must be one of its choices, and a slider's must be in its range. Every `requires`, `slider`, and `conflicts` must name an option the module has. When a file fails to load here, it's usually a new global the stand-in can't fake (a color, a string, a function whose answer the file uses at load). Stub that one in `spec/modules.lua`.
- `release`: the TOC's version and both changelogs agree, and every file the TOC loads is there.
- `rules`: the AGENTS.md rules a machine can check exactly. Every file starts with its addon's `ns` line (after comments); none calls a Classic global the client doesn't have (docs/forever-api.md's list, kept out of `.luarc.json` too; `C_Item.GetItemInfo` is fine); none uses `COMBAT_LOG_EVENT_UNFILTERED`; only the files in `ONLY` read `WOW_PROJECT_ID` or `print`; and no line is indented with tabs or ends in spaces. A real exception goes in the spec's list, with why.
