-- Notify sound. Uses C_UnitAuras.AddAuraSound: we register "play this sound
-- when spell X lands on unit Y" and the client plays it, so we never read an
-- aura (safe under 12.0 secret-value rules). Registration is combat-locked, so
-- it happens out of combat and retries on PLAYER_REGEN_ENABLED (driven from the
-- core event handler via PI:QueueSoundRegister).
--
-- Unlike the reference addon, which registers every raid token, we register
-- only the assigned target's token -- exactly the person we care about. The
-- trade the client forces on us: this sound cannot be gated on PI's cooldown
-- (AddAuraSound can't be toggled mid-fight), so it fires whenever the target
-- bursts. The glow handles the PI-ready gating; the sound is the ungated cue.
local _, PI = ...

-- Built-in sounds. AddAuraSound needs a FileDataID -- a "Sound\..." path string
-- is not playable through it -- so a preset carries a known fileID or a path we
-- resolve to a fileID. Any preset that fails to resolve is dropped so the picker
-- never offers a silent option.
PI.SOUND_PRESETS = {
    { key = "bell",       name = "Bell",         fileID = 567458 },
    { key = "raidwarn",   name = "Raid Warning", path = "Sound\\Interface\\RaidWarning.ogg" },
    { key = "readycheck", name = "Ready Check",  path = "Sound\\Interface\\ReadyCheck.ogg" },
}

local function ResolveFileID(preset)
    if type(preset.fileID) == "number" and preset.fileID > 1 then
        return preset.fileID
    end
    local path = preset.path
    if type(path) ~= "string" or path == "" then return nil end
    if GetFileIDFromPath then
        local ok, id = pcall(GetFileIDFromPath, path)
        if ok and type(id) == "number" and id > 1 then return id end
    end
    if C_UIFileAsset and C_UIFileAsset.GetFileID then
        local ok, id = pcall(C_UIFileAsset.GetFileID, path)
        if ok and type(id) == "number" and id > 1 then return id end
    end
    return nil
end

local resolvedPresets
local function Presets()
    if resolvedPresets then return resolvedPresets end
    resolvedPresets = {}
    for i = 1, #PI.SOUND_PRESETS do
        local p = PI.SOUND_PRESETS[i]
        local id = ResolveFileID(p)
        if id then
            resolvedPresets[#resolvedPresets + 1] = { key = p.key, name = p.name, fileID = id }
        end
    end
    return resolvedPresets
end

local function PresetByKey(key)
    if not key or key == "none" then return nil end
    local list = Presets()
    for i = 1, #list do
        if list[i].key == key then return list[i] end
    end
    return nil
end

local function GetLSM()
    local stub = _G.LibStub
    if type(stub) ~= "function" and type(stub) ~= "table" then return nil end
    local ok, lib = pcall(stub, "LibSharedMedia-3.0", true)
    if ok and type(lib) == "table" then return lib end
    return nil
end

-- Resolve any sound key to a playable descriptor: { fileID = n } or { path = s }.
-- Handles built-in presets and "lsm:<name>" LibSharedMedia entries. AddAuraSound
-- takes a FileDataID or a real file path (addon paths work; Blizzard Sound\ ones
-- do not, which is why the built-ins carry file IDs).
local function ResolveSoundMedia(key)
    if not key or key == "none" then return nil end
    local lsmName = key:match("^lsm:(.+)$")
    if lsmName then
        local lsm = GetLSM()
        if lsm and lsm.Fetch then
            local data = lsm:Fetch("sound", lsmName, true)
            if type(data) == "number" and data > 1 then return { fileID = data } end
            if type(data) == "string" and data ~= "" then return { path = data } end
        end
        return nil
    end
    local p = PresetByKey(key)
    if p then return { fileID = p.fileID } end
    return nil
end

-- Ordered list for the picker: "None", built-in presets, then LibSharedMedia
-- sounds (BigWigs/Details/etc.) if that library is present.
function PI:GetSoundItems()
    local items = { { key = "none", name = "None" } }
    local list = Presets()
    for i = 1, #list do
        items[#items + 1] = { key = list[i].key, name = list[i].name }
    end
    local lsm = GetLSM()
    if lsm and lsm.List then
        local names = lsm:List("sound")
        if type(names) == "table" then
            for i = 1, #names do
                items[#items + 1] = { key = "lsm:" .. names[i], name = names[i] }
            end
        end
    end
    return items
end

function PI:GetSoundName(key)
    if not key or key == "none" then return "None" end
    local lsmName = key:match("^lsm:(.+)$")
    if lsmName then return lsmName end
    local p = PresetByKey(key)
    return p and p.name or key
end

-- Test button: play the given sound now.
function PI:PlayTestSound(key)
    local m = ResolveSoundMedia(key)
    if not m then return end
    pcall(PlaySoundFile, m.fileID or m.path, PowerInfusionAssignmentsDB.soundChannel or "Master")
end

-- Handles from AddAuraSound, kept so we can remove them on the next refresh.
local auraSoundIDs = {}
local queued

local function TriggerAdded()
    if Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added then
        return Enum.UnitAuraSoundTrigger.Added
    end
    return 0
end

-- AddAuraSound is blocked in combat/encounters; refresh retries on combat end.
local function SoundsLocked()
    return InCombatLockdown() and true or false
end

function PI:ClearTargetSounds()
    if C_UnitAuras and C_UnitAuras.RemoveAuraSound then
        for i = 1, #auraSoundIDs do
            pcall(C_UnitAuras.RemoveAuraSound, auraSoundIDs[i])
        end
    end
    wipe(auraSoundIDs)
end

-- Register a play-on-appearance sound for every tracked spell on the assigned
-- target's raid token. Only for a healer priest with notify on and a sound
-- chosen. Cleared and rebuilt from scratch each call so it always reflects the
-- current target, spell set and sound.
function PI:RegisterTargetSounds()
    PI:ClearTargetSounds()
    local db = PowerInfusionAssignmentsDB
    if not db or not db.notifyOnCooldown then return end
    if db.testMode then return end
    if not PI.watchSelf and (not PI.playerIsPriest or not PI:IsHealerSpec()) then return end
    if not db.soundName or db.soundName == "none" then return end
    if not C_UnitAuras or not C_UnitAuras.AddAuraSound then return end
    -- Only arm while PI is ready. It cannot re-arm mid-combat (AddAuraSound is
    -- combat-locked), so after you PI the cue stays gone until combat ends;
    -- that is the one gap we can't close with a client-driven sound.
    if PI.IsPIReady and not PI:IsPIReady() then return end

    -- /pi watchself points the sound at your own token for testing.
    local token
    if PI.watchSelf then
        token = "player"
    else
        local myTarget = db.assignments and db.assignments[PI:GetPlayerName()]
        if not myTarget or myTarget == "" then return end
        token = PI:GetUnitTokenForName(myTarget)
    end
    if not token then return end
    if SoundsLocked() then return end  -- retried on PLAYER_REGEN_ENABLED

    local media = ResolveSoundMedia(db.soundName)
    if not media then return end
    local channel = db.soundChannel or "Master"
    for spellID in pairs(PI:GetTrackedSpellSet()) do
        local info = {
            spellID = spellID,
            unitToken = token,
            outputChannel = channel,
        }
        if media.fileID then info.soundFileID = media.fileID else info.soundFileName = media.path end
        local ok, id = pcall(C_UnitAuras.AddAuraSound, TriggerAdded(), info)
        if ok and type(id) == "number" then
            auraSoundIDs[#auraSoundIDs + 1] = id
        end
    end
    PI:Debug("registered %d aura sounds on %s", #auraSoundIDs, tostring(token))
end

-- Debounced: several triggers (target change, roster, settings) can fire in one
-- frame, so coalesce into a single re-register on the next tick.
function PI:QueueSoundRegister()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        PI:RegisterTargetSounds()
    end)
end
