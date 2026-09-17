-- Cooldown catalog: which offensive cooldowns the notify feature can watch,
-- organised by DPS spec. Detection only ever needs the flat set of enabled
-- spell IDs (PI:GetTrackedSpellSet); the per-spec grouping exists purely so the
-- Tracking tab reads well. Tanks and healers are omitted on purpose -- a PI
-- target is a DPS, and we only ever watch our own target.
--
-- The spell IDs are current 12.0 burst cooldowns; names are only fallbacks, as
-- PI:GetSpellDisplayName resolves the live localised name from the ID when it
-- can. A few specs have no confident default and are left empty; the custom
-- spell-ID box in the Tracking tab covers those and anything else.
local _, PI = ...

-- Ordered so the Tracking tab lists classes alphabetically, specs within class
-- in their in-game order. Each entry: class file, spec name, spec id, and the
-- cooldowns as { spellID, fallbackName } pairs.
PI.TRACK_CATALOG = {
    { class = "DEATHKNIGHT", spec = "Frost",         specID = 251,  cds = { {51271, "Pillar of Frost"} } },
    { class = "DEATHKNIGHT", spec = "Unholy",        specID = 252,  cds = { {42650, "Army of the Dead"} } },
    { class = "DEMONHUNTER", spec = "Havoc",         specID = 577,  cds = { {162264, "Metamorphosis"} } },
    { class = "DEMONHUNTER", spec = "Devourer",      specID = 1474,  cds = { {1217607, "Void Metamorphosis"} } },
    { class = "DRUID",       spec = "Balance",       specID = 102,  cds = { {102560, "Incarnation: Chosen of Elune"}, {194223, "Celestial Alignment"} } },
    { class = "DRUID",       spec = "Feral",         specID = 103,  cds = { {106951, "Berserk"} } },
    { class = "EVOKER",      spec = "Devastation",   specID = 1467, cds = { {375087, "Dragonrage"} } },
    { class = "HUNTER",      spec = "Beast Mastery", specID = 253,  cds = { {19574, "Bestial Wrath"} } },
    { class = "HUNTER",      spec = "Marksmanship",  specID = 254,  cds = { {288613, "Trueshot"} } },
    { class = "HUNTER",      spec = "Survival",      specID = 255,  cds = { {1250646, "Takedown"} } },
    { class = "MAGE",        spec = "Arcane",        specID = 62,   cds = { {365362, "Arcane Surge"} } },
    { class = "MAGE",        spec = "Fire",          specID = 63,   cds = { {190319, "Combustion"} } },
    { class = "MAGE",        spec = "Frost",         specID = 64,   cds = { {1247908, "Splinterstorm"} } },
    { class = "MONK",        spec = "Windwalker",    specID = 269,  cds = { {1249625, "Zenith"}, {1248992, "Celestial Conduit"} } },
    { class = "PALADIN",     spec = "Retribution",   specID = 70,   cds = { {31884, "Avenging Wrath"} } },
    { class = "PRIEST",      spec = "Shadow",        specID = 258,  cds = { {194249, "Voidform"} } },
    { class = "ROGUE",       spec = "Assassination", specID = 259,  cds = { {1249810, "Deathmark"} } },
    { class = "ROGUE",       spec = "Outlaw",        specID = 260,  cds = { {13750, "Adrenaline Rush"} } },
    { class = "ROGUE",       spec = "Subtlety",      specID = 261,  cds = { {121471, "Shadow Blades"} } },
    { class = "SHAMAN",      spec = "Elemental",     specID = 262,  cds = { {1219480, "Ascendance"} } },
    { class = "SHAMAN",      spec = "Enhancement",   specID = 263,  cds = { {114051, "Ascendance"} } },
    { class = "WARLOCK",     spec = "Affliction",    specID = 265,  cds = { {442726, "Malevolence"} } },
    { class = "WARLOCK",     spec = "Demonology",    specID = 266,  cds = { {1276166, "Summon Demonic Tyrant"} } },
    { class = "WARLOCK",     spec = "Destruction",   specID = 267,  cds = { {266087, "Summon Infernal"}, {417282, "Crashing Chaos"} } },
    { class = "WARRIOR",     spec = "Arms",          specID = 71,   cds = { {107574, "Avatar"} } },
    { class = "WARRIOR",     spec = "Fury",          specID = 72,   cds = { {1719, "Recklessness"} } },
}

-- Live, localised spell name when the client can give one; the catalog's
-- fallback string otherwise (a spell not yet in the local cache, or a custom
-- ID the client doesn't know). Improves on hard-coded names.
function PI:GetSpellDisplayName(spellID, fallback)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return fallback or ("Spell "..tostring(spellID))
end

-- Saved-variable defaults for tracking. Called from PI:InitDB.
-- trackedSpells: spellID -> false to disable; absent means enabled (default on).
-- customSpells: array of extra spell IDs to watch.
function PI:InitTrackingDB()
    local db = PowerInfusionAssignmentsDB
    if db.notifyOnCooldown == nil then db.notifyOnCooldown = true end
    -- Dungeon (5-man) cooldown alerts: "off" | "assignment" | "alldps".
    -- Fresh installs default to "alldps"; an existing choice (incl. "off") is kept.
    if db.dungeonMode == nil then db.dungeonMode = "alldps" end
    if db.dungeonMode ~= "assignment" and db.dungeonMode ~= "alldps" and db.dungeonMode ~= "off" then
        db.dungeonMode = "off"
    end
    if type(db.trackedSpells) ~= "table" then db.trackedSpells = {} end
    if type(db.customSpells) ~= "table" then db.customSpells = {} end
    -- Alert visuals are now two INDEPENDENT things: the cooldown icon (shows the
    -- actual cooldown's icon + a countdown) and, optionally, an extra Pulse Border
    -- / Flash Frame effect on the cell. These used to be one 3-way `glowStyle`;
    -- migrate that once to the split model.
    if db.showCdIcon == nil then
        local gs = db.glowStyle
        if gs == "border" or gs == "fill" then
            db.showCdIcon = false
            db.extraEffect = gs
        else  -- "picon"/"pixel" (old icon-only) or unset (fresh install)
            db.showCdIcon = true
            -- Fresh installs default to a pulse border too; old icon-only users keep none.
            db.extraEffect = (gs == nil) and "border" or "none"
        end
    end
    if db.extraEffect ~= "border" and db.extraEffect ~= "fill" then db.extraEffect = "none" end
    -- Cooldown-icon anchor: a 9-point anchor on the cell, optionally just OUTSIDE
    -- the cell edge (handy in dungeons; less so in raids).
    local ANCHORS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    if not ANCHORS[db.cdAnchor] then db.cdAnchor = "CENTER" end
    if db.cdOutside == nil then db.cdOutside = false end
    if type(db.glowColor) ~= "table" then
        db.glowColor = { 0.87058, 0.87058, 0 }  -- #dede00
    end
    -- Which icon the cell shows: "cooldown" (the actual spell used) or "pi" (the
    -- Power Infusion icon, the default). db.showCdIcon is the on/off; "none" in the picker.
    if db.iconType ~= "pi" and db.iconType ~= "cooldown" then db.iconType = "pi" end
    -- Cooldown-icon size (px), nudge offset (px) and opacity (percent).
    if type(db.iconSize) ~= "number" then db.iconSize = 30 end
    if type(db.iconX) ~= "number" then db.iconX = 0 end
    if type(db.iconY) ~= "number" then db.iconY = 0 end
    if type(db.iconAlpha) ~= "number" then db.iconAlpha = 100 end
    if db.iconCountdown == nil then db.iconCountdown = true end  -- number on the icon
    -- Pulse Border / Flash Frame effect: intensity (alpha percent) and border thickness.
    if type(db.glowAlpha) ~= "number" then db.glowAlpha = 70 end
    if type(db.pixelThickness) ~= "number" then db.pixelThickness = 5 end
end

-- True on a healer priest (Discipline 256 / Holy 257). The notify feature only
-- acts for healers; Shadow keeps the plain assign-and-PI flow. Own spec is
-- readable even under combat secret-value rules.
function PI:IsHealerSpec()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if type(getSpec) ~= "function" or type(getInfo) ~= "function" then return false end
    local ok, idx = pcall(getSpec)
    if not ok or type(idx) ~= "number" then return false end
    local ok2, specID = pcall(getInfo, idx)
    if not ok2 or type(specID) ~= "number" then return false end
    return specID == 256 or specID == 257
end

-- A catalog cooldown is on unless explicitly disabled. Custom spells are always on.
function PI:IsSpellTracked(spellID)
    local t = PowerInfusionAssignmentsDB.trackedSpells
    return not (t and t[spellID] == false)
end

function PI:SetSpellTracked(spellID, enabled)
    local t = PowerInfusionAssignmentsDB.trackedSpells
    -- Store false to disable; clear back to nil (the default-on state) to enable,
    -- so the table only ever holds the user's deviations from the defaults.
    if enabled then
        t[spellID] = nil
    else
        t[spellID] = false
    end
end

-- The flat { [spellID] = true } set the detection engine filters on: every
-- enabled catalog cooldown plus every custom ID.
function PI:GetTrackedSpellSet()
    local set = {}
    for i = 1, #PI.TRACK_CATALOG do
        local cds = PI.TRACK_CATALOG[i].cds
        for j = 1, #cds do
            local id = cds[j][1]
            if PI:IsSpellTracked(id) then set[id] = true end
        end
    end
    local custom = PowerInfusionAssignmentsDB.customSpells
    if type(custom) == "table" then
        for i = 1, #custom do
            local id = custom[i]
            if type(id) == "number" then set[id] = true end
        end
    end
    return set
end

-- Returns true if the id was added, false if invalid or already present.
function PI:AddCustomSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return false end
    spellID = math.floor(spellID)
    local custom = PowerInfusionAssignmentsDB.customSpells
    for i = 1, #custom do
        if custom[i] == spellID then return false end
    end
    custom[#custom + 1] = spellID
    return true
end

function PI:RemoveCustomSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID then return end
    local custom = PowerInfusionAssignmentsDB.customSpells
    for i = #custom, 1, -1 do
        if custom[i] == spellID then table.remove(custom, i) end
    end
end
