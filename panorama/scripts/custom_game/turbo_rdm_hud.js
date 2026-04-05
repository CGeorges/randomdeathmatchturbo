"use strict";
/**
 * Turbo Random Deathmatch - Panorama HUD Script
 * Handles hero swap notifications, hero history display, and hero selection UI
 */
let heroHistory = [];
let selectionTimerHandle = null;
let selectionCountdown = 0;
let isWaitingForRespawn = false;
function InitEvents() {
    GameEvents.Subscribe("turbo_rdm_hero_swap", (e) => OnHeroSwap(e));
    GameEvents.Subscribe("turbo_rdm_hero_history", (e) => OnHeroHistoryUpdate(e));
    GameEvents.Subscribe("turbo_rdm_hero_choices", (e) => OnHeroChoices(e));
    GameEvents.Subscribe("turbo_rdm_hero_chosen", () => OnHeroChosen());
    GameEvents.Subscribe("dota_buyback", (e) => OnBuyback(e));
}
function OnBuyback(event) {
    const localPlayerID = Players.GetLocalPlayer();
    if (event.player_id === localPlayerID) {
        HideSelectionUI();
    }
}
function OnHeroSwap(event) {
    const notifPanel = $("#SwapNotification");
    const swapText = $("#SwapText");
    if (notifPanel && swapText) {
        swapText.text = event.player_name + " \u2192 " + event.hero_name.replace("npc_dota_hero_", "").toUpperCase();
        notifPanel.style.visibility = "visible";
        $.Schedule(3.0, () => {
            notifPanel.style.visibility = "collapse";
        });
    }
    const localPlayerID = Players.GetLocalPlayer();
    if (event.player_id === localPlayerID) {
        HideSelectionUI();
    }
}
function OnHeroHistoryUpdate(event) {
    const raw = event.heroes_json || "";
    heroHistory = raw.length > 0 ? raw.split(",") : [];
    RebuildHeroHistoryUI();
}
function RebuildHeroHistoryUI() {
    const container = $("#HeroHistoryIcons");
    if (!container)
        return;
    container.RemoveAndDeleteChildren();
    for (let i = 0; i < heroHistory.length; i++) {
        const heroName = heroHistory[i];
        const icon = $.CreatePanel("Image", container, "hero_" + i);
        icon.AddClass("history-icon");
        if (i === heroHistory.length - 1) {
            icon.AddClass("history-icon-current");
        }
        icon.SetImage("s2r://panorama/images/heroes/" + heroName + "_png.vtex");
    }
}
function OnHeroChoices(event) {
    const heroes = [event.hero1, event.hero2, event.hero3];
    const respawnTime = event.respawn_time;
    const overlay = $("#HeroSelectionOverlay");
    const container = $("#HeroChoices");
    if (!overlay || !container)
        return;
    // Reset state
    isWaitingForRespawn = false;
    container.style.visibility = "visible";
    const title = $("#SelectionTitle");
    if (title) {
        title.text = "CHOOSE YOUR NEXT HERO";
    }
    const timerLabel = $("#SelectionTimer");
    if (timerLabel) {
        timerLabel.RemoveClass("respawn-countdown");
    }
    // Build the 3 hero choice cards
    container.RemoveAndDeleteChildren();
    for (let i = 0; i < heroes.length; i++) {
        const heroName = heroes[i];
        const card = $.CreatePanel("Panel", container, "choice_" + i);
        card.AddClass("hero-choice-card");
        const portrait = $.CreatePanel("Image", card, "portrait_" + i);
        portrait.AddClass("hero-choice-portrait");
        portrait.SetImage("s2r://panorama/images/heroes/" + heroName + "_png.vtex");
        const label = $.CreatePanel("Label", card, "label_" + i);
        label.AddClass("hero-choice-name");
        label.text = heroName.replace("npc_dota_hero_", "").replace(/_/g, " ").toUpperCase();
        // Click to pick this hero — hide overlay immediately
        card.SetPanelEvent("onactivate", () => {
            GameEvents.SendCustomGameEventToServer("turbo_rdm_hero_pick", {
                hero_name: heroName
            });
            HideSelectionUI();
        });
    }
    // Show the overlay
    overlay.style.visibility = "visible";
    overlay.AddClass("selection-fade-in");
    // Start countdown timer
    selectionCountdown = respawnTime;
    UpdateSelectionTimer();
    if (selectionTimerHandle) {
        $.CancelScheduled(selectionTimerHandle);
    }
    TickSelectionTimer();
}
function TickSelectionTimer() {
    selectionCountdown -= 1;
    if (selectionCountdown >= 0) {
        UpdateSelectionTimer();
        selectionTimerHandle = $.Schedule(1.0, TickSelectionTimer);
    }
}
function UpdateSelectionTimer() {
    const timerLabel = $("#SelectionTimer");
    if (!timerLabel)
        return;
    if (isWaitingForRespawn) {
        timerLabel.text = selectionCountdown > 0
            ? "Respawning in " + selectionCountdown + "s"
            : "Respawning...";
    }
    else {
        timerLabel.text = selectionCountdown > 0
            ? "Auto-selecting in " + selectionCountdown + "s..."
            : "Selecting...";
    }
}
/**
 * Called when the server confirms a hero was chosen.
 * Hide the overlay immediately — respawn timer is visible in the default Dota death UI.
 */
function OnHeroChosen() {
    HideSelectionUI();
}
function HideSelectionUI() {
    isWaitingForRespawn = false;
    const overlay = $("#HeroSelectionOverlay");
    if (overlay) {
        overlay.RemoveClass("selection-fade-in");
        overlay.style.visibility = "collapse";
    }
    const title = $("#SelectionTitle");
    if (title) {
        title.text = "CHOOSE YOUR NEXT HERO";
    }
    const container = $("#HeroChoices");
    if (container) {
        container.style.visibility = "visible";
    }
    const timerLabel = $("#SelectionTimer");
    if (timerLabel) {
        timerLabel.RemoveClass("respawn-countdown");
    }
    if (selectionTimerHandle) {
        $.CancelScheduled(selectionTimerHandle);
        selectionTimerHandle = null;
    }
}
// Init
(() => {
    InitEvents();
})();
