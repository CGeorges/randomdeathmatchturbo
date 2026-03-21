--------------------------------------------------------------------------------
-- addon_game_mode.lua
-- Entry point loaded by the Dota 2 engine for custom games
-- Precache and Activate MUST be defined here (engine looks in this file)
--------------------------------------------------------------------------------

print("[TurboRDM] addon_game_mode.lua is loading...")

-- Load utilities
require("timers")

-- Load main game mode module (compiled from TypeScript via tstl)
local TurboRDM = require("turbo_rdm")

print("[TurboRDM] All modules loaded successfully.")

--------------------------------------------------------------------------------
-- Precache (called by the engine before hero models load)
--------------------------------------------------------------------------------
function Precache(context)
    print("[TurboRDM] Precache() called!")
    -- Hero models are precached on-demand via PrecacheUnitByNameAsync.
    -- Precaching all 130+ heroes exceeds the engine's resource limit.
end

--------------------------------------------------------------------------------
-- Activate (called by the engine to start the game mode)
--------------------------------------------------------------------------------
function Activate()
    print("[TurboRDM] Activate() called!")
    TurboRDM.InitGameMode()
end
