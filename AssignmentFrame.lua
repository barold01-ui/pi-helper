-- The on-screen assignment panel: pooled rows, the layout pass, and the
-- diff-driven update that keeps the ticker cheap.
local _, PI = ...

-- Scratch table reused so the 3 second ticker doesn't churn garbage.
local reuseErrorLines = {}
local reuseTargetCounts = {}

-- The panel is drawn from row descriptors rather than one concatenated string,
-- so these are the two halves of the display diff: reuseRows is rebuilt every
-- update, lastRows mirrors what is actually on screen. Both hold the same
-- tables from update to update; only their fields are overwritten.
local reuseRows = {}
local reuseRowCount = 0
local lastRows = {}
local lastRowCount = -1   -- -1 so the first update always draws

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
    width       = 236,  -- ~10% narrower than the 264 handoff; still grows to fit long pairs
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
    -- Make test mode obvious: recolour the header and tag it while it's on.
    if PowerInfusionAssignmentsDB.testMode then
        PI.frame.header:SetText("POWER INFUSION  |cffFF7B72(TEST MODE)|r")
        TintText(PI.frame.header, PC.none)
    else
        PI.frame.header:SetText("POWER INFUSION")
        TintText(PI.frame.header, PC.header)
    end
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

-- InitDB calls this on login so the first UpdateAssignmentFrame always draws.
function PI:ResetPanelDiff()
    lastRowCount = -1
    PI.lastFrameErrorText = nil
end
