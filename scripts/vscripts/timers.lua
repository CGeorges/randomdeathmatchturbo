--------------------------------------------------------------------------------
-- Timers utility for Dota 2 custom games
-- Lightweight timer system (standard in most custom game templates)
--------------------------------------------------------------------------------

if Timers == nil then
    Timers = class({})
end

Timers.timers = {}
Timers.nextID = 0

function Timers:CreateTimer(delay, callback)
    local id = self.nextID
    self.nextID = self.nextID + 1

    self.timers[id] = {
        endTime  = GameRules:GetGameTime() + delay,
        callback = callback,
    }

    if not self._thinking then
        self._thinking = true
        GameRules:GetGameModeEntity():SetThink("_TimersTick", self, "TimersThink", 0.03)
    end

    return id
end

function Timers:RemoveTimer(id)
    self.timers[id] = nil
end

function Timers:_TimersTick()
    local now = GameRules:GetGameTime()
    local toRemove = {}

    for id, timer in pairs(self.timers) do
        if now >= timer.endTime then
            local result = timer.callback()
            if type(result) == "number" then
                timer.endTime = now + result  -- Reschedule
            else
                table.insert(toRemove, id)
            end
        end
    end

    for _, id in ipairs(toRemove) do
        self.timers[id] = nil
    end

    -- Keep ticking as long as timers exist
    if next(self.timers) then
        return 0.03
    else
        self._thinking = false
        return nil
    end
end
