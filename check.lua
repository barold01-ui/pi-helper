-- Offline stub harness for PowerInfusionAssignments.lua (Lua 5.1)
-- Stubs enough of the WoW API to load the addon and exercise its logic.

local sent = {}          -- captured SendChatMessage calls
local addonMsgs = {}     -- captured SendAddonMessage calls
local prints = {}

-- ---------------------------------------------------------------- utilities
function strsplit(delim, str)
    local out = {}
    local pattern = "([^"..delim.."]*)"..delim
    local last = 1
    for cap, pos in string.gmatch(str, "()"..pattern) do end
    -- simple manual split
    out = {}
    local start = 1
    while true do
        local s, e = string.find(str, delim, start, true)
        if not s then out[#out+1] = string.sub(str, start) break end
        out[#out+1] = string.sub(str, start, s-1)
        start = e + 1
    end
    return unpack(out)
end
function strlower(s) return string.lower(s) end
function strtrim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local realPrint = print
function print(...) prints[#prints+1] = table.concat({...}, " ") end

-- ---------------------------------------------------------------- frame stub
local frameMT = {}
frameMT.__index = function(t, k)
    if type(k) == "string" and string.sub(k, 1, 1) == "_" then return nil end
    local fn = rawget(t, "_methods") and rawget(t, "_methods")[k]
    if fn then return fn end
    -- generic no-op method
    return function(self, ...) return self end
end

local function NewStub()
    local o = { _scripts = {}, _shown = true, _text = "" }
    o._methods = {
        SetScript = function(self, name, fn) self._scripts[name] = fn end,
        GetScript = function(self, name) return self._scripts[name] end,
        SetText = function(self, s) self._text = s or "" end,
        GetText = function(self) return self._text end,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        IsShown = function(self) return self._shown end,
        SetShown = function(self, v) self._shown = v and true or false end,
        -- Retail rejects a nil flags argument; mirror that so the harness
        -- catches it instead of the client doing it at load time.
        SetFont = function(self, file, height, flags)
            if type(file) ~= "string" or type(height) ~= "number" or type(flags) ~= "string" then
                error("SetFont(fontFile, height, flags): flags is required", 2)
            end
        end,
        GetFrameLevel = function() return 1 end,
        GetParent = function(self) return self._parent end,
        GetStringWidth = function() return 100 end,
        GetStringHeight = function() return 12 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetChecked = function(self) return self._checked end,
        SetChecked = function(self, v) self._checked = v end,
        RegisterEvent = function(self, e) self._events = self._events or {}; self._events[e] = true end,
        CreateFontString = function() return NewStub() end,
        CreateTexture = function() return NewStub() end,
    }
    return setmetatable(o, frameMT)
end

UIParent = NewStub()
GameTooltip = NewStub()

local eventFrame = nil
function CreateFrame(kind, name, parent, template)
    local o = NewStub()
    o._parent = parent
    if name then _G[name] = o end
    if not eventFrame and kind == "Frame" and name == nil and parent == nil then
        eventFrame = o
    end
    return o
end

-- ---------------------------------------------------------------- world stub
local world = {
    realm = "Frostmourne",
    playerName = "Mypriest",
    playerClass = "PRIEST",
    zone = "Liberation of Undermine",
    inRaid = true,
    raid = {}, -- { name=, realm=, class=, zone=, role=, guild=, connected= }
}

function GetNormalizedRealmName() return world.realm end
function UnitFullName(unit)
    if unit == "player" then return world.playerName, world.realm end
end
function GetZoneText() return world.zone end
function IsInRaid() return world.inRaid end
function IsInGroup() return world.inRaid end
LE_PARTY_CATEGORY_INSTANCE = 2
function GetNumGroupMembers() return #world.raid end
function GetTime() return world.time or 0 end
function GetInstanceInfo()
    return "Undermine", world.instanceType or "raid", 1, "Mythic", 20
end

local function member(unit)
    local i = tonumber(string.match(unit or "", "^raid(%d+)$"))
    if i then return world.raid[i] end
    if unit == "player" then
        return { name = world.playerName, realm = world.realm, class = world.playerClass,
                 zone = world.zone, role = "HEALER", guild = true, connected = true }
    end
    return world.mouseover
end

function UnitExists(unit) return member(unit) ~= nil end
function UnitIsConnected(unit) local m = member(unit); return m and m.connected ~= false end
function UnitName(unit)
    local m = member(unit)
    if not m then return nil end
    -- WoW returns realm only when it differs from the player's
    if m.realm and m.realm ~= world.realm then return m.name, m.realm end
    return m.name, nil
end
function UnitClass(unit)
    local m = member(unit)
    if not m then return nil end
    return m.class, m.class
end
function UnitGroupRolesAssigned(unit) local m = member(unit); return m and m.role or "NONE" end
function UnitIsInMyGuild(unit) local m = member(unit); return m and m.guild or false end
function GetRaidRosterInfo(i)
    local m = world.raid[i]
    if not m then return nil end
    local full = m.name
    if m.realm and m.realm ~= world.realm then full = m.name.."-"..m.realm end
    return full, 0, 1, 70, m.class, m.class, m.zone, m.connected ~= false, false, m.role, false, m.role
end

-- only used by the pre-fix version, kept so the same harness runs against both
function GetNumGuildMembers() return #world.raid end
function GetGuildRosterInfo(i)
    local m = world.raid[i]
    if not m or not m.guild then return nil end
    local full = m.name
    if m.realm and m.realm ~= world.realm then full = m.name.."-"..m.realm end
    return full
end

RAID_CLASS_COLORS = {
    PRIEST  = { r = 1,    g = 1,    b = 1    },
    ROGUE   = { r = 1,    g = 0.96, b = 0.41 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    MAGE    = { r = 0.25, g = 0.78, b = 0.92 },
}

-- macros
local macros = {}
function GetNumMacros() return #macros, 0 end
function GetMacroInfo(i)
    local m = macros[i]
    if not m then return nil end
    return m.name, "icon", m.body
end
function GetMacroIndexByName(name)
    for i, m in ipairs(macros) do if m.name == name then return i end end
    return 0
end

function SendChatMessage(msg, chatType, lang, target)
    sent[#sent+1] = { msg = msg, chatType = chatType, target = target }
end

C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(prefix, payload, channel)
        addonMsgs[#addonMsgs+1] = { prefix = prefix, payload = payload, channel = channel }
    end,
}

local tickers = {}
local deferred = {}
C_Timer = {
    NewTicker = function(interval, fn)
        local t = { fn = fn, cancelled = false }
        t.Cancel = function(self) self.cancelled = true end
        tickers[#tickers+1] = t
        return t
    end,
    After = function(delay, fn) deferred[#deferred+1] = fn end,
}
-- run anything queued with C_Timer.After, as the next frame would
local function flush()
    while #deferred > 0 do
        local fn = table.remove(deferred, 1)
        fn()
    end
end

-- UI odds and ends
SlashCmdList = {}
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function IsControlKeyDown() return false end
GameFontNormal, GameFontHighlight, GameFontHighlightLarge, GameFontGreen = {}, {}, {}, {}

-- ---------------------------------------------------------------- run addon
local src = assert(io.open(arg[1] or "PowerInfusionAssignments.lua", "r"))
local chunk = assert(loadstring(src:read("*a"), "@PowerInfusionAssignments.lua"))
src:close()
chunk()

local fire = function(...) eventFrame._scripts.OnEvent(eventFrame, ...); flush() end
local function tick()
    for _, t in ipairs(tickers) do if not t.cancelled then t.fn() end end
    flush()
end

-- ---------------------------------------------------------------- assertions
local failures = 0
local function check(label, cond, detail)
    if cond then
        realPrint("  ok   "..label)
    else
        failures = failures + 1
        realPrint("  FAIL "..label..(detail and ("  -> "..tostring(detail)) or ""))
    end
end

-- The panel draws one row frame per assignment rather than a single
-- FontString, so flatten the visible rows back to "Priest -> Target" text.
local function panelText()
    local out = {}
    for _, row in ipairs(PIAssignmentFrame and PIAssignmentFrame.rows or {}) do
        if row:IsShown() then
            out[#out+1] = row.name:GetText().." -> "..row.target:GetText()
        end
    end
    return table.concat(out, "\n")
end

realPrint("== scenario: cross-realm raid, macro mode ==")

world.raid = {
    { name = "Mypriest",   realm = "Frostmourne", class = "PRIEST",  zone = world.zone, role = "HEALER",  guild = true },
    { name = "Zaltpriest",  realm = "Barthilas",   class = "PRIEST",  zone = world.zone, role = "DAMAGER", guild = true },
    { name = "Roguestab",  realm = "Barthilas",   class = "ROGUE",   zone = world.zone, role = "DAMAGER", guild = true },
    { name = "Tankwar",    realm = "Frostmourne", class = "WARRIOR", zone = world.zone, role = "TANK",    guild = true },
    { name = "Firemage",   realm = "Frostmourne", class = "MAGE",    zone = "Dornogal",  role = "DAMAGER", guild = false },
}
macros[1] = { name = "PI", body = "/use [@mouseover,nodead,help]Power Infusion;[@Roguestab,exists,nodead]Power Infusion;[@player]Power Infusion" }

PowerInfusionAssignmentsDB = { macroName = "PI", piMode = 1, enableWhispers = true }
fire("PLAYER_LOGIN")

local DB = PowerInfusionAssignmentsDB
tick()

check("own name is realm-qualified", DB.assignments["Mypriest-Frostmourne"] ~= nil,
      (next(DB.assignments)))
check("macro target resolved to the cross-realm player",
      DB.assignments["Mypriest-Frostmourne"] == "Roguestab-Barthilas",
      DB.assignments["Mypriest-Frostmourne"])
check("whisper went to the qualified name",
      sent[1] and sent[1].target == "Roguestab-Barthilas" and sent[1].chatType == "WHISPER",
      sent[1] and sent[1].target)
check("broadcast payload stays 1.4.x-readable, target qualified",
      addonMsgs[1] and addonMsgs[1].payload == "Mypriest:Roguestab-Barthilas",
      addonMsgs[1] and addonMsgs[1].payload)

realPrint("== inbound message from a cross-realm priest ==")
-- payload deliberately lies about the sender; identity must come from `sender`
fire("CHAT_MSG_ADDON", "PIAssign", "Someoneelse:Tankwar", "RAID", "Zaltpriest-Barthilas")
check("assignment keyed off sender, not payload",
      DB.assignments["Zaltpriest-Barthilas"] == "Tankwar-Frostmourne",
      DB.assignments["Zaltpriest-Barthilas"])
check("spoofed name was not stored", DB.assignments["Someoneelse"] == nil)

tick()
check("cross-realm priest survives cleanup", DB.assignments["Zaltpriest-Barthilas"] ~= nil)

realPrint("== warnings ==")
local frameText = _G["PIAssignmentFrame"]
check("role warning fires for cross-realm assigner on a tank",
      string.find(PIAssignmentFrame.errorText:GetText(), "HEALER or TANK") ~= nil,
      PIAssignmentFrame.errorText:GetText())

-- both priests onto the same target
fire("CHAT_MSG_ADDON", "PIAssign", "x:Roguestab-Barthilas", "RAID", "Zaltpriest-Barthilas")
check("duplicate warning fires",
      string.find(PIAssignmentFrame.errorText:GetText(), "Duplicate") ~= nil,
      PIAssignmentFrame.errorText:GetText())

-- target in a different zone
fire("CHAT_MSG_ADDON", "PIAssign", "x:Firemage-Frostmourne", "RAID", "Zaltpriest-Barthilas")
check("different-zone warning fires",
      string.find(PIAssignmentFrame.errorText:GetText(), "different zone") ~= nil,
      PIAssignmentFrame.errorText:GetText())

-- target that left the raid
fire("CHAT_MSG_ADDON", "PIAssign", "x:Ghost-Frostmourne", "RAID", "Zaltpriest-Barthilas")
check("not-in-raid warning fires",
      string.find(PIAssignmentFrame.errorText:GetText(), "not in the raid") ~= nil,
      PIAssignmentFrame.errorText:GetText())

realPrint("== display strips realms ==")
local plain = panelText()
check("display shows short names",
      string.find(plain, "Mypriest %-> Roguestab") ~= nil, plain)
check("display does not leak a realm suffix",
      string.find(plain, "%-Barthilas") == nil, plain)
check("the player's own row is first and ticked",
      PIAssignmentFrame.rows[1].name:GetText() == "Mypriest"
      and PIAssignmentFrame.rows[1].tick:IsShown(),
      PIAssignmentFrame.rows[1].name:GetText())
check("other priests' rows are not ticked",
      not PIAssignmentFrame.rows[2].tick:IsShown())

realPrint("== !pi reporting ==")
fire("CHAT_MSG_ADDON", "PIAssign", "x:Tankwar-Frostmourne", "RAID", "Zaltpriest-Barthilas")
sent = {}
world.time = 100
fire("CHAT_MSG_RAID", "!pi", "Roguestab-Barthilas")
check("responder replied once, packed into one line", #sent == 1, #sent.." messages")
check("reply is zone-filtered and short-named",
      sent[1] and sent[1].msg == "[PI] Mypriest -> Roguestab | Zaltpriest -> Tankwar",
      sent[1] and sent[1].msg)

world.time = 102
fire("CHAT_MSG_RAID", "!pi", "Roguestab-Barthilas")
check("second !pi within cooldown is ignored", #sent == 1, #sent.." messages")
world.time = 200
fire("CHAT_MSG_RAID", "!pi", "Roguestab-Barthilas")
check("!pi works again after the cooldown", #sent == 2, #sent.." messages")

-- 12.0 can deliver a chat payload as a secret value, which errors on any read
-- (#msg, strlower, ...) while our code is on the stack. A userdata whose __len
-- and __index throw is the closest a plain Lua 5.1 harness gets to one.
local secretChat = newproxy(true)
do
    local mt = getmetatable(secretChat)
    mt.__len = function() error("attempt to get length of a secret string value", 0) end
    mt.__index = function() error("attempt to index a secret string value", 0) end
    mt.__concat = mt.__index
end
issecretvalue = function(v) return v == secretChat end
sent = {}
world.time = 500
local secretOk, secretErr = pcall(fire, "CHAT_MSG_RAID", secretChat, secretChat)
check("a secret chat message is dropped instead of read", secretOk, secretErr)
check("nothing is sent for a secret message", #sent == 0, #sent.." messages")
world.time = 505
fire("CHAT_MSG_RAID", "!pi", "Roguestab-Barthilas")
check("a secret message doesn't consume the !pi cooldown", #sent == 1, #sent.." messages")
issecretvalue = nil

-- a priest sorting before us must win the election, leaving us silent
world.raid[#world.raid+1] = { name = "Apriest", realm = "Frostmourne", class = "PRIEST",
                              zone = world.zone, role = "DAMAGER", guild = true }
fire("GROUP_ROSTER_UPDATE")
DB.assignments["Apriest-Frostmourne"] = "Roguestab-Barthilas"
sent = {}
world.time = 400
fire("CHAT_MSG_RAID", "!pi", "Roguestab-Barthilas")
check("stays silent when another priest is elected responder", #sent == 0, #sent.." messages")
table.remove(world.raid, #world.raid)
DB.assignments["Apriest-Frostmourne"] = nil

realPrint("== leaving the group ==")
table.remove(world.raid, 2) -- Zaltpriest leaves
fire("GROUP_ROSTER_UPDATE")
check("departed priest is dropped", DB.assignments["Zaltpriest-Barthilas"] == nil)
check("own assignment is kept", DB.assignments["Mypriest-Frostmourne"] == "Roguestab-Barthilas")

realPrint("== test mode ==")
PI_TestModeCheckbox = nil
local o = _G["PIOptionsWindow"]
-- drive it through the same entry point the checkbox uses
local PIref = getmetatable(o) -- not reachable; use the slash command surface instead
SlashCmdList["POWERINFUSION"]("")
check("slash command toggled the options window", o:IsShown() == true)

realPrint("== 1.4.x wire compatibility ==")
-- a same-realm target must go out unqualified, exactly as 1.4.x sent it,
-- or 1.4.x clients drop it on their next cleanup pass
world.raid = {
    { name = "Mypriest",  realm = "Frostmourne", class = "PRIEST",  zone = world.zone, role = "HEALER",  guild = true },
    { name = "Homeboy",   realm = "Frostmourne", class = "ROGUE",   zone = world.zone, role = "DAMAGER", guild = true },
    { name = "Awayboy",   realm = "Barthilas",   class = "ROGUE",   zone = world.zone, role = "DAMAGER", guild = true },
    { name = "Zpriest",   realm = "Barthilas",   class = "PRIEST",  zone = world.zone, role = "DAMAGER", guild = true },
}
fire("GROUP_ROSTER_UPDATE")
macros[1].body = "/use [@Homeboy,exists,nodead]Power Infusion"
cachedreset = nil
addonMsgs = {}
PI_previous = nil
DB.assignments = {}
-- force a re-scan by clearing the cached macro body via a rename round-trip
DB.macroName = "PI"
tick()
check("same-realm target is sent unqualified (1.4.x readable)",
      addonMsgs[#addonMsgs] and addonMsgs[#addonMsgs].payload == "Mypriest:Homeboy",
      addonMsgs[#addonMsgs] and addonMsgs[#addonMsgs].payload)
check("but is stored qualified locally",
      DB.assignments["Mypriest-Frostmourne"] == "Homeboy-Frostmourne",
      DB.assignments["Mypriest-Frostmourne"])

macros[1].body = "/use [@Awayboy,exists,nodead]Power Infusion"
tick()
check("cross-realm target keeps its realm on the wire",
      addonMsgs[#addonMsgs] and addonMsgs[#addonMsgs].payload == "Mypriest:Awayboy-Barthilas",
      addonMsgs[#addonMsgs] and addonMsgs[#addonMsgs].payload)

-- inbound, in the shape a 1.4.x client would send it
fire("CHAT_MSG_ADDON", "PIAssign", "Zpriest:Homeboy", "RAID", "Zpriest-Barthilas")
check("bare target from a cross-realm 1.4.x sender resolves to the real player",
      DB.assignments["Zpriest-Barthilas"] == "Homeboy-Frostmourne",
      DB.assignments["Zpriest-Barthilas"])

fire("CHAT_MSG_ADDON", "PIAssign", "Zpriest:Awayboy", "RAID", "Zpriest-Barthilas")
check("bare target on the sender's own realm resolves to their realm",
      DB.assignments["Zpriest-Barthilas"] == "Awayboy-Barthilas",
      DB.assignments["Zpriest-Barthilas"])

realPrint("== !pi chunking in a big raid ==")
world.raid = {}
world.raid[1] = { name = "Mypriest", realm = "Frostmourne", class = "PRIEST",
                  zone = world.zone, role = "HEALER", guild = true }
for i = 1, 20 do
    world.raid[#world.raid+1] = { name = string.format("Priest%02d", i), realm = "Frostmourne",
                                  class = "PRIEST", zone = world.zone, role = "DAMAGER", guild = true }
    world.raid[#world.raid+1] = { name = string.format("Target%02d", i), realm = "Frostmourne",
                                  class = "ROGUE", zone = world.zone, role = "DAMAGER", guild = true }
end
fire("GROUP_ROSTER_UPDATE")
for i = 1, 20 do
    DB.assignments[string.format("Priest%02d-Frostmourne", i)] = string.format("Target%02d-Frostmourne", i)
end
DB.assignments["Mypriest-Frostmourne"] = "Target01-Frostmourne"
sent = {}
world.time = 1000
fire("CHAT_MSG_RAID", "!pi", "Target01-Frostmourne")
check("21 assignments are packed into several messages, not 21",
      #sent > 1 and #sent <= 4, #sent.." messages")
local longest, total = 0, 0
for _, s in ipairs(sent) do
    longest = math.max(longest, #s.msg)
    local _, n = string.gsub(s.msg, "%->", "")
    total = total + n
end
check("no message exceeds the 255 char chat limit", longest <= 255, longest.." chars")
check("every assignment appears exactly once across the messages", total == 21, total.." entries")

realPrint("== raid group in a city, not zoned into a raid ==")
world.instanceType = "none"
world.zone = "Dornogal"
world.raid = {
    { name = "Mypriest",    realm = "Frostmourne", class = "PRIEST", zone = "Dornogal", role = "DAMAGER", guild = true },
    { name = "Otherpriest", realm = "Frostmourne", class = "PRIEST", zone = "Dornogal", role = "DAMAGER", guild = true },
    { name = "Healbot",     realm = "Frostmourne", class = "PRIEST", zone = "Dornogal", role = "HEALER",  guild = true },
}
DB.assignments = {}
DB.testMode = false
fire("GROUP_ROSTER_UPDATE")
DB.assignments["Mypriest-Frostmourne"] = "Healbot-Frostmourne"

fire("CHAT_MSG_ADDON", "PIAssign", "Otherpriest:Healbot", "RAID", "Otherpriest-Frostmourne")
check("inbound assignment is stored in a city",
      DB.assignments["Otherpriest-Frostmourne"] == "Healbot-Frostmourne",
      DB.assignments["Otherpriest-Frostmourne"])
tick()
check("it survives a ticker pass in a city",
      DB.assignments["Otherpriest-Frostmourne"] ~= nil)
local cityText = panelText()
check("the other priest is drawn in the window",
      string.find(cityText, "Otherpriest") ~= nil, cityText)
-- Warnings are intentionally silent outside a raid instance; they would be
-- noise while the raid forms up. Comms above must still work here.
check("warnings stay silent in a city, by design",
      (PIAssignmentFrame.errorText:GetText() or "") == "",
      "errorText="..tostring(PIAssignmentFrame.errorText:GetText()))

-- /pi debug lifts the raid-instance gate so warnings can be seen anywhere
SlashCmdList["POWERINFUSION"]("debug")
fire("GROUP_ROSTER_UPDATE")
check("debug mode shows warnings outside a raid instance",
      string.find(PIAssignmentFrame.errorText:GetText() or "", "HEALER") ~= nil,
      "errorText="..tostring(PIAssignmentFrame.errorText:GetText()))
SlashCmdList["POWERINFUSION"]("debug")
fire("GROUP_ROSTER_UPDATE")
check("turning debug back off silences them again",
      (PIAssignmentFrame.errorText:GetText() or "") == "",
      "errorText="..tostring(PIAssignmentFrame.errorText:GetText()))
world.instanceType = "raid"

realPrint("== unassigned own row ==")
-- The panel's loudest state: no target of our own. The row must still be
-- drawn, must read "(none)", and its leader takes the same red at 40%.
DB.assignments = {}
DB.assignments["Otherpriest-Frostmourne"] = "Healbot-Frostmourne"
fire("GROUP_ROSTER_UPDATE")
check("own row is still drawn with no assignment",
      PIAssignmentFrame.rows[1].name:GetText() == "Mypriest",
      panelText())
check("an unassigned target renders as (none)",
      PIAssignmentFrame.rows[1].target:GetText() == "(none)",
      PIAssignmentFrame.rows[1].target:GetText())
-- the surplus row from the widest earlier scenario must be hidden, not stale
check("surplus pooled rows are hidden",
      PIAssignmentFrame.rows[3] == nil or not PIAssignmentFrame.rows[3]:IsShown())

realPrint("== reload handshake ==")
-- our target is unchanged, so the dedupe would normally keep us silent;
-- a request must still get an answer out
DB.assignments = {}
DB.assignments["Mypriest-Frostmourne"] = "Healbot-Frostmourne"
addonMsgs = {}
fire("CHAT_MSG_ADDON", "PIAssign", "?", "RAID", "Otherpriest-Frostmourne")
check("a request makes us re-announce despite the dedupe",
      #addonMsgs == 1 and addonMsgs[1].payload == "Mypriest:Healbot",
      addonMsgs[1] and addonMsgs[1].payload or (#addonMsgs.." messages"))
check("the request itself was not stored as an assignment",
      DB.assignments["Otherpriest-Frostmourne"] == nil)

-- a reloaded client with nothing but its own row should ask
addonMsgs = {}
DB.assignments = {}
DB.assignments["Mypriest-Frostmourne"] = "Healbot-Frostmourne"
fire("PLAYER_ENTERING_WORLD")
check("a reload with no peer data sends a request",
      #addonMsgs == 1 and addonMsgs[1].payload == "?",
      addonMsgs[1] and addonMsgs[1].payload or (#addonMsgs.." messages"))

-- but a client that already knows about someone stays quiet
addonMsgs = {}
DB.assignments["Otherpriest-Frostmourne"] = "Healbot-Frostmourne"
fire("PLAYER_ENTERING_WORLD")
check("a loading screen with peer data already known stays quiet",
      #addonMsgs == 0, #addonMsgs.." messages")

realPrint("== options window keeps every control the old one had ==")
local win = _G["PIOptionsWindow"]
DB.testMode = false
for _, f in ipairs({"edit", "errorText", "macroHintText", "exampleMacroEdit",
                    "mouseoverMacroEdit", "copyMacroButton", "exampleCopyMacroButton",
                    "UpdateModeVisibility", "UpdateHintVisibility"}) do
    check("window still exposes "..f, win[f] ~= nil)
end

win.SetMode(2)
check("mode 2 swaps the mouseover macro in",
      win.mouseoverMacroBlock:IsShown() and not win.exampleMacroBlock:IsShown())
check("mode 2 hides the macro name field", not win.editBox:IsShown())
win.SetMode(1)
check("mode 1 swaps the example macro back",
      win.exampleMacroBlock:IsShown() and not win.mouseoverMacroBlock:IsShown())
check("mode 1 shows the macro name field", win.editBox:IsShown())

macros[1].name = "PI"
win.edit:SetText("PI")
win.edit:GetScript("OnEnterPressed")(win.edit)
check("macro name validation still reports a hit",
      string.find(win.errorText:GetText(), "Found macro") ~= nil, win.errorText:GetText())
win.edit:SetText("Nope")
win.edit:GetScript("OnEnterPressed")(win.edit)
check("macro name validation still reports a miss",
      string.find(win.errorText:GetText(), "not found") ~= nil, win.errorText:GetText())
win.edit:SetText("PI")
win.edit:GetScript("OnEnterPressed")(win.edit)

check("all five toggles are present", #win.toggleRows == 5, #win.toggleRows.." rows")
local before = {
    DB.hideInCombat, DB.showForNonPriest, DB.enableWhispers, DB.testMode, DB.lockFrame,
}
for i = 1, #win.toggleRows do
    local row = win.toggleRows[i]
    row:GetScript("OnClick")(row)
end
check("every toggle writes its saved variable",
      DB.hideInCombat ~= before[1] and DB.showForNonPriest ~= before[2]
      and DB.enableWhispers ~= before[3] and DB.testMode ~= before[4]
      and DB.lockFrame ~= before[5])
-- put them back
for i = 1, #win.toggleRows do
    local row = win.toggleRows[i]
    row:GetScript("OnClick")(row)
end
check("toggling back restores every saved variable",
      DB.hideInCombat == before[1] and DB.showForNonPriest == before[2]
      and DB.enableWhispers == before[3] and DB.testMode == before[4]
      and DB.lockFrame == before[5])

local slider = _G["PI_ScaleSlider"]
slider:GetScript("OnValueChanged")(slider, 5)
check("scale clamps at the top of the slider range", DB.scale == 2.0, DB.scale)
slider:GetScript("OnValueChanged")(slider, 0.1)
check("scale clamps at the bottom of the slider range", DB.scale == 0.7, DB.scale)
local scaleBox = _G["PI_ScaleInput"]
scaleBox:SetText("1.25")
scaleBox:GetScript("OnEnterPressed")(scaleBox)
check("typing an exact scale still works", DB.scale == 1.25, DB.scale)

check("FAQ ships the real content, not the prototype placeholder",
      win.faqText == nil or string.find(win.faqText:GetText() or "", "placeholder") == nil)

realPrint("")
if failures == 0 then
    realPrint("ALL CHECKS PASSED")
else
    realPrint(failures.." CHECK(S) FAILED")
    os.exit(1)
end
