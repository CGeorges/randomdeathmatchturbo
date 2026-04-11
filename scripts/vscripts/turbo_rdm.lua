local ____lualib = require("lualib_bundle")
local __TS__StringStartsWith = ____lualib.__TS__StringStartsWith
local __TS__ObjectEntries = ____lualib.__TS__ObjectEntries
local __TS__Delete = ____lualib.__TS__Delete
local __TS__ArrayIncludes = ____lualib.__TS__ArrayIncludes
local ____exports = {}
local GetAvailableHeroes, AssignRandomHero, GetHeroChoices, CaptureHeroState, SavePlayerInventory, RestorePlayerInventory, ApplyTurboBuildingModifiers, OnGameStateChange, OnNPCSpawned, OnEntityKilled, OnHeroPicked, ExecuteHeroSwap, OnThink, HERO_CHOICES_COUNT, usedHeroes, playerHeroHistory, playerItems, playerGold, pendingChoices, playerConsumed, playerDeathTime, swappingPlayers, restoringXP
function GetAvailableHeroes(self, _playerID)
    local heroData = LoadKeyValues("scripts/npc/npc_heroes.txt")
    local available = {}
    if heroData ~= nil then
        for ____, ____value in ipairs(__TS__ObjectEntries(heroData)) do
            local heroName = ____value[1]
            if type(heroName) == "string" and __TS__StringStartsWith(heroName, "npc_dota_hero_") and heroName ~= "npc_dota_hero_base" and heroName ~= "npc_dota_hero_target_dummy" and not usedHeroes[heroName] then
                available[#available + 1] = heroName
            end
        end
    end
    if #available == 0 then
        print("[TurboRDM] Hero pool exhausted, resetting...")
        for key in pairs(usedHeroes) do
            __TS__Delete(usedHeroes, key)
        end
        return GetAvailableHeroes(nil, _playerID)
    end
    return available
end
function AssignRandomHero(self, playerID)
    local available = GetAvailableHeroes(nil, playerID)
    local pick = available[RandomInt(0, #available - 1) + 1]
    usedHeroes[pick] = playerID
    if not playerHeroHistory[playerID] then
        playerHeroHistory[playerID] = {}
    end
    local ____playerHeroHistory_playerID_0 = playerHeroHistory[playerID]
    ____playerHeroHistory_playerID_0[#____playerHeroHistory_playerID_0 + 1] = pick
    print((("[TurboRDM] Player " .. tostring(playerID)) .. " assigned hero: ") .. pick)
    return pick
end
function GetHeroChoices(self, playerID, count)
    local available = GetAvailableHeroes(nil, playerID)
    local choices = {}
    do
        local i = 0
        while i < math.min(count, #available) do
            local j = RandomInt(i, #available - 1)
            local ____temp_1 = {available[j + 1], available[i + 1]}
            available[i + 1] = ____temp_1[1]
            available[j + 1] = ____temp_1[2]
            choices[#choices + 1] = available[i + 1]
            i = i + 1
        end
    end
    return choices
end
function CaptureHeroState(self, hero, playerID)
    local items = {}
    do
        local slot = 0
        while slot <= 16 do
            local item = hero:GetItemInSlot(slot)
            if item then
                items[#items + 1] = {
                    name = item:GetAbilityName(),
                    charges = item:GetCurrentCharges(),
                    slot = slot,
                    cooldown = item:GetCooldownTimeRemaining()
                }
            end
            slot = slot + 1
        end
    end
    playerItems[playerID] = items
    playerGold[playerID] = PlayerResource:GetGold(playerID)
    playerConsumed[playerID] = {
        shard = hero:HasModifier("modifier_item_aghanims_shard"),
        scepter = hero:HasModifier("modifier_item_ultimate_scepter_consumed"),
        moonshard = hero:HasModifier("modifier_item_moon_shard_consumed")
    }
end
function SavePlayerInventory(self, hero, playerID)
    CaptureHeroState(nil, hero, playerID)
    playerDeathTime[playerID] = GameRules:GetGameTime()
    print((("[TurboRDM] Saved " .. tostring(#playerItems[playerID])) .. " items for player ") .. tostring(playerID))
end
function RestorePlayerInventory(self, hero, playerID)
    local items = playerItems[playerID]
    local gold = playerGold[playerID]
    local deadElapsed = 0
    if playerDeathTime[playerID] ~= nil then
        deadElapsed = GameRules:GetGameTime() - playerDeathTime[playerID]
        __TS__Delete(playerDeathTime, playerID)
    end
    if items ~= nil then
        for ____, entry in ipairs(items) do
            local newItem = CreateItem(entry.name, hero, hero)
            if newItem then
                local defaultCharges = newItem:GetCurrentCharges()
                if entry.charges == 0 and defaultCharges > 0 then
                    UTIL_Remove(newItem)
                else
                    newItem:SetCurrentCharges(entry.charges)
                    if not hero:AddItem(newItem) then
                        print("[TurboRDM] Warning: could not restore item " .. entry.name)
                        UTIL_Remove(newItem)
                    else
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
        __TS__Delete(playerItems, playerID)
    end
    if gold ~= nil then
        PlayerResource:SetGold(playerID, gold, true)
        __TS__Delete(playerGold, playerID)
    end
    local consumed = playerConsumed[playerID]
    if consumed ~= nil then
        if consumed.shard then
            local shard = CreateItem("item_aghanims_shard", hero, hero)
            if shard then
                hero:AddItem(shard)
            end
        end
        if consumed.scepter then
            local blessing = CreateItem("item_ultimate_scepter_2", hero, hero)
            if blessing then
                hero:AddItem(blessing)
            end
        end
        if consumed.moonshard then
            hero:AddNewModifier(hero, nil, "modifier_item_moon_shard_consumed", {})
        end
        __TS__Delete(playerConsumed, playerID)
    end
end
function ApplyTurboBuildingModifiers(self)
    local towers = Entities:FindAllByClassname("npc_dota_tower")
    for ____, tower in ipairs(towers) do
        if tower and IsValidEntity(tower) then
            local maxHP = tower:GetMaxHealth()
            tower:SetMaxHealth(math.floor(maxHP * 0.6))
            tower:SetHealth(math.floor(maxHP * 0.6))
        end
    end
    local barracks = Entities:FindAllByClassname("npc_dota_barracks")
    for ____, rax in ipairs(barracks) do
        if rax and IsValidEntity(rax) then
            local maxHP = rax:GetMaxHealth()
            rax:SetMaxHealth(math.floor(maxHP * 0.6))
            rax:SetHealth(math.floor(maxHP * 0.6))
        end
    end
    local ancients = Entities:FindAllByClassname("npc_dota_fort")
    for ____, fort in ipairs(ancients) do
        if fort and IsValidEntity(fort) then
            local maxHP = fort:GetMaxHealth()
            fort:SetMaxHealth(math.floor(maxHP * 0.75))
            fort:SetHealth(math.floor(maxHP * 0.75))
        end
    end
    print("[TurboRDM] Applied Turbo building modifiers (reduced HP).")
end
function OnGameStateChange(self)
    local state = GameRules:State_Get()
    if state == DOTA_GAMERULES_STATE_HERO_SELECTION then
        do
            local playerID = 0
            while playerID < PlayerResource:GetPlayerCount() do
                if PlayerResource:IsValidPlayerID(playerID) then
                    local heroName = AssignRandomHero(nil, playerID)
                    local player = PlayerResource:GetPlayer(playerID)
                    if player then
                        player:SetSelectedHero(heroName)
                    end
                end
                playerID = playerID + 1
            end
        end
    end
    if state == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        Timers:CreateTimer(
            1,
            function()
                ApplyTurboBuildingModifiers(nil)
                return nil
            end
        )
    end
end
function OnNPCSpawned(self, event)
    local npc = EntIndexToHScript(event.entindex)
    if not npc then
        return
    end
    if npc:IsCourier() then
        Timers:CreateTimer(
            0.1,
            function()
                if npc and IsValidEntity(npc) then
                    npc:SetBaseMoveSpeed(1100)
                end
                return nil
            end
        )
        return
    end
    if not npc:IsRealHero() then
        return
    end
    local playerID = npc:GetPlayerID()
    if pendingChoices[playerID] and not swappingPlayers[playerID] then
        local chosen = pendingChoices[playerID].chosenHero or pendingChoices[playerID].heroes[1]
        ExecuteHeroSwap(nil, playerID, chosen)
    end
end
function OnEntityKilled(self, event)
    local killedUnit = EntIndexToHScript(event.entindex_killed)
    if not killedUnit or not killedUnit:IsRealHero() then
        return
    end
    local playerID = killedUnit:GetPlayerID()
    SavePlayerInventory(nil, killedUnit, playerID)
    local xp = killedUnit:GetCurrentXP()
    local respawnTime = killedUnit:GetRespawnTime()
    local choices = GetHeroChoices(nil, playerID, HERO_CHOICES_COUNT)
    pendingChoices[playerID] = {heroes = choices, xp = xp}
    local player = PlayerResource:GetPlayer(playerID)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, "turbo_rdm_hero_choices", {hero1 = choices[1], hero2 = choices[2], hero3 = choices[3] or choices[1], respawn_time = respawnTime})
    end
end
function OnHeroPicked(self, event)
    local playerID = event.PlayerID
    local heroName = event.hero_name
    local pending = pendingChoices[playerID]
    if not pending then
        return
    end
    if not __TS__ArrayIncludes(pending.heroes, heroName) then
        print((("[TurboRDM] Player " .. tostring(playerID)) .. " sent invalid pick: ") .. heroName)
        return
    end
    pending.chosenHero = heroName
    print((("[TurboRDM] Player " .. tostring(playerID)) .. " chose: ") .. heroName)
    local player = PlayerResource:GetPlayer(playerID)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, "turbo_rdm_hero_chosen", {})
    end
end
function ExecuteHeroSwap(self, playerID, heroName)
    local pending = pendingChoices[playerID]
    if not pending then
        return
    end
    swappingPlayers[playerID] = true
    if usedHeroes[heroName] then
        for ____, h in ipairs(pending.heroes) do
            if not usedHeroes[h] then
                heroName = h
                break
            end
        end
        if usedHeroes[heroName] then
            local available = GetAvailableHeroes(nil, playerID)
            heroName = available[RandomInt(0, #available - 1) + 1]
        end
    end
    usedHeroes[heroName] = playerID
    if not playerHeroHistory[playerID] then
        playerHeroHistory[playerID] = {}
    end
    local ____playerHeroHistory_playerID_2 = playerHeroHistory[playerID]
    ____playerHeroHistory_playerID_2[#____playerHeroHistory_playerID_2 + 1] = heroName
    local targetXP = pending.xp
    __TS__Delete(pendingChoices, playerID)
    local player = PlayerResource:GetPlayer(playerID)
    if not player then
        return
    end
    local oldHero = PlayerResource:GetSelectedHeroEntity(playerID)
    if oldHero and IsValidEntity(oldHero) then
        CaptureHeroState(nil, oldHero, playerID)
        oldHero:SetRespawnsDisabled(true)
        UTIL_Remove(oldHero)
    end
    PrecacheUnitByNameAsync(
        heroName,
        function()
            local newHero = CreateHeroForPlayer(heroName, player)
            if newHero ~= nil then
                newHero:SetControllableByPlayer(playerID, true)
                newHero:SetOwner(player)
                player:SetAssignedHeroEntity(newHero)
                restoringXP[playerID] = true
                newHero:AddExperience(targetXP, DOTA_ModifyXP_Unspecified, false, true)
                restoringXP[playerID] = false
                do
                    local slot = 0
                    while slot <= 16 do
                        local defaultItem = newHero:GetItemInSlot(slot)
                        if defaultItem then
                            newHero:RemoveItem(defaultItem)
                        end
                        slot = slot + 1
                    end
                end
                RestorePlayerInventory(nil, newHero, playerID)
                newHero:SetRespawnsDisabled(false)
                newHero:RespawnHero(false, false)
                local msg = ((PlayerResource:GetPlayerName(playerID) .. " has become ") .. heroName) .. "!"
                GameRules:SendCustomMessage(msg, 0, 0)
                CustomGameEventManager:Send_ServerToAllClients(
                    "turbo_rdm_hero_swap",
                    {
                        player_id = playerID,
                        hero_name = heroName,
                        player_name = PlayerResource:GetPlayerName(playerID)
                    }
                )
                local history = playerHeroHistory[playerID] or ({})
                CustomGameEventManager:Send_ServerToPlayer(
                    player,
                    "turbo_rdm_hero_history",
                    {heroes_json = table.concat(history, ",")}
                )
                CustomGameEventManager:Send_ServerToPlayer(player, "turbo_rdm_hero_chosen", {})
                print(((((((("[TurboRDM] Player " .. tostring(playerID)) .. " swapped to ") .. heroName) .. " with ") .. tostring(targetXP)) .. " XP (level ") .. tostring(newHero:GetLevel())) .. ")")
            else
                print("[TurboRDM] ERROR: Failed to create hero " .. heroName)
            end
            swappingPlayers[playerID] = false
        end,
        playerID
    )
end
function OnThink(self)
    return 30
end
HERO_CHOICES_COUNT = 3
usedHeroes = {}
playerHeroHistory = {}
playerItems = {}
playerGold = {}
pendingChoices = {}
playerConsumed = {}
playerDeathTime = {}
swappingPlayers = {}
restoringXP = {}
function ____exports.InitGameMode(self)
    print("[TurboRDM] Initializing Turbo Random Deathmatch...")
    local mode = GameRules:GetGameModeEntity()
    GameRules:SetUseUniversalShopMode(true)
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetStrategyTime(0)
    GameRules:SetShowcaseTime(0)
    GameRules:SetPreGameTime(45)
    GameRules:SetPostGameTime(45)
    GameRules:EnableCustomGameSetupAutoLaunch(true)
    GameRules:SetCustomGameSetupAutoLaunchDelay(0)
    GameRules:SetGoldPerTick(2)
    GameRules:SetGoldTickTime(0.6)
    GameRules:SetStartingGold(750)
    GameRules:SetCustomGameAllowHeroPickMusic(false)
    GameRules:SetCustomGameAllowMusicAtGameStart(true)
    GameRules:SetTreeRegrowTime(30)
    GameRules:SetSameHeroSelectionEnabled(false)
    mode:SetFreeCourierModeEnabled(true)
    mode:SetCustomXPRequiredToReachNextLevel({
        [1] = 0,
        [2] = 120,
        [3] = 160,
        [4] = 210,
        [5] = 260,
        [6] = 320,
        [7] = 380,
        [8] = 450,
        [9] = 520,
        [10] = 600,
        [11] = 690,
        [12] = 780,
        [13] = 880,
        [14] = 990,
        [15] = 1100,
        [16] = 1220,
        [17] = 1350,
        [18] = 1500,
        [19] = 1660,
        [20] = 1830,
        [21] = 2010,
        [22] = 2200,
        [23] = 2400,
        [24] = 2610,
        [25] = 2830,
        [26] = 3200,
        [27] = 3600,
        [28] = 4000,
        [29] = 4400,
        [30] = 4800
    })
    mode:SetCustomGameForceHero("")
    mode:SetGiveFreeTPOnDeath(true)
    mode:SetCustomBackpackSwapCooldown(3)
    mode:SetModifyExperienceFilter(
        function(self, event)
            if restoringXP[event.player_id_const] then
                return true
            end
            event.experience = event.experience * 1.6
            return true
        end,
        {}
    )
    ListenToGameEvent(
        "npc_spawned",
        function(event) return OnNPCSpawned(nil, event) end,
        nil
    )
    ListenToGameEvent(
        "entity_killed",
        function(event) return OnEntityKilled(nil, event) end,
        nil
    )
    ListenToGameEvent(
        "game_rules_state_change",
        function() return OnGameStateChange(nil) end,
        nil
    )
    CustomGameEventManager:RegisterListener(
        "turbo_rdm_hero_pick",
        function(_, event)
            OnHeroPicked(nil, event)
        end
    )
    mode:SetThink(
        function(____, entity)
            return OnThink(nil)
        end,
        nil,
        "TurboRDMThink",
        1
    )
    mode:SetUseDefaultDOTARuneSpawnLogic(true)
    GameRules:SetRuneSpawnTime(120)
    mode:SetBountyRuneSpawnInterval(180)
    print("[TurboRDM] Initialization complete.")
end
return ____exports
