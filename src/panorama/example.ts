/**
 * Example Panorama file in TypeScript.
 *
 * This compiles to JS via standard tsc.
 * You get full autocomplete for the Panorama API ($, GameEvents, etc).
 *
 * To compile:  npm run build:panorama
 * To watch:    npm run dev:panorama
 * Output goes to: panorama/scripts/custom_game/example.js
 */

// Example: full autocomplete on Panorama API
function ExamplePanoramaInit(): void {
    // $ is typed — every panel method is available
    const panel = $("#HeroSelectionOverlay");
    if (panel) {
        panel.style.visibility = "visible";
    }

    // GameEvents is typed
    GameEvents.Subscribe("turbo_rdm_hero_swap", (event: object) => {
        const data = event as TurboRDMHeroSwap;
        $.Msg(`${data.player_name} swapped to ${data.hero_name}`);
    });
}
