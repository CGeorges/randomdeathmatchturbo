# Turbo Random Deathmatch

A Dota 2 custom game mode that combines **Random Deathmatch** with **Turbo** rules. Every time you die, you respawn as a new random hero — but you keep all your items, gold, and level.

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3685829403)

## How It Works

- **Random Deathmatch**: On death, choose from 3 random heroes to respawn as
- **Turbo Rules**: 2x passive gold, 2x XP, free TP scrolls, free courier, weaker buildings
- **Item Persistence**: Your inventory, gold, and level carry over to your new hero
- **Consumed Items Persist**: Aghanim's Shard, Scepter Blessing, and Moon Shard survive death
- **Full Hero Pool**: All heroes available, automatically updated when Valve adds new ones
- **No Duplicates**: Each hero can only be played once per match (pool resets if exhausted)
- **Standard Win Condition**: Destroy the enemy Ancient

## Playing

1. Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3685829403)
2. Launch Dota 2 → Play → Custom Games → Turbo Random Deathmatch
3. Up to 5v5 players

## Development

The project uses TypeScript with full Dota 2 API autocomplete, compiled to Lua (server) and JS (client).

### Prerequisites

- [Node.js](https://nodejs.org/) (v18+)
- Dota 2 with Workshop Tools DLC

### Setup

```bash
cd "<dota 2>/content/dota_addons/randomdeathmatchturbo"
npm install
```

### Build & Run

```bash
npm run dev      # Watch mode — recompiles + syncs to game/ on save
npm run build    # One-shot build + sync
```

Then launch from the Dota 2 console:
```
dota_launch_custom_game randomdeathmatchturbo dota
```

### Project Structure

```
src/
  vscripts/turbo_rdm.ts       # Server game logic (TypeScript → Lua)
  panorama/turbo_rdm_hud.ts   # Client HUD logic (TypeScript → JS)
  common/types.d.ts            # Shared event type declarations

scripts/vscripts/
  addon_game_mode.lua          # Engine entry point (must be Lua)
  turbo_rdm.lua                # Compiled from TypeScript — do not edit
  timers.lua                   # Timer utility library

panorama/
  layout/custom_game/          # HUD XML layouts
  scripts/custom_game/         # Compiled JS — do not edit
  styles/custom_game/          # CSS styling
```

### Tech Stack

- **[TypeScript-to-Lua](https://typescripttolua.github.io/)** — server-side game logic
- **TypeScript** — client-side Panorama UI
- **[@moddota/dota-lua-types](https://github.com/ModDota/TypeScriptDeclarations)** — full Dota 2 API type definitions
- **[@moddota/panorama-types](https://github.com/ModDota/TypeScriptDeclarations)** — Panorama UI type definitions

## License

This project is open source. Feel free to use it as a reference for your own Dota 2 custom games.
