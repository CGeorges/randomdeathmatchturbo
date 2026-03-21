/**
 * Shared types between VScripts (Lua) and Panorama (JS).
 * Add custom event payloads, constants, etc. here.
 */

/** Custom game event payloads (server → client) */
interface TurboRDMHeroChoices {
    hero1: string;
    hero2: string;
    hero3: string;
    respawn_time: number;
}

interface TurboRDMHeroSwap {
    player_id: PlayerID;
    hero_name: string;
    player_name: string;
}

interface TurboRDMHeroHistory {
    heroes_json: string;
}

/** Custom game event payloads (client → server) */
interface TurboRDMHeroPick {
    hero_name: string;
}
