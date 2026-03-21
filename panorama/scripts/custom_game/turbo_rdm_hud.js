/**
 * Turbo Random Deathmatch - Panorama HUD Script
 * Handles hero swap notifications, hero history display, and hero selection UI
 */

"use strict";

var heroHistory = [];
var selectionTimerHandle = null;
var selectionCountdown = 0;
var isWaitingForRespawn = false;

/**
 * Listen for custom game events from Lua
 */
function InitEvents() {
    GameEvents.Subscribe("turbo_rdm_hero_swap", OnHeroSwap);
    GameEvents.Subscribe("turbo_rdm_hero_history", OnHeroHistoryUpdate);
    GameEvents.Subscribe("turbo_rdm_hero_choices", OnHeroChoices);
    GameEvents.Subscribe("turbo_rdm_hero_chosen", OnHeroChosen);
    GameEvents.Subscribe("dota_buyback", OnBuyback);
}

/**
 * Called when a player buys back — hide selection UI for the local player
 */
function OnBuyback(event) {
    var localPlayerID = Players.GetLocalPlayer();
    if (event.player_id === localPlayerID) {
        HideSelectionUI();
    }
}

/**
 * Called when any player swaps to a new hero
 */
function OnHeroSwap(event) {
    var playerName = event.player_name;
    var heroName   = event.hero_name;

    var notifPanel = $("#SwapNotification");
    var swapText   = $("#SwapText");

    if (notifPanel && swapText) {
        swapText.text = playerName + " \u2192 " + heroName.replace("npc_dota_hero_", "").toUpperCase();
        notifPanel.style.visibility = "visible";

        $.Schedule(3.0, function() {
            notifPanel.style.visibility = "collapse";
        });
    }

    // Hide the selection/respawn overlay when the local player's swap completes
    var localPlayerID = Players.GetLocalPlayer();
    if (event.player_id === localPlayerID) {
        HideSelectionUI();
    }
}

/**
 * Update the local player's hero history strip
 */
function OnHeroHistoryUpdate(event) {
    var heroes = JSON.parse(event.heroes_json || "[]");
    heroHistory = heroes;
    RebuildHeroHistoryUI();
}

/**
 * Rebuild the hero icon strip
 */
function RebuildHeroHistoryUI() {
    var container = $("#HeroHistoryIcons");
    if (!container) return;

    container.RemoveAndDeleteChildren();

    for (var i = 0; i < heroHistory.length; i++) {
        var heroName = heroHistory[i];
        var icon = $.CreatePanel("Image", container, "hero_" + i);
        icon.AddClass("history-icon");

        if (i === heroHistory.length - 1) {
            icon.AddClass("history-icon-current");
        }

        icon.SetImage("s2r://panorama/images/heroes/" + heroName + "_png.vtex");
    }
}

/**
 * Called when the server sends 3 hero choices after death
 */
function OnHeroChoices(event) {
    var heroes = [event.hero1, event.hero2, event.hero3];
    var respawnTime = event.respawn_time;

    var overlay = $("#HeroSelectionOverlay");
    var container = $("#HeroChoices");
    if (!overlay || !container) return;

    // Reset state
    isWaitingForRespawn = false;
    container.style.visibility = "visible";
    var title = $("#SelectionTitle");
    if (title) { title.text = "CHOOSE YOUR NEXT HERO"; }
    var timerLabel = $("#SelectionTimer");
    if (timerLabel) { timerLabel.RemoveClass("respawn-countdown"); }

    // Build the 3 hero choice cards
    container.RemoveAndDeleteChildren();

    for (var i = 0; i < heroes.length; i++) {
        (function(heroName) {
            var card = $.CreatePanel("Panel", container, "choice_" + i);
            card.AddClass("hero-choice-card");

            var portrait = $.CreatePanel("Image", card, "portrait_" + i);
            portrait.AddClass("hero-choice-portrait");
            portrait.SetImage("s2r://panorama/images/heroes/" + heroName + "_png.vtex");

            var label = $.CreatePanel("Label", card, "label_" + i);
            label.AddClass("hero-choice-name");
            label.text = heroName.replace("npc_dota_hero_", "").replace(/_/g, " ").toUpperCase();

            // Click to pick this hero
            card.SetPanelEvent("onactivate", function() {
                GameEvents.SendCustomGameEventToServer("turbo_rdm_hero_pick", {
                    hero_name: heroName
                });
                ShowRespawnWait(heroName);
            });
        })(heroes[i]);
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

/**
 * Countdown tick for the selection timer
 */
function TickSelectionTimer() {
    selectionCountdown = selectionCountdown - 1;
    if (selectionCountdown >= 0) {
        UpdateSelectionTimer();
        selectionTimerHandle = $.Schedule(1.0, TickSelectionTimer);
    }
}

/**
 * Update the timer label text
 */
function UpdateSelectionTimer() {
    var timerLabel = $("#SelectionTimer");
    if (timerLabel) {
        if (isWaitingForRespawn) {
            if (selectionCountdown > 0) {
                timerLabel.text = "Respawning in " + selectionCountdown + "s";
            } else {
                timerLabel.text = "Respawning...";
            }
        } else {
            if (selectionCountdown > 0) {
                timerLabel.text = "Auto-selecting in " + selectionCountdown + "s...";
            } else {
                timerLabel.text = "Selecting...";
            }
        }
    }
}

/**
 * Called when the server confirms a hero was chosen (manual or auto).
 * Don't hide — switch to respawn wait mode so the countdown stays visible.
 * The UI is hidden later when turbo_rdm_hero_swap fires for the local player.
 */
function OnHeroChosen() {
    if (!isWaitingForRespawn) {
        ShowRespawnWait("");
    }
}

/**
 * Transition the overlay from hero selection to respawn countdown.
 * Hides the hero cards, updates the title, and keeps the timer ticking.
 */
function ShowRespawnWait(heroName) {
    isWaitingForRespawn = true;

    // Hide the hero choice cards
    var container = $("#HeroChoices");
    if (container) {
        container.style.visibility = "collapse";
    }

    // Update title to show the selected hero
    var title = $("#SelectionTitle");
    if (title) {
        if (heroName && heroName !== "") {
            var displayName = heroName.replace("npc_dota_hero_", "").replace(/_/g, " ").toUpperCase();
            title.text = displayName + " SELECTED";
        } else {
            title.text = "HERO SELECTED";
        }
    }

    // Make the countdown more prominent
    var timerLabel = $("#SelectionTimer");
    if (timerLabel) {
        timerLabel.AddClass("respawn-countdown");
    }

    UpdateSelectionTimer();
}

/**
 * Hide the selection overlay and reset all state
 */
function HideSelectionUI() {
    isWaitingForRespawn = false;

    var overlay = $("#HeroSelectionOverlay");
    if (overlay) {
        overlay.RemoveClass("selection-fade-in");
        overlay.style.visibility = "collapse";
    }

    // Reset title and choices visibility for next death
    var title = $("#SelectionTitle");
    if (title) {
        title.text = "CHOOSE YOUR NEXT HERO";
    }
    var container = $("#HeroChoices");
    if (container) {
        container.style.visibility = "visible";
    }
    var timerLabel = $("#SelectionTimer");
    if (timerLabel) {
        timerLabel.RemoveClass("respawn-countdown");
    }

    if (selectionTimerHandle) {
        $.CancelScheduled(selectionTimerHandle);
        selectionTimerHandle = null;
    }
}

/**
 * Init
 */
(function() {
    InitEvents();
})();
