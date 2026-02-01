local addonName = "PowerInfusionAssignments"

local PI = {}
local PI_MSG_PREFIX = "PIAssign"

-- Cached data
local classColorCache = {}
local reuseLines = {}
local reusePriests = {}

local function Print(...) DEFAULT_CHAT_FRAME:AddMessage("[PI] "..strjoin(" ", tostringall(...))) end

-- Global function for macro to call (captures mouseover target)
function PI_SetPITarget()
    local name, realm = UnitName("mouseover")
    if not name then
        return
    end
    if realm and realm ~= "" then
        name = name.."-"..realm
    end
    PI.mouseoverTarget = name
    Print("PI target set to: "..name)
end

function PI:GetMyGuildName()
    local guildName = GetGuildInfo("player")
    return guildName
end

function PI:GetGroupPriests()
    local result = {}

    -- Only work in raid groups
    if not IsInRaid() then return result end

    local numGroup = GetNumGroupMembers()
    if numGroup == 0 then return result end

    for i = 1, numGroup do
        local unit = "raid"..i
        if UnitExists(unit) then
            local name, realm = UnitName(unit)
            if realm and realm ~= "" then
                name = name.."-"..realm
            end
            local _, classFile = UnitClass(unit)
            if classFile == "PRIEST" and name ~= PI:GetPlayerName() then
                table.insert(result, name)
            end
        end
    end
    return result
end

function PI:BroadcastAssignment()
    local player = PI:GetPlayerName()
    local target = PowerInfusionAssignmentsDB.assignments[player]
    if not target or target == "" then return end
    if not IsInRaid() then return end

    local payload = player..":"..target
    -- Use RAID channel for more reliable communication in instances
    C_ChatInfo.SendAddonMessage(PI_MSG_PREFIX, payload, "RAID")
end

function PI:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PI_MSG_PREFIX then return end
    local fromPlayer, toTarget = strsplit(":", message)
    if not fromPlayer or not toTarget then return end
    -- store assignment from remote priest
    PowerInfusionAssignmentsDB.assignments[fromPlayer] = toTarget
    PI:UpdateAssignmentFrame()
end

function PI:ShouldReportAssignments()
    -- Return true if this priest is alphabetically first among priests with assignments
    wipe(reusePriests)
    for player, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if target and target ~= "" then
            reusePriests[#reusePriests + 1] = player
        end
    end
    
    if #reusePriests == 0 then return false end
    
    table.sort(reusePriests, function(a, b) return strlower(a) < strlower(b) end)
    local myName = PI:GetPlayerName()
    return reusePriests[1] == myName
end

function PI:ReportAssignmentsToChat()
    if not PI:ShouldReportAssignments() then return end
    if not IsInRaid() then return end
    
    local chatType = "INSTANCE_CHAT"
    -- Fall back to raid chat if not in instance group
    if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        chatType = "RAID"
    end
    
    -- Collect assignments using reusable table
    wipe(reuseLines)
    for player, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if target and target ~= "" then
            reuseLines[#reuseLines + 1] = player.." -> "..target
        end
    end
    
    if #reuseLines == 0 then
        SendChatMessage("[PI] No PI assignments.", chatType)
    else
        SendChatMessage("[PI] Power Infusion Assignments:", chatType)
        for i = 1, #reuseLines do
            SendChatMessage(reuseLines[i], chatType)
        end
    end
end

function PI:OnChatMessage(message, sender)
    if PI.inCombat then return end
    if strlower(strtrim(message)) == "!pi" then
        PI:ReportAssignmentsToChat()
    end
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
    if not PowerInfusionAssignmentsDB then PowerInfusionAssignmentsDB = {} end
    if type(PowerInfusionAssignmentsDB) ~= "table" then PowerInfusionAssignmentsDB = {} end
    PowerInfusionAssignmentsDB.macroName = PowerInfusionAssignmentsDB.macroName or ""
    PowerInfusionAssignmentsDB.assignments = PowerInfusionAssignmentsDB.assignments or {}
    PowerInfusionAssignmentsDB.framePos = PowerInfusionAssignmentsDB.framePos or { point = "CENTER", x = 0, y = -200 }
    PowerInfusionAssignmentsDB.piMode = PowerInfusionAssignmentsDB.piMode or 1  -- 1 = macro mode, 2 = mouseover/target mode
    PowerInfusionAssignmentsDB.testMode = false  -- Always reset test mode on login
    if PowerInfusionAssignmentsDB.hideInCombat == nil then PowerInfusionAssignmentsDB.hideInCombat = true end
    if PowerInfusionAssignmentsDB.enableWhispers == nil then PowerInfusionAssignmentsDB.enableWhispers = true end
end

-- Fake test data for test mode
local TEST_ASSIGNMENTS = {
    ["Priest 2"] = "Roguemaster",
    ["Priest 3"] = "Dpswarrior",
    ["Priest 4"] = "Firemage",
}

-- Class colors for fake test data (priest = white, others = class colors)
local TEST_CLASS_COLORS = {
    ["Priest 2"] = "|cffFFFFFF",      -- White (Priest)
    ["Priest 3"] = "|cffFFFFFF",      -- White (Priest)
    ["Priest 4"] = "|cffFFFFFF",      -- White (Priest)
    ["Roguemaster"] = "|cffFFF468",   -- Rogue yellow
    ["Dpswarrior"] = "|cffC69B6D",    -- Warrior brown
    ["Firemage"] = "|cff3FC7EB",      -- Mage light blue
    ["TestTarget"] = "|cffFFFFFF",    -- White (generic)
}

function PI:SetTestMode(enabled)
    PowerInfusionAssignmentsDB.testMode = enabled
    if enabled then
        -- Populate fake data
        local myName = PI:GetPlayerName()
        PowerInfusionAssignmentsDB.assignments[myName] = "TestTarget"
        for priest, target in pairs(TEST_ASSIGNMENTS) do
            PowerInfusionAssignmentsDB.assignments[priest] = target
        end
        -- Add fake class colors to cache
        for name, color in pairs(TEST_CLASS_COLORS) do
            classColorCache[name] = color
        end
    else
        -- Clear fake data
        local myName = PI:GetPlayerName()
        for priest, _ in pairs(TEST_ASSIGNMENTS) do
            PowerInfusionAssignmentsDB.assignments[priest] = nil
        end
        -- Keep player's real assignment if any, or clear test target
        if PowerInfusionAssignmentsDB.assignments[myName] == "TestTarget" then
            PowerInfusionAssignmentsDB.assignments[myName] = nil
        end
        -- Remove fake class colors from cache
        for name, _ in pairs(TEST_CLASS_COLORS) do
            classColorCache[name] = nil
        end
    end
    PI:UpdateAssignmentFrame()
    PI:UpdateAssignmentFrameVisibility()
    PI:UpdateTickerState()
end

function PI:GetPlayerName()
    local name = UnitName("player") or "Unknown"
    return name
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

function PI:RefreshClassColorCache()
    wipe(classColorCache)
    -- Cache player color
    local myName = PI:GetPlayerName()
    classColorCache[myName] = PI:GetClassColorForUnit("player")
    -- Cache raid members
    if IsInRaid() then
        local numGroup = GetNumGroupMembers()
        for i = 1, numGroup do
            local unit = "raid"..i
            if UnitExists(unit) then
                local unitName, realm = UnitName(unit)
                if realm and realm ~= "" then
                    unitName = unitName.."-"..realm
                end
                classColorCache[unitName] = PI:GetClassColorForUnit(unit)
            end
        end
    end
end

function PI:GetClassColorForName(name)
    if not name or name == "" then return nil end
    return classColorCache[name]
end

function PI:ColorText(text, colorCode)
    if colorCode then
        return colorCode..text.."|r"
    end
    return text
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

local function isIgnoredToken(tok)
    if not tok then return true end
    tok = strlower(tok)
    local ignore = {
        mouseover=true, target=true, focus=true, player=true, pet=true, vehicle=true,
        exists=true, nodead=true, help=true, harm=true, nouser=true, caster=true,
    }
    return ignore[tok]
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
    if not playerName or playerName == "" then return false end
    local numGuildMembers = GetNumGuildMembers()
    for i = 1, numGuildMembers do
        local name = GetGuildRosterInfo(i)
        if name then
            -- Guild roster names include realm, strip it for comparison
            local shortName = strsplit("-", name)
            if shortName == playerName or name == playerName then
                return true
            end
        end
    end
    return false
end

PI.previousTarget = nil

function PI:ScanMacroAndSave()
    if PI.inCombat then
        return false
    end

    local macroName = PowerInfusionAssignmentsDB.macroName
    if not macroName or macroName == "" then
        return false
    end
    local idx = PI:FindMacroIndexByName(macroName)
    if not idx then
        return false
    end
    local target = PI:ParseMacroForTarget(idx)
    if target then
        local player = PI:GetPlayerName()
        local oldTarget = PI.previousTarget
        
        -- Check if target changed
        if oldTarget ~= target then
            -- Whisper old target if whispers enabled, they're in guild, in raid group, and not yourself
            if PowerInfusionAssignmentsDB.enableWhispers and oldTarget and oldTarget ~= "" and oldTarget ~= player and PI:IsPlayerInGuild(oldTarget) and PI:IsPlayerInGroup(oldTarget) then
                SendChatMessage("You no longer have PI", "WHISPER", nil, oldTarget)
            end
            -- Whisper new target if whispers enabled, they're in guild, in raid group, and not yourself
            if PowerInfusionAssignmentsDB.enableWhispers and target ~= player and PI:IsPlayerInGuild(target) and PI:IsPlayerInGroup(target) then
                SendChatMessage("PI set to you", "WHISPER", nil, target)
            end
            PI.previousTarget = target
        end
        
        PowerInfusionAssignmentsDB.assignments[player] = target
        PI:UpdateAssignmentFrame()
        return true
    else
        return false
    end
end

-- Mode 2: Use the mouseover target set by PI_SetPITarget macro
function PI:ScanMouseoverAndSave()
    local target = PI.mouseoverTarget
    if not target or target == "" then
        return false
    end
    
    local player = PI:GetPlayerName()
    local oldTarget = PI.previousTarget
    
    -- Check if target changed
    if oldTarget ~= target then
        -- Whisper old target if whispers enabled, they're in guild, in raid group, and not yourself
        if PowerInfusionAssignmentsDB.enableWhispers and oldTarget and oldTarget ~= "" and oldTarget ~= player and PI:IsPlayerInGuild(oldTarget) and PI:IsPlayerInGroup(oldTarget) then
            SendChatMessage("You no longer have PI", "WHISPER", nil, oldTarget)
        end
        -- Whisper new target if whispers enabled, they're in guild, in raid group, and not yourself
        if PowerInfusionAssignmentsDB.enableWhispers and target ~= player and PI:IsPlayerInGuild(target) and PI:IsPlayerInGroup(target) then
            SendChatMessage("PI set to you", "WHISPER", nil, target)
        end
        PI.previousTarget = target
    end
    
    PowerInfusionAssignmentsDB.assignments[player] = target
    PI:UpdateAssignmentFrame()
    return true
end

function PI:CreateAssignmentFrame()
    if PI.frame then return end
    local f = CreateFrame("Frame", "PIAssignmentFrame", UIParent, "BackdropTemplate")
    f.minWidth = 220
    f.minHeight = 40
    f.padX = 28
    f.padY = 22
    f:SetSize(f.minWidth, f.minHeight)
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
    f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0,0,0,0.6)

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("LEFT", f, "LEFT", 10, 0)
    text:SetJustifyH("LEFT")
    text:SetText("")
    f.text = text

    -- Warning icons for duplicate targets (left and right)
    local warningIconLeft = f:CreateTexture(nil, "OVERLAY")
    warningIconLeft:SetSize(96, 96)
    warningIconLeft:SetPoint("RIGHT", f, "LEFT", -4, 0)
    warningIconLeft:SetTexture("Interface\\DialogFrame\\DialogAlertIcon")
    warningIconLeft:Hide()
    f.warningIconLeft = warningIconLeft

    local warningIconRight = f:CreateTexture(nil, "OVERLAY")
    warningIconRight:SetSize(96, 96)
    warningIconRight:SetPoint("LEFT", f, "RIGHT", 4, 0)
    warningIconRight:SetTexture("Interface\\DialogFrame\\DialogAlertIcon")
    warningIconRight:Hide()
    f.warningIconRight = warningIconRight

    -- Flash animation state
    f.flashElapsed = 0
    f.flashVisible = true
    f:SetScript("OnUpdate", function(self, elapsed)
        if not self.warningIconLeft:IsShown() then return end
        self.flashElapsed = self.flashElapsed + elapsed
        if self.flashElapsed >= 0.5 then
            self.flashElapsed = 0
            self.flashVisible = not self.flashVisible
            local alpha = self.flashVisible and 1 or 0.2
            self.warningIconLeft:SetAlpha(alpha)
            self.warningIconRight:SetAlpha(alpha)
        end
    end)

    f:Show()
    PI.frame = f
    PI:UpdateAssignmentFrame()
end

function PI:CheckForDuplicateTargets()
    local targetCounts = {}
    for player, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if target and target ~= "" then
            targetCounts[target] = (targetCounts[target] or 0) + 1
        end
    end
    for target, count in pairs(targetCounts) do
        if count > 1 then
            return true, target
        end
    end
    return false, nil
end

function PI:ResizeAssignmentFrameToText()
    if not PI.frame or not PI.frame.text then return end
    local textWidth = PI.frame.text:GetStringWidth() or 0
    local textHeight = PI.frame.text:GetStringHeight() or 0
    local minWidth = PI.frame.minWidth or 220
    local minHeight = PI.frame.minHeight or 40
    local padX = PI.frame.padX or 28
    local padY = PI.frame.padY or 22
    PI.frame:SetSize(math.max(minWidth, textWidth + padX), math.max(minHeight, textHeight + padY))
end

function PI:UpdateAssignmentFrame()
    PI:CreateAssignmentFrame()
    
    wipe(reuseLines)
    local myName = PI:GetPlayerName()
    
    -- First add the local player's assignment at the top
    local myTarget = PowerInfusionAssignmentsDB.assignments[myName]
    local myColor = PI:GetClassColorForName(myName)
    local coloredMe = PI:ColorText(myName, myColor)
    if myTarget and myTarget ~= "" then
        local targetColor = PI:GetClassColorForName(myTarget)
        local coloredTarget = PI:ColorText(myTarget, targetColor)
        reuseLines[#reuseLines + 1] = coloredMe.." -> "..coloredTarget
    else
        reuseLines[#reuseLines + 1] = coloredMe.." -> (none)"
    end
    
    -- Then add other players' assignments
    for player, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        if player ~= myName and target and target ~= "" then
            local playerColor = PI:GetClassColorForName(player)
            local coloredPlayer = PI:ColorText(player, playerColor)
            local targetColor = PI:GetClassColorForName(target)
            local coloredTarget = PI:ColorText(target, targetColor)
            reuseLines[#reuseLines + 1] = coloredPlayer.." -> "..coloredTarget
        end
    end
    
    PI.frame.text:SetText(table.concat(reuseLines, "\n"))
    PI:ResizeAssignmentFrameToText()
    
    -- Check for duplicate targets and show/hide warning icons
    local hasDuplicates, duplicateTarget = PI:CheckForDuplicateTargets()
    if hasDuplicates then
        PI.frame.warningIconLeft:Show()
        PI.frame.warningIconRight:Show()
        PI.frame.flashElapsed = 0
        PI.frame.flashVisible = true
        PI.frame.warningIconLeft:SetAlpha(1)
        PI.frame.warningIconRight:SetAlpha(1)
    else
        PI.frame.warningIconLeft:Hide()
        PI.frame.warningIconRight:Hide()
    end
end

function PI:CreateOptionsWindow()
    if PI.options then return end
    local o = CreateFrame("Frame", "PIOptionsWindow", UIParent, "BackdropTemplate")
    o:SetSize(400, 330)
    o:SetScale(1.5)
    o:SetFrameStrata("DIALOG")
    o:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    o:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    o:SetBackdropColor(0,0,0,0.95)
    o:SetMovable(true)
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    o:SetScript("OnDragStart", function(self) self:StartMoving() end)
    o:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    o:SetClampedToScreen(true)
    o:Hide()

    local close = CreateFrame("Button", nil, o, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", o, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() o:Hide() end)

    -- Heading above tabs
    local heading = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -10)
    heading:SetText("Power Infusion Assignment Helper")

    -- Tab buttons
    local function CreateTabButton(parent, id, text, xOffset)
        local tab = CreateFrame("Button", "PIOptionsTab"..id, parent)
        tab:SetSize(100, 28)
        tab:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, -28)
        
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab.text:SetText(text)
        
        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints()
        tab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
        
        tab.selected = false
        tab.SetSelected = function(self, selected)
            self.selected = selected
            if selected then
                self.bg:SetColorTexture(0.4, 0.4, 0.4, 1)
                self.text:SetFontObject(GameFontHighlight)
            else
                self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                self.text:SetFontObject(GameFontNormal)
            end
        end
        
        return tab
    end

    local tab1 = CreateTabButton(o, 1, "Configuration", 8)
    local tab2 = CreateTabButton(o, 2, "FAQ", 112)
    
    -- Tab content containers
    local tab1Content = CreateFrame("Frame", "PIOptionsTab1Content", o)
    tab1Content:SetPoint("TOPLEFT", o, "TOPLEFT", 0, -56)
    tab1Content:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", 0, 0)
    
    local tab2Content = CreateFrame("Frame", "PIOptionsTab2Content", o)
    tab2Content:SetPoint("TOPLEFT", o, "TOPLEFT", 0, -56)
    tab2Content:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", 0, 0)
    tab2Content:Hide()
    
    -- Tab 2 FAQ content
    local faqText = tab2Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    faqText:SetPoint("TOPLEFT", tab2Content, "TOPLEFT", 12, -10)
    faqText:SetPoint("TOPRIGHT", tab2Content, "TOPRIGHT", -12, -10)
    faqText:SetJustifyH("LEFT")
    faqText:SetWordWrap(true)
    faqText:SetSpacing(2)
    faqText:SetText("|cFFFFD100Q: What does this addon do?|r\nThis addon works in raid groups only. It lets your priests coordinate their PI assignments, by showing each priest's PI target in a moveable window.\n\nIf more than 1 priest has PI set to the same person, it will show a warning.\n\nAlso allows any raid member to check PI assignments with the !pi command in instance chat.\n\n|cFFFFD100Q: How do I set up the addon?|r\nUse the /pi command to open configuration. Follow the setup instructions in the \"PI Options\" tab. Each priest in your group needs to have the addon running.\n\n|cFFFFD100Q: How do I macro Power Infusion?|r\nI suggest checking out the Advanced Power Infusion macro in the Shadow Priest Icy Veins guide.")
    
    local function SelectTab(tabNum)
        if tabNum == 1 then
            tab1:SetSelected(true)
            tab2:SetSelected(false)
            tab1Content:Show()
            tab2Content:Hide()
        else
            tab1:SetSelected(false)
            tab2:SetSelected(true)
            tab1Content:Hide()
            tab2Content:Show()
        end
    end
    
    tab1:SetScript("OnClick", function() SelectTab(1) end)
    tab2:SetScript("OnClick", function() SelectTab(2) end)
    
    -- Select tab 1 by default
    SelectTab(1)
    
    o.tab1Content = tab1Content
    o.tab2Content = tab2Content
    o.SelectTab = SelectTab

    -- === TAB 1 CONTENT (PI Options) ===
    
    -- PI Mode dropdown
    local modeLabel = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeLabel:SetPoint("TOPLEFT", tab1Content, "TOPLEFT", 12, -10)
    modeLabel:SetText("Mode:")

    local PI_MODE_OPTIONS = {
        [1] = "My PI target is set in a macro",
        [2] = "My PI target is *not* set in a macro",
    }

    local modeDropdown = CreateFrame("Frame", "PI_ModeDropdown", tab1Content, "UIDropDownMenuTemplate")
    modeDropdown:SetPoint("TOPLEFT", tab1Content, "TOPLEFT", 55, -4)
    UIDropDownMenu_SetWidth(modeDropdown, 280)

    local function UpdateModeVisibility()
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        if mode == 1 then
            o.macroHelpText:Show()
            o.macroLabel:Show()
            o.edit:Show()
            o.mouseoverMacroLabel:Hide()
            o.mouseoverMacroScroll:Hide()
            o.copyMacroButton:Hide()
        else
            o.macroHelpText:Hide()
            o.macroLabel:Hide()
            o.edit:Hide()
            o.mouseoverMacroLabel:Show()
            o.mouseoverMacroScroll:Show()
            o.copyMacroButton:Show()
            -- Hide error text in mode 2
            PI:ClearError()
        end
    end
    o.UpdateModeVisibility = UpdateModeVisibility

    local function ModeDropdown_OnClick(self, arg1)
        PowerInfusionAssignmentsDB.piMode = arg1
        UIDropDownMenu_SetText(modeDropdown, PI_MODE_OPTIONS[arg1])
        UpdateModeVisibility()
        o:UpdateHintVisibility()
    end

    local function ModeDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for i = 1, 2 do
            info.text = PI_MODE_OPTIONS[i]
            info.arg1 = i
            info.func = ModeDropdown_OnClick
            info.checked = (PowerInfusionAssignmentsDB.piMode == i)
            info.fontObject = GameFontHighlightLarge
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(modeDropdown, ModeDropdown_Initialize)
    UIDropDownMenu_SetText(modeDropdown, PI_MODE_OPTIONS[PowerInfusionAssignmentsDB.piMode or 1])

    -- Macro name input (only visible in macro mode)
    local macroHintText = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    macroHintText:SetPoint("TOPLEFT", tab1Content, "TOPLEFT", 12, -40)
    macroHintText:SetTextColor(0.2, 1, 0.2, 1)
    macroHintText:SetText("Enter your macro name to get started")

    local macroHelpText = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    macroHelpText:SetPoint("TOPLEFT", tab1Content, "TOPLEFT", 12, -55)
    macroHelpText:SetPoint("RIGHT", tab1Content, "RIGHT", -12, 0)
    macroHelpText:SetJustifyH("LEFT")
    macroHelpText:SetText("Your macro should contain a reference to your PI target in the form of target=yourtarget or @yourtarget")

    local macroLabel = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    macroLabel:SetPoint("TOPLEFT", tab1Content, "TOPLEFT", 12, -85)
    macroLabel:SetText("What's the name of your PI macro?")

    local edit = CreateFrame("EditBox", "PI_MacroNameEditBox", tab1Content, "InputBoxTemplate")
    edit:SetSize(120, 24)
    edit:SetPoint("TOPLEFT", tab1Content, "TOPLEFT", 202, -79)
    edit:SetAutoFocus(false)
    edit:SetText(PowerInfusionAssignmentsDB.macroName or "")
    
    -- Save and validate macro name when text changes
    local function ValidateMacroName()
        local macroName = edit:GetText() or ""
        PowerInfusionAssignmentsDB.macroName = macroName
        
        if macroName == "" then
            PI:ClearError()
            return
        end
        
        local idx = PI:FindMacroIndexByName(macroName)
        if not idx then
            PI:SetError("Macro not found: " .. macroName)
        else
            PI:SetSuccess("Macro found: " .. macroName .. "\nYou're all set!")
        end
    end
    
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            PowerInfusionAssignmentsDB.macroName = self:GetText() or ""
            o:UpdateHintVisibility()
        end
    end)
    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ValidateMacroName()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Mouseover mode: macro text area (only visible in mouseover mode)
    local mouseoverMacroLabel = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mouseoverMacroLabel:SetPoint("TOPLEFT", tab1Content, "TOPLEFT", 12, -40)
    mouseoverMacroLabel:SetPoint("TOPRIGHT", tab1Content, "TOPRIGHT", -12, -40)
    mouseoverMacroLabel:SetJustifyH("LEFT")
    mouseoverMacroLabel:SetWordWrap(true)
    mouseoverMacroLabel:SetText("You can still communicate your PI target to the group by following these steps: \n\n1) Bind the below macro to a key\n2) While out of combat, mouseover your intended PI target, press the key.\n3) Your intended target is now communicated to your fellow priests!")
    mouseoverMacroLabel:Hide()

    local mouseoverMacroScroll = CreateFrame("ScrollFrame", "PI_MouseoverMacroScroll", tab1Content, "UIPanelScrollFrameTemplate,BackdropTemplate")
    mouseoverMacroScroll:SetSize(340, 40)
    mouseoverMacroScroll:SetPoint("TOPLEFT", tab1Content, "TOPLEFT", 12, -122)
    mouseoverMacroScroll:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    mouseoverMacroScroll:SetBackdropColor(0, 0, 0, 1)
    mouseoverMacroScroll:SetBackdropBorderColor(1, 0.82, 0, 1)
    mouseoverMacroScroll:Hide()

    local mouseoverMacroEdit = CreateFrame("EditBox", "PI_MouseoverMacroEditBox", mouseoverMacroScroll)
    mouseoverMacroEdit:SetMultiLine(true)
    mouseoverMacroEdit:SetFontObject(GameFontGreen)
    mouseoverMacroEdit:SetSize(300, 30)
    mouseoverMacroEdit:SetAutoFocus(false)
    mouseoverMacroEdit:EnableMouse(true)
    mouseoverMacroEdit:EnableKeyboard(true)
    mouseoverMacroEdit:SetText("/run PI_SetPITarget()")
    mouseoverMacroEdit:SetTextInsets(8, 8, 8, 8)
    mouseoverMacroEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    mouseoverMacroEdit:SetScript("OnKeyDown", function(self, key)
        -- Allow Ctrl+C and Ctrl+A, block everything else
        if IsControlKeyDown() and (key == "C" or key == "A") then
            return
        end
        self:SetPropagateKeyboardInput(false)
    end)
    mouseoverMacroEdit:SetScript("OnChar", function(self) end)
    mouseoverMacroEdit:SetScript("OnTextChanged", function(self)
        self:SetText("/run PI_SetPITarget()")
    end)
    mouseoverMacroScroll:SetScrollChild(mouseoverMacroEdit)

    local copyMacroButton = CreateFrame("Button", nil, tab1Content, "UIPanelButtonTemplate")
    copyMacroButton:SetSize(200, 22)
    copyMacroButton:SetPoint("TOPLEFT", mouseoverMacroScroll, "BOTTOMLEFT", 0, -4)
    copyMacroButton:SetText("Select All (Ctrl+C to copy)")
    copyMacroButton:SetScript("OnClick", function()
        mouseoverMacroEdit:SetFocus()
        mouseoverMacroEdit:HighlightText(0)
    end)
    copyMacroButton:Hide()

    o.mouseoverMacroLabel = mouseoverMacroLabel
    o.mouseoverMacroScroll = mouseoverMacroScroll
    o.mouseoverMacroEdit = mouseoverMacroEdit
    o.copyMacroButton = copyMacroButton

    local errorText = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    errorText:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 2, -6)
    errorText:SetPoint("TOPRIGHT", edit, "BOTTOMRIGHT", -2, -6)
    errorText:SetJustifyH("LEFT")
    errorText:SetTextColor(1, 0.2, 0.2, 1)
    errorText:SetText("")
    errorText:Hide()

    -- Hide in combat checkbox
    local hideInCombatCheck = CreateFrame("CheckButton", "PI_HideInCombatCheckbox", tab1Content, "UICheckButtonTemplate")
    hideInCombatCheck:SetPoint("BOTTOMLEFT", tab1Content, "BOTTOMLEFT", 8, 60)
    hideInCombatCheck:SetSize(24, 24)
    hideInCombatCheck:SetChecked(PowerInfusionAssignmentsDB.hideInCombat)
    hideInCombatCheck:SetScript("OnClick", function(self)
        PowerInfusionAssignmentsDB.hideInCombat = self:GetChecked()
        PI:UpdateAssignmentFrameVisibility()
    end)

    local hideInCombatLabel = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideInCombatLabel:SetPoint("LEFT", hideInCombatCheck, "RIGHT", 2, 0)
    hideInCombatLabel:SetText("Hide PI assignments in combat")

    -- Enable whispers checkbox
    local enableWhispersCheck = CreateFrame("CheckButton", "PI_EnableWhispersCheckbox", tab1Content, "UICheckButtonTemplate")
    enableWhispersCheck:SetPoint("BOTTOMLEFT", tab1Content, "BOTTOMLEFT", 8, 36)
    enableWhispersCheck:SetSize(24, 24)
    enableWhispersCheck:SetChecked(PowerInfusionAssignmentsDB.enableWhispers)
    enableWhispersCheck:SetScript("OnClick", function(self)
        PowerInfusionAssignmentsDB.enableWhispers = self:GetChecked()
    end)

    local enableWhispersLabel = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    enableWhispersLabel:SetPoint("LEFT", enableWhispersCheck, "RIGHT", 2, 0)
    enableWhispersLabel:SetText("Enable whispers")

    -- Info icon for whispers
    local whispersInfoIcon = CreateFrame("Frame", nil, tab1Content)
    whispersInfoIcon:SetSize(16, 16)
    whispersInfoIcon:SetPoint("LEFT", enableWhispersLabel, "RIGHT", 4, 0)
    
    local whispersInfoTexture = whispersInfoIcon:CreateTexture(nil, "ARTWORK")
    whispersInfoTexture:SetAllPoints()
    whispersInfoTexture:SetTexture("Interface/FriendsFrame/InformationIcon")
    
    whispersInfoIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Enable Whispers", 1, 1, 1)
        GameTooltip:AddLine("When you change your PI target, send them a whisper to let them know! Only works for guild members.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    whispersInfoIcon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Test mode checkbox
    local testModeCheck = CreateFrame("CheckButton", "PI_TestModeCheckbox", tab1Content, "UICheckButtonTemplate")
    testModeCheck:SetPoint("BOTTOMLEFT", tab1Content, "BOTTOMLEFT", 8, 12)
    testModeCheck:SetSize(24, 24)
    testModeCheck:SetChecked(PowerInfusionAssignmentsDB.testMode or false)
    testModeCheck:SetScript("OnClick", function(self)
        PI:SetTestMode(self:GetChecked())
    end)

    local testModeLabel = tab1Content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    testModeLabel:SetPoint("LEFT", testModeCheck, "RIGHT", 2, 0)
    testModeLabel:SetText("Test mode (show fake data)")

    o.macroHintText = macroHintText
    o.macroHelpText = macroHelpText
    o.macroLabel = macroLabel
    o.edit = edit
    o.errorText = errorText
    o.modeDropdown = modeDropdown
    
    -- Function to update hint visibility based on mode and macro name
    local function UpdateHintVisibility()
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        local macroName = PowerInfusionAssignmentsDB.macroName or ""
        if mode == 1 and macroName == "" then
            o.macroHintText:Show()
        else
            o.macroHintText:Hide()
        end
    end
    o.UpdateHintVisibility = UpdateHintVisibility
    
    PI.options = o

    -- Initialize visibility based on current mode
    UpdateModeVisibility()
    UpdateHintVisibility()
end

SLASH_POWERINFUSION1 = "/pi"
SlashCmdList["POWERINFUSION"] = function(msg)
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
    -- Hide during combat if option is enabled (applies to both test mode and normal mode)
    if PI.inCombat and PowerInfusionAssignmentsDB.hideInCombat then
        PI.frame:Hide()
    elseif PowerInfusionAssignmentsDB.testMode then
        PI.frame:Show()
    elseif IsInRaid() then
        PI.frame:Show()
    else
        PI.frame:Hide()
    end
end

function PI:IsPlayerInGroup(playerName)
    if not playerName or playerName == "" then return false end
    local myName = PI:GetPlayerName()
    if playerName == myName then return true end
    
    -- Only check raid groups
    if not IsInRaid() then return false end
    
    local numGroup = GetNumGroupMembers()
    if numGroup == 0 then return false end
    
    for i = 1, numGroup do
        local unit = "raid"..i
        if UnitExists(unit) then
            local name, realm = UnitName(unit)
            if realm and realm ~= "" then
                name = name.."-"..realm
            end
            if name == playerName then
                return true
            end
        end
    end
    return false
end

function PI:CleanupStaleAssignments()
    -- Don't cleanup in test mode, we want to keep the fake data
    if PowerInfusionAssignmentsDB.testMode then return end
    
    local myName = PI:GetPlayerName()
    local toRemove = {}
    
    for player, target in pairs(PowerInfusionAssignmentsDB.assignments) do
        -- Don't remove our own assignment, only remote players who left the group
        if player ~= myName and not PI:IsPlayerInGroup(player) then
            table.insert(toRemove, player)
        end
    end
    
    for _, player in ipairs(toRemove) do
        PowerInfusionAssignmentsDB.assignments[player] = nil
    end
    
    if #toRemove > 0 then
        PI:UpdateAssignmentFrame()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
f:RegisterEvent("CHAT_MSG_RAID")
f:RegisterEvent("CHAT_MSG_RAID_LEADER")

-- Ticker management
local scanTicker = nil

local function StartScanTicker()
    if scanTicker then return end -- Already running
    scanTicker = C_Timer.NewTicker(3, function()
        if PI.inCombat then return end
        
        -- In test mode, just keep the frame visible but don't scan/broadcast
        if PowerInfusionAssignmentsDB.testMode then return end
        
        PI:CleanupStaleAssignments()
        
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        if mode == 1 then
            -- Mode 1: scan macro for target
            if PowerInfusionAssignmentsDB.macroName and PowerInfusionAssignmentsDB.macroName ~= "" then
                PI:ScanMacroAndSave()
                PI:BroadcastAssignment()
            end
        else
            -- Mode 2: use mouseover target from PI_SetPITarget macro
            PI:ScanMouseoverAndSave()
            PI:BroadcastAssignment()
        end
    end)
end

local function StopScanTicker()
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
end

-- Expose as PI method so SetTestMode can call it
function PI:UpdateTickerState()
    if IsInRaid() or PowerInfusionAssignmentsDB.testMode then
        StartScanTicker()
    else
        StopScanTicker()
    end
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(PI_MSG_PREFIX)
        PI:InitDB()
        PI:RefreshClassColorCache()
        PI:CreateAssignmentFrame()
        PI:CreateOptionsWindow()
        PI:UpdateAssignmentFrame()
        PI:UpdateAssignmentFrameVisibility()
        -- Start ticker only if in raid or test mode
        PI:UpdateTickerState()
    elseif event == "PLAYER_REGEN_DISABLED" then
        PI.inCombat = true
        PI:UpdateAssignmentFrameVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        PI.inCombat = false
        PI:UpdateAssignmentFrameVisibility()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        PI:OnAddonMessage(prefix, message, channel, sender)
    elseif event == "GROUP_ROSTER_UPDATE" then
        PI:RefreshClassColorCache()
        PI:CleanupStaleAssignments()
        PI:UpdateAssignmentFrameVisibility()
        PI:UpdateTickerState()
    elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        local message, sender = ...
        PI:OnChatMessage(message, sender)
    end
end)
