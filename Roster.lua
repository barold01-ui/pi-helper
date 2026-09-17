-- Roster, identity, and name resolution for PowerInfusionAssignments.
-- Owns every per-member cache plus the name/wire helpers that read them, so
-- the rest of the addon only ever touches this state through PI: methods.
local _, PI = ...

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

-- Resolved once at login; every stored name is qualified against this realm.
local myFullName = nil
local myRealm = nil

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
function PI:RealmOf(fullName)
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
    if PI:RealmOf(fullName) == myRealm then return PI:ShortName(fullName) end
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

-- Called by InitDB once the player's name/realm are known. Sets the realm
-- first so Qualify can use it, then resolves and caches our own qualified
-- name. PI.fullName mirrors myFullName for the event handler's identity check.
function PI:SetIdentity(name, realm)
    myRealm = (realm and realm ~= "" and realm) or GetNormalizedRealmName() or ""
    myFullName = PI:Qualify(name or UnitName("player"), myRealm)
    PI.myRealm = myRealm
    PI.fullName = myFullName
end

-- Macro bodies contain whatever the player typed, which is usually just a
-- first name. Match it against the roster so a cross-realm target keeps its
-- own realm instead of being silently reassigned to ours.
function PI:ResolveName(name)
    if not name or name == "" then return nil end
    if string.find(name, "-", 1, true) then return name end
    return shortToFull[name] or PI:Qualify(name)
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

-- The unit token ("raid7", "player", ...) for a qualified name, or nil if they
-- aren't in the current raid. Used to point the notify glow at a specific
-- player. Raid only for now (rosterNames is only filled in a raid); dungeon
-- party tokens come with dungeon mode.
function PI:GetUnitTokenForName(fullName)
    if not fullName or fullName == "" then return nil end
    if fullName == PI:GetPlayerName() then return "player" end
    for i = 1, rosterCount do
        if rosterNames[i] == fullName then return "raid"..i end
    end
    -- rosterNames only covers a raid; in a 5-man party match the party units.
    if IsInGroup() and not IsInRaid() then
        for i = 1, 4 do
            local u = "party"..i
            if UnitExists(u) and PI:GetUnitName(u) == fullName then return u end
        end
    end
    return nil
end
