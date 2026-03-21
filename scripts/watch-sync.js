/**
 * Watches compiled output files and syncs to game/ on change.
 * Run alongside tstl --watch and tsc --watch via npm run dev.
 */
const fs = require("fs");
const path = require("path");

const CONTENT = path.resolve(__dirname, "..");
const GAME = CONTENT.replace(
    path.join("content", "dota_addons"),
    path.join("game", "dota_addons")
);

const FILES = [
    "scripts/vscripts/turbo_rdm.lua",
    "scripts/vscripts/lualib_bundle.lua",
    "panorama/scripts/custom_game/turbo_rdm_hud.js",
];

// Also sync static files once at startup
const STATIC = [
    "scripts/custom_game_mode.kv",
    "scripts/vscripts/addon_game_mode.lua",
    "scripts/vscripts/timers.lua",
    "panorama/layout/custom_game/custom_ui_manifest.xml",
    "panorama/layout/custom_game/turbo_rdm_hud.xml",
    "panorama/styles/custom_game/turbo_rdm_hud.css",
];

function syncFile(file) {
    const src = path.join(CONTENT, file);
    const dst = path.join(GAME, file);
    if (fs.existsSync(src)) {
        fs.mkdirSync(path.dirname(dst), { recursive: true });
        fs.copyFileSync(src, dst);
        return true;
    }
    return false;
}

// Sync static files once
for (const file of STATIC) {
    syncFile(file);
}
console.log(`[sync] Synced ${STATIC.length} static files`);

// Watch compiled files for changes
for (const file of FILES) {
    const src = path.join(CONTENT, file);
    const dir = path.dirname(src);

    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }

    fs.watchFile(src, { interval: 500 }, () => {
        if (syncFile(file)) {
            console.log(`[sync] ${file}`);
        }
    });
}

console.log(`[sync] Watching ${FILES.length} compiled files for changes...`);
