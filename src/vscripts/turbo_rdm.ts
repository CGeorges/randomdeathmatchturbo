/**
 * Turbo Random Deathmatch - Core game-mode logic
 *
 * Mechanics:
 *   - Each player starts with a random hero (All Random)
 *   - On death the player chooses from 3 random heroes to respawn as
 *   - All items are kept across hero swaps (stash + inventory)
 *   - Turbo rules: 2x passive gold, 2x XP, free TP scrolls, weaker buildings
 *   - Win condition: destroy the enemy Ancient (same as vanilla)
 */

const HERO_CHOICES_COUNT = 3;

interface SavedItem {
  name: string;
  charges: number;
  slot: number;
  cooldown: number;
}

interface ConsumedItems {
  shard: boolean;
  scepter: boolean;
  moonshard: boolean;
}

interface PendingChoice {
  heroes: string[];
  xp: number;
  chosenHero?: string;
}

// Declare Timers library (loaded from timers.lua)
declare const Timers: {
  CreateTimer(delay: number, callback: () => number | undefined): void;
};

// Hero pool tracking (avoid duplicates in the same game)
const usedHeroes: { [heroName: string]: PlayerID } = {};
const playerHeroHistory: { [playerID: number]: string[] } = {};
const playerItems: { [playerID: number]: SavedItem[] } = {};
const playerGold: { [playerID: number]: number } = {};
const pendingChoices: { [playerID: number]: PendingChoice } = {};
const playerConsumed: { [playerID: number]: ConsumedItems } = {};
const playerDeathTime: { [playerID: number]: number } = {};
const swappingPlayers: { [playerID: number]: boolean } = {};
// When true for a player, the XP filter skips the Turbo multiplier so we can
// restore the exact XP amount on a new hero without double-multiplying.
const restoringXP: { [playerID: number]: boolean } = {};

// ---------------------------------------------------------------------------
// Init (called from Activate() in addon_game_mode.lua)
// ---------------------------------------------------------------------------
export function InitGameMode(): void {
  print("[TurboRDM] Initializing Turbo Random Deathmatch...");

  const mode = GameRules.GetGameModeEntity();

  // Turbo-style game rules
  GameRules.SetUseUniversalShopMode(true);
  GameRules.SetHeroSelectionTime(0);
  GameRules.SetStrategyTime(0);
  GameRules.SetShowcaseTime(0);
  GameRules.SetPreGameTime(45);
  GameRules.SetPostGameTime(45);
  GameRules.EnableCustomGameSetupAutoLaunch(true);
  GameRules.SetCustomGameSetupAutoLaunchDelay(0);
  GameRules.SetGoldPerTick(2);
  GameRules.SetGoldTickTime(0.6);
  GameRules.SetStartingGold(750);
  GameRules.SetCustomGameAllowHeroPickMusic(false);
  GameRules.SetCustomGameAllowMusicAtGameStart(true);
  GameRules.SetTreeRegrowTime(30);
  GameRules.SetSameHeroSelectionEnabled(false);

  // Free courier from the start (Turbo)
  mode.SetFreeCourierModeEnabled(true);

  // XP multiplier (halved from vanilla)
  mode.SetCustomXPRequiredToReachNextLevel({
    [1]: 0,
    [2]: 120,
    [3]: 160,
    [4]: 210,
    [5]: 260,
    [6]: 320,
    [7]: 380,
    [8]: 450,
    [9]: 520,
    [10]: 600,
    [11]: 690,
    [12]: 780,
    [13]: 880,
    [14]: 990,
    [15]: 1100,
    [16]: 1220,
    [17]: 1350,
    [18]: 1500,
    [19]: 1660,
    [20]: 1830,
    [21]: 2010,
    [22]: 2200,
    [23]: 2400,
    [24]: 2610,
    [25]: 2830,
    [26]: 3200,
    [27]: 3600,
    [28]: 4000,
    [29]: 4400,
    [30]: 4800,
  } as any);

  mode.SetCustomGameForceHero("");
  mode.SetGiveFreeTPOnDeath(true);
  mode.SetCustomBackpackSwapCooldown(3.0);

  // Double XP from all sources (Turbo rules)
  mode.SetModifyExperienceFilter(
    function (event: ModifyExperienceFilterEvent) {
      // Skip the multiplier while we're restoring saved XP on a hero swap —
      // the saved value is already post-multiplier and should not be scaled again.
      if (restoringXP[event.player_id_const]) {
        return true;
      }
      event.experience = event.experience * 1.6;
      return true;
    } as any,
    {} as any,
  );

  // Event listeners
  ListenToGameEvent("npc_spawned", (event) => OnNPCSpawned(event), undefined);
  ListenToGameEvent(
    "entity_killed",
    (event) => OnEntityKilled(event),
    undefined,
  );
  ListenToGameEvent(
    "game_rules_state_change",
    () => OnGameStateChange(),
    undefined,
  );

  // Client-to-server event: player picked a hero from the selection UI
  CustomGameEventManager.RegisterListener(
    "turbo_rdm_hero_pick" as any,
    (_: number, event: any) => {
      OnHeroPicked(event as { PlayerID: PlayerID; hero_name: string });
    },
  );

  // Thinker for periodic tasks
  mode.SetThink(
    ((entity: CBaseEntity): number | undefined => {
      return OnThink();
    }) as any,
    undefined,
    "TurboRDMThink",
    1.0,
  );

  // Rune system
  mode.SetUseDefaultDOTARuneSpawnLogic(true);
  GameRules.SetRuneSpawnTime(120);
  mode.SetBountyRuneSpawnInterval(180);

  print("[TurboRDM] Initialization complete.");
}

// ---------------------------------------------------------------------------
// Get all available hero names (full pool minus already in use)
// ---------------------------------------------------------------------------
function GetAvailableHeroes(_playerID: PlayerID): string[] {
  const heroData = LoadKeyValues("scripts/npc/npc_heroes.txt") as Record<
    string,
    any
  >;
  const available: string[] = [];

  if (heroData !== undefined) {
    for (const [heroName] of Object.entries(heroData)) {
      if (
        typeof heroName === "string" &&
        heroName.startsWith("npc_dota_hero_") &&
        heroName !== "npc_dota_hero_base" &&
        heroName !== "npc_dota_hero_target_dummy" &&
        !usedHeroes[heroName]
      ) {
        available.push(heroName);
      }
    }
  }

  // If somehow all heroes are exhausted, reset the pool
  if (available.length === 0) {
    print("[TurboRDM] Hero pool exhausted, resetting...");
    for (const key in usedHeroes) {
      delete usedHeroes[key];
    }
    return GetAvailableHeroes(_playerID);
  }

  return available;
}

// ---------------------------------------------------------------------------
// Pick a random hero for a player (used for initial hero assignment)
// ---------------------------------------------------------------------------
function AssignRandomHero(playerID: PlayerID): string {
  const available = GetAvailableHeroes(playerID);
  const pick = available[RandomInt(0, available.length - 1)];

  usedHeroes[pick] = playerID;
  if (!playerHeroHistory[playerID]) {
    playerHeroHistory[playerID] = [];
  }
  playerHeroHistory[playerID].push(pick);

  print(`[TurboRDM] Player ${playerID} assigned hero: ${pick}`);
  return pick;
}

// ---------------------------------------------------------------------------
// Get N random hero choices for the selection UI (does NOT mark them as used)
// ---------------------------------------------------------------------------
function GetHeroChoices(playerID: PlayerID, count: number): string[] {
  const available = GetAvailableHeroes(playerID);
  const choices: string[] = [];

  // Fisher-Yates shuffle on the first 'count' elements
  for (let i = 0; i < Math.min(count, available.length); i++) {
    const j = RandomInt(i, available.length - 1);
    [available[i], available[j]] = [available[j], available[i]];
    choices.push(available[i]);
  }

  return choices;
}

// ---------------------------------------------------------------------------
// Snapshot a hero's items, gold, and consumed modifiers. Used both at death
// and again right before the hero swap so items bought while dead (which go
// to the stash on the old hero) are not lost. Does NOT touch playerDeathTime
// so callers can control whether the dead-time elapsed clock resets.
// ---------------------------------------------------------------------------
function CaptureHeroState(
  hero: CDOTA_BaseNPC_Hero,
  playerID: PlayerID,
): void {
  const items: SavedItem[] = [];

  // Inventory (0-5) + Backpack (6-8) + Stash (9-14) + TP/Neutral (15-16)
  for (let slot = 0; slot <= 16; slot++) {
    const item = hero.GetItemInSlot(slot);
    if (item) {
      items.push({
        name: item.GetAbilityName(),
        charges: item.GetCurrentCharges(),
        slot,
        cooldown: item.GetCooldownTimeRemaining(),
      });
    }
  }

  playerItems[playerID] = items;
  playerGold[playerID] = PlayerResource.GetGold(playerID);

  // Save consumed items (modifiers on the hero, not in item slots)
  playerConsumed[playerID] = {
    shard: hero.HasModifier("modifier_item_aghanims_shard"),
    scepter: hero.HasModifier("modifier_item_ultimate_scepter_consumed"),
    moonshard: hero.HasModifier("modifier_item_moon_shard_consumed"),
  };
}

// ---------------------------------------------------------------------------
// Save a player's items + gold at the moment of death. Stamps the death time
// so item cooldowns can be reduced by the dead duration on restore.
// ---------------------------------------------------------------------------
function SavePlayerInventory(
  hero: CDOTA_BaseNPC_Hero,
  playerID: PlayerID,
): void {
  CaptureHeroState(hero, playerID);
  playerDeathTime[playerID] = GameRules.GetGameTime();
  print(
    `[TurboRDM] Saved ${playerItems[playerID].length} items for player ${playerID}`,
  );
}

// ---------------------------------------------------------------------------
// Restore items + gold to a new hero
// ---------------------------------------------------------------------------
function RestorePlayerInventory(
  hero: CDOTA_BaseNPC_Hero,
  playerID: PlayerID,
): void {
  const items = playerItems[playerID];
  const gold = playerGold[playerID];

  // Calculate how long the player was dead so cooldowns tick down properly
  let deadElapsed = 0;
  if (playerDeathTime[playerID] !== undefined) {
    deadElapsed = GameRules.GetGameTime() - playerDeathTime[playerID];
    delete playerDeathTime[playerID];
  }

  if (items !== undefined) {
    for (const entry of items) {
      const newItem = CreateItem(entry.name, hero as any, hero);
      if (newItem) {
        // Skip fully consumed charge-based items (e.g., wards at 0 charges)
        const defaultCharges = newItem.GetCurrentCharges();
        if (entry.charges === 0 && defaultCharges > 0) {
          UTIL_Remove(newItem);
        } else {
          newItem.SetCurrentCharges(entry.charges);
          if (!hero.AddItem(newItem)) {
            print(`[TurboRDM] Warning: could not restore item ${entry.name}`);
            UTIL_Remove(newItem);
          } else {
            const remaining = (entry.cooldown || 0) - deadElapsed;
            if (remaining > 0) {
              newItem.StartCooldown(remaining);
            } else {
              newItem.EndCooldown();
            }
          }
        }
      }
    }
    delete playerItems[playerID];
  }

  if (gold !== undefined) {
    PlayerResource.SetGold(playerID, gold, true);
    delete playerGold[playerID];
  }

  // Restore consumed items (Shard, Scepter Blessing, Moon Shard)
  const consumed = playerConsumed[playerID];
  if (consumed !== undefined) {
    if (consumed.shard) {
      const shard = CreateItem("item_aghanims_shard", hero as any, hero);
      if (shard) hero.AddItem(shard);
    }
    if (consumed.scepter) {
      const blessing = CreateItem("item_ultimate_scepter_2", hero as any, hero);
      if (blessing) hero.AddItem(blessing);
    }
    if (consumed.moonshard) {
      hero.AddNewModifier(
        hero,
        undefined,
        "modifier_item_moon_shard_consumed",
        {},
      );
    }
    delete playerConsumed[playerID];
  }
}

// ---------------------------------------------------------------------------
// Weaken buildings (Turbo-style: reduced HP)
// ---------------------------------------------------------------------------
function ApplyTurboBuildingModifiers(): void {
  const towers = Entities.FindAllByClassname(
    "npc_dota_tower",
  ) as CDOTA_BaseNPC[];
  for (const tower of towers) {
    if (tower && IsValidEntity(tower)) {
      const maxHP = tower.GetMaxHealth();
      tower.SetMaxHealth(Math.floor(maxHP * 0.6));
      tower.SetHealth(Math.floor(maxHP * 0.6));
    }
  }

  const barracks = Entities.FindAllByClassname(
    "npc_dota_barracks",
  ) as CDOTA_BaseNPC[];
  for (const rax of barracks) {
    if (rax && IsValidEntity(rax)) {
      const maxHP = rax.GetMaxHealth();
      rax.SetMaxHealth(Math.floor(maxHP * 0.6));
      rax.SetHealth(Math.floor(maxHP * 0.6));
    }
  }

  const ancients = Entities.FindAllByClassname(
    "npc_dota_fort",
  ) as CDOTA_BaseNPC[];
  for (const fort of ancients) {
    if (fort && IsValidEntity(fort)) {
      const maxHP = fort.GetMaxHealth();
      fort.SetMaxHealth(Math.floor(maxHP * 0.75));
      fort.SetHealth(Math.floor(maxHP * 0.75));
    }
  }

  print("[TurboRDM] Applied Turbo building modifiers (reduced HP).");
}

// ---------------------------------------------------------------------------
// EVENT: Game state change
// ---------------------------------------------------------------------------
function OnGameStateChange(): void {
  const state = GameRules.State_Get();

  if (state === DOTA_GameState.DOTA_GAMERULES_STATE_HERO_SELECTION) {
    for (
      let playerID = 0 as PlayerID;
      playerID < PlayerResource.GetPlayerCount();
      playerID++
    ) {
      if (PlayerResource.IsValidPlayerID(playerID)) {
        const heroName = AssignRandomHero(playerID);
        const player = PlayerResource.GetPlayer(playerID);
        if (player) {
          player.SetSelectedHero(heroName);
        }
      }
    }
  }

  if (state === DOTA_GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS) {
    Timers.CreateTimer(1.0, () => {
      ApplyTurboBuildingModifiers();
      return undefined;
    });
  }
}

// ---------------------------------------------------------------------------
// EVENT: NPC (hero) spawned
// ---------------------------------------------------------------------------
function OnNPCSpawned(event: NpcSpawnedEvent): void {
  const npc = EntIndexToHScript(event.entindex) as CDOTA_BaseNPC;
  if (!npc) return;

  // Turbo courier speed
  if (npc.IsCourier()) {
    Timers.CreateTimer(0.1, () => {
      if (npc && IsValidEntity(npc)) {
        npc.SetBaseMoveSpeed(1100);
      }
      return undefined;
    });
    return;
  }

  if (!npc.IsRealHero()) return;

  const playerID = (npc as CDOTA_BaseNPC_Hero).GetPlayerID();

  // If this player has a pending hero swap (engine just respawned the old
  // hero after death / buyback), execute the swap now.
  if (pendingChoices[playerID] && !swappingPlayers[playerID]) {
    const chosen =
      pendingChoices[playerID].chosenHero || pendingChoices[playerID].heroes[0];
    ExecuteHeroSwap(playerID, chosen);
  }
}

// ---------------------------------------------------------------------------
// EVENT: Entity killed (hero death triggers RDM hero selection)
// ---------------------------------------------------------------------------
function OnEntityKilled(event: EntityKilledEvent): void {
  const killedUnit = EntIndexToHScript(
    event.entindex_killed,
  ) as CDOTA_BaseNPC_Hero;
  if (!killedUnit || !killedUnit.IsRealHero()) return;

  const playerID = killedUnit.GetPlayerID();

  // 1. Save current items and gold
  SavePlayerInventory(killedUnit, playerID);

  // 2. Get the engine's respawn time for the UI countdown. Save the exact XP
  //    total (not just integer level) so partial progress toward the next
  //    level is preserved across the hero swap.
  const xp = killedUnit.GetCurrentXP();
  const respawnTime = killedUnit.GetRespawnTime();

  // 3. Get 3 hero choices and send to the client
  const choices = GetHeroChoices(playerID, HERO_CHOICES_COUNT);

  pendingChoices[playerID] = {
    heroes: choices,
    xp,
  };

  const player = PlayerResource.GetPlayer(playerID);
  if (player) {
    CustomGameEventManager.Send_ServerToPlayer(
      player,
      "turbo_rdm_hero_choices" as any,
      {
        hero1: choices[0],
        hero2: choices[1],
        hero3: choices[2] || choices[0],
        respawn_time: respawnTime,
      },
    );
  }
}

// ---------------------------------------------------------------------------
// EVENT: Player picked a hero from the selection UI (client → server)
// ---------------------------------------------------------------------------
function OnHeroPicked(event: { PlayerID: PlayerID; hero_name: string }): void {
  const playerID = event.PlayerID;
  const heroName = event.hero_name;

  const pending = pendingChoices[playerID];
  if (!pending) return;

  // Validate the pick is one of the offered choices
  if (!pending.heroes.includes(heroName)) {
    print(`[TurboRDM] Player ${playerID} sent invalid pick: ${heroName}`);
    return;
  }

  // Store choice — swap happens when engine respawns the hero
  pending.chosenHero = heroName;
  print(`[TurboRDM] Player ${playerID} chose: ${heroName}`);

  // Hide the selection UI
  const player = PlayerResource.GetPlayer(playerID);
  if (player) {
    CustomGameEventManager.Send_ServerToPlayer(
      player,
      "turbo_rdm_hero_chosen" as any,
      {},
    );
  }
}

// ---------------------------------------------------------------------------
// Execute the actual hero swap (called from OnNPCSpawned)
// ---------------------------------------------------------------------------
function ExecuteHeroSwap(playerID: PlayerID, heroName: string): void {
  const pending = pendingChoices[playerID];
  if (!pending) return;

  // Guard: prevent re-entry when CreateHeroForPlayer fires npc_spawned
  swappingPlayers[playerID] = true;

  // If the hero was taken by another player, fall back
  if (usedHeroes[heroName]) {
    for (const h of pending.heroes) {
      if (!usedHeroes[h]) {
        heroName = h;
        break;
      }
    }
    if (usedHeroes[heroName]) {
      const available = GetAvailableHeroes(playerID);
      heroName = available[RandomInt(0, available.length - 1)];
    }
  }

  // Mark hero as used
  usedHeroes[heroName] = playerID;
  if (!playerHeroHistory[playerID]) {
    playerHeroHistory[playerID] = [];
  }
  playerHeroHistory[playerID].push(heroName);

  const targetXP = pending.xp;
  delete pendingChoices[playerID];

  const player = PlayerResource.GetPlayer(playerID);
  if (!player) return;

  const oldHero = PlayerResource.GetSelectedHeroEntity(playerID);

  // Re-snapshot the old hero right before removing it so items bought while
  // dead (which went to the stash on this entity) and any gold changes since
  // death are preserved. Death time is left untouched so item cooldowns
  // continue to tick down across the dead period.
  if (oldHero && IsValidEntity(oldHero)) {
    CaptureHeroState(oldHero, playerID);
    oldHero.SetRespawnsDisabled(true);
    UTIL_Remove(oldHero);
  }

  // Precache hero model, then create in callback
  PrecacheUnitByNameAsync(
    heroName,
    () => {
      const newHero = CreateHeroForPlayer(heroName, player);

      if (newHero !== undefined) {
        newHero.SetControllableByPlayer(playerID, true);
        newHero.SetOwner(player);
        player.SetAssignedHeroEntity(newHero);

        // Match old hero's XP exactly (preserves partial progress toward the
        // next level). Suppress the Turbo XP multiplier during this restore
        // since the saved value is already post-multiplier.
        restoringXP[playerID] = true;
        newHero.AddExperience(
          targetXP,
          EDOTA_ModifyXP_Reason.DOTA_ModifyXP_Unspecified,
          false,
          true,
        );
        restoringXP[playerID] = false;

        // Remove default items
        for (let slot = 0; slot <= 16; slot++) {
          const defaultItem = newHero.GetItemInSlot(slot);
          if (defaultItem) {
            newHero.RemoveItem(defaultItem);
          }
        }

        // Restore items and gold (gold is set inside RestorePlayerInventory
        // from the snapshot captured just before the old hero was removed).
        RestorePlayerInventory(newHero, playerID);

        // Respawn the new hero
        newHero.SetRespawnsDisabled(false);
        newHero.RespawnHero(false, false);

        // Notify all players
        const msg =
          PlayerResource.GetPlayerName(playerID) +
          " has become " +
          heroName +
          "!";
        GameRules.SendCustomMessage(msg, 0, 0);

        CustomGameEventManager.Send_ServerToAllClients(
          "turbo_rdm_hero_swap" as any,
          {
            player_id: playerID,
            hero_name: heroName,
            player_name: PlayerResource.GetPlayerName(playerID),
          },
        );

        // Send hero history (use table.concat — JSON.stringify is not available in Lua)
        const history = playerHeroHistory[playerID] || [];
        CustomGameEventManager.Send_ServerToPlayer(
          player,
          "turbo_rdm_hero_history" as any,
          {
            heroes_json: history.join(","),
          },
        );

        // Tell client to hide selection UI
        CustomGameEventManager.Send_ServerToPlayer(
          player,
          "turbo_rdm_hero_chosen" as any,
          {},
        );

        print(
          `[TurboRDM] Player ${playerID} swapped to ${heroName} with ${targetXP} XP (level ${newHero.GetLevel()})`,
        );
      } else {
        print(`[TurboRDM] ERROR: Failed to create hero ${heroName}`);
      }

      swappingPlayers[playerID] = false;
    },
    playerID,
  );
}

// ---------------------------------------------------------------------------
// Periodic thinker
// ---------------------------------------------------------------------------
function OnThink(): number {
  return 30;
}
