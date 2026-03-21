/**
 * Copies all runtime files from content/ to game/ directory.
 * Called automatically after each build via npm scripts.
 */
const fs = require("fs");
const path = require("path");

const CONTENT = path.resolve(__dirname, "..");
const GAME = CONTENT.replace(
    path.join("content", "dota_addons"),
    path.join("game", "dota_addons")
);

const FILES = [
    "scripts/vscripts/addon_game_mode.lua",
    "scripts/vscripts/turbo_rdm.lua",
    "scripts/vscripts/lualib_bundle.lua",
    "scripts/vscripts/timers.lua",
    "panorama/layout/custom_game/custom_ui_manifest.xml",
    "panorama/layout/custom_game/turbo_rdm_hud.xml",
    "panorama/scripts/custom_game/turbo_rdm_hud.js",
    "panorama/styles/custom_game/turbo_rdm_hud.css",
];

let copied = 0;
for (const file of FILES) {
    const src = path.join(CONTENT, file);
    const dst = path.join(GAME, file);
    if (fs.existsSync(src)) {
        fs.mkdirSync(path.dirname(dst), { recursive: true });
        fs.copyFileSync(src, dst);
        copied++;
    }
}
console.log(`[sync] Copied ${copied} files to game directory`);
