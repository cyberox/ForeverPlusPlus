# Forever Agent

The program on your PC that Forever++'s **Agent Chat** talks to. The plan is chatting with your T3 Code threads (Claude, Codex, and the rest) from inside WoW: Forever, the same threads you use outside the game. For now it only does the link test.

## How the link works

An addon can't write files or open sockets, so the link uses files the game already reads and writes. Nothing reads the screen, takes screenshots, sends keys to the game, or reads its memory.

- **Game to PC:** 256 helper addons (`FPPAgentBit000`-`255`), each one bit. Agent Chat turns them on and off for your character and calls `C_AddOns.SaveAddOns()`, which writes `WTF\Account\...\<character>\AddOns.txt` at once. This program watches that file. A frame is 32 bytes: a sequence number, flags and length, 28 bytes of message, and a checksum. `ForeverPlusPlus/Lib/AgentLink.lua` writes them; `internal/link` reads them.
- **PC to game:** load-on-demand helper addons (`FPPAgentSlot000`...). The program writes a reply into a slot's `Data.lua`, then makes a signal: a tiny silent sound in `FPPAgentSignals` (`0000.wav`...). Agent Chat checks for it with `PlaySoundFile`, which works with game sound off, and loads the slot with `C_AddOns.LoadAddOn` as soon as it's there. Each slot loads once per UI session, so `/reload` makes them all usable again.
- **Signals:** the game only knows files that existed when it started, and once it has found one it remembers it until it restarts. So the program makes every signal while the game is closed, deletes them at each UI session's start, and makes one per reply. Each works once per game launch (2000 by default). Without a free one, a slot loads after a second anyway.

The helper addons live in `%LOCALAPPDATA%\ForeverPlusPlus\Agent\addons`. The game's `Interface\AddOns` only gets a junction to each, so nothing is written inside the game's folder while it runs. They're grouped under Forever++ in the game's AddOns list.

## Try the link

```sh
cd agent
go build -o forever-agent.exe ./cmd/forever-agent
forever-agent install    # once, then restart the game fully (not /reload)
forever-agent run        # leave it running
```

In game: `/fpp agent ping hello`. Chat shows the reply and how long each step took, and whether the game noticed each ready file change.

`--game` (or `WOW_DIR`) points at another client folder; the default is `D:\BattleNet\World of Warcraft\_forever_`. `--slots` sets the number of reply slots (100). `forever-agent uninstall` removes the junctions and the helpers.

## T3 Code

The program talks to T3 Code through its MCP endpoint, the way T3 supports outside programs. Sign in once:

```sh
forever-agent login        # approve "Forever Agent (WoW: Forever)" in the browser
forever-agent t3 tools     # what T3 offers
forever-agent t3 call t3_thread_list '{"allProjects":true,"limit":5}'
```

The sign-in uses T3's standard MCP OAuth (registration, PKCE, scopes `orchestration:read` and `orchestration:operate`) and is saved in `%LOCALAPPDATA%\ForeverPlusPlus\Agent\t3.json`. T3 gives no refresh token, so sign in again when it runs out. `--t3` picks another T3 server; the default is the one in `~/.t3/userdata/server-runtime.json`.

## Tests

`go test ./...` from this folder: the frame format (with the same vectors as `tests/spec/agentlink.lua`), installing into a fake game folder, and reading frames as the game writes them.
