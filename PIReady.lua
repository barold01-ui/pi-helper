-- Tracks whether our own Power Infusion is ready, so the notify glow only fires
-- when we can actually cast it. Own casts are readable even under 12.0
-- secret-value rules (RegisterUnitEvent on "player"), and GetSpellCooldown's
-- isActive flag is never secret, so we can notice an early reset. The live
-- remaining time IS secret in combat, so we never read it -- we start a fixed
-- 120s lock on cast and poll isActive to release early if a reset (M+ CDR)
-- ends the cooldown sooner. The lock is session-only; a /reload assumes ready.
local _, PI = ...

local PI_SPELL_ID = 10060      -- Power Infusion
local PI_CD = 120              -- base cooldown, seconds
local PI_SETTLE = 100          -- only poll isActive after this (avoids a false
                               -- "ready" right after the cast event)

local cdEndsAt                 -- GetTime() when PI is ready again; nil = ready
local releaseTimer
local settleTimer
local pollTicker

function PI:IsPIReady()
    if not cdEndsAt then return true end
    return (cdEndsAt - GetTime()) <= 0
end

-- Fired whenever ready-state flips, so the glow re-evaluates (shows again when PI
-- comes back off cooldown; SetEnabled is combat-safe, so this works mid-fight).
local function OnReadyStateChanged()
    if PI.QueueGlowUpdate then PI:QueueGlowUpdate() end
end

local function StopTimers()
    if releaseTimer then releaseTimer:Cancel(); releaseTimer = nil end
    if settleTimer then settleTimer:Cancel(); settleTimer = nil end
    if pollTicker then pollTicker:Cancel(); pollTicker = nil end
end

local function ClearLock(silent)
    StopTimers()
    local wasLocked = cdEndsAt ~= nil
    cdEndsAt = nil
    if wasLocked and not silent then OnReadyStateChanged() end
end

-- isActive is NeverSecret: true while PI is on cooldown, false once ready.
local function PICooldownActive()
    if not C_Spell or not C_Spell.GetSpellCooldown then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, PI_SPELL_ID)
    if not ok or type(info) ~= "table" then return nil end
    local active = info.isActive
    if type(active) ~= "boolean" then return nil end
    return active
end

local function StartPoll()
    if pollTicker then pollTicker:Cancel() end
    pollTicker = C_Timer.NewTicker(1, function()
        if not cdEndsAt then
            if pollTicker then pollTicker:Cancel(); pollTicker = nil end
            return
        end
        if PICooldownActive() == false then
            PI:Debug("PI cooldown ended early (reset); releasing lock")
            ClearLock()
        end
    end)
end

local function ArmLock()
    StopTimers()
    cdEndsAt = GetTime() + PI_CD
    releaseTimer = C_Timer.NewTimer(PI_CD, function()
        releaseTimer = nil
        cdEndsAt = nil
        OnReadyStateChanged()
    end)
    settleTimer = C_Timer.NewTimer(PI_SETTLE, function()
        settleTimer = nil
        if cdEndsAt then StartPoll() end
    end)
end

function PI:OnPICast()
    PI:Debug("own Power Infusion cast; gating notify for %ds", PI_CD)
    ArmLock()
    -- PI is now on cooldown: disable the glow (SetEnabled is combat-safe), so it
    -- hides while PI is down and shows again when PI is ready.
    if PI.QueueGlowUpdate then PI:QueueGlowUpdate() end
end

-- Raid boss kill/wipe resets cooldowns; dungeon/M+ bosses fire ENCOUNTER_END
-- too but do NOT reset them, so gate on the difficulty's group type.
local function EncounterEndResetsCooldowns(difficultyID)
    if type(difficultyID) ~= "number" then return false end
    if not GetDifficultyInfo then return false end
    local ok, _, groupType, _, isChallenge = pcall(GetDifficultyInfo, difficultyID)
    if not ok then return false end
    if isChallenge == true then return false end
    return groupType == "raid"
end

local f = CreateFrame("Frame")
-- Player-only: RegisterEvent would also deliver party/raid casts whose payload
-- is secret in combat and errors when read.
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("CHALLENGE_MODE_START")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and spellID == PI_SPELL_ID then
            PI:OnPICast()
        end
    elseif event == "CHALLENGE_MODE_START" then
        ClearLock()
    elseif event == "ENCOUNTER_END" then
        local _, _, difficultyID = ...
        if EncounterEndResetsCooldowns(difficultyID) then
            ClearLock()
        end
    end
end)
