-- The glow engine. Binds one Blizzard AuraContainer to the assigned target's
-- cell, filtered to the tracked spell IDs. The engine shows an aura button when
-- a matching buff is present, and our glow (Glow.lua) is a child of that button,
-- so the glow appears exactly when the target uses a tracked cooldown -- with no
-- aura reading on our side (safe under 12.0 secret-value rules).
--
-- SetEnabled(false) works in combat, so that is how the glow is PI-gated: when
-- notify is off, we aren't a healer, or PI is on cooldown, the container is
-- disabled and the glow vanishes. Our own engine, scoped to a single target;
-- informed by, not copied from, the reference addon.
local _, PI = ...

local GROUP_KEY = "PIA_notify"
local containers = setmetatable({}, { __mode = "k" })  -- cell frame -> AuraContainer
local queued
local hookedCompact

local function Forbidden(frame)
    if not frame or not frame.IsForbidden then return false end
    local ok, v = pcall(frame.IsForbidden, frame)
    if not ok then return true end
    return v == true
end

local function AuraContainerReady()
    if not C_AddOns then return false end
    if C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then return true end
    pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    return C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") == true
end

local function HelpfulFilter()
    if AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.Helpful then
        return AuraUtil.AuraFilters.Helpful
    end
    return "HELPFUL"
end

local function FilterTable()
    return { includeSpellIDs = PI:GetTrackedSpellSet() }
end

-- The active notify mode for the current group context:
--   raid  -> "assignment" if notifyOnCooldown, else "off"
--   party -> the Dungeon Options setting ("off" | "assignment" | "alldps")
-- "assignment" watches your one PI target; "alldps" watches every party DPS.
function PI:GetNotifyMode()
    local db = PowerInfusionAssignmentsDB
    if not db or db.testMode then return "off" end
    if IsInRaid() then
        return db.notifyOnCooldown and "assignment" or "off"
    elseif IsInGroup() then   -- 5-man party / dungeon
        return db.dungeonMode or "off"
    end
    return "off"
end

-- Whether we should be WATCHING at all, independent of PI readiness: a healer
-- priest (or watchSelf), not in test mode, with at least one tracked spell.
-- Containers are created and BOUND based on this; PI readiness only toggles
-- SetEnabled (combat-safe), so the glow can resume mid-combat when PI comes back
-- without a SetUnit re-bind (SetUnit is restricted in combat). watchSelf
-- (/pi watchself) drops the spec gate for solo testing.
local function WatchAllowed()
    local db = PowerInfusionAssignmentsDB
    if not db or db.testMode then return false end
    if not next(PI:GetTrackedSpellSet()) then return false end
    if PI.watchSelf then return true end
    if not PI.playerIsPriest or not PI:IsHealerSpec() then return false end
    return true
end

-- Full gate incl. PI readiness (used by the /pi notify status readout).
local function NotifyAllowed()
    return WatchAllowed() and PI:IsPIReady()
end

-- A party member whose assigned role is not tank/healer (i.e. a DPS to watch).
-- Role can be secret in combat; treat unknown as "not DPS" to avoid false glows.
local function IsUnitDPS(unit)
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if not ok or (issecretvalue and issecretvalue(role)) or type(role) ~= "string" then
        return false
    end
    return role ~= "TANK" and role ~= "HEALER"
end

-- The set of unit tokens to watch right now, given mode + context. Fresh table
-- each call (callers may hold it across the other's call).
function PI:GetWatchedUnits()
    local units = {}
    if PI.watchSelf then units[1] = "player"; return units end
    local mode = PI:GetNotifyMode()
    if mode == "assignment" then
        local db = PowerInfusionAssignmentsDB
        local name = db.assignments and db.assignments[PI:GetPlayerName()]
        if name and name ~= "" then
            local tok = PI:GetUnitTokenForName(name)
            if tok then units[#units + 1] = tok end
        end
    elseif mode == "alldps" then
        -- Every DPS party member (dungeon). player is the healer priest, skipped.
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and IsUnitDPS(u) then units[#units + 1] = u end
        end
    end
    return units
end

-- Solo self-test: a fixed on-screen frame the aura container can bind to "player"
-- when there's no raid/party cell, so detection can be tested with no group.
local selfTestFrame
local function SelfTestFrame()
    if selfTestFrame then return selfTestFrame end
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent)
    if not ok or not f then return nil end
    f:SetSize(90, 44)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    f:SetFrameStrata("HIGH")   -- so the buff-tied fallback glow isn't buried
    f:EnableMouse(false)
    selfTestFrame = f
    return f
end

-- First watched unit, for the effect test preview.
local function TargetUnit()
    if PI.watchSelf then return "player" end
    local units = PI:GetWatchedUnits()
    return units[1]
end

local function SetLive(container, on)
    if not container then return end
    container.piaLive = on and true or false
    if container.SetEnabled then pcall(container.SetEnabled, container, on and true or false) end
end

local function DisableOthers(keep)
    for frame, container in pairs(containers) do
        if frame ~= keep then SetLive(container, false) end
    end
end

local function EnsureContainer(frame)
    local c = containers[frame]
    if c then return c end
    if Forbidden(frame) or not AuraContainerReady() then return nil end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    if not ok or not container then return nil end
    pcall(container.ClearAllPoints, container)
    pcall(container.SetPoint, container, "TOPLEFT", frame, "TOPLEFT")
    pcall(container.SetSize, container, 1, 1)
    pcall(container.EnableMouse, container, false)
    container.piaHasSlot = false
    containers[frame] = container
    return container
end

local function EnsureSlot(container, frame)
    if container.piaHasSlot then return true end
    local opts = {
        maxFrameCount = 1,
        candidateFilters = FilterTable(),
        initializeFrame = function(button)
            container.piaButton = button
            -- Fires when the engine first creates the button for this cell, i.e.
            -- a TRACKED buff (matching spell ID) actually appeared on this unit.
            -- If this never logs during a run, nothing matched (e.g. NPC/creature
            -- ability IDs differ from the player cooldown IDs we filter on) --
            -- that means "not detected", not "engine failed".
            PI:Debug("notify: tracked buff DETECTED on %s (aura button created)", tostring(container.piaUnit or "?"))
            PI:DecorateGlowButton(button, frame)
        end,
    }
    local ok = pcall(container.AddAuraSlot, container, GROUP_KEY, HelpfulFilter(), opts)
    if not ok and container.AddAuraGroup then
        ok = pcall(container.AddAuraGroup, container, GROUP_KEY, HelpfulFilter(), opts)
    end
    if not ok then return false end
    container.piaHasSlot = true
    return true
end

local function UpdateFilters(container)
    local f = FilterTable()
    if container.SetAuraSlotCandidateFilters then
        pcall(container.SetAuraSlotCandidateFilters, container, GROUP_KEY, f)
    elseif container.SetAuraGroupCandidateFilters then
        pcall(container.SetAuraGroupCandidateFilters, container, GROUP_KEY, f)
    end
end

-- Re-apply the persistent test preview with current settings. Previews EVERY
-- watched cell (all DPS in dungeon-alldps), so you can verify the glow attaches
-- to each cell without needing anyone to actually pop a cooldown -- and watch
-- cells appear/drop live. Falls back to a standalone box if nothing is found.
local previewCells = {}
function PI:RepaintTestPreview()
    if not PI.effectTesting then return end
    wipe(previewCells)
    local units = PI:GetWatchedUnits()
    for i = 1, #units do
        local f = PI:FindUnitFrame(units[i])
        if not f and PI.watchSelf then f = SelfTestFrame() end
        if f then previewCells[#previewCells + 1] = f end
    end
    if #previewCells == 0 then
        -- Nothing watched/found: try your target or own cell, else a box, so the
        -- Test button always shows something.
        local f = PI:FindUnitFrame(TargetUnit() or "player")
        if f then previewCells[1] = f end
    end
    if #previewCells > 0 then
        PI:ShowTestGlows(previewCells)
    else
        PI:StopCellGlow()
        PI:StartTestBoxGlow()
    end
end

-- Enable and (re)bind a container on one cell for one unit.
local function EnableContainerOn(frame, unit)
    local container = EnsureContainer(frame)
    if not container then return end
    if not EnsureSlot(container, frame) then return end
    UpdateFilters(container)
    -- Bind the unit ONCE (or when it actually changes). SetUnit must run while the
    -- container is enabled, so enable first. Crucially we must NOT re-SetUnit just
    -- because the PI gate toggled enabled off then on: SetUnit is restricted in
    -- combat, so a re-bind there silently fails and the container ends up
    -- enabled-but-unbound (PI ready, cells found, yet no glow -- the reported bug).
    -- Bind once, then only toggle SetEnabled (combat-safe) for the PI gate.
    if container.piaUnit ~= unit then
        if container.SetEnabled then pcall(container.SetEnabled, container, true) end
        container.piaUnit = unit
        if container.SetUnit then pcall(container.SetUnit, container, unit) end
        if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end
    end
    -- PI-ready gate: SetEnabled works in combat, so this can flip anytime.
    SetLive(container, PI:IsPIReady())
    -- The button is decorated once when the engine creates it (initializeFrame).
    -- Re-decorating touches textures on the (in-instance forbidden) aura button,
    -- so only do it OUT of combat, where those ops are allowed -- that is enough
    -- to apply a style/colour/size change the user made (always out of combat).
    if container.piaButton and not InCombatLockdown() then
        PI:DecorateGlowButton(container.piaButton, frame)
    end
end

local keptFrames = {}
local watchedSet = {}
function PI:RefreshGlow()
    queued = false
    if PI.effectTesting then return end   -- test preview owns the cell glow
    -- Tear down only when we shouldn't watch at all. When PI is merely on
    -- cooldown we KEEP the containers bound and let EnableContainerOn disable them
    -- via SetEnabled, so they can re-enable in combat when PI returns.
    if not WatchAllowed() then DisableOthers(nil); return end

    local units = PI:GetWatchedUnits()
    wipe(watchedSet)
    for i = 1, #units do watchedSet[units[i]] = true end
    wipe(keptFrames)
    -- One container per watched unit's cell (raid: your 1 target; dungeon-alldps:
    -- every DPS cell). watchSelf with no cell falls back to a standalone box.
    for i = 1, #units do
        local frame = PI:FindUnitFrame(units[i])
        if not frame and PI.watchSelf then frame = SelfTestFrame() end
        if frame and not keptFrames[frame] then
            keptFrames[frame] = true
            EnableContainerOn(frame, units[i])
        end
    end
    -- Disable a container only if its unit is no longer watched. A watched unit
    -- whose cell we couldn't find this pass (e.g. the finder can't scan in
    -- combat) KEEPS its existing container live rather than flapping the glow
    -- off -- the container is a child of the cell, so it stays put regardless.
    for frame, container in pairs(containers) do
        if not keptFrames[frame] then
            local u = container.piaUnit
            if not (u and watchedSet[u]) then SetLive(container, false) end
        end
    end
end

-- Re-resolve when Blizzard reassigns a cell's unit (raid re-sort, join/leave).
local function HookCompact()
    if hookedCompact then return end
    if type(CompactUnitFrame_SetUnit) == "function" then
        hookedCompact = true
        hooksecurefunc("CompactUnitFrame_SetUnit", function()
            PI:QueueGlowUpdate()
        end)
    end
end

function PI:QueueGlowUpdate()
    HookCompact()
    if queued then return end
    queued = true
    C_Timer.After(0.05, function()
        queued = false
        if PI.effectTesting then PI:RepaintTestPreview() else PI:RefreshGlow() end
    end)
end

-- Toggle a persistent preview of the current effect on EVERY watched cell,
-- bypassing detection and the gates, so the visuals + cell-finding can be checked
-- without anyone popping a cooldown (ideal in a follower dungeon). Returns state.
function PI:ToggleEffectTest()
    if PI.effectTesting then
        PI.effectTesting = false
        PI:StopCellGlow()
        return false
    end
    PI.effectTesting = true
    PI:RepaintTestPreview()
    return true
end

-- /pi notify: print exactly which gate is (or isn't) passing, so a glow that
-- won't show can be diagnosed instead of guessed.
function PI:NotifyStatus()
    local db = PowerInfusionAssignmentsDB
    local function yn(v) return v and "yes" or "no" end
    local set = PI:GetTrackedSpellSet()
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    local mode = PI:GetNotifyMode()
    local units = PI:GetWatchedUnits()
    PI:Out("|cff9cd6ff[PI]|r notify status:")
    PI:Out(string.format("  mode=%s notifyOn=%s dungeonMode=%s testMode=%s watchSelf=%s",
        mode, yn(db.notifyOnCooldown), tostring(db.dungeonMode), yn(db.testMode), yn(PI.watchSelf)))
    PI:Out(string.format("  priest=%s healerSpec=%s inRaid=%s inGroup=%s PIready=%s allowed=%s",
        yn(PI.playerIsPriest), yn(PI:IsHealerSpec()), yn(IsInRaid()), yn(IsInGroup()),
        yn(PI:IsPIReady()), yn(NotifyAllowed())))
    PI:Out(string.format("  trackedSpells=%d cdIcon=%s anchor=%s%s effect=%s countdown=%s",
        n, tostring(db.showCdIcon), tostring(db.cdAnchor), db.cdOutside and "(out)" or "",
        tostring(db.extraEffect), tostring(db.iconCountdown)))
    if #units == 0 then
        PI:Out("  watched units: (none) - mode off, no target, or no party DPS")
    end
    for i = 1, #units do
        local u = units[i]
        PI:Out(string.format("  watch %s (%s) cellFound=%s", u, tostring(PI:ShortName(PI:GetUnitName(u) or u)), yn(PI:FindUnitFrame(u))))
    end
end
