local PI = {}
local PI_MSG_PREFIX = "PIAssign"

-- Sent after a reload to ask the other priests to re-announce. A 1.4.x client
-- splits this on ":" , gets no second field and drops it, so it is safe to
-- send into a mixed raid.
local PI_MSG_REQUEST = "?"

-- Fake test data for test mode. Names are stored unqualified here and get a
-- realm attached by SetTestMode, so they key the same way as real players.
local TEST_ASSIGNMENTS = {
    ["Priest 2"] = "Roguestabber",
    ["Priest 3"] = "Roguestabber",  -- Duplicate target to test warnings
    ["Priest 4"] = "Tankwarrior",
}

-- Class colors for fake test data (priest = white, others = class colors)
local TEST_CLASS_COLORS = {
    ["Priest 2"] = "|cffFFFFFF",      -- White (Priest)
    ["Priest 3"] = "|cffFFFFFF",      -- White (Priest)
    ["Priest 4"] = "|cffFFFFFF",      -- White (Priest)
    ["Roguestabber"] = "|cffFFF468",  -- Rogue yellow
    ["Tankwarrior"] = "|cffC69B6D",   -- Warrior brown
}

-- Roster caches, all keyed by realm-qualified name. Rebuilt as one pass by
-- PI:RefreshRoster(); nothing else may write to them.
local groupMembers = {}
local memberZones = {}
local memberRoles = {}
local memberInGuild = {}
local classColorCache = {}
local shortToFull = {}    -- "Name" -> "Name-Realm", for names off the wire
local rosterNames = {}    -- raid index -> qualified name, until the next rebuild
local rosterCount = 0

-- "raid1".."raid40", built once instead of concatenating them every pass.
local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid"..i end

-- Scratch tables reused so the 3 second ticker doesn't churn garbage.
local reuseErrorLines = {}
local reusePriests = {}
local reuseReport = {}
local reuseTargetCounts = {}

-- The panel is drawn from row descriptors rather than one concatenated string,
-- so these are the two halves of the display diff: reuseRows is rebuilt every
-- update, lastRows mirrors what is actually on screen. Both hold the same
-- tables from update to update; only their fields are overwritten.
local reuseRows = {}
local reuseRowCount = 0
local lastRows = {}
local lastRowCount = -1   -- -1 so the first update always draws

-- Macro parse cache
local cachedMacroTarget = nil
local cachedMacroBody = nil
local cachedMacroIndex = nil
local cachedMacroName = nil

-- Resolved once at login; every stored name is qualified against this realm.
local myFullName = nil
local myRealm = nil

-- Session-only debug logging, toggled with /pi debug. Not a saved variable:
-- it should never survive a reload and there is no option for it.
function PI:Debug(fmt, ...)
    if not PI.debugging then return end
    print("|cff9cd6ff[PI]|r "..string.format(fmt, ...))
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

-- Names are stored realm-qualified ("Name-Realm") everywhere. A short name is
-- ambiguous across connected realms, and mixing the two forms was silently
-- dropping cross-realm priests out of the group and role checks.
function PI:Qualify(name, realm)
    if not name or name == "" then return nil end
    if realm and realm ~= "" then return name.."-"..realm end
    if string.find(name, "-", 1, true) then return name end
    if not myRealm or myRealm == "" then return name end
    return name.."-"..myRealm
end

function PI:ShortName(name)
    if not name or name == "" then return name end
    return (strsplit("-", name))
end

function PI:GetUnitName(unit)
    local name, realm = UnitName(unit)
    return PI:Qualify(name, realm)
end

-- Realm names can contain a hyphen ("Azjol-Nerub"), so the realm is everything
-- after the *first* separator rather than the second field of a split.
local function RealmOf(fullName)
    local sep = string.find(fullName, "-", 1, true)
    if sep then return string.sub(fullName, sep + 1) end
    return myRealm
end

-- Wire format, for compatibility with 1.4.x clients still in the raid. 1.4.x
-- keyed everything off UnitName, which only appends a realm when it differs
-- from the reader's, so we emit that same shape and put the realm back on
-- receipt using the sender's. A 1.4.x client therefore sees exactly what
-- another 1.4.x client would have sent it.
function PI:ToWire(fullName)
    if not fullName or fullName == "" then return "" end
    if RealmOf(fullName) == myRealm then return PI:ShortName(fullName) end
    return fullName
end

function PI:FromWire(name, senderRealm)
    if not name or name == "" then return nil end
    if string.find(name, "-", 1, true) then return name end
    local guess = name.."-"..(senderRealm or myRealm)
    if groupMembers[guess] then return guess end
    -- 1.4.x sent bare names even for cross-realm targets, so fall back to
    -- whoever in the raid actually answers to this name.
    return shortToFull[name] or guess
end

function PI:GetPlayerName()
    return myFullName or "Unknown"
end

-- Macro bodies contain whatever the player typed, which is usually just a
-- first name. Match it against the roster so a cross-realm target keeps its
-- own realm instead of being silently reassigned to ours.
function PI:ResolveName(name)
    if not name or name == "" then return nil end
    if string.find(name, "-", 1, true) then return name end
    return shortToFull[name] or PI:Qualify(name)
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

function PI:GetClassColorForUnit(unit)
    if not unit or not UnitExists(unit) then return nil end
    local _, classFile = UnitClass(unit)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return nil
end

-- One pass over the raid fills every per-member cache. Zone comes from
-- GetRaidRosterInfo (GetZoneText only ever reports our own zone, whatever
-- unit you pass it) and guild membership from UnitIsInMyGuild, which needs
-- no roster request the way GetGuildRosterInfo does.
function PI:RefreshRoster()
    wipe(groupMembers)
    wipe(memberZones)
    wipe(memberRoles)
    wipe(memberInGuild)
    wipe(classColorCache)
    wipe(shortToFull)
    wipe(rosterNames)
    rosterCount = IsInRaid() and GetNumGroupMembers() or 0

    local myName = PI:GetPlayerName()
    groupMembers[myName] = true
    memberZones[myName] = GetZoneText() or ""
    memberRoles[myName] = UnitGroupRolesAssigned("player")
    memberInGuild[myName] = true
    classColorCache[myName] = PI:GetClassColorForUnit("player")
    shortToFull[PI:ShortName(myName)] = myName

    for i = 1, rosterCount do
        local unit = RAID_UNITS[i]
        if unit and UnitExists(unit) and UnitIsConnected(unit) then
            local fullName = PI:GetUnitName(unit)
            if fullName and fullName ~= myName then
                local _, _, _, _, _, _, zone = GetRaidRosterInfo(i)
                rosterNames[i] = fullName
                groupMembers[fullName] = true
                memberZones[fullName] = zone
                memberRoles[fullName] = UnitGroupRolesAssigned(unit)
                memberInGuild[fullName] = UnitIsInMyGuild(unit) and true or false
                classColorCache[fullName] = PI:GetClassColorForUnit(unit)
                -- First one wins, so two same-named players from different
                -- realms resolve the way the roster is ordered rather than randomly.
                local short = PI:ShortName(fullName)
                if not shortToFull[short] then shortToFull[short] = fullName end
            end
        end
    end

    -- Test mode's fake priests aren't on the roster, so re-add their colours.
    if PowerInfusionAssignmentsDB.testMode then
        for name, color in pairs(TEST_CLASS_COLORS) do
            classColorCache[PI:Qualify(name)] = color
        end
    end
end

-- Called every tick. Raid indices only shift on a GROUP_ROSTER_UPDATE, which
-- does the full rebuild, so the cached names still line up; the size check is
-- there in case that event is ever missed.
function PI:RefreshZones()
    if (IsInRaid() and GetNumGroupMembers() or 0) ~= rosterCount then
        return PI:RefreshRoster()
    end
    memberZones[PI:GetPlayerName()] = GetZoneText() or ""
    for i = 1, rosterCount do
        local fullName = rosterNames[i]
        if fullName then
            local _, _, _, _, _, _, zone = GetRaidRosterInfo(i)
            memberZones[fullName] = zone
        end
    end
end

function PI:GetClassColorForName(name)
    if not name or name == "" then return nil end
    return classColorCache[name]
end

-- The roster cache stores colours as "|cffRRGGBB" escape codes. The panel
-- colours FontStrings directly, so unpack the hex into 0-1 RGB. Keyed by the
-- code string, which only ever holds one entry per class.
local classRGBCache = {}
function PI:GetClassRGB(name)
    local code = PI:GetClassColorForName(name)
    if not code then return 1, 1, 1 end
    local rgb = classRGBCache[code]
    if not rgb then
        local r, g, b = string.match(code, "|c%x%x(%x%x)(%x%x)(%x%x)")
        if not r then return 1, 1, 1 end
        rgb = { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
        classRGBCache[code] = rgb
    end
    return rgb[1], rgb[2], rgb[3]
end

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

function PI:IsPlayerInGuild(playerName)
    if not playerName then return false end
    return memberInGuild[playerName] or false
end

function PI:IsPlayerInGroup(playerName)
    if not playerName or playerName == "" then return false end
    return groupMembers[playerName] or false
end

function PI:IsPlayerInZone(playerName, zone)
    if not PI:IsPlayerInGroup(playerName) then return false end
    local playerZone = memberZones[playerName]
    -- The roster reports no zone for a moment after a loading screen; treat
    -- that as a match rather than flapping the display and the warnings.
    if not playerZone or playerZone == "" then return true end
    return playerZone == zone
end

function PI:IsPlayerInSameZone(playerName)
    return PI:IsPlayerInZone(playerName, GetZoneText() or "")
end

function PI:GetZoneOfPlayer(playerName)
    return memberZones[playerName]
end

function PI:GetRoleForName(name)
    if not name then return nil end
    return memberRoles[name]
end

PI.previousTarget = nil
PI.lastBroadcastedTarget = nil

function PI:BroadcastAssignment(force)
    if not PI.playerIsPriest then return end
    if not IsInRaid() then return end
    local target = PowerInfusionAssignmentsDB.assignments[PI:GetPlayerName()]
    if not target or target == "" then return end
    -- Only record the send after the guards above, or joining a raid with an
    -- unchanged target would look already-broadcast and stay silent.
    if not force and target == PI.lastBroadcastedTarget then return end
    PI.lastBroadcastedTarget = target

    -- Payload keeps the 1.4.x "Player:Target" shape and naming. We ignore the
    -- name field on receipt (see OnAddonMessage) but 1.4.x clients key off it.
    local payload = PI:ToWire(PI:GetPlayerName())..":"..PI:ToWire(target)
    -- Use RAID channel for more reliable communication in instances
    PI:Debug("send %s", payload)
    C_ChatInfo.SendAddonMessage(PI_MSG_PREFIX, payload, "RAID")
end

function PI:RequestAssignments()
    if not IsInRaid() then return end
    if PowerInfusionAssignmentsDB.testMode then return end
    PI:Debug("asking the raid to re-announce")
    C_ChatInfo.SendAddonMessage(PI_MSG_PREFIX, PI_MSG_REQUEST, "RAID")
end

function PI:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PI_MSG_PREFIX then return end
    PI:Debug("recv channel=%s sender=%s msg=%s", tostring(channel), tostring(sender), tostring(message))
    -- Deliberately no channel filter. The prefix is already unique to us, and
    -- filtering on the reported channel dropped every message in a raid group
    -- that wasn't an instance group.
    -- Key the assignment off the sender the server reports rather than the
    -- name in the payload, so nobody can post under another priest's name.
    local from = PI:Qualify(sender)
    if not from or from == PI:GetPlayerName() then return end

    -- Someone reloaded and lost their copy. Re-announce ours even though it
    -- hasn't changed, staggered so a raid full of priests doesn't answer in
    -- the same frame.
    if message == PI_MSG_REQUEST then
        if PI.playerIsPriest and not PowerInfusionAssignmentsDB.testMode then
            PI:Debug("%s asked for assignments, re-announcing", from)
            C_Timer.After(math.random() * 2, function() PI:BroadcastAssignment(true) end)
        end
        return
    end

    local _, target = strsplit(":", message)
    if not target or target == "" then return end
    -- An unqualified target is on the sender's realm, not ours
    local resolved = PI:FromWire(target, RealmOf(from))
    PI:Debug("stored [%s] -> %s", from, tostring(resolved))
    PowerInfusionAssignmentsDB.assignments[from] = resolved
    PI:RequestFrameUpdate()
end

local function ByNameLower(a, b) return strlower(a) < strlower(b) end

function PI:ReportAssignmentsToChat(zone)
    if not zone or zone == "" then return end
    if not IsInRaid() then return end

    -- Collect priests in the same zone as requester
    wipe(reusePriests)
    for player, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if target and target ~= "" and PI:IsPlayerInZone(player, zone) then
            reusePriests[#reusePriests + 1] = player
        end
    end

    if #reusePriests == 0 then return end

    -- Every priest running the addon hears the !pi, so elect one responder.
    table.sort(reusePriests, ByNameLower)
    if reusePriests[1] ~= PI:GetPlayerName() then return end

    local chatType = "INSTANCE_CHAT"
    -- Fall back to raid chat if not in instance group
    if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        chatType = "RAID"
    end

    wipe(reuseReport)
    for i = 1, #reusePriests do
        local player = reusePriests[i]
        local target = PowerInfusionAssignmentsDB.assignments[player]
        reuseReport[#reuseReport + 1] = PI:ShortName(player).." -> "..PI:ShortName(target)
    end

    -- Pack several assignments per line. One message per priest is an easy
    -- way to hit the chat throttle (and get disconnected) in a full raid.
    local line = nil
    for i = 1, #reuseReport do
        local candidate = line and (line.." | "..reuseReport[i]) or ("[PI] "..reuseReport[i])
        if #candidate > 240 then
            SendChatMessage(line, chatType)
            line = "[PI] "..reuseReport[i]
        else
            line = candidate
        end
    end
    if line then
        SendChatMessage(line, chatType)
    end
end

local REPORT_COOLDOWN = 10

function PI:OnChatMessage(message, sender)
    if PI.inCombat then return end
    -- 12.0 can hand chat payloads to addon code as secret values: reading one
    -- while our own code is on the stack errors, and #message below is the
    -- first thing that touches it. Nothing to do with a secret line but drop
    -- it -- the client is refusing to let us read the raid's chat at all.
    if issecretvalue and (issecretvalue(message) or issecretvalue(sender)) then return end
    -- Raid chat is busy; bail on length before allocating the lowered/trimmed
    -- copies, since every line in the raid comes through here.
    if not message or #message > 8 then return end
    if strlower(strtrim(message)) ~= "!pi" then return end
    -- Anyone can type !pi, so rate limit it before it can spam raid chat.
    local now = GetTime()
    if PI.lastReportTime and (now - PI.lastReportTime) < REPORT_COOLDOWN then return end
    PI.lastReportTime = now
    PI:ReportAssignmentsToChat(PI:GetZoneOfPlayer(PI:Qualify(sender)))
end

function PI:SetError(message)
    if not PI.options or not PI.options.errorText then return end
    if message and message ~= "" then
        PI.options.errorText:SetTextColor(1, 0.2, 0.2, 1)
        PI.options.errorText:SetText(message)
        PI.options.errorText:Show()
    else
        PI.options.errorText:SetText("")
        PI.options.errorText:Hide()
    end
end

function PI:SetSuccess(message)
    if not PI.options or not PI.options.errorText then return end
    if message and message ~= "" then
        PI.options.errorText:SetTextColor(0.2, 1, 0.2, 1)
        PI.options.errorText:SetText(message)
        PI.options.errorText:Show()
    else
        PI.options.errorText:SetText("")
        PI.options.errorText:Hide()
    end
end

function PI:ClearError()
    PI:SetError(nil)
end

function PI:InitDB()
    if type(PowerInfusionAssignmentsDB) ~= "table" then PowerInfusionAssignmentsDB = {} end
    PowerInfusionAssignmentsDB.macroName = PowerInfusionAssignmentsDB.macroName or ""
    PowerInfusionAssignmentsDB.framePos = PowerInfusionAssignmentsDB.framePos or { point = "CENTER", x = 0, y = -200 }
    PowerInfusionAssignmentsDB.piMode = PowerInfusionAssignmentsDB.piMode or 1  -- 1 = macro mode, 2 = mouseover/target mode
    PowerInfusionAssignmentsDB.testMode = false  -- Always reset test mode on login
    -- Assignments are live raid state that every priest rebroadcasts within a
    -- few seconds, so start empty rather than restoring last session's (or
    -- last session's test mode) names.
    PowerInfusionAssignmentsDB.assignments = {}
    lastRowCount = -1
    PI.lastFrameErrorText = nil
    if PowerInfusionAssignmentsDB.hideInCombat == nil then PowerInfusionAssignmentsDB.hideInCombat = true end
    if PowerInfusionAssignmentsDB.enableWhispers == nil then PowerInfusionAssignmentsDB.enableWhispers = false end
    PowerInfusionAssignmentsDB.scale = PowerInfusionAssignmentsDB.scale or 1
    if PowerInfusionAssignmentsDB.showForNonPriest == nil then PowerInfusionAssignmentsDB.showForNonPriest = false end
    if PowerInfusionAssignmentsDB.lockFrame == nil then PowerInfusionAssignmentsDB.lockFrame = false end

    local name, realm = UnitFullName("player")
    myRealm = (realm and realm ~= "" and realm) or GetNormalizedRealmName() or ""
    myFullName = PI:Qualify(name or UnitName("player"), myRealm)
    PI.myRealm = myRealm
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

local function FlashOnUpdate(self, elapsed)
    self.flashElapsed = self.flashElapsed + elapsed
    if self.flashElapsed >= 0.5 then
        self.flashElapsed = 0
        self.flashVisible = not self.flashVisible
        self.warningIconTop:SetAlpha(self.flashVisible and 1 or 0.2)
    end
end

-- Metrics and palette come from the assignment-panel handoff in
-- .claude/design/design_handoff_pi_assignment_panel/ (option 2A, "Leader
-- lines"). Every number there is already converted to 1x game pixels, so they
-- are used as written and the frame's own SetScale does the rest.
local PANEL = {
    width       = 264,
    padX        = 9,
    padTop      = 7,
    padBottom   = 8,
    headerH     = 13,
    headerGap   = 5,    -- header block down to the divider
    dividerGap  = 6,    -- divider down to the first row
    rowH        = 14,
    rowGap      = 4,
    tickW       = 2,
    tickH       = 10,
    nameIndent  = 7,    -- tick (2px) plus its 5px gap; tickless rows match it
    leaderInset = 5,    -- clear space each side of the leader line
    leaderMin   = 10,   -- shortest leader run a row is allowed to squeeze to
    errorGap    = 6,
    fontRow     = 14,
    fontHeader  = 10,
    fontError   = 12,
}

-- Arial Narrow is the condensed face the client already ships, which is the
-- handoff's preferred answer before bundling a TTF of our own.
local PANEL_FONT = "Fonts\\ARIALN.TTF"

local PC = {
    bg         = {0.035, 0.031, 0.051, 0.84},
    border     = {1, 1, 1, 0.13},
    lip        = {1, 1, 1, 0.07},
    divider    = {1, 1, 1, 0.09},
    -- The handoff dims the header to 42% white. At 10px that is too faint to
    -- read at a glance, which is the one thing this panel is for, so it is
    -- full white instead.
    header     = {1, 1, 1, 1},
    nameSelf   = {1, 1, 1, 1},
    nameOther  = {1, 1, 1, 0.86},
    none       = {1, 0.482, 0.447, 1},      -- #FF7B72
    accent     = {0.847, 0.706, 0.416, 1},  -- #D8B46A
    -- The design's leader is a 1px dotted line. There is no dot texture to
    -- tile, so this is the handoff's sanctioned fallback: a solid line at 40%
    -- of the dotted alpha, which averages out to the same weight at 1px.
    leader     = {1, 1, 1, 0.16 * 0.4},
    leaderNone = {1, 0.482, 0.447, 0.40 * 0.4},
}

local function Tint(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4])
end

local function TintText(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4])
end

-- Rows are pooled and only ever hidden, never destroyed: the vertical anchor
-- of row n never changes, so it is set once here.
local function AcquireRow(f, index)
    local row = f.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, f)
    row:SetHeight(PANEL.rowH)
    local y = PANEL.padTop + PANEL.headerH + PANEL.headerGap + 1 + PANEL.dividerGap
              + (index - 1) * (PANEL.rowH + PANEL.rowGap)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL.padX, -y)
    row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PANEL.padX, -y)

    local tick = row:CreateTexture(nil, "ARTWORK")
    tick:SetSize(PANEL.tickW, PANEL.tickH)
    tick:SetPoint("LEFT", row, "LEFT", 0, 0)
    Tint(tick, PC.accent)
    tick:Hide()
    row.tick = tick

    local name = row:CreateFontString(nil, "OVERLAY")
    name:SetFont(PANEL_FONT, PANEL.fontRow, "")
    name:SetPoint("LEFT", row, "LEFT", PANEL.nameIndent, 0)
    name:SetJustifyH("LEFT")
    name:SetShadowOffset(1, -1)
    name:SetShadowColor(0, 0, 0, 1)
    row.name = name

    local target = row:CreateFontString(nil, "OVERLAY")
    target:SetFont(PANEL_FONT, PANEL.fontRow, "")
    target:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    target:SetJustifyH("RIGHT")
    target:SetShadowOffset(1, -1)
    target:SetShadowColor(0, 0, 0, 1)
    row.target = target

    -- Anchored between the two unsized FontStrings, so it stretches and
    -- shrinks with the names without anything measuring them.
    local leader = row:CreateTexture(nil, "ARTWORK")
    leader:SetHeight(1)
    leader:SetPoint("LEFT", name, "RIGHT", PANEL.leaderInset, 0)
    leader:SetPoint("RIGHT", target, "LEFT", -PANEL.leaderInset, 0)
    row.leader = leader

    f.rows[index] = row
    return row
end

function PI:CreateAssignmentFrame()
    if PI.frame then return end
    local f = CreateFrame("Frame", "PIAssignmentFrame", UIParent)
    f:SetSize(PANEL.width, 60)
    local pos = PowerInfusionAssignmentsDB and PowerInfusionAssignmentsDB.framePos
    if pos and pos.point and pos.x and pos.y then
        f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        if PowerInfusionAssignmentsDB then
            PowerInfusionAssignmentsDB.framePos = PowerInfusionAssignmentsDB.framePos or {}
            PowerInfusionAssignmentsDB.framePos.point = point or "CENTER"
            PowerInfusionAssignmentsDB.framePos.x = x or 0
            PowerInfusionAssignmentsDB.framePos.y = y or 0
        end
    end)
    f:SetClampedToScreen(true)
    f:SetScale(PowerInfusionAssignmentsDB.scale or 1)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    Tint(bg, PC.bg)

    -- Four 1px textures rather than a backdrop edge file: SetBackdrop cannot
    -- draw a square hairline border, which is the whole look here.
    local edges = {}
    for i = 1, 4 do
        edges[i] = f:CreateTexture(nil, "BORDER")
        Tint(edges[i], PC.border)
    end
    edges[1]:SetPoint("TOPLEFT");    edges[1]:SetPoint("TOPRIGHT");    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT");    edges[3]:SetPoint("BOTTOMLEFT");  edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT");   edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)

    -- The faint lip just inside the top edge
    local lip = f:CreateTexture(nil, "BORDER")
    lip:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    lip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    lip:SetHeight(1)
    Tint(lip, PC.lip)

    -- The design tracks the header by 1.5px. WoW has no letter-spacing API and
    -- padding it with real spaces overshoots by double, so it ships untracked.
    local header = f:CreateFontString(nil, "OVERLAY")
    header:SetFont(PANEL_FONT, PANEL.fontHeader, "")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL.padX, -PANEL.padTop)
    header:SetJustifyH("LEFT")
    header:SetShadowOffset(1, -1)
    header:SetShadowColor(0, 0, 0, 1)
    TintText(header, PC.header)
    header:SetText("POWER INFUSION")
    f.header = header

    local divY = PANEL.padTop + PANEL.headerH + PANEL.headerGap
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL.padX, -divY)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PANEL.padX, -divY)
    divider:SetHeight(1)
    Tint(divider, PC.divider)
    f.divider = divider

    -- Warning lines. Anchored by the layout pass, because where they start
    -- depends on how many rows are showing.
    local errorText = f:CreateFontString(nil, "OVERLAY")
    errorText:SetFont(PANEL_FONT, PANEL.fontError, "")
    errorText:SetJustifyH("LEFT")
    TintText(errorText, PC.none)
    errorText:SetShadowOffset(1, -1)
    errorText:SetShadowColor(0, 0, 0, 1)
    errorText:SetText("")
    f.errorText = errorText

    f.rows = {}

    -- Warning icon for issues (top)
    local warningIconTop = f:CreateTexture(nil, "OVERLAY")
    warningIconTop:SetSize(80, 80)
    warningIconTop:SetPoint("BOTTOM", f, "TOP", 0, -15)
    warningIconTop:SetTexture("Interface\\DialogFrame\\DialogAlertIcon")
    warningIconTop:Hide()
    f.warningIconTop = warningIconTop

    -- Flash animation state. The OnUpdate handler is only attached while the
    -- icon is up, so the frame costs nothing per frame the rest of the time.
    f.flashElapsed = 0
    f.flashVisible = true

    f:Show()
    PI.frame = f
    PI:UpdateAssignmentFrame()
    PI:UpdateFrameLock()
end

function PI:CheckForDuplicateTargets()
    wipe(reuseTargetCounts)
    for _, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if target and target ~= "" then
            if reuseTargetCounts[target] then return true, target end
            reuseTargetCounts[target] = true
        end
    end
    return false, nil
end

-- Two separate problems, both of which mean a priest is going to waste a PI:
-- the target has left the raid, or they're in a different zone to us.
function PI:CheckTargetProblems()
    if PowerInfusionAssignmentsDB.testMode then return false, false end
    local missing, wrongZone = false, false
    for _, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if target and target ~= "" then
            if not PI:IsPlayerInGroup(target) then
                missing = true
            elseif not PI:IsPlayerInSameZone(target) then
                wrongZone = true
            end
        end
    end
    return missing, wrongZone
end

function PI:CheckForRoleWarnings()
    for _, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if target and target ~= "" then
            local role = PI:GetRoleForName(target)
            if role == "HEALER" or role == "TANK" then
                return true
            end
            -- In test mode, simulate a role warning for Tankwarrior (tank)
            if PowerInfusionAssignmentsDB.testMode and PI:ShortName(target) == "Tankwarrior" then
                return true
            end
        end
    end
    return false
end

-- Writes the row descriptors onto the pooled row frames and hides the surplus.
-- Only called when the diff in UpdateAssignmentFrame says something moved.
local function ApplyPanelRows(f)
    for i = 1, reuseRowCount do
        local r = reuseRows[i]
        local row = AcquireRow(f, i)

        row.name:SetText(r.name)
        TintText(row.name, r.isSelf and PC.nameSelf or PC.nameOther)
        if r.isSelf then row.tick:Show() else row.tick:Hide() end

        row.target:SetText(r.target)
        if r.none then
            TintText(row.target, PC.none)
            Tint(row.leader, PC.leaderNone)
        else
            row.target:SetTextColor(PI:GetClassRGB(r.full))
            Tint(row.leader, PC.leader)
        end
        row:Show()
    end
    for i = reuseRowCount + 1, #f.rows do
        f.rows[i]:Hide()
    end
end

-- The panel is a fixed 264px in the design. It only ever grows from there,
-- and only far enough that the longest pair still has a leader between it —
-- the alternative is a name running into the target column.
function PI:LayoutAssignmentFrame()
    local f = PI.frame
    if not f then return end

    local widest = 0
    for i = 1, reuseRowCount do
        local row = f.rows[i]
        local w = PANEL.nameIndent + (row.name:GetStringWidth() or 0)
                  + PANEL.leaderInset * 2 + PANEL.leaderMin
                  + (row.target:GetStringWidth() or 0)
        if w > widest then widest = w end
    end
    local width = math.max(PANEL.width, math.ceil(widest) + PANEL.padX * 2)

    local height = PANEL.padTop + PANEL.headerH + PANEL.headerGap + 1 + PANEL.dividerGap
    if reuseRowCount > 0 then
        height = height + reuseRowCount * PANEL.rowH + (reuseRowCount - 1) * PANEL.rowGap
    end

    if f.errorText:GetText() ~= "" then
        f.errorText:SetWidth(width - PANEL.padX * 2)
        f.errorText:ClearAllPoints()
        f.errorText:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL.padX, -(height + PANEL.errorGap))
        height = height + PANEL.errorGap + math.ceil(f.errorText:GetStringHeight() or 0)
    end

    f:SetSize(width, height + PANEL.padBottom)
end

-- One row of the panel. `full` is the qualified target, kept because the class
-- colour is looked up by it; `color` is that colour, kept because the diff
-- below has to repaint a row whose target keeps its name but changes class -
-- a test-mode toggle, or a reconnect that refills the colour cache.
local function PushRow(displayName, target, isSelf)
    reuseRowCount = reuseRowCount + 1
    local r = reuseRows[reuseRowCount]
    if not r then r = {}; reuseRows[reuseRowCount] = r end
    r.name = displayName
    r.isSelf = isSelf
    if target and target ~= "" then
        r.full = target
        r.target = PI:ShortName(target)
        r.color = PI:GetClassColorForName(target)
        r.none = false
    else
        r.full = nil
        r.target = "(none)"
        r.color = nil
        r.none = true
    end
end

function PI:UpdateAssignmentFrame()
    PI:CreateAssignmentFrame()
    reuseRowCount = 0
    local myName = PI:GetPlayerName()

    -- First add the local player's assignment at the top (only if priest)
    if PI.playerIsPriest then
        PushRow(PI:ShortName(myName), PowerInfusionAssignmentsDB.assignments[myName], true)
    end

    -- Then add other players' assignments
    for player, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if player ~= myName and target and target ~= "" and (PowerInfusionAssignmentsDB.testMode or PI:IsPlayerInSameZone(player)) then
            PushRow(PI:ShortName(player), target, false)
        end
    end

    -- Check for duplicate targets, role warnings (PI assigned healer/tank), or
    -- targets who left the raid / are in another zone
    local hasDuplicates = false
    local hasRoleWarning = false
    local targetMissing = false
    local targetsNotInZone = false

    -- Deliberately gated on standing inside a raid instance, not merely being
    -- in a raid group: the warnings are noise in a city or out in the world.
    -- This is why nothing fires while the raid is still forming up.
    -- /pi debug lifts the gate so the warnings can be exercised anywhere.
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" or PI.debugging then
        hasDuplicates = PI:CheckForDuplicateTargets()
        hasRoleWarning = PI:CheckForRoleWarnings()
        targetMissing, targetsNotInZone = PI:CheckTargetProblems()
    end

    wipe(reuseErrorLines)
    if hasDuplicates then
        reuseErrorLines[#reuseErrorLines + 1] = "Duplicate PI targets!"
    end
    if hasRoleWarning then
        reuseErrorLines[#reuseErrorLines + 1] = "PI assigned to HEALER or TANK!"
    end
    if targetMissing then
        reuseErrorLines[#reuseErrorLines + 1] = "One or more PI targets are not in the raid!"
    end
    if targetsNotInZone then
        reuseErrorLines[#reuseErrorLines + 1] = "One or more PI targets are in a different zone!"
    end

    -- Diff against what is on screen rather than rebuilding a string to
    -- compare: this runs on the ticker for everyone in the raid.
    local changed = (reuseRowCount ~= lastRowCount)
    if not changed then
        for i = 1, reuseRowCount do
            local a, b = reuseRows[i], lastRows[i]
            if a.name ~= b.name or a.target ~= b.target
               or a.isSelf ~= b.isSelf or a.color ~= b.color then
                changed = true
                break
            end
        end
    end

    local newErrorText = table.concat(reuseErrorLines, "\n")
    if changed or newErrorText ~= PI.lastFrameErrorText then
        ApplyPanelRows(PI.frame)
        PI.frame.errorText:SetText(newErrorText)
        PI:LayoutAssignmentFrame()
        for i = 1, reuseRowCount do
            local a = reuseRows[i]
            local b = lastRows[i]
            if not b then b = {}; lastRows[i] = b end
            b.name, b.target, b.isSelf, b.color = a.name, a.target, a.isSelf, a.color
        end
        lastRowCount = reuseRowCount
        PI.lastFrameErrorText = newErrorText
    end

    -- Show/hide warning icon. Only touched on a transition so the flash keeps
    -- its rhythm instead of restarting on every update.
    local hasWarning = hasDuplicates or hasRoleWarning or targetMissing or targetsNotInZone
    if hasWarning and not PI.frame.warningIconTop:IsShown() then
        PI.frame.flashElapsed = 0
        PI.frame.flashVisible = true
        PI.frame.warningIconTop:SetAlpha(1)
        PI.frame.warningIconTop:Show()
        PI.frame:SetScript("OnUpdate", FlashOnUpdate)
    elseif not hasWarning and PI.frame.warningIconTop:IsShown() then
        PI.frame.warningIconTop:Hide()
        PI.frame:SetScript("OnUpdate", nil)
    end
end

-- Palette, sizes and copy come from the sidebar handoff in
-- .claude/design/design_handoff_pi_helper_sidebar/. Colours are that
-- document's hex values as 0-1 RGB. The design is visual only: every control
-- the old window had is still here, including both PI modes and the macro
-- name validation, neither of which the handoff knew about.
local C = {
    frame        = {0.106, 0.086, 0.067},
    rail         = {0.090, 0.071, 0.051},
    bar          = {0.133, 0.106, 0.075},
    railSel      = {0.141, 0.114, 0.078},
    inset        = {0.063, 0.051, 0.035},
    code         = {0.047, 0.039, 0.027},
    btnFace      = {0.165, 0.129, 0.094},
    btnHover     = {0.227, 0.176, 0.106},
    primary      = {0.290, 0.227, 0.090},
    primaryHover = {0.361, 0.282, 0.125},

    edgeFrame    = {0.290, 0.227, 0.133},
    edgeRegion   = {0.227, 0.176, 0.106},
    edgeRow      = {0.133, 0.106, 0.075},
    edgeCtrl     = {0.271, 0.208, 0.098},
    edgeCode     = {0.239, 0.188, 0.094},
    edgeDrop     = {0.427, 0.325, 0.125},
    edgeHot      = {0.478, 0.361, 0.133},
    edgeFocus    = {0.788, 0.573, 0.184},

    trackBg      = {0.173, 0.141, 0.102},
    trackEdge    = {0.098, 0.075, 0.035},
    accent       = {0.851, 0.631, 0.231},
    handle       = {0.949, 0.776, 0.427},
    handleEdge   = {0.071, 0.063, 0.043},

    title        = {0.949, 0.776, 0.427},
    body         = {0.784, 0.733, 0.651},
    field        = {0.941, 0.886, 0.769},
    micro        = {0.690, 0.541, 0.239},
    desc         = {0.490, 0.451, 0.384},
    muted        = {0.431, 0.392, 0.333},
    caption      = {0.545, 0.498, 0.427},
    macroGreen   = {0.561, 0.812, 0.478},
    onAccent     = {0.059, 0.051, 0.039},
}

local UI_FONT = "Fonts\\FRIZQT__.TTF"

local RAIL_W, TITLE_H, BODY_H = 172, 46, 450
local PANE_PAD_X, PANE_PAD_Y = 20, 18
local WINDOW_W = 720
local PANE_W = WINDOW_W - RAIL_W - PANE_PAD_X * 2
local ROW_H = 44

local function Fill(frame, color, alpha)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return t
end

-- Flat single-pixel edges. SetBackdrop's edge files can't give the design's
-- square corners and hairline borders, so the surfaces are built by hand.
local function Edge(frame, side, color)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(color[1], color[2], color[3], 1)
    if side == "TOP" then
        t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
    elseif side == "BOTTOM" then
        t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(1)
    elseif side == "LEFT" then
        t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(1)
    else
        t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(1)
    end
    return t
end

local function Outline(frame, color)
    return {
        Edge(frame, "TOP", color), Edge(frame, "BOTTOM", color),
        Edge(frame, "LEFT", color), Edge(frame, "RIGHT", color),
    }
end

local function SetOutlineColor(edges, color)
    for i = 1, #edges do
        edges[i]:SetColorTexture(color[1], color[2], color[3], 1)
    end
end

-- SetFont's flags argument is not optional in retail; passing nil errors.
local FONT_FLAGS = ""

local function Label(parent, size, color, wrap)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(UI_FONT, size, FONT_FLAGS)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(wrap and true or false)
    return fs
end

-- Flat button: fill + outline + centred label, with a hover fill.
local function FlatButton(parent, w, h, text, face, hover, border, textColor)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = Fill(b, face)
    Outline(b, border)
    b.label = Label(b, 14, textColor)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(text)
    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(hover[1], hover[2], hover[3], 1)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(face[1], face[2], face[3], 1)
    end)
    return b
end

-- Single-line text field on the design's inset surface.
local function InsetEditBox(parent, w, h, fontSize, justify)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    Fill(box, C.inset)
    box.edges = Outline(box, C.edgeCtrl)

    local e = CreateFrame("EditBox", nil, box)
    e:SetPoint("TOPLEFT", box, "TOPLEFT", 8, 0)
    e:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 0)
    e:SetFont(UI_FONT, fontSize or 15, FONT_FLAGS)
    e:SetTextColor(C.field[1], C.field[2], C.field[3])
    e:SetJustifyH(justify or "LEFT")
    e:SetAutoFocus(false)
    e:SetScript("OnEditFocusGained", function() SetOutlineColor(box.edges, C.edgeFocus) end)
    e:SetScript("OnEditFocusLost", function() SetOutlineColor(box.edges, C.edgeCtrl) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e.container = box
    return e, box
end

-- Read-only macro block. Kept selectable so Ctrl+C still works, exactly as
-- the old window did: swallow typing, allow Ctrl+A / Ctrl+C, restore the text
-- if anything slips through.
local function MacroBlock(parent, w, h, text)
    local block = CreateFrame("Frame", nil, parent)
    block:SetSize(w, h)
    Fill(block, C.code)
    Outline(block, C.edgeCode)

    local e = CreateFrame("EditBox", nil, block)
    e:SetPoint("TOPLEFT", block, "TOPLEFT", 12, -10)
    e:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", -12, 10)
    e:SetMultiLine(true)
    e:SetFont(UI_FONT, 12, FONT_FLAGS)
    e:SetTextColor(C.macroGreen[1], C.macroGreen[2], C.macroGreen[3])
    e:SetAutoFocus(false)
    e:SetText(text)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnKeyDown", function(self, key)
        if IsControlKeyDown() and (key == "C" or key == "A") then return end
        self:SetPropagateKeyboardInput(false)
    end)
    e:SetScript("OnChar", function() end)
    e:SetScript("OnTextChanged", function(self) self:SetText(text) end)
    return e, block
end

function PI:CreateOptionsWindow()
    if PI.options then return end

    local o = CreateFrame("Frame", "PIOptionsWindow", UIParent)
    o:SetSize(WINDOW_W, TITLE_H + BODY_H)
    o:SetFrameStrata("DIALOG")
    o:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    Fill(o, C.frame)
    Outline(o, C.edgeFrame)
    o:SetMovable(true)
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    o:SetScript("OnDragStart", function(self) self:StartMoving() end)
    o:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    o:SetClampedToScreen(true)
    o:Hide()

    local UpdateBadges, UpdateModeVisibility, UpdateHintVisibility

    -- === TITLE BAR ===
    local titleBar = CreateFrame("Frame", nil, o)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(TITLE_H)
    Fill(titleBar, C.bar)
    Edge(titleBar, "BOTTOM", C.edgeRegion)

    local heading = Label(titleBar, 17, C.title)
    heading:SetPoint("LEFT", titleBar, "LEFT", 16, 0)
    heading:SetText("Power Infusion Assignment Helper")

    -- The handoff asks for the game's existing red X here
    local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    close:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    close:SetScript("OnClick", function() o:Hide() end)

    -- === BODY ===
    local body = CreateFrame("Frame", nil, o)
    body:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", 0, 0)

    local rail = CreateFrame("Frame", nil, body)
    rail:SetPoint("TOPLEFT")
    rail:SetPoint("BOTTOMLEFT")
    rail:SetWidth(RAIL_W)
    Fill(rail, C.rail)
    Edge(rail, "RIGHT", C.edgeRegion)

    local paneArea = CreateFrame("Frame", nil, body)
    paneArea:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    paneArea:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

    local panes, navButtons = {}, {}

    local function NewPane(key)
        local p = CreateFrame("Frame", nil, paneArea)
        p:SetPoint("TOPLEFT", paneArea, "TOPLEFT", PANE_PAD_X, -PANE_PAD_Y)
        p:SetPoint("BOTTOMRIGHT", paneArea, "BOTTOMRIGHT", -PANE_PAD_X, PANE_PAD_Y)
        p:Hide()
        panes[key] = p
        return p
    end

    local function SelectSection(key)
        o.section = key
        for i = 1, #navButtons do
            local b = navButtons[i]
            local on = (b.key == key)
            b.selected = on
            b.bg:SetShown(on)
            b.mark:SetShown(on)
            local col = on and C.title or C.body
            b.label:SetTextColor(col[1], col[2], col[3])
        end
        for k, pane in pairs(panes) do
            pane:SetShown(k == key)
        end
    end

    local function CreateNavButton(index, key, text)
        local b = CreateFrame("Button", nil, rail)
        b:SetSize(RAIL_W, 40)
        b:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -8 - (index - 1) * 40)

        b.bg = Fill(b, C.railSel)
        b.bg:Hide()
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetPoint("TOPLEFT")
        b.mark:SetPoint("BOTTOMLEFT")
        b.mark:SetWidth(3)
        b.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        b.mark:Hide()

        b.label = Label(b, 15, C.body)
        b.label:SetPoint("LEFT", b, "LEFT", 14, 0)
        b.label:SetText(text)

        b.badge = Label(b, 12, C.muted)
        b.badge:SetPoint("RIGHT", b, "RIGHT", -14, 0)
        b.badge:SetJustifyH("RIGHT")

        b.key = key
        b:SetScript("OnClick", function(self) SelectSection(self.key) end)
        b:SetScript("OnEnter", function(self)
            if self.selected then return end
            self.bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], 1)
            self.bg:Show()
        end)
        b:SetScript("OnLeave", function(self)
            if self.selected then return end
            self.bg:Hide()
            self.bg:SetColorTexture(C.railSel[1], C.railSel[2], C.railSel[3], 1)
        end)

        navButtons[index] = b
        navButtons[key] = b
        return b
    end

    CreateNavButton(1, "setup", "Setup")
    CreateNavButton(2, "behavior", "Behavior")
    CreateNavButton(3, "display", "Display")
    CreateNavButton(4, "faq", "FAQ")

    -- === SETUP PANE ===
    local setup = NewPane("setup")

    local modeMicro = Label(setup, 11, C.micro)
    modeMicro:SetPoint("TOPLEFT", setup, "TOPLEFT", 0, 0)
    modeMicro:SetText("MODE")

    local PI_MODE_OPTIONS = {
        [1] = "My PI target is set in a macro",
        [2] = "My PI target is *not* set in a macro",
    }

    -- Both modes are still here. UIDropDownMenu can't be flattened to this
    -- design, so the picker is a plain button plus a two-row popup.
    local modeButton = CreateFrame("Button", "PI_ModeDropdown", setup)
    modeButton:SetSize(PANE_W, 34)
    modeButton:SetPoint("TOPLEFT", modeMicro, "BOTTOMLEFT", 0, -10)
    Fill(modeButton, C.inset)
    Outline(modeButton, C.edgeDrop)
    modeButton.label = Label(modeButton, 15, C.field)
    modeButton.label:SetPoint("LEFT", modeButton, "LEFT", 10, 0)
    local modeArrow = Label(modeButton, 12, C.field)
    modeArrow:SetPoint("RIGHT", modeButton, "RIGHT", -10, 0)
    modeArrow:SetText("v")

    local modeMenu = CreateFrame("Frame", nil, modeButton)
    modeMenu:SetPoint("TOPLEFT", modeButton, "BOTTOMLEFT", 0, -1)
    modeMenu:SetSize(PANE_W, 68)
    modeMenu:SetFrameLevel(modeButton:GetFrameLevel() + 10)
    Fill(modeMenu, C.inset)
    Outline(modeMenu, C.edgeDrop)
    modeMenu:Hide()

    local function SetMode(mode)
        PowerInfusionAssignmentsDB.piMode = mode
        modeButton.label:SetText(PI_MODE_OPTIONS[mode])
        modeMenu:Hide()
        UpdateModeVisibility()
        UpdateHintVisibility()
        UpdateBadges()
    end

    for i = 1, 2 do
        local item = CreateFrame("Button", nil, modeMenu)
        item:SetSize(PANE_W - 2, 33)
        item:SetPoint("TOPLEFT", modeMenu, "TOPLEFT", 1, -1 - (i - 1) * 33)
        item.bg = Fill(item, C.btnHover)
        item.bg:Hide()
        item.label = Label(item, 15, C.body)
        item.label:SetPoint("LEFT", item, "LEFT", 9, 0)
        item.label:SetText(PI_MODE_OPTIONS[i])
        item:SetScript("OnClick", function() SetMode(i) end)
        item:SetScript("OnEnter", function(self) self.bg:Show() end)
        item:SetScript("OnLeave", function(self) self.bg:Hide() end)
    end

    modeButton:SetScript("OnClick", function()
        modeMenu:SetShown(not modeMenu:IsShown())
    end)

    -- Macro name row (mode 1)
    local macroLabel = Label(setup, 15, C.body)
    macroLabel:SetPoint("TOPLEFT", modeButton, "BOTTOMLEFT", 0, -16)
    macroLabel:SetText("Macro name")

    local edit, editBox = InsetEditBox(setup, 150, 30, 15)
    editBox:SetPoint("LEFT", macroLabel, "RIGHT", 12, 0)
    edit:SetText(PowerInfusionAssignmentsDB.macroName or "")

    -- Green "get started" hint and the validation result share this line
    local macroHintText = Label(setup, 13, {0.2, 1, 0.2})
    macroHintText:SetPoint("TOPLEFT", macroLabel, "BOTTOMLEFT", 0, -10)
    macroHintText:SetText("Enter your macro name to get started")

    local errorText = Label(setup, 13, {1, 0.2, 0.2})
    errorText:SetPoint("TOPLEFT", macroHintText, "BOTTOMLEFT", 0, -4)
    errorText:SetText("")
    errorText:Hide()

    local function ValidateMacroName()
        local macroName = edit:GetText() or ""
        PowerInfusionAssignmentsDB.macroName = macroName
        UpdateBadges()
        if macroName == "" then
            PI:ClearError()
            return
        end
        if not PI:FindMacroIndexByName(macroName) then
            PI:SetError("Macro not found: " .. macroName)
        else
            PI:SetSuccess("Found macro: " .. macroName)
        end
    end

    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            PowerInfusionAssignmentsDB.macroName = self:GetText() or ""
            UpdateHintVisibility()
            UpdateBadges()
        end
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ValidateMacroName()
    end)

    -- Example macro (mode 1)
    local exampleMacroLabel = Label(setup, 14, C.caption)
    exampleMacroLabel:SetPoint("TOPLEFT", errorText, "BOTTOMLEFT", 0, -14)
    exampleMacroLabel:SetText("Example macro, if you need to create one")

    local EXAMPLE_MACRO = "/use [@mouseover,nodead,help]Power Infusion;[@YOUR_PI_TARGET_HERE,exists,nodead]Power Infusion;[@player]Power Infusion"
    local exampleMacroEdit, exampleMacroBlock = MacroBlock(setup, PANE_W, 76, EXAMPLE_MACRO)
    exampleMacroBlock:SetPoint("TOPLEFT", exampleMacroLabel, "BOTTOMLEFT", 0, -8)

    local exampleCopyMacroButton = FlatButton(setup, 200, 30, "Select all (Ctrl+C to copy)",
        C.primary, C.primaryHover, C.edgeHot, C.title)
    exampleCopyMacroButton:SetPoint("TOPLEFT", exampleMacroBlock, "BOTTOMLEFT", 0, -10)
    exampleCopyMacroButton:SetScript("OnClick", function()
        exampleMacroEdit:SetFocus()
        exampleMacroEdit:HighlightText(0)
    end)

    -- Mouseover instructions and macro (mode 2)
    local mouseoverMacroLabel = Label(setup, 14, C.body, true)
    mouseoverMacroLabel:SetPoint("TOPLEFT", modeButton, "BOTTOMLEFT", 0, -16)
    mouseoverMacroLabel:SetWidth(PANE_W)
    mouseoverMacroLabel:SetText("You can still communicate your PI target to the group by following these steps: \n\n1) Bind the below macro to a key\n2) While out of combat, mouseover your intended PI target, press the key.\n3) Your intended target is now communicated to your fellow priests!")
    mouseoverMacroLabel:Hide()

    local mouseoverMacroEdit, mouseoverMacroBlock = MacroBlock(setup, PANE_W, 44, "/run PI_SetPITarget()")
    mouseoverMacroBlock:SetPoint("TOPLEFT", mouseoverMacroLabel, "BOTTOMLEFT", 0, -14)
    mouseoverMacroBlock:Hide()

    local copyMacroButton = FlatButton(setup, 200, 30, "Select all (Ctrl+C to copy)",
        C.primary, C.primaryHover, C.edgeHot, C.title)
    copyMacroButton:SetPoint("TOPLEFT", mouseoverMacroBlock, "BOTTOMLEFT", 0, -10)
    copyMacroButton:SetScript("OnClick", function()
        mouseoverMacroEdit:SetFocus()
        mouseoverMacroEdit:HighlightText(0)
    end)
    copyMacroButton:Hide()

    -- === TOGGLE ROWS ===
    local toggleRows = {}

    local function CreateToggleRow(parent, index, text, desc, get, set)
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(PANE_W, ROW_H)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_H)
        Edge(row, "BOTTOM", C.edgeRow)

        local box = CreateFrame("Frame", nil, row)
        box:SetSize(16, 16)
        box:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -11)
        row.boxFill = Fill(box, C.inset)
        row.boxEdges = Outline(box, C.edgeCtrl)
        row.check = box:CreateTexture(nil, "OVERLAY")
        row.check:SetPoint("CENTER")
        row.check:SetSize(16, 16)
        row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        row.check:SetVertexColor(C.onAccent[1], C.onAccent[2], C.onAccent[3])
        row.check:Hide()

        row.label = Label(row, 15, C.body)
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -9)
        row.label:SetText(text)

        row.desc = Label(row, 13, C.desc, true)
        row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
        row.desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.desc:SetText(desc)

        row.Refresh = function(self)
            local on = get() and true or false
            self.check:SetShown(on)
            if on then
                self.boxFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                SetOutlineColor(self.boxEdges, C.edgeHot)
                self.label:SetTextColor(C.title[1], C.title[2], C.title[3])
            else
                self.boxFill:SetColorTexture(C.inset[1], C.inset[2], C.inset[3], 1)
                SetOutlineColor(self.boxEdges, C.edgeCtrl)
                self.label:SetTextColor(C.body[1], C.body[2], C.body[3])
            end
        end
        row:SetScript("OnClick", function(self)
            set(not get())
            self:Refresh()
            UpdateBadges()
        end)

        toggleRows[#toggleRows + 1] = row
        return row
    end

    -- === BEHAVIOR PANE ===
    local behavior = NewPane("behavior")

    CreateToggleRow(behavior, 1, "Hide PI assignments in combat",
        "The assignment window is hidden while you are in combat.",
        function() return PowerInfusionAssignmentsDB.hideInCombat end,
        function(v)
            PowerInfusionAssignmentsDB.hideInCombat = v
            PI:UpdateAssignmentFrameVisibility()
        end)

    CreateToggleRow(behavior, 2, "Show PI assignments even if I'm not a priest",
        "Shows the window on non-priest characters, for raid leads tracking PI.",
        function() return PowerInfusionAssignmentsDB.showForNonPriest end,
        function(v)
            PowerInfusionAssignmentsDB.showForNonPriest = v
            PI:UpdateAssignmentFrameVisibility()
            PI:UpdateTickerState()
        end)

    local whispersRow = CreateToggleRow(behavior, 3, "Enable whispers (guild only)",
        "Whispers your old and new target whenever your PI target changes.",
        function() return PowerInfusionAssignmentsDB.enableWhispers end,
        function(v) PowerInfusionAssignmentsDB.enableWhispers = v end)

    local whispersInfoIcon = CreateFrame("Frame", nil, whispersRow)
    whispersInfoIcon:SetSize(16, 16)
    whispersInfoIcon:SetPoint("LEFT", whispersRow.label, "RIGHT", 6, 0)
    local whispersInfoTexture = whispersInfoIcon:CreateTexture(nil, "ARTWORK")
    whispersInfoTexture:SetAllPoints()
    whispersInfoTexture:SetTexture("Interface/FriendsFrame/InformationIcon")
    whispersInfoIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Enable Whispers", 1, 1, 1)
        GameTooltip:AddLine("When you change your PI target, notify old and new targets. Only works for guild members.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    whispersInfoIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- === DISPLAY PANE ===
    local display = NewPane("display")

    CreateToggleRow(display, 1, "Test mode (show fake data)",
        "Fills the window with sample assignments so you can position it. Off on login.",
        function() return PowerInfusionAssignmentsDB.testMode end,
        function(v) PI:SetTestMode(v) end)

    CreateToggleRow(display, 2, "Lock frame",
        "Stops the assignment window being dragged.",
        function() return PowerInfusionAssignmentsDB.lockFrame end,
        function(v)
            PowerInfusionAssignmentsDB.lockFrame = v
            PI:UpdateFrameLock()
        end)

    -- === FAQ PANE ===
    local faq = NewPane("faq")
    local faqText = Label(faq, 13, C.body, true)
    faqText:SetPoint("TOPLEFT", faq, "TOPLEFT", 0, 0)
    faqText:SetPoint("TOPRIGHT", faq, "TOPRIGHT", 0, 0)
    faqText:SetSpacing(3)
    faqText:SetText("|cFFFFD100Q: What does this addon do?|r\n- shows PI targets for yourself + other priests in a movable window\n- warns you if multiple priests are PIing the same person\n- warns you if any priest has PI set to a tank or healer\n- lets your raid team run !pi command to check who PIs are set to\n\n|cFFFFD100Q: How do I set up the addon|r\n- Follow instructions in the \"Setup\" tab\n\n|cFFFFD100Q: Restrictions|r\n- only works in raid groups\n- all of your priests will need to run the addon for it to communicate properly")

    -- === SCALE (in the Display pane) ===
    -- The handoff put this in a footer visible in every section; it lives in
    -- Display instead, under the two toggle rows.
    local scaleRow = CreateFrame("Frame", nil, display)
    scaleRow:SetPoint("TOPLEFT", display, "TOPLEFT", 0, -(2 * ROW_H) - 20)
    scaleRow:SetSize(PANE_W, 26)

    local scaleLabel = Label(scaleRow, 15, C.body)
    scaleLabel:SetPoint("LEFT", scaleRow, "LEFT", 0, 0)
    scaleLabel:SetText("Scale")

    local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.7, 2.0, 0.05
    local applyingScale = false

    local stepper = CreateFrame("Frame", nil, scaleRow)
    stepper:SetSize(104, 26)
    stepper:SetPoint("RIGHT", scaleRow, "RIGHT", 0, 0)
    Fill(stepper, C.inset)
    Outline(stepper, C.edgeCtrl)

    -- A real Slider skinned down to the design's 4px bar, so drag handling and
    -- step snapping come free.
    local scaleSlider = CreateFrame("Slider", "PI_ScaleSlider", scaleRow)
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", 14, 0)
    scaleSlider:SetPoint("RIGHT", stepper, "LEFT", -14, 0)
    scaleSlider:SetHeight(20)
    scaleSlider:SetOrientation("HORIZONTAL")
    scaleSlider:SetMinMaxValues(SCALE_MIN, SCALE_MAX)
    scaleSlider:SetValueStep(SCALE_STEP)
    scaleSlider:SetObeyStepOnDrag(true)

    local trackEdge = scaleSlider:CreateTexture(nil, "BACKGROUND")
    trackEdge:SetPoint("LEFT")
    trackEdge:SetPoint("RIGHT")
    trackEdge:SetHeight(6)
    trackEdge:SetColorTexture(C.trackEdge[1], C.trackEdge[2], C.trackEdge[3], 1)

    local trackBg = scaleSlider:CreateTexture(nil, "BORDER")
    trackBg:SetPoint("LEFT", trackEdge, "LEFT", 1, 0)
    trackBg:SetPoint("RIGHT", trackEdge, "RIGHT", -1, 0)
    trackBg:SetHeight(4)
    trackBg:SetColorTexture(C.trackBg[1], C.trackBg[2], C.trackBg[3], 1)

    local thumb = scaleSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(9, 18)
    thumb:SetColorTexture(C.handle[1], C.handle[2], C.handle[3], 1)
    scaleSlider:SetThumbTexture(thumb)

    -- Anchored to the thumb so the fill follows the value with no OnUpdate
    local trackFill = scaleSlider:CreateTexture(nil, "ARTWORK")
    trackFill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
    trackFill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
    trackFill:SetHeight(4)
    trackFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

    -- The readout is an EditBox, not a label, so the old window's ability to
    -- type an exact scale survives the redesign.
    local scaleInput, scaleInputBox = InsetEditBox(stepper, 52, 24, 15, "CENTER")
    scaleInputBox:SetPoint("CENTER", stepper, "CENTER", 0, 0)
    scaleInput:SetTextColor(C.title[1], C.title[2], C.title[3])
    _G["PI_ScaleInput"] = scaleInput

    local function ApplyScale(value, fromInput)
        if applyingScale then return end
        value = tonumber(value)
        if not value then return end
        if value < SCALE_MIN then value = SCALE_MIN end
        if value > SCALE_MAX then value = SCALE_MAX end
        -- Snap to the step grid, then round off the float noise that leaves
        -- behind, so the saved variable holds 0.70 rather than 0.7000000000001
        value = math.floor(value / SCALE_STEP + 0.5) * SCALE_STEP
        value = math.floor(value * 100 + 0.5) / 100
        applyingScale = true
        PowerInfusionAssignmentsDB.scale = value
        if PI.frame then PI.frame:SetScale(value) end
        scaleSlider:SetValue(value)
        if not fromInput then
            scaleInput:SetText(string.format("%.2f", value))
        end
        applyingScale = false
    end

    scaleSlider:SetScript("OnValueChanged", function(_, value) ApplyScale(value) end)

    scaleInput:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()
        local filtered = text:gsub("[^0-9.]", "")
        if filtered ~= text then self:SetText(filtered) end
    end)
    scaleInput:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            ApplyScale(value, true)
        end
        self:SetText(string.format("%.2f", PowerInfusionAssignmentsDB.scale or 1))
        self:ClearFocus()
    end)

    local minusButton = FlatButton(stepper, 26, 26, "-", C.btnFace, C.btnHover, C.edgeCtrl, C.field)
    minusButton:SetPoint("LEFT", stepper, "LEFT", 0, 0)
    minusButton:SetScript("OnClick", function()
        ApplyScale((PowerInfusionAssignmentsDB.scale or 1) - SCALE_STEP)
    end)

    local plusButton = FlatButton(stepper, 26, 26, "+", C.btnFace, C.btnHover, C.edgeCtrl, C.field)
    plusButton:SetPoint("RIGHT", stepper, "RIGHT", 0, 0)
    plusButton:SetScript("OnClick", function()
        ApplyScale((PowerInfusionAssignmentsDB.scale or 1) + SCALE_STEP)
    end)

    -- === DERIVED STATE ===
    UpdateBadges = function()
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        navButtons.setup.badge:SetText(mode == 1 and (PowerInfusionAssignmentsDB.macroName or "") or "")

        local b = 0
        if PowerInfusionAssignmentsDB.hideInCombat then b = b + 1 end
        if PowerInfusionAssignmentsDB.showForNonPriest then b = b + 1 end
        if PowerInfusionAssignmentsDB.enableWhispers then b = b + 1 end
        navButtons.behavior.badge:SetText(b.."/3")

        local d = 0
        if PowerInfusionAssignmentsDB.testMode then d = d + 1 end
        if PowerInfusionAssignmentsDB.lockFrame then d = d + 1 end
        navButtons.display.badge:SetText(d.."/2")
    end

    UpdateModeVisibility = function()
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        local macroMode = (mode == 1)
        macroLabel:SetShown(macroMode)
        editBox:SetShown(macroMode)
        exampleMacroLabel:SetShown(macroMode)
        exampleMacroBlock:SetShown(macroMode)
        exampleCopyMacroButton:SetShown(macroMode)
        mouseoverMacroLabel:SetShown(not macroMode)
        mouseoverMacroBlock:SetShown(not macroMode)
        copyMacroButton:SetShown(not macroMode)
        if macroMode then
            UpdateHintVisibility()
        else
            macroHintText:Hide()
            PI:ClearError()
        end
    end

    UpdateHintVisibility = function()
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        local macroName = PowerInfusionAssignmentsDB.macroName or ""
        macroHintText:SetShown(mode == 1 and macroName == "")
    end

    local function RefreshToggles()
        for i = 1, #toggleRows do toggleRows[i]:Refresh() end
    end

    o:SetScript("OnShow", function(self)
        modeMenu:Hide()
        RefreshToggles()
        UpdateBadges()
        UpdateModeVisibility()
        if self.edit then self.edit:ClearFocus() end
        if self.exampleMacroEdit then self.exampleMacroEdit:ClearFocus() end
        if self.mouseoverMacroEdit then self.mouseoverMacroEdit:ClearFocus() end
        scaleInput:ClearFocus()
    end)

    o.macroHintText = macroHintText
    o.macroLabel = macroLabel
    o.edit = edit
    o.editBox = editBox
    o.exampleMacroBlock = exampleMacroBlock
    o.mouseoverMacroBlock = mouseoverMacroBlock
    o.toggleRows = toggleRows
    o.SetMode = SetMode
    o.exampleMacroLabel = exampleMacroLabel
    o.exampleMacroEdit = exampleMacroEdit
    o.exampleCopyMacroButton = exampleCopyMacroButton
    o.mouseoverMacroLabel = mouseoverMacroLabel
    o.mouseoverMacroEdit = mouseoverMacroEdit
    o.copyMacroButton = copyMacroButton
    o.errorText = errorText
    o.faqText = faqText
    o.modeDropdown = modeButton
    o.SelectSection = SelectSection
    o.UpdateModeVisibility = UpdateModeVisibility
    o.UpdateHintVisibility = UpdateHintVisibility
    o.UpdateBadges = UpdateBadges
    o.RefreshToggles = RefreshToggles

    PI.options = o

    modeButton.label:SetText(PI_MODE_OPTIONS[PowerInfusionAssignmentsDB.piMode or 1])
    scaleSlider:SetValue(PowerInfusionAssignmentsDB.scale or 1)
    scaleInput:SetText(string.format("%.2f", PowerInfusionAssignmentsDB.scale or 1))
    edit:ClearFocus()
    exampleMacroEdit:ClearFocus()
    mouseoverMacroEdit:ClearFocus()
    scaleInput:ClearFocus()

    RefreshToggles()
    UpdateBadges()
    UpdateModeVisibility()
    SelectSection("setup")
end

function PI:DumpState()
    local db = PowerInfusionAssignmentsDB
    print("|cff9cd6ff[PI]|r debug "..(PI.debugging and "ON" or "OFF"))
    print(string.format("  me=%s realm=%s priest=%s inRaid=%s inCombat=%s",
        tostring(PI:GetPlayerName()), tostring(PI.myRealm or ""),
        tostring(PI.playerIsPriest), tostring(IsInRaid()), tostring(PI.inCombat)))
    local _, instanceType = GetInstanceInfo()
    print(string.format("  zone=%s instanceType=%s groupSize=%d ticker=%s",
        tostring(GetZoneText()), tostring(instanceType), GetNumGroupMembers(),
        tostring(PI:IsScanning())))
    print(string.format("  mode=%d macro=%s testMode=%s lastBroadcast=%s",
        db.piMode or 1, tostring(db.macroName), tostring(db.testMode),
        tostring(PI.lastBroadcastedTarget)))
    local n = 0
    for player, target in pairs(db.assignments) do
        n = n + 1
        print(string.format("  [%s] -> %s  inGroup=%s sameZone=%s role=%s",
            player, tostring(target), tostring(PI:IsPlayerInGroup(player)),
            tostring(PI:IsPlayerInSameZone(player)), tostring(PI:GetRoleForName(target))))
    end
    if n == 0 then print("  (no assignments)") end
end

SLASH_POWERINFUSION1 = "/pi"
SlashCmdList["POWERINFUSION"] = function(msg)
    local cmd = strlower(strtrim(msg or ""))
    if cmd == "debug" then
        PI.debugging = not PI.debugging
        PI:DumpState()
        return
    elseif cmd == "status" then
        PI:DumpState()
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
    if ((PI.playerIsPriest or PowerInfusionAssignmentsDB.showForNonPriest) and IsInRaid() and not PI.inCombat) then
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zones and roster data are only valid again once the loading screen
        -- is done, and PLAYER_LOGIN doesn't fire on a zone-in or a reload.
        if myFullName then
            PI:RefreshRoster()
            PI:UpdateAssignmentFrame()
            PI:UpdateAssignmentFrameVisibility()
            PI:UpdateTickerState()
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
    end
end)
