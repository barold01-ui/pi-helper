-- PowerInfusionAssignments core: the shared namespace, saved-variable setup,
-- the scan ticker, combat/visibility state, the slash command and the event
-- dispatch. The rest of the addon lives in sibling files loaded after this one
-- (see the .toc); each reaches this same PI via `local _, PI = ...`:
--   Roster.lua           roster caches, identity, name/wire helpers, queries
--   Comms.lua            addon-message networking and the !pi report
--   Macro.lua            macro parsing and writing our own PI target
--   AssignmentFrame.lua  the on-screen assignment panel
--   Options.lua          the /pi options window
local _, PI = ...

-- Unique addon-message prefix. Shared with Comms.lua via the PI table since
-- that file also sends/receives on it.
local PI_MSG_PREFIX = "PIAssign"
PI.MSG_PREFIX = PI_MSG_PREFIX

-- Fake test data for test mode. Names are stored unqualified here and get a
-- realm attached by SetTestMode, so they key the same way as real players.
local TEST_ASSIGNMENTS = {
    ["Priest 2"] = "Roguestabber",
    ["Priest 3"] = "Roguestabber",  -- Duplicate target to test warnings
    ["Priest 4"] = "Tankwarrior",
}

-- Persisted debug log (SavedVariable PowerInfusionAssignmentsLog), so a dungeon
-- run can be captured while /pi debug is on and shared afterwards. Written to
-- disk on /reload or logout. Ring-buffered so it can't grow unbounded.
local LOG_MAX = 4000
local function StripColor(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
function PI:LogAppend(msg)
    if type(PowerInfusionAssignmentsLog) ~= "table" then PowerInfusionAssignmentsLog = {} end
    local L = PowerInfusionAssignmentsLog
    if type(L.lines) ~= "table" then L.lines = {} end
    L.lines[#L.lines + 1] = date("%H:%M:%S").."  "..StripColor(tostring(msg))
    local n = #L.lines
    if n > LOG_MAX then
        local drop = n - LOG_MAX
        for i = 1, LOG_MAX do L.lines[i] = L.lines[i + drop] end
        for i = LOG_MAX + 1, n do L.lines[i] = nil end
    end
end

-- Print to chat AND capture to the log. `PI.silentLog` suppresses the chat print
-- (used by the auto-snapshots so they don't spam chat). Status dumps use this.
function PI:Out(msg)
    if not PI.silentLog then print(msg) end
    PI:LogAppend(msg)
end

-- Debug logging, toggled with /pi debug. Prints when on, and always captures to
-- the persisted log while debugging so a shared file has the full trace.
function PI:Debug(fmt, ...)
    if not PI.debugging then return end
    local msg = string.format(fmt, ...)
    print("|cff9cd6ff[PI]|r "..msg)
    PI:LogAppend(msg)
end

-- Periodic notify snapshot into the log while debugging, so a dungeon capture
-- shows how state evolved without the user typing /pi notify repeatedly.
local snapshotTicker
function PI:StartDebugSnapshots()
    if snapshotTicker then return end
    snapshotTicker = C_Timer.NewTicker(20, function()
        if not PI.debugging then return end
        PI.silentLog = true
        PI:LogAppend("--- auto snapshot ---")
        if PI.NotifyStatus then PI:NotifyStatus() end
        PI.silentLog = false
    end)
end
function PI:StopDebugSnapshots()
    if snapshotTicker then snapshotTicker:Cancel(); snapshotTicker = nil end
end

-- Ticker management
local scanTicker = nil

-- Several priests broadcasting inside the same tick would each rebuild the
-- whole display. Coalesce them into one rebuild on the next frame.
local updateQueued = false
local function RunQueuedUpdate()
    updateQueued = false
    PI:UpdateAssignmentFrame()
end

function PI:RequestFrameUpdate()
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0, RunQueuedUpdate)
end

local function StartScanTicker()
    if scanTicker then return end -- Already running
    scanTicker = C_Timer.NewTicker(3, function()
        if PI.inCombat then return end
        -- Zone is the only roster field that changes without an event, so the
        -- tick refreshes just that; everything else waits for a roster update.
        PI:RefreshZones()
        PI:CleanupStaleAssignments()
        PI:UpdateAssignmentFrameVisibility()
        -- non priests don't need to broadcast, exit early
        if not PI.playerIsPriest then return end

        local mode = PowerInfusionAssignmentsDB.piMode or 1
        if mode == 1 then
            -- Mode 1: scan macro for target
            if PowerInfusionAssignmentsDB.macroName and PowerInfusionAssignmentsDB.macroName ~= "" then
                PI:ScanMacroAndSave()
                if not PowerInfusionAssignmentsDB.testMode then
                    PI:BroadcastAssignment()
                end
            end
        else
            -- Mode 2: use mouseover target from PI_SetPITarget macro
            PI:ScanMouseoverAndSave()
            if not PowerInfusionAssignmentsDB.testMode then
                PI:BroadcastAssignment()
            end
        end
    end)
end

local function StopScanTicker()
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
end

function PI:IsScanning()
    return scanTicker ~= nil
end

function PI:InitDB()
    if type(PowerInfusionAssignmentsDB) ~= "table" then PowerInfusionAssignmentsDB = {} end
    -- First run: the saved-variable flag is absent. Set it now and remember, so
    -- login can pop the options window (Setup Guide) once, on fresh installs only.
    PI.firstRun = PowerInfusionAssignmentsDB.hasSeenWelcome == nil
    PowerInfusionAssignmentsDB.hasSeenWelcome = true
    PowerInfusionAssignmentsDB.macroName = PowerInfusionAssignmentsDB.macroName or ""
    PowerInfusionAssignmentsDB.framePos = PowerInfusionAssignmentsDB.framePos or { point = "CENTER", x = 0, y = -200 }
    PowerInfusionAssignmentsDB.piMode = PowerInfusionAssignmentsDB.piMode or 1  -- 1 = macro mode, 2 = mouseover/target mode
    PowerInfusionAssignmentsDB.testMode = false  -- Always reset test mode on login
    -- Assignments are live raid state that every priest rebroadcasts within a
    -- few seconds, so start empty rather than restoring last session's (or
    -- last session's test mode) names.
    PowerInfusionAssignmentsDB.assignments = {}
    PI:ResetPanelDiff()
    if PowerInfusionAssignmentsDB.hideInCombat == nil then PowerInfusionAssignmentsDB.hideInCombat = true end
    if PowerInfusionAssignmentsDB.enableWhispers == nil then PowerInfusionAssignmentsDB.enableWhispers = false end
    PowerInfusionAssignmentsDB.scale = PowerInfusionAssignmentsDB.scale or 1
    PowerInfusionAssignmentsDB.optionsScale = PowerInfusionAssignmentsDB.optionsScale or 1
    if PowerInfusionAssignmentsDB.showForNonPriest == nil then PowerInfusionAssignmentsDB.showForNonPriest = false end
    if PowerInfusionAssignmentsDB.lockFrame == nil then PowerInfusionAssignmentsDB.lockFrame = true end
    PI:InitTrackingDB()

    PI:SetIdentity(UnitFullName("player"))
    PI.playerIsPriest = select(2, UnitClass("player")) == "PRIEST"
end

function PI:SetTestMode(enabled)
    PowerInfusionAssignmentsDB.testMode = enabled
    if enabled then
        -- Save real assignments before wiping
        PI.realAssignments = {}
        for k, v in pairs(PowerInfusionAssignmentsDB.assignments) do
            PI.realAssignments[k] = v
        end
        wipe(PowerInfusionAssignmentsDB.assignments)
        -- Restore the player's real assignment if it exists
        local myName = PI:GetPlayerName()
        if PI.realAssignments[myName] then
            PowerInfusionAssignmentsDB.assignments[myName] = PI.realAssignments[myName]
        end
        -- Populate fake data for other priests
        for priest, target in pairs(TEST_ASSIGNMENTS) do
            PowerInfusionAssignmentsDB.assignments[PI:Qualify(priest)] = PI:Qualify(target)
        end
        -- The macro scan only runs on the ticker in a raid, so solo (the usual
        -- test-mode case) our own target is never populated and the self row
        -- shows "(none)". Scan it now so test mode shows our real assignment.
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        if mode == 1 then
            PI:ScanMacroAndSave()
        else
            PI:ScanMouseoverAndSave()
        end
    else
        wipe(PowerInfusionAssignmentsDB.assignments)
        -- Restore real assignments if they were saved
        if PI.realAssignments then
            for k, v in pairs(PI.realAssignments) do
                PowerInfusionAssignmentsDB.assignments[k] = v
            end
            PI.realAssignments = nil
        end
    end
    PI:RefreshRoster()  -- adds or drops the fake class colours
    PI:UpdateAssignmentFrame()
    PI:UpdateAssignmentFrameVisibility()
    PI:UpdateTickerState()
    if PI.QueueGlowUpdate then PI:QueueGlowUpdate() end
end

function PI:DumpState()
    local db = PowerInfusionAssignmentsDB
    PI:Out("|cff9cd6ff[PI]|r debug "..(PI.debugging and "ON" or "OFF"))
    PI:Out(string.format("  me=%s realm=%s priest=%s inRaid=%s inCombat=%s",
        tostring(PI:GetPlayerName()), tostring(PI.myRealm or ""),
        tostring(PI.playerIsPriest), tostring(IsInRaid()), tostring(PI.inCombat)))
    local _, instanceType = GetInstanceInfo()
    PI:Out(string.format("  zone=%s instanceType=%s groupSize=%d ticker=%s",
        tostring(GetZoneText()), tostring(instanceType), GetNumGroupMembers(),
        tostring(PI:IsScanning())))
    PI:Out(string.format("  mode=%d macro=%s testMode=%s lastBroadcast=%s",
        db.piMode or 1, tostring(db.macroName), tostring(db.testMode),
        tostring(PI.lastBroadcastedTarget)))
    local n = 0
    for player, target in pairs(db.assignments) do
        n = n + 1
        PI:Out(string.format("  [%s] -> %s  inGroup=%s sameZone=%s role=%s",
            player, tostring(target), tostring(PI:IsPlayerInGroup(player)),
            tostring(PI:IsPlayerInSameZone(player)), tostring(PI:GetRoleForName(target))))
    end
    if n == 0 then PI:Out("  (no assignments)") end
end

SLASH_POWERINFUSION1 = "/pi"
SlashCmdList["POWERINFUSION"] = function(msg)
    local cmd = strlower(strtrim(msg or ""))
    if cmd == "debug" then
        -- The one command for capturing a session: toggles debug printing +
        -- logging to file, dumps a snapshot, and auto-snapshots while on.
        PI.debugging = not PI.debugging
        if PI.debugging then
            PowerInfusionAssignmentsLog = { lines = {} }   -- fresh capture each time
            PI:LogAppend("========== DEBUG SESSION START ==========")
            print("|cff9cd6ff[PI]|r debug ON - capturing to a log file.")
            print("  Play/run your dungeon, then |cffffff00/reload|r (or log out) and send me:")
            print("  WTF\\Account\\<ACCOUNT>\\SavedVariables\\PowerInfusionAssignments.lua")
            print("  helpers: /pi watchself (solo test) - /pi testglow (preview) - /pi notify (snapshot) - /pi log (info/clear)")
            PI:DumpState()
            if PI.NotifyStatus then PI:NotifyStatus() end
            PI:StartDebugSnapshots()
        else
            PI:StopDebugSnapshots()
            PI:LogAppend("========== DEBUG SESSION END ==========")
            print("|cff9cd6ff[PI]|r debug OFF. |cffffff00/reload|r or log out to write the log to disk.")
        end
        return
    elseif cmd == "log" or cmd == "log clear" then
        if cmd == "log clear" then
            PowerInfusionAssignmentsLog = { lines = {} }
            print("|cff9cd6ff[PI]|r debug log cleared.")
        else
            local L = PowerInfusionAssignmentsLog
            local n = (type(L) == "table" and type(L.lines) == "table") and #L.lines or 0
            print(string.format("|cff9cd6ff[PI]|r debug log has %d line(s). |cffffff00/reload|r or log out to write it to disk, then send:", n))
            print("  WTF\\Account\\<ACCOUNT>\\SavedVariables\\PowerInfusionAssignments.lua")
            print("  /pi log clear  - wipe the log")
        end
        return
    elseif cmd == "status" then
        PI:DumpState()
        return
    elseif cmd == "notify" then
        if PI.NotifyStatus then PI:NotifyStatus() end
        return
    elseif cmd == "testglow" then
        if PI.ToggleEffectTest then PI:ToggleEffectTest() end
        return
    elseif cmd == "watchself" then
        PI.watchSelf = not PI.watchSelf
        print("|cff9cd6ff[PI]|r watch-self test mode " .. (PI.watchSelf
            and "ON - watching your OWN buffs (any spec, works solo). Add a spammable self-buff's spell ID as a custom spell in the Tracking tab, then cast it on yourself. With no raid/party cell the glow shows on a box in the screen centre."
            or "OFF"))
        if PI.QueueGlowUpdate then PI:QueueGlowUpdate() end
        return
    elseif cmd == "welcome" then
        -- Clear the first-run flag so the next /reload replays the auto-open, and
        -- open the window now (on the Setup Guide) to check it immediately.
        PowerInfusionAssignmentsDB.hasSeenWelcome = nil
        PI:CreateOptionsWindow()
        if PI.options.SelectSection then PI.options.SelectSection("setup") end
        PI.options:Show()
        print("|cff9cd6ff[PI]|r first-run flag cleared - the Setup Guide will auto-open on your next /reload.")
        return
    end
    PI:CreateOptionsWindow()
    if PI.options:IsShown() then
        PI.options:Hide()
    else
        PI.options:Show()
        PI.options.edit:SetText(PowerInfusionAssignmentsDB.macroName or "")
    end
end

PI.inCombat = false

function PI:UpdateAssignmentFrameVisibility()
    if not PI.frame then return end
    -- Test mode bypasses all other visibility criteria
    if PowerInfusionAssignmentsDB.testMode then
        PI.frame:Show()
        return
    end
    -- Check visibility for priests and non-priests
    local shouldShow = (PI.playerIsPriest or PowerInfusionAssignmentsDB.showForNonPriest) and next(PowerInfusionAssignmentsDB.assignments) ~= nil
    if not shouldShow then
        PI.frame:Hide()
        return
    end
    -- Hide during combat if option is enabled
    if PI.inCombat and PowerInfusionAssignmentsDB.hideInCombat then
        PI.frame:Hide()
    elseif IsInRaid() then
        PI.frame:Show()
    else
        PI.frame:Hide()
    end
end

function PI:UpdateFrameLock()
    if not PI.frame then return end
    if PowerInfusionAssignmentsDB.lockFrame then
        PI.frame:SetMovable(false)
        PI.frame:EnableMouse(false)
    else
        PI.frame:SetMovable(true)
        PI.frame:EnableMouse(true)
    end
end

function PI:CleanupStaleAssignments()
    -- Don't cleanup in test mode, we want to keep the fake data
    if PowerInfusionAssignmentsDB.testMode then return end

    local myName = PI:GetPlayerName()
    local changed = false
    -- Only drop priests who actually left the group. Out-of-zone ones are
    -- filtered at display time instead, so a loading screen can't clear the
    -- list and force everyone to rebroadcast.
    for player in pairs(PowerInfusionAssignmentsDB.assignments) do
        if player ~= myName and not PI:IsPlayerInGroup(player) then
            PI:Debug("cleanup dropped %s (not in group)", player)
            PowerInfusionAssignmentsDB.assignments[player] = nil
            changed = true
        end
    end

    if changed then
        PI:RequestFrameUpdate()
    end
end

function PI:UpdateTickerState()
    local db = PowerInfusionAssignmentsDB
    -- Also run in a 5-man party for a priest when dungeon alerts are on, so the
    -- macro scan keeps your PI target populated for "assignment" dungeon mode.
    local dungeonActive = PI.playerIsPriest and db.dungeonMode and db.dungeonMode ~= "off"
        and IsInGroup() and not IsInRaid()
    if not PI.inCombat and (
        ((PI.playerIsPriest or db.showForNonPriest) and IsInRaid())
        or dungeonActive
    ) then
        StartScanTicker()
    else
        StopScanTicker()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
f:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
f:RegisterEvent("CHAT_MSG_RAID")
f:RegisterEvent("CHAT_MSG_RAID_LEADER")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- Player-only: own spec is readable, party/raid spec payloads are secret in combat.
f:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

-- Re-point the notify glow after anything that could change our target, their
-- cell, our spec, or the PI-ready gate. Guarded so a feature-module load failure
-- can never break the core event loop.
local function RefreshNotify()
    if PI.InvalidateFrameCache then PI:InvalidateFrameCache() end
    if PI.QueueGlowUpdate then PI:QueueGlowUpdate() end
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(PI_MSG_PREFIX)
        PI:InitDB()
        print("[PI] To configure Power Infusion Assignment Helper, type /pi")
        PI:RefreshRoster()
        PI:CreateAssignmentFrame()
        PI:CreateOptionsWindow()
        PI:UpdateAssignmentFrame()
        PI:UpdateAssignmentFrameVisibility()
        -- Start ticker only if in raid or test mode
        PI:UpdateTickerState()
        RefreshNotify()
        -- First install: open the options window (defaults to the Setup Guide)
        -- so a new user isn't left guessing. Only ever happens once.
        if PI.firstRun and PI.options then
            PI.options:Show()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zones and roster data are only valid again once the loading screen
        -- is done, and PLAYER_LOGIN doesn't fire on a zone-in or a reload.
        if PI.fullName then
            PI:RefreshRoster()
            PI:UpdateAssignmentFrame()
            PI:UpdateAssignmentFrameVisibility()
            PI:UpdateTickerState()
            RefreshNotify()
            -- A reload leaves us with an empty table, and nothing on the other
            -- clients prompts them to re-send, so ask. Skipped once we know
            -- about anyone, which keeps ordinary loading screens quiet.
            C_Timer.After(3, function()
                local myName = PI:GetPlayerName()
                for player in pairs(PowerInfusionAssignmentsDB.assignments) do
                    if player ~= myName then return end
                end
                PI:RequestAssignments()
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        PI.inCombat = true
        PI:UpdateAssignmentFrameVisibility()
        PI:UpdateTickerState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        PI.inCombat = false
        PI:UpdateAssignmentFrameVisibility()
        PI:UpdateTickerState()
        -- Combat ended: refresh the target cell now that unit tokens are readable
        -- again (they can be secret in combat).
        RefreshNotify()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        PI:OnAddonMessage(prefix, message, channel, sender)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Fires several times in a row when a raid forms up
        PI:RefreshRoster()
        PI:CleanupStaleAssignments()
        PI:RequestFrameUpdate()
        PI:UpdateAssignmentFrameVisibility()
        PI:UpdateTickerState()
        RefreshNotify()
        -- Broadcast current assignment to new group members
        if PI.playerIsPriest and IsInRaid() and not PowerInfusionAssignmentsDB.testMode then
            PI:BroadcastAssignment(true)
        end
    elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER"
        or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        local message, sender = ...
        PI:OnChatMessage(message, sender)
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        PI:RefreshRoster()
        PI:CleanupStaleAssignments()
        PI:RequestFrameUpdate()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Swapping to/from a healer spec turns the notify feature on or off.
        RefreshNotify()
    end
end)
