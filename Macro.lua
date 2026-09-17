-- Macro parsing, the mouseover capture, and writing our own PI target.
local _, PI = ...

-- Macro parse cache
local cachedMacroTarget = nil
local cachedMacroBody = nil
local cachedMacroIndex = nil
local cachedMacroName = nil

PI.previousTarget = nil

function PI:FindMacroIndexByName(name)
    if not name or name == "" then return nil end
    if GetMacroIndexByName then
        local idx = GetMacroIndexByName(name)
        if idx and idx > 0 then return idx end
    end
    local num = GetNumMacros()
    for i = 1, num do
        local mname = select(1, GetMacroInfo(i))
        if mname == name then return i end
    end
    return nil
end

local IGNORED_TOKENS = {
    mouseover=true, target=true, focus=true, player=true, pet=true, vehicle=true,
    exists=true, nodead=true, help=true, harm=true, nouser=true, caster=true, cursor=true,
}

local function isIgnoredToken(tok)
    if not tok then return true end
    return IGNORED_TOKENS[strlower(tok)]
end

function PI:ParseMacroForTarget(macroIndex)
    if not macroIndex then return nil end
    local body = select(3, GetMacroInfo(macroIndex))
    if not body or body == "" then return nil end
    -- search for @Name occurrences and target=Name occurrences
    -- Use [^%],;%[%]%s]+ to match any characters except delimiters (supports Unicode names)
    for token in string.gmatch(body, "@([^%],;%[%]%s]+)") do
        if not isIgnoredToken(token) then
            return token
        end
    end
    for token in string.gmatch(body, "target=([^%],;%[%]%s]+)") do
        if not isIgnoredToken(token) then
            return token
        end
    end
    return nil
end

-- Global function for macro to call (captures mouseover target)
function PI_SetPITarget()
    local name = PI:GetUnitName("mouseover")
    if not name then
        return
    end
    PI.mouseoverTarget = name
    print("PI target set to: "..PI:ShortName(name))
end

-- Single entry point for "my PI target is now X": handles the whispers and
-- writes the assignment. Both scan modes end up here.
function PI:SetMyTarget(target)
    if not target or target == "" then return end
    local player = PI:GetPlayerName()
    local oldTarget = PI.previousTarget

    -- Whispers fire on a real change of target only
    if oldTarget ~= target then
        if PowerInfusionAssignmentsDB.enableWhispers then
            -- Only guild members who are actually in the raid, and never ourselves
            if oldTarget and oldTarget ~= "" and oldTarget ~= player
                and PI:IsPlayerInGuild(oldTarget) and PI:IsPlayerInGroup(oldTarget) then
                SendChatMessage("You no longer have PI", "WHISPER", nil, oldTarget)
            end
            if target ~= player and PI:IsPlayerInGuild(target) and PI:IsPlayerInGroup(target) then
                SendChatMessage("PI set to you", "WHISPER", nil, target)
            end
        end
        PI.previousTarget = target
        -- Point the notify glow at the new target.
        if PI.QueueGlowUpdate then PI:QueueGlowUpdate() end
    end

    -- Written unconditionally so our own row comes back if anything ever
    -- clears it, without waiting for the macro to change
    if PowerInfusionAssignmentsDB.assignments[player] ~= target then
        PowerInfusionAssignmentsDB.assignments[player] = target
        PI:RequestFrameUpdate()
    end
end

function PI:ScanMacroAndSave()
    if PI.inCombat then
        return false
    end

    local macroName = PowerInfusionAssignmentsDB.macroName
    if not macroName or macroName == "" then
        return false
    end
    if macroName ~= cachedMacroName then
        cachedMacroName = macroName
        cachedMacroIndex = PI:FindMacroIndexByName(macroName)
    end
    if not cachedMacroIndex then
        return false
    end
    -- Macro indices shift when the player adds or deletes macros, so confirm
    -- the cached index still points at the macro we were asked for.
    local foundName, _, body = GetMacroInfo(cachedMacroIndex)
    if foundName ~= macroName then
        cachedMacroIndex = PI:FindMacroIndexByName(macroName)
        if not cachedMacroIndex then return false end
        foundName, _, body = GetMacroInfo(cachedMacroIndex)
    end
    if body ~= cachedMacroBody then
        cachedMacroBody = body
        cachedMacroTarget = PI:ParseMacroForTarget(cachedMacroIndex)
    end
    if not cachedMacroTarget then
        return false
    end
    PI:SetMyTarget(PI:ResolveName(cachedMacroTarget))
    return true
end

-- Mode 2: Use the mouseover target set by PI_SetPITarget macro
function PI:ScanMouseoverAndSave()
    local target = PI.mouseoverTarget
    if not target or target == "" then
        return false
    end
    PI:SetMyTarget(target)
    return true
end
