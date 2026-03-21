# Turbo Random Deathmatch - Dota 2 Custom Game

## What This Is

A Dota 2 custom game mode combining **Random Deathmatch** (new random hero on each death) with **Turbo** rules (2x gold/XP, free TP, weaker buildings). On death, the player is shown 3 random heroes to choose from. Items, gold, and level are preserved across hero swaps.

## Project Structure

```
content/dota_addons/randomdeathmatchturbo/   <-- SOURCE (you edit here)
  scripts/
    vscripts/
      addon_game_mode.lua     # Engine entry point (Precache + Activate)
      turbo_rdm.lua           # Core game mode logic (all mechanics)
      timers.lua              # Timer utility library
    custom_game_mode.kv       # Game mode KV config (not auto-loaded by engine)
    npc/
      herolist.txt            # Legacy hardcoded hero list (UNUSED - uses npc_heroes.txt now)
  panorama/
    layout/custom_game/
      custom_ui_manifest.xml  # Registers custom HUD with the engine
      turbo_rdm_hud.xml       # HUD layout (selection overlay only)
    scripts/custom_game/
      turbo_rdm_hud.js        # HUD logic (hero selection UI, swap notifications)
    styles/custom_game/
      turbo_rdm_hud.css       # HUD styling
  addoninfo.txt               # Addon metadata

game/dota_addons/randomdeathmatchturbo/      <-- RUNTIME (engine reads here)
  (mirror of the above - must be manually synced)
```

## Critical: Dual Directory System

Dota 2 addons have TWO directories:
- **`content/`** - Source/authoring directory. This is our working directory.
- **`game/`** - Runtime directory. The engine ONLY loads from here.

**You MUST copy files from `content/` to `game/` after every edit.** Use:
```bash
GAME_DIR="/c/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota_addons/randomdeathmatchturbo"
CONTENT_DIR="/c/Program Files (x86)/Steam/steamapps/common/dota 2 beta/content/dota_addons/randomdeathmatchturbo"
cp "$CONTENT_DIR/scripts/vscripts/addon_game_mode.lua" "$GAME_DIR/scripts/vscripts/addon_game_mode.lua"
cp "$CONTENT_DIR/scripts/vscripts/turbo_rdm.lua" "$GAME_DIR/scripts/vscripts/turbo_rdm.lua"
cp "$CONTENT_DIR/scripts/vscripts/timers.lua" "$GAME_DIR/scripts/vscripts/timers.lua"
cp "$CONTENT_DIR/panorama/layout/custom_game/custom_ui_manifest.xml" "$GAME_DIR/panorama/layout/custom_game/custom_ui_manifest.xml"
cp "$CONTENT_DIR/panorama/layout/custom_game/turbo_rdm_hud.xml" "$GAME_DIR/panorama/layout/custom_game/turbo_rdm_hud.xml"
cp "$CONTENT_DIR/panorama/scripts/custom_game/turbo_rdm_hud.js" "$GAME_DIR/panorama/scripts/custom_game/turbo_rdm_hud.js"
cp "$CONTENT_DIR/panorama/styles/custom_game/turbo_rdm_hud.css" "$GAME_DIR/panorama/styles/custom_game/turbo_rdm_hud.css"
```

## Dota 2 VScript API Pitfalls

These are hard-won lessons. Violating any of these will silently break the addon:

### addon_game_mode.lua Rules
- `Precache(context)` and `Activate()` **MUST be defined directly in addon_game_mode.lua**, not in a `require()`'d module. The engine only looks in this file for these entry points.
- `Activate()` must create a class instance and store it on GameRules:
  ```lua
  function Activate()
      GameRules.TurboRDM = TurboRDM()
      GameRules.TurboRDM:InitGameMode()
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
2. **PRE_GAME**: 30 seconds, hero spawns at fountain
3. **GAME_IN_PROGRESS**: Buildings get HP reduction (turbo modifier)
4. **On Death**: `OnEntityKilled` fires:
   - Saves inventory/gold
   - Disables auto-respawn (`SetRespawnsDisabled(true)`)
   - Picks 3 random heroes, sends to client Panorama UI
   - Starts respawn timer (halved Turbo formula: `max(floor((level*2+4) * 0.5), 3)`)
5. **Hero Selection**: Player picks from 3 heroes during respawn wait. Choice is stored but swap waits for timer.
6. **Timer Expires**: `ExecuteHeroSwap` precaches the chosen hero, creates it via `CreateHeroForPlayer`, assigns to player, restores level/items/gold, and respawns.

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

## Notes

- The hero pool reads from Valve's built-in `scripts/npc/npc_heroes.txt` at runtime so new heroes are automatically included.
- Each hero can only be played once per match (pool tracks used heroes, resets if exhausted).
- `custom_game_mode.kv` exists but is NOT automatically loaded by the engine — all game settings are applied via Lua in `InitGameMode()`.
