--------------------------------------------------------------------------------
-- Turbo Random Deathmatch
-- Core game-mode logic
--
-- Mechanics:
--   * Each player starts with a random hero (All Random)
--   * On death the player chooses from 3 random heroes to respawn as
--   * All items are kept across hero swaps (stash + inventory)
--   * Turbo rules: 2x passive gold, 2x XP, free TP scrolls,
--     halved respawn timers, weaker buildings
--   * Win condition: destroy the enemy Ancient (same as vanilla)
--------------------------------------------------------------------------------

if TurboRDM == nil then
    TurboRDM = class({})
end

-- Hero pool tracking (avoid duplicates in the same game)
TurboRDM.usedHeroes        = {}   -- [heroName] = playerID or nil
TurboRDM.playerHeroHistory = {}   -- [playerID] = { hero1, hero2, ... }
TurboRDM.playerItems       = {}   -- [playerID] = saved item table
TurboRDM.playerGold        = {}   -- [playerID] = saved gold
TurboRDM.pendingChoices    = {}   -- [playerID] = { heroes, level }
TurboRDM.playerConsumed    = {}   -- [playerID] = { shard, scepter, moonshard }
TurboRDM.playerDeathTime   = {}   -- [playerID] = GameTime at death (for cooldown calc)
TurboRDM.swappingPlayers   = {}   -- [playerID] = true while a swap is in progress

local HERO_CHOICES_COUNT = 3


--------------------------------------------------------------------------------
-- Init (called from Activate() in addon_game_mode.lua)
--------------------------------------------------------------------------------
function TurboRDM:InitGameMode()
    print("[TurboRDM] Initializing Turbo Random Deathmatch...")

    local mode = GameRules:GetGameModeEntity()

    ---------------------------------------------------------------------------
    -- Turbo-style game rules
    ---------------------------------------------------------------------------
    GameRules:SetUseUniversalShopMode(true)           -- Buy anywhere
    GameRules:SetHeroSelectionTime(0)                  -- Skip pick screen
    GameRules:SetStrategyTime(0)                       -- Skip strategy phase
    GameRules:SetShowcaseTime(0)                       -- Skip showcase phase
    GameRules:SetPreGameTime(45)                       -- Short pre-game
    GameRules:SetPostGameTime(45)
    GameRules:EnableCustomGameSetupAutoLaunch(true)
    GameRules:SetCustomGameSetupAutoLaunchDelay(0)
    GameRules:SetGoldPerTick(2)                        -- 2x passive gold
    GameRules:SetGoldTickTime(0.6)
    GameRules:SetStartingGold(750)
    GameRules:SetCustomGameAllowHeroPickMusic(false)
    GameRules:SetCustomGameAllowMusicAtGameStart(true)
    GameRules:SetTreeRegrowTime(30)                    -- Faster tree regrow
    GameRules:SetSameHeroSelectionEnabled(false)       -- No duplicate heroes

    -- Free courier from the start (Turbo)
    mode:SetFreeCourierModeEnabled(true)

    -- XP multiplier
    mode:SetCustomXPRequiredToReachNextLevel({
        0,      -- Level 1
        120,    -- Level 2   (vanilla 230, halved ~)
        160,    -- Level 3
        210,    -- Level 4
        260,    -- Level 5
        320,    -- Level 6
        380,    -- Level 7
        450,    -- Level 8
        520,    -- Level 9
        600,    -- Level 10
        690,    -- Level 11
        780,    -- Level 12
        880,    -- Level 13
        990,    -- Level 14
        1100,   -- Level 15
        1220,   -- Level 16
        1350,   -- Level 17
        1500,   -- Level 18
        1660,   -- Level 19
        1830,   -- Level 20
        2010,   -- Level 21
        2200,   -- Level 22
        2400,   -- Level 23
        2610,   -- Level 24
        2830,   -- Level 25
        3200,   -- Level 26
        3600,   -- Level 27
        4000,   -- Level 28
        4400,   -- Level 29
        4800,   -- Level 30
    })

    mode:SetCustomGameForceHero("")  -- No forced hero

    -- Free TP on death (built-in Turbo mechanic — replaces manual GrantFreeTP)
    mode:SetGiveFreeTPOnDeath(true)

    -- Shorter backpack swap cooldown (Turbo: 3s vs normal 6s)
    mode:SetCustomBackpackSwapCooldown(3.0)

    ---------------------------------------------------------------------------
    -- Event listeners
    ---------------------------------------------------------------------------
    ListenToGameEvent("npc_spawned",           Dynamic_Wrap(TurboRDM, "OnNPCSpawned"), self)
    ListenToGameEvent("entity_killed",         Dynamic_Wrap(TurboRDM, "OnEntityKilled"), self)
    ListenToGameEvent("game_rules_state_change", Dynamic_Wrap(TurboRDM, "OnGameStateChange"), self)

    -- Client-to-server event: player picked a hero from the selection UI
    CustomGameEventManager:RegisterListener("turbo_rdm_hero_pick", function(_, event)
        self:OnHeroPicked(event)
    end)

    -- Thinker for periodic tasks (free TP scroll grants, etc.)
    mode:SetThink("OnThink", self, "TurboRDMThink", 1.0)

    ---------------------------------------------------------------------------
    -- Rune system: tell the engine to use default Dota rune spawn logic
    -- with the standard intervals for each rune type.
    ---------------------------------------------------------------------------
    mode:SetUseDefaultDOTARuneSpawnLogic(true)
    GameRules:SetRuneSpawnTime(120)                -- base: every 2 min
    mode:SetBountyRuneSpawnInterval(180)           -- bounty: every 3 min

    print("[TurboRDM] Initialization complete.")
end

--------------------------------------------------------------------------------
-- Get all available hero names (full pool minus already in use)
-- Uses Valve's built-in npc_heroes.txt so new heroes are included automatically.
--------------------------------------------------------------------------------
function TurboRDM:GetAvailableHeroes(playerID)
    local heroData = LoadKeyValues("scripts/npc/npc_heroes.txt")
    local available = {}

    if heroData then
        for heroName, data in pairs(heroData) do
            -- Skip the "Version" key and base class entries
            -- Valid hero names start with "npc_dota_hero_"
            if type(heroName) == "string"
                and string.sub(heroName, 1, 14) == "npc_dota_hero_"
                and heroName ~= "npc_dota_hero_base"
                and heroName ~= "npc_dota_hero_target_dummy"
                and not self.usedHeroes[heroName]
            then
                table.insert(available, heroName)
            end
        end
    end

    -- If somehow all heroes are exhausted, reset the pool (unlikely in 5v5)
    if #available == 0 then
        print("[TurboRDM] Hero pool exhausted, resetting...")
        self.usedHeroes = {}
        return self:GetAvailableHeroes(playerID)
    end

    return available
end

--------------------------------------------------------------------------------
-- Pick a random hero for a player (used for initial hero assignment)
--------------------------------------------------------------------------------
function TurboRDM:AssignRandomHero(playerID)
    local available = self:GetAvailableHeroes(playerID)
    local pick = available[RandomInt(1, #available)]

    -- Track it
    self.usedHeroes[pick] = playerID
    if not self.playerHeroHistory[playerID] then
        self.playerHeroHistory[playerID] = {}
    end
    table.insert(self.playerHeroHistory[playerID], pick)

    print("[TurboRDM] Player " .. playerID .. " assigned hero: " .. pick)
    return pick
end

--------------------------------------------------------------------------------
-- Get N random hero choices for the selection UI (does NOT mark them as used)
--------------------------------------------------------------------------------
function TurboRDM:GetHeroChoices(playerID, count)
    local available = self:GetAvailableHeroes(playerID)
    local choices = {}

    -- Fisher-Yates shuffle on the first 'count' elements
    for i = 1, math.min(count, #available) do
        local j = RandomInt(i, #available)
        available[i], available[j] = available[j], available[i]
        table.insert(choices, available[i])
    end

    return choices
end

--------------------------------------------------------------------------------
-- Save a player's items + gold before hero swap
--------------------------------------------------------------------------------
function TurboRDM:SavePlayerInventory(hero, playerID)
    local items = {}

    -- Inventory (slots 0-5) + Backpack (6-8) + Stash (9-14) + TP/Neutral (15-16)
    for slot = 0, 16 do
        local item = hero:GetItemInSlot(slot)
        if item then
            table.insert(items, {
                name     = item:GetAbilityName(),
                charges  = item:GetCurrentCharges(),
                slot     = slot,
                cooldown = item:GetCooldownTimeRemaining(),
            })
        end
    end

    self.playerItems[playerID]    = items
    self.playerGold[playerID]     = PlayerResource:GetGold(playerID)
    self.playerDeathTime[playerID] = GameRules:GetGameTime()  -- for cooldown reduction

    -- Save consumed items (these are modifiers on the hero, not in item slots)
    self.playerConsumed[playerID] = {
        shard     = hero:HasModifier("modifier_item_aghanims_shard"),
        scepter   = hero:HasModifier("modifier_item_ultimate_scepter_consumed"),
        moonshard = hero:HasModifier("modifier_item_moon_shard_consumed"),
    }

    print("[TurboRDM] Saved " .. #items .. " items for player " .. playerID)
end

--------------------------------------------------------------------------------
-- Restore items + gold to a new hero
--------------------------------------------------------------------------------
function TurboRDM:RestorePlayerInventory(hero, playerID)
    local items = self.playerItems[playerID]
    local gold  = self.playerGold[playerID]

    -- Calculate how long the player was dead so cooldowns tick down properly
    local deadElapsed = 0
    if self.playerDeathTime[playerID] then
        deadElapsed = GameRules:GetGameTime() - self.playerDeathTime[playerID]
        self.playerDeathTime[playerID] = nil
    end

    if items then
        for _, entry in ipairs(items) do
            local newItem = CreateItem(entry.name, hero, hero)
            if newItem then
                -- Skip fully consumed charge-based items (e.g., wards at 0 charges).
                -- A freshly created charge-based item has default charges > 0;
                -- if the saved charges were 0, the item was used up and shouldn't
                -- be restored (otherwise it lingers as a 0-charge ghost item).
                local defaultCharges = newItem:GetCurrentCharges()
                if entry.charges == 0 and defaultCharges > 0 then
                    UTIL_Remove(newItem)
                else
                    newItem:SetCurrentCharges(entry.charges)
                    -- Try to place in original slot, fallback to any free slot
                    if not hero:AddItem(newItem) then
                        print("[TurboRDM] Warning: could not restore item " .. entry.name)
                        UTIL_Remove(newItem)
                    else
                        -- Restore cooldown minus time spent dead
                        local remaining = (entry.cooldown or 0) - deadElapsed
                        if remaining > 0 then
                            newItem:StartCooldown(remaining)
                        else
                            newItem:EndCooldown()
                        end
                    end
                end
            end
        end
        self.playerItems[playerID] = nil
    end

    if gold then
        PlayerResource:SetGold(playerID, gold, true)  -- reliable gold
        self.playerGold[playerID] = nil
    end

    -- Restore consumed items (Shard, Scepter Blessing, Moon Shard)
    local consumed = self.playerConsumed[playerID]
    if consumed then
        if consumed.shard then
            local shard = CreateItem("item_aghanims_shard", hero, hero)
            if shard then hero:AddItem(shard) end
        end
        if consumed.scepter then
            local blessing = CreateItem("item_ultimate_scepter_2", hero, hero)
            if blessing then hero:AddItem(blessing) end
        end
        if consumed.moonshard then
            -- Moon Shard consumed is a permanent modifier; re-apply directly
            hero:AddNewModifier(hero, nil, "modifier_item_moon_shard_consumed", {})
        end
        self.playerConsumed[playerID] = nil
    end
end

--------------------------------------------------------------------------------
-- Weaken buildings (Turbo-style: buildings take more damage / have less HP)
--------------------------------------------------------------------------------
function TurboRDM:ApplyTurboBuildingModifiers()
    local buildings = Entities:FindAllByClassname("npc_dota_tower")
    for _, tower in pairs(buildings) do
        if tower and IsValidEntity(tower) then
            local maxHP = tower:GetMaxHealth()
            tower:SetMaxHealth(math.floor(maxHP * 0.6))  -- 60% HP
            tower:SetHealth(math.floor(maxHP * 0.6))
        end
    end

    local barracks = Entities:FindAllByClassname("npc_dota_barracks")
    for _, rax in pairs(barracks) do
        if rax and IsValidEntity(rax) then
            local maxHP = rax:GetMaxHealth()
            rax:SetMaxHealth(math.floor(maxHP * 0.6))
            rax:SetHealth(math.floor(maxHP * 0.6))
        end
    end

    -- Ancients / Thrones
    local ancients = Entities:FindAllByClassname("npc_dota_fort")
    for _, fort in pairs(ancients) do
        if fort and IsValidEntity(fort) then
            local maxHP = fort:GetMaxHealth()
            fort:SetMaxHealth(math.floor(maxHP * 0.75))
            fort:SetHealth(math.floor(maxHP * 0.75))
        end
    end

    print("[TurboRDM] Applied Turbo building modifiers (reduced HP).")
end

--------------------------------------------------------------------------------
-- EVENT: Game state change
--------------------------------------------------------------------------------
function TurboRDM:OnGameStateChange(event)
    local state = GameRules:State_Get()

    if state == DOTA_GAMERULES_STATE_HERO_SELECTION then
        -- Force all-random for every player
        for playerID = 0, PlayerResource:GetPlayerCount() - 1 do
            if PlayerResource:IsValidPlayerID(playerID) then
                local heroName = self:AssignRandomHero(playerID)
                local player = PlayerResource:GetPlayer(playerID)
                if player then
                    player:SetSelectedHero(heroName)
                end
            end
        end
    end

    if state == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        -- Apply building nerfs once the game starts
        Timers:CreateTimer(1.0, function()
            self:ApplyTurboBuildingModifiers()
        end)
    end
end

--------------------------------------------------------------------------------
-- EVENT: NPC (hero) spawned
--------------------------------------------------------------------------------
function TurboRDM:OnNPCSpawned(event)
    local npc = EntIndexToHScript(event.entindex)
    if not npc then return end

    -- Turbo courier speed: boost couriers to ~1100 move speed
    if npc:IsCourier() then
        Timers:CreateTimer(0.1, function()
            if npc and IsValidEntity(npc) then
                npc:SetBaseMoveSpeed(1100)
            end
        end)
        return
    end

    if not npc:IsRealHero() then return end

    local playerID = npc:GetPlayerID()

    -- If this player has a pending hero swap (engine just respawned the old
    -- hero after death / buyback), execute the swap now.
    -- The swappingPlayers guard prevents re-entry when CreateHeroForPlayer
    -- fires another npc_spawned for the NEW hero.
    if self.pendingChoices[playerID] and not self.swappingPlayers[playerID] then
        local chosen = self.pendingChoices[playerID].chosenHero
            or self.pendingChoices[playerID].heroes[1]
        self:ExecuteHeroSwap(playerID, chosen)
    end
end

--------------------------------------------------------------------------------
-- EVENT: Entity killed (hero death triggers RDM hero selection)
--------------------------------------------------------------------------------
function TurboRDM:OnEntityKilled(event)
    local killedUnit = EntIndexToHScript(event.entindex_killed)
    if not killedUnit or not killedUnit:IsRealHero() then return end

    local playerID = killedUnit:GetPlayerID()

    ---------------------------------------------------------------------------
    -- 1. Save current items and gold
    ---------------------------------------------------------------------------
    self:SavePlayerInventory(killedUnit, playerID)

    ---------------------------------------------------------------------------
    -- 2. Get the engine's respawn time (for the UI countdown) BEFORE any
    --    modifications.  The engine handles the actual respawn — we just
    --    intercept it in OnNPCSpawned to swap the hero.
    ---------------------------------------------------------------------------
    local level = killedUnit:GetLevel()
    local respawnTime = killedUnit:GetRespawnTime()

    ---------------------------------------------------------------------------
    -- 3. Get 3 hero choices and send to the client for selection
    ---------------------------------------------------------------------------
    local choices = self:GetHeroChoices(playerID, HERO_CHOICES_COUNT)

    self.pendingChoices[playerID] = {
        heroes = choices,
        level  = level,
    }

    local player = PlayerResource:GetPlayer(playerID)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, "turbo_rdm_hero_choices", {
            hero1        = choices[1],
            hero2        = choices[2],
            hero3        = choices[3] or choices[1],  -- fallback if pool < 3
            respawn_time = respawnTime,
        })
    end

    -- No custom timer — the engine respawns the hero at the correct time,
    -- and OnNPCSpawned triggers ExecuteHeroSwap.
end

--------------------------------------------------------------------------------
-- EVENT: Player picked a hero from the selection UI (client → server)
-- Stores the choice but does NOT swap immediately — waits for respawn timer.
--------------------------------------------------------------------------------
function TurboRDM:OnHeroPicked(event)
    local playerID = event.PlayerID
    local heroName = event.hero_name

    local pending = self.pendingChoices[playerID]
    if not pending then return end

    -- Validate the pick is one of the offered choices
    local valid = false
    for _, h in ipairs(pending.heroes) do
        if h == heroName then
            valid = true
            break
        end
    end

    if not valid then
        print("[TurboRDM] Player " .. playerID .. " sent invalid pick: " .. tostring(heroName))
        return
    end

    -- Store choice — swap happens when respawn timer expires
    pending.chosenHero = heroName
    print("[TurboRDM] Player " .. playerID .. " chose: " .. heroName)

    -- Hide the selection UI
    local player = PlayerResource:GetPlayer(playerID)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, "turbo_rdm_hero_chosen", {})
    end
end

--------------------------------------------------------------------------------
-- Execute the actual hero swap (called from OnNPCSpawned when the engine
-- respawns the old hero — works for normal respawn, buyback, etc.)
--------------------------------------------------------------------------------
function TurboRDM:ExecuteHeroSwap(playerID, heroName)
    local pending = self.pendingChoices[playerID]
    if not pending then return end

    -- Guard: prevent re-entry when CreateHeroForPlayer fires npc_spawned
    self.swappingPlayers[playerID] = true

    -- If the hero was taken by another player in the meantime, fall back
    if self.usedHeroes[heroName] then
        for _, h in ipairs(pending.heroes) do
            if not self.usedHeroes[h] then
                heroName = h
                break
            end
        end
        -- If all choices are taken (extremely unlikely), grab any available
        if self.usedHeroes[heroName] then
            local available = self:GetAvailableHeroes(playerID)
            heroName = available[RandomInt(1, #available)]
        end
    end

    -- Mark hero as used
    self.usedHeroes[heroName] = playerID
    if not self.playerHeroHistory[playerID] then
        self.playerHeroHistory[playerID] = {}
    end
    table.insert(self.playerHeroHistory[playerID], heroName)

    local targetLevel = pending.level

    -- Clear pending state
    self.pendingChoices[playerID] = nil

    -- Replace the hero
    local player = PlayerResource:GetPlayer(playerID)
    if not player then return end

    local savedGold = PlayerResource:GetGold(playerID)
    local oldHero = PlayerResource:GetSelectedHeroEntity(playerID)

    -- Remove the old hero FIRST so the new one becomes the player's hero
    if oldHero and IsValidEntity(oldHero) then
        oldHero:SetRespawnsDisabled(true)
        UTIL_Remove(oldHero)
    end

    -- Precache hero model, then create hero in the callback (after model loads)
    PrecacheUnitByNameAsync(heroName, function()
        local newHero = CreateHeroForPlayer(heroName, player)

        if newHero then
            -- Bind the player controller to the new hero
            newHero:SetControllableByPlayer(playerID, true)
            newHero:SetOwner(player)
            player:SetAssignedHeroEntity(newHero)

            -- Match the old hero's level
            for i = 1, targetLevel - 1 do
                newHero:HeroLevelUp(false)
            end

            -- Remove any default items the new hero came with (e.g. TP scroll
            -- with purchase cooldown) so restored items can take their slots
            for slot = 0, 16 do
                local defaultItem = newHero:GetItemInSlot(slot)
                if defaultItem then
                    newHero:RemoveItem(defaultItem)
                end
            end

            -- Restore items and gold
            self:RestorePlayerInventory(newHero, playerID)
            PlayerResource:SetGold(playerID, savedGold, true)

            -- Respawn the new hero
            newHero:SetRespawnsDisabled(false)
            newHero:RespawnHero(false, false)

            -- Notify all players
            local msg = PlayerResource:GetPlayerName(playerID) ..
                " has become " .. heroName .. "!"
            GameRules:SendCustomMessage(msg, 0, 0)

            -- Fire UI events
            CustomGameEventManager:Send_ServerToAllClients("turbo_rdm_hero_swap", {
                player_id   = playerID,
                hero_name   = heroName,
                player_name = PlayerResource:GetPlayerName(playerID),
            })

            -- Send updated hero history to the player
            local history = self.playerHeroHistory[playerID] or {}
            local parts = {}
            for _, h in ipairs(history) do
                table.insert(parts, '"' .. h .. '"')
            end
            CustomGameEventManager:Send_ServerToPlayer(player, "turbo_rdm_hero_history", {
                heroes_json = "[" .. table.concat(parts, ",") .. "]",
            })

            -- Tell client to hide the selection UI
            CustomGameEventManager:Send_ServerToPlayer(player, "turbo_rdm_hero_chosen", {})

            print("[TurboRDM] Player " .. playerID ..
                " swapped to " .. heroName ..
                " at level " .. targetLevel)
        else
            print("[TurboRDM] ERROR: Failed to create hero " .. heroName)
        end

        -- Clear the re-entry guard
        self.swappingPlayers[playerID] = nil
    end, playerID)
end

--------------------------------------------------------------------------------
-- Periodic thinker (runs every second)
--------------------------------------------------------------------------------
function TurboRDM:OnThink()
    -- Placeholder for future periodic tasks
    -- Free TP is now handled by mode:SetGiveFreeTPOnDeath(true)
    return 30
end


