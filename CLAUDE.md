# Turbo Random Deathmatch - Dota 2 Custom Game

## What This Is

A Dota 2 custom game mode combining **Random Deathmatch** (new random hero on each death) with **Turbo** rules (2x gold/XP, free TP, weaker buildings). On death, the player is shown 3 random heroes to choose from. Items, gold, and level are preserved across hero swaps.

## Project Structure

```
content/dota_addons/randomdeathmatchturbo/   <-- SOURCE (you edit here)
  src/                          # TypeScript source (source of truth)
    vscripts/turbo_rdm.ts      # Server game logic (TS → Lua via tstl)
    panorama/turbo_rdm_hud.ts  # Client HUD logic (TS → JS via tsc)
    common/types.d.ts           # Shared type declarations
  scripts/
    vscripts/
      addon_game_mode.lua     # Engine entry point (must stay Lua)
      turbo_rdm.lua           # COMPILED from src/vscripts/ — do not edit
      lualib_bundle.lua       # tstl runtime library — do not edit
      timers.lua              # Timer utility library
    sync.js                     # File sync script (content → game)
    watch-sync.js               # File watcher for dev mode
  panorama/
    layout/custom_game/
      custom_ui_manifest.xml  # Registers custom HUD with the engine
      turbo_rdm_hud.xml       # HUD layout (selection overlay only)
    scripts/custom_game/
      turbo_rdm_hud.js        # COMPILED from src/panorama/ — do not edit
    styles/custom_game/
      turbo_rdm_hud.css       # HUD styling
  package.json                  # npm deps + build scripts
  addoninfo.txt                 # Addon metadata

game/dota_addons/randomdeathmatchturbo/      <-- RUNTIME (engine reads here)
  (auto-synced from content/ via npm run build/dev)
```

## TypeScript Development (Recommended for New Code)

The project supports writing game logic in TypeScript with **full autocomplete** for the entire Dota 2 API. TypeScript compiles to Lua (vscripts) or JS (panorama) automatically.

### Setup
```bash
cd "<project_root>"
npm install                    # Install dependencies (first time only)
```

### Development Workflow
```bash
npm run dev                    # Watch mode: recompile + auto-sync to game/ on save
npm run build                  # One-shot build + sync to game/
npm run sync                   # Manually sync content/ → game/ (no build)
```

### How It Works
- **VScripts**: `src/vscripts/*.ts` → compiled by `tstl` (TypeScript-to-Lua) → `scripts/vscripts/*.lua`
- **Panorama**: `src/panorama/*.ts` → compiled by `tsc` → `panorama/scripts/custom_game/*.js`
- **Auto-sync**: `scripts/watch-sync.js` watches compiled output and copies to `game/` automatically
- **Shared types**: `src/common/*.d.ts` — event payloads, constants shared between server and client
- **API types**: `@moddota/dota-lua-types` (server) and `@moddota/panorama-types` (client) provide full IntelliSense

### Key Benefits
- **Autocomplete**: Type `GameRules.` or `mode.` and see every available method with parameter types
- **Compile-time errors**: Catch typos, wrong argument types, and missing methods before launching the game
- **Auto-sync**: No manual file copying — `npm run dev` and `npm run build` handle everything

### Important Notes
- **Edit TypeScript files in `src/`**, not the compiled `.lua`/`.js` files — those are overwritten on build.
- `addon_game_mode.lua` **must stay as Lua** — the engine requires this specific file at this path.
- The tstl-generated Lua depends on `lualib_bundle.lua` — this is auto-generated and must be synced too.
- Reference: [ModDota TypeScript guide](https://moddota.com/scripting/Typescript/typescript-introduction/), [API docs](https://docs.moddota.com/lua_server/)

## Critical: Dual Directory System

Dota 2 addons have TWO directories:
- **`content/`** - Source/authoring directory. This is our working directory.
- **`game/`** - Runtime directory. The engine ONLY loads from here.

**Syncing is automated.** `npm run build` and `npm run dev` copy files to `game/` automatically via `scripts/sync.js`. You can also run `npm run sync` manually. If you edit static files (XML, CSS, `addon_game_mode.lua`), run `npm run sync` to copy them.

## Dota 2 VScript API Pitfalls

These are hard-won lessons. Violating any of these will silently break the addon:

### addon_game_mode.lua Rules
- `Precache(context)` and `Activate()` **MUST be defined directly in addon_game_mode.lua**, not in a `require()`'d module. The engine only looks in this file for these entry points.
- `Activate()` must import and call the game mode's init function:
  ```lua
  local TurboRDM = require("turbo_rdm")
  function Activate()
      TurboRDM.InitGameMode()
  end
  ```

### Hero Selection API
- `PlayerResource:SetSelectedHero()` does NOT exist. Use `player:SetSelectedHero(heroName)` on the CDOTAPlayer entity obtained via `PlayerResource:GetPlayer(playerID)`.

### Hero Swapping (CreateHeroForPlayer)
- `ReplaceHeroWith` has a **facet bug** — it fails when the current hero's facet index doesn't exist on the new hero (`ReplaceHeroWith failed as facet=N is invalid`). Sometimes non-fatal, sometimes returns nil. **Unreliable — do not use.**
- Instead, use `CreateHeroForPlayer(heroName, player)` with this sequence:
  1. `UTIL_Remove(oldHero)` — remove old hero first
  2. `PrecacheUnitByNameAsync(heroName, callback, playerID)` — precache model
  3. Inside the callback: `CreateHeroForPlayer(heroName, player)` — create new hero
  4. `player:SetAssignedHeroEntity(newHero)` — bind player controller to new hero
  5. `newHero:SetControllableByPlayer(playerID, true)` — ensure controllability
- The precache callback is **critical** — creating a hero before its model loads causes ERROR models and potential crashes.

### Precaching
- Do NOT `PrecacheUnitByNameSync` all 130+ heroes in `Precache()`. This exceeds the engine's 32767 resource limit and causes a fatal crash.
- Instead, precache individual heroes on-demand using `PrecacheUnitByNameAsync` right before creating them.

### Event Listeners
- Built-in game events use `ListenToGameEvent("event_name", Dynamic_Wrap(ClassName, "MethodName"), self)`
- Custom client-server events use `CustomGameEventManager:RegisterListener("event_name", callback)`
- Do NOT use `Dynamic_Wrap` for methods that don't exist on the class — it will error at wrap time or call time.

### Panorama (Custom UI)
- A `custom_ui_manifest.xml` file is required to register custom HUD panels. Without it, your XML/JS/CSS files exist but never load.
- The HUD XML **must include** `<styles>` and `<scripts>` blocks with `<include>` tags pointing to the CSS/JS files. Without these, the layout loads but has no styling or logic.
- The root `<Panel>` element in HUD XML files **cannot have an `id` attribute**. The Panorama compiler will reject it.
- Use `hittest="false"` on the root panel to prevent blocking game input (minimap clicks, etc.). Only set `hittest="true"` on interactive elements like selection cards.
- Panorama CSS does NOT support `transform: scale()`. Use `pre-transform-scale2d: 1.05` instead.
- Client-to-server events: `GameEvents.SendCustomGameEventToServer("event_name", data)`
- Server-to-client events: `GameEvents.Subscribe("event_name", callback)`

## Game Flow

1. **HERO_SELECTION**: `OnGameStateChange` assigns each player a random hero via `player:SetSelectedHero()`
2. **PRE_GAME**: 45 seconds, hero spawns at fountain
3. **GAME_IN_PROGRESS**: Buildings get HP reduction (turbo modifier)
4. **On Death**: `OnEntityKilled` fires:
   - Saves inventory, gold, consumed items (Shard/Scepter/Moon Shard), and death timestamp
   - Picks 3 random heroes, sends to client Panorama UI
   - Engine handles respawn timing natively (no custom timer)
5. **Hero Selection**: Player picks from 3 heroes. Selection UI hides immediately after pick.
6. **Engine Respawn / Buyback**: When the engine respawns the old hero (normal timer or buyback), `OnNPCSpawned` detects the pending choice and calls `ExecuteHeroSwap` — precaches the chosen hero, creates it via `CreateHeroForPlayer`, restores level/items/gold (with cooldowns reduced by dead time), and respawns.

## Testing

Launch from VConsole: `dota_launch_custom_game randomdeathmatchturbo dota`
Kill your hero quickly: `dota_kill 0`

## Resolved Issues

- **Facet bug**: `ReplaceHeroWith` fails with invalid facet on many heroes. Solved by using `CreateHeroForPlayer` + `SetAssignedHeroEntity` instead.
- **ERROR models**: Caused by creating heroes before their models are loaded. Solved by using `PrecacheUnitByNameAsync` with callback.
- **Hero not assigned to player**: `CreateHeroForPlayer` alone doesn't bind the player controller. Solved by calling `player:SetAssignedHeroEntity(newHero)`.
- **Minimap blocked**: HUD panel covered entire screen. Solved by using `hittest="false"` on root panel.
- **Selection UI not loading**: XML file had no `<scripts>`/`<styles>` includes. Added them.
- **Instant respawn**: Player pick triggered immediate swap. Solved by separating pick from respawn timer — pick stores choice, swap happens when timer expires.
- **Buyback not working**: `SetRespawnsDisabled(true)` blocked buyback respawn. Solved by letting the engine handle respawns natively — `OnNPCSpawned` intercepts and does the hero swap.
- **Item cooldowns reset on swap**: Items got fresh cooldowns on new hero. Solved by saving `GameRules:GetGameTime()` at death and subtracting elapsed dead time from saved cooldowns.
- **Ghost 0-charge items**: Wards/consumables with 0 charges persisted after restore. Solved by comparing saved charges against newly created item's default charges — skip if saved=0 but default>0.
- **Consumed items lost on death**: Aghanim's Shard, Scepter Blessing, Moon Shard are hero modifiers, not inventory items. Solved by saving modifier state in `playerConsumed` and re-applying on new hero.

## Notes

- The hero pool reads from Valve's built-in `scripts/npc/npc_heroes.txt` at runtime so new heroes are automatically included.
- Each hero can only be played once per match (pool tracks used heroes, resets if exhausted).
- All game settings are applied in `InitGameMode()` via the Dota 2 API — no KV config files needed.
- Rune spawning in custom games does not behave like normal Dota — custom game rune management may be needed.
