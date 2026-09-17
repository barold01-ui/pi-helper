-- Addon-message networking between priests, plus the !pi chat report.
local _, PI = ...

-- The unique prefix is defined in the core file; mirror it into a plain local
-- so the send/receive code below reads exactly as it used to. Core loads
-- before this file (see the .toc), so PI.MSG_PREFIX is already set here.
local PI_MSG_PREFIX = PI.MSG_PREFIX

-- Sent after a reload to ask the other priests to re-announce. A 1.4.x client
-- splits this on ":" , gets no second field and drops it, so it is safe to
-- send into a mixed raid.
local PI_MSG_REQUEST = "?"

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
    local resolved = PI:FromWire(target, PI:RealmOf(from))
    PI:Debug("stored [%s] -> %s", from, tostring(resolved))
    PowerInfusionAssignmentsDB.assignments[from] = resolved
    PI:RequestFrameUpdate()
end

local function ByNameLower(a, b) return strlower(a) < strlower(b) end

-- Scratch tables reused so the report doesn't churn garbage each !pi.
local reusePriests = {}
local reuseReport = {}

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
