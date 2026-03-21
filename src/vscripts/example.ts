/**
 * Example VScript file in TypeScript.
 *
 * This compiles to Lua via tstl (TypeScript-to-Lua).
 * You get full autocomplete for the entire Dota 2 API.
 *
 * Try it: type "GameRules:" or "GameRules.GetGameModeEntity():" and
 * see every method with parameter types and descriptions.
 *
 * To compile:  npm run build:vscripts
 * To watch:    npm run dev:vscripts
 * Output goes to: scripts/vscripts/example.lua
 */

// Example: full autocomplete on GameRules, PlayerResource, etc.
function ExampleInit(): void {
    const mode = GameRules.GetGameModeEntity();

    // Every method is typed — hover for signatures
    mode.SetFreeCourierModeEnabled(true);
    mode.SetGiveFreeTPOnDeath(true);
    mode.SetCustomBackpackSwapCooldown(3.0);
    mode.SetBountyRuneSpawnInterval(180);

    GameRules.SetGoldPerTick(2);
    GameRules.SetStartingGold(750);

    // Typed event listeners
    ListenToGameEvent("entity_killed", (event) => {
        // event.entindex_killed is typed as EntityIndex
        const unit = EntIndexToHScript(event.entindex_killed) as CDOTA_BaseNPC_Hero;
        if (unit && unit.IsRealHero()) {
            print(`Hero killed: ${unit.GetUnitName()}`);
        }
    }, undefined);
}
