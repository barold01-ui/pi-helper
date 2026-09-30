-- Locate one unit's raid/party cell across the supported frame addons, so the
-- notify glow can be laid over the assigned target. We only ever need a single
-- unit, so this is far leaner than enumerating every cell: direct unit->frame
-- maps where an addon offers one (Cell, Grid2), a matched scan otherwise.
--
-- Frame unit tokens go secret in combat, so the resolved cell is cached and the
-- cache is only rebuilt out of combat. In combat we trust the last known cell.
-- The per-addon lookups are our own; only the facts (where each addon keeps its
-- cells) come from studying the reference.
local _, PI = ...

local frameCache = {}   -- unit token -> frame, cleared out of combat

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function Forbidden(frame)
    if not frame or not frame.IsForbidden then return false end
    local ok, v = pcall(frame.IsForbidden, frame)
    if not ok or IsSecret(v) then return true end
    return v == true
end

-- The unit a cell currently displays, or nil if forbidden/secret/none.
local function FrameUnit(frame)
    if not frame or Forbidden(frame) then return nil end
    local u = frame.displayedUnit or frame.unit or frame.unitToken
    if type(u) ~= "string" or u == "" or IsSecret(u) then
        if frame.GetAttribute then
            local ok, attr = pcall(frame.GetAttribute, frame, "unit")
            if ok and type(attr) == "string" and not IsSecret(attr) then
                u = attr
            else
                u = nil
            end
        else
            u = nil
        end
    end
    if type(u) ~= "string" or u == "" then return nil end
    if u:find("nameplate", 1, true) or u:find("pet", 1, true) then return nil end
    return u
end

local function InCombat()
    return InCombatLockdown() and true or false
end

-- true if `frame` currently shows `unit` (direct token or same-GUID unit).
local function FrameShowsUnit(frame, unit)
    local fu = FrameUnit(frame)
    if not fu then return false end
    if fu == unit then return true end
    local ok, same = pcall(UnitIsUnit, fu, unit)
    return ok and not IsSecret(same) and same == true
end

local function Visible(frame)
    if not frame or not frame.IsVisible then return false end
    local ok, v = pcall(frame.IsVisible, frame)
    return ok and not IsSecret(v) and v == true
end

-- Direct maps first: an addon that keys cells by unit needs no scan.
local function DirectLookup(unit)
    -- Cell: Cell.unitButtons.{solo,party.units,raid.units}[unit]
    local cell = _G.Cell and _G.Cell.unitButtons
    if type(cell) == "table" then
        local candidates = {
            cell.solo,
            cell.party and cell.party.units,
            cell.raid and cell.raid.units,
        }
        for i = 1, #candidates do
            local map = candidates[i]
            if type(map) == "table" and map[unit] then
                return map[unit]
            end
        end
    end
    -- Grid2: Grid2:GetUnitFrames(unit) -> set of frames
    if _G.Grid2 and _G.Grid2.GetUnitFrames then
        local ok, frames = pcall(_G.Grid2.GetUnitFrames, _G.Grid2, unit)
        if ok and type(frames) == "table" then
            for frame in pairs(frames) do
                if frame and not Forbidden(frame) then return frame end
            end
        end
    end
    return nil
end

-- Global frame names the scan looks up, built once at load rather than
-- concatenated on every scan (VuhDo alone is 510 names).
local function Names(fmt, a, b)
    local t = {}
    for i = 1, a do
        if b then
            for j = 1, b do t[#t + 1] = string.format(fmt, i, j) end
        else
            t[#t + 1] = string.format(fmt, i)
        end
    end
    return t
end
local BLIZZ_NAMES = Names("CompactRaidFrame%d", 40)
for _, n in ipairs(Names("CompactRaidGroup%dMember%d", 8, 5)) do BLIZZ_NAMES[#BLIZZ_NAMES + 1] = n end
for _, n in ipairs(Names("CompactPartyFrameMember%d", 5)) do BLIZZ_NAMES[#BLIZZ_NAMES + 1] = n end
local ERF_GROUP_NAMES = Names("ERFGroupHeader%d", 8)
local VUHDO_NAMES = Names("Vd%dH%d", 10, 51)
local CHILD_KEYS = Names("child%d", 40)

-- The scan's state lives in upvalues so a scan builds no closures. `Try` is
-- also what Blizzard's ApplyToFrames calls back, so it has to be a plain
-- function of the frame.
local scanUnit, scanFound

local function Try(frame)
    if scanFound or not frame then return end
    if Forbidden(frame) or not Visible(frame) then return end
    if FrameShowsUnit(frame, scanUnit) then scanFound = frame end
end

local function TryNames(names)
    for i = 1, #names do
        if scanFound then return end
        Try(_G[names[i]])
    end
end

-- DandersFrames: headers keyed by "childN"
local function WalkHeader(header, n)
    if not header or not header.GetAttribute then return end
    for i = 1, n do
        if scanFound then return end
        local ok, child = pcall(header.GetAttribute, header, CHILD_KEYS[i])
        if ok and child then Try(child) end
    end
end

-- Offer every candidate cell of the active frame addons to Try, stopping at
-- the first match. Kept to the addons we support; Blizzard is skipped when a
-- replacement addon is loaded.
local function ScanCandidates()
    local replaced = _G.DandersFrames or _G.ElvUF_Raid1 or _G.Grid2Frame
        or (_G.EllesmereUI or _G.ERFFlatHeader or _G.ERFGroupHeader1)
        or _G.VUHDO_UNIT_BUTTONS or (_G.Cell and _G.Cell.unitButtons)

    -- Blizzard compact frames
    if not replaced then
        if CompactRaidFrameContainer and CompactRaidFrameContainer.ApplyToFrames then
            pcall(CompactRaidFrameContainer.ApplyToFrames, CompactRaidFrameContainer, "normal", Try)
        end
        if CompactPartyFrame and CompactPartyFrame.ApplyToFrames then
            pcall(CompactPartyFrame.ApplyToFrames, CompactPartyFrame, "normal", Try)
        end
        TryNames(BLIZZ_NAMES)
    end
    if scanFound then return end

    local DF = _G.DandersFrames
    if type(DF) == "table" then
        WalkHeader(DF.partyHeader, 5)
        WalkHeader(DF.raidCombinedHeader, 40)
        if type(DF.raidSeparatedHeaders) == "table" then
            for g = 1, 8 do WalkHeader(DF.raidSeparatedHeaders[g], 5) end
        end
        if type(DF.raidFrames) == "table" then for i = 1, 40 do Try(DF.raidFrames[i]) end end
        if type(DF.partyFrames) == "table" then for i = 1, 5 do Try(DF.partyFrames[i]) end end
    end
    if scanFound then return end

    -- EllesmereUI raid frames
    local modules = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
    local ns = modules and modules.EllesmereUIRaidFrames
    if ns and type(ns._euiUnitButtons) == "table" then
        for frame in pairs(ns._euiUnitButtons) do Try(frame) end
    end
    if ns and type(ns._flatButtons) == "table" then
        for i = 1, #ns._flatButtons do Try(ns._flatButtons[i]) end
    end
    if _G.ERFFlatHeader then for i = 1, 40 do Try(_G.ERFFlatHeader[i]) end end
    for g = 1, 8 do
        local hdr = _G[ERF_GROUP_NAMES[g]]
        if hdr then for i = 1, 5 do Try(hdr[i]) end end
    end
    if scanFound then return end

    -- VuhDo heal buttons Vd<panel>H<button>
    if _G.VUHDO_UNIT_BUTTONS or _G.Vd1 then TryNames(VUHDO_NAMES) end
end

-- Scan candidates for the one that shows `unit`. Only reliable out of combat
-- (frame unit tokens can be secret in combat).
local function ScanForUnit(unit)
    scanUnit, scanFound = unit, nil
    ScanCandidates()
    local found = scanFound
    scanUnit, scanFound = nil, nil
    return found
end

-- A unit whose cell a full scan couldn't find is not scanned again for
-- MISS_TTL seconds. Without this, a target with no cell on screen (frames
-- hidden, unsupported frame addon) cost a full scan on every glow refresh.
-- Short enough that a cell appearing later is still picked up promptly.
local MISS_TTL = 2
local missUntil = {}   -- unit token -> GetTime() the miss expires

-- The raid/party cell currently showing `unit`, or nil. Cached; cache only
-- rebuilds out of combat so a mid-fight secret token can't drop a known cell.
function PI:FindUnitFrame(unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    local cached = frameCache[unit]
    if cached then
        -- Trust a cell we already found THROUGH combat, even if it is now a
        -- forbidden frame (EllesmereUI/others make their cells forbidden in
        -- combat) -- we can still anchor/draw on it. Dropping it here and being
        -- unable to re-scan in combat was the cause of the glow "disappearing".
        if InCombat() then return cached end
        -- Out of combat, revalidate it still shows this unit; drop it if not.
        if not Forbidden(cached) and FrameShowsUnit(cached, unit) and Visible(cached) then
            return cached
        end
        frameCache[unit] = nil
    end
    -- Direct maps are cheap and safe in combat, so they're always tried.
    local frame = DirectLookup(unit)
    if not frame and not InCombat() then
        local miss = missUntil[unit]
        if miss and GetTime() < miss then return nil end
        frame = ScanForUnit(unit)
        missUntil[unit] = (not frame) and (GetTime() + MISS_TTL) or nil
    end
    if frame then frameCache[unit] = frame end
    return frame
end

function PI:InvalidateFrameCache()
    wipe(missUntil)
    if InCombat() then return end
    wipe(frameCache)
end
