-- The /pi options window: palette, flat-UI widget helpers, and the window
-- builder. Also owns the shared error/success line the window shows.
--
-- The window is role-adaptive: a HEALER priest (Disc/Holy) sees the cooldown
-- alert tabs (Cooldown Alerts, Tracked Cooldowns); a Shadow priest or a
-- non-priest sees only the tabs that apply to them (Setup, Window, Help). Tab
-- visibility is rebuilt on show and on PLAYER_SPECIALIZATION_CHANGED.
local _, PI = ...

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
    ok           = {0.561, 0.812, 0.478},
    bad          = {0.918, 0.404, 0.404},
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
    -- Sizing is handled by the title-bar Window scale slider (below), not a
    -- drag-resize grip -- the two fight each other, so we keep only the scaler.

    o:Hide()

    local UpdateModeVisibility, UpdateHintVisibility, RefreshSetupStatus, RefreshTabVisibility
    -- Kept as a no-op: several controls still call it after changing a setting
    -- (tab badges were removed; nav tabs show their name only).
    local UpdateBadges = function() end

    local function IsHealer()
        return PI.playerIsPriest and PI:IsHealerSpec()
    end

    -- === TITLE BAR ===
    local titleBar = CreateFrame("Frame", nil, o)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(TITLE_H)
    Fill(titleBar, C.bar)
    Edge(titleBar, "BOTTOM", C.edgeRegion)

    local heading = Label(titleBar, 17, C.title)
    heading:SetPoint("LEFT", titleBar, "LEFT", 16, 0)
    heading:SetText("PI Assignment Helper")

    -- The handoff asks for the game's existing red X here
    local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    close:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    close:SetScript("OnClick", function() o:Hide() end)

    -- Scale slider for this whole window, pinned to the right of the title bar.
    o:SetScale(PowerInfusionAssignmentsDB.optionsScale or 1)
    local OSCALE_MIN, OSCALE_MAX = 0.7, 1.5
    local winScaleReadout = Label(titleBar, 13, C.title)
    winScaleReadout:SetPoint("RIGHT", close, "LEFT", -8, 0)
    winScaleReadout:SetJustifyH("RIGHT")
    winScaleReadout:SetWidth(40)
    local winScale = CreateFrame("Slider", nil, titleBar)
    winScale:SetPoint("RIGHT", winScaleReadout, "LEFT", -8, 0)
    winScale:SetSize(150, 18)
    winScale:SetOrientation("HORIZONTAL")
    winScale:SetMinMaxValues(OSCALE_MIN, OSCALE_MAX)
    winScale:SetValueStep(0.05)
    winScale:SetObeyStepOnDrag(true)
    local winScaleLabel = Label(titleBar, 13, C.body)
    winScaleLabel:SetPoint("RIGHT", winScale, "LEFT", -8, 0)
    winScaleLabel:SetText("Scale")
    local wsTrack = winScale:CreateTexture(nil, "BACKGROUND")
    wsTrack:SetPoint("LEFT"); wsTrack:SetPoint("RIGHT"); wsTrack:SetHeight(4)
    wsTrack:SetColorTexture(C.trackBg[1], C.trackBg[2], C.trackBg[3], 1)
    local wsThumb = winScale:CreateTexture(nil, "OVERLAY")
    wsThumb:SetSize(10, 18)
    wsThumb:SetColorTexture(C.handle[1], C.handle[2], C.handle[3], 1)
    winScale:SetThumbTexture(wsThumb)
    winScale:SetValue(PowerInfusionAssignmentsDB.optionsScale or 1)
    winScaleReadout:SetText(string.format("%d%%", math.floor((PowerInfusionAssignmentsDB.optionsScale or 1) * 100 + 0.5)))
    -- Apply on release: o:SetScale live would move this slider (a child of o)
    -- under the cursor and re-fire OnValueChanged in a runaway loop.
    local function ApplyWindowScale()
        o:SetScale(PowerInfusionAssignmentsDB.optionsScale or 1)
    end
    winScale:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / 0.05 + 0.5) * 0.05
        PowerInfusionAssignmentsDB.optionsScale = v
        winScaleReadout:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
    end)
    winScale:SetScript("OnMouseUp", ApplyWindowScale)
    winScale:HookScript("OnMouseWheel", ApplyWindowScale)

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
        -- Never land on a tab the current spec can't see.
        local btn = navButtons[key]
        if btn and btn.healerOnly and not IsHealer() then key = "setup" end
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

    -- Nav buttons are created once; RefreshTabVisibility hides the healer-only
    -- ones for other specs and re-lays out the remaining ones with no gaps.
    local function CreateNavButton(index, key, text, healerOnly)
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

        b.key = key
        b.healerOnly = healerOnly and true or false
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

    CreateNavButton(1, "setup",   "Setup")
    CreateNavButton(2, "alerts",  "Cooldown Alerts",   true)
    CreateNavButton(3, "style",   "Alert Style",       true)
    CreateNavButton(4, "tracked", "Tracked Cooldowns", true)
    CreateNavButton(5, "window",  "Display")
    CreateNavButton(6, "help",    "Help")

    RefreshTabVisibility = function()
        local healer = IsHealer()
        local shown = 0
        for i = 1, #navButtons do
            local b = navButtons[i]
            local show = (not b.healerOnly) or healer
            b:SetShown(show)
            if show then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -8 - shown * 40)
                shown = shown + 1
            end
        end
        -- If the current tab just became hidden (e.g. healer -> shadow swap),
        -- fall back to Setup.
        local cur = navButtons[o.section]
        if cur and cur.healerOnly and not healer then
            SelectSection("setup")
        end
    end

    -- Red "!" on the Setup tab when macro mode is on but no valid macro is set,
    -- so the priority to fix it is visible from any tab.
    local setupAlert = Label(navButtons.setup, 16, {0.95, 0.35, 0.35})
    setupAlert:SetPoint("RIGHT", navButtons.setup, "RIGHT", -14, 0)
    setupAlert:SetText("!")
    setupAlert:Hide()

    -- =====================================================================
    -- SETUP PANE (everyone): a live status checklist + the macro setup.
    -- =====================================================================
    local setup = NewPane("setup")

    -- --- Status (top): the one thing that must be right, plus the sharing note. ---
    local macroStatus = Label(setup, 15, C.body, true)
    macroStatus:SetPoint("TOPLEFT", setup, "TOPLEFT", 0, 2)
    macroStatus:SetPoint("RIGHT", setup, "RIGHT", 0, 0)

    local coLine = Label(setup, 13, C.desc, true)
    coLine:SetPoint("TOPLEFT", macroStatus, "BOTTOMLEFT", 0, -8)
    coLine:SetPoint("RIGHT", setup, "RIGHT", 0, 0)
    coLine:SetText("Assignments sync only between priests who run this addon.")

    local divider = setup:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPLEFT", coLine, "BOTTOMLEFT", 0, -14)
    divider:SetPoint("RIGHT", setup, "RIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(C.edgeRow[1], C.edgeRow[2], C.edgeRow[3], 1)

    -- --- Macro setup (below the checklist) ---
    local modeMicro = Label(setup, 11, C.micro)
    modeMicro:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -16)
    modeMicro:SetText("YOUR PI ASSIGNMENT")

    local PI_MODE_OPTIONS = {
        [1] = "My PI target is set in a macro",
        [2] = "My PI target is *not* set in a macro",
    }

    -- UIDropDownMenu can't be flattened to this design, so the picker is a plain
    -- button plus a two-row popup.
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
        RefreshSetupStatus()
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
        PowerInfusionAssignmentsDB.macroName = edit:GetText() or ""
        UpdateHintVisibility()
        RefreshSetupStatus()
    end

    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            PowerInfusionAssignmentsDB.macroName = self:GetText() or ""
            UpdateHintVisibility()
            RefreshSetupStatus()
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
    mouseoverMacroLabel:SetText("Tell the addon who your PI target is so it can watch their cooldowns and share your assignment with your fellow priests: \n\n1) Bind the below macro to a key\n2) Out of combat, mouseover your PI target and press the key.\n3) Done - your assignment is now set, shared, and tracked.")
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

    -- === TOGGLE ROWS (used by the Window pane) ===
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
        end)

        toggleRows[#toggleRows + 1] = row
        return row
    end

    -- Compact single-line checkbox (no per-row description), used where the
    -- 44px toggle row is too tall (the raid alert toggle, the icon countdown).
    local compactChecks = {}
    local function CompactCheck(parent, text, getV, setV, onChange)
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(PANE_W, 22)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(15, 15)
        box:SetPoint("LEFT", row, "LEFT", 0, 0)
        local fill = Fill(box, C.inset)
        local edges = Outline(box, C.edgeCtrl)
        local check = box:CreateTexture(nil, "OVERLAY")
        check:SetPoint("CENTER"); check:SetSize(15, 15)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        check:SetVertexColor(C.onAccent[1], C.onAccent[2], C.onAccent[3])
        local lbl = Label(row, 14, C.body)
        lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        lbl:SetText(text)
        row.Refresh = function()
            local on = getV() and true or false
            check:SetShown(on)
            if on then
                fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                SetOutlineColor(edges, C.edgeHot)
                lbl:SetTextColor(C.title[1], C.title[2], C.title[3])
            else
                fill:SetColorTexture(C.inset[1], C.inset[2], C.inset[3], 1)
                SetOutlineColor(edges, C.edgeCtrl)
                lbl:SetTextColor(C.body[1], C.body[2], C.body[3])
            end
        end
        row:SetScript("OnClick", function()
            setV(not getV())
            row.Refresh()
            if onChange then onChange() end
        end)
        row.Refresh()
        compactChecks[#compactChecks + 1] = row
        return row
    end

    -- =====================================================================
    -- COOLDOWN ALERTS PANE (healer only): WHEN + ALERT STYLE.
    -- =====================================================================
    local alerts = NewPane("alerts")

    -- --- WHEN ---
    local whenMicro = Label(alerts, 11, C.micro)
    whenMicro:SetPoint("TOPLEFT", alerts, "TOPLEFT", 0, 0)
    whenMicro:SetText("WHEN TO ALERT ME (HEALER)")

    local whenDesc = Label(alerts, 12, C.desc, true)
    whenDesc:SetPoint("TOPLEFT", whenMicro, "BOTTOMLEFT", 0, -6)
    whenDesc:SetPoint("RIGHT", alerts, "RIGHT", 0, 0)
    whenDesc:SetText("Highlight your PI target's frame when they use cooldowns, so you know when to press Power Infusion.")

    local raidCheck = CompactCheck(alerts,
        "Raids: alert me when my PI assignment uses cooldowns",
        function() return PowerInfusionAssignmentsDB.notifyOnCooldown end,
        function(v) PowerInfusionAssignmentsDB.notifyOnCooldown = v end,
        function() PI:QueueGlowUpdate() end)
    raidCheck:SetPoint("TOPLEFT", whenDesc, "BOTTOMLEFT", 0, -10)

    local dungLabel = Label(alerts, 14, C.body)
    dungLabel:SetPoint("TOPLEFT", raidCheck, "BOTTOMLEFT", 0, -10)
    dungLabel:SetText("Dungeons (5-man)")

    local DUNGEON_MODES = {
        { id = "off",        name = "Off" },
        { id = "assignment", name = "Notify when my PI assignment uses cooldowns" },
        { id = "alldps",     name = "Notify when any DPS uses cooldowns" },
    }
    local function CurrentDungeonName()
        local cur = PowerInfusionAssignmentsDB.dungeonMode or "off"
        for i = 1, #DUNGEON_MODES do
            if DUNGEON_MODES[i].id == cur then return DUNGEON_MODES[i].name end
        end
        return DUNGEON_MODES[1].name
    end
    local dungButton = FlatButton(alerts, PANE_W, 30, "", C.inset, C.btnHover, C.edgeDrop, C.field)
    dungButton:SetPoint("TOPLEFT", dungLabel, "BOTTOMLEFT", 0, -6)
    local dungArrow = Label(dungButton, 12, C.field)
    dungArrow:SetPoint("RIGHT", dungButton, "RIGHT", -8, 0)
    dungArrow:SetText("v")
    dungButton.label:ClearAllPoints()
    dungButton.label:SetPoint("LEFT", dungButton, "LEFT", 10, 0)
    dungButton.label:SetPoint("RIGHT", dungArrow, "LEFT", -4, 0)
    dungButton.label:SetJustifyH("LEFT")
    local function RefreshDungButton() dungButton.label:SetText(CurrentDungeonName()) end

    local dungMenu = CreateFrame("Frame", nil, dungButton)
    dungMenu:SetPoint("TOPLEFT", dungButton, "BOTTOMLEFT", 0, -2)
    dungMenu:SetSize(PANE_W, #DUNGEON_MODES * 26 + 6)
    dungMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    Fill(dungMenu, C.inset)
    Outline(dungMenu, C.edgeDrop)
    dungMenu:Hide()
    local dungItems = {}
    for i = 1, #DUNGEON_MODES do
        local item = CreateFrame("Button", nil, dungMenu)
        item:SetSize(PANE_W - 2, 26)
        item:SetPoint("TOPLEFT", dungMenu, "TOPLEFT", 1, -3 - (i - 1) * 26)
        item.bg = Fill(item, C.btnHover); item.bg:Hide()
        item.tick = item:CreateTexture(nil, "OVERLAY")
        item.tick:SetSize(14, 14)
        item.tick:SetPoint("LEFT", item, "LEFT", 4, 0)
        item.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        item.tick:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        item.itemLabel = Label(item, 13, C.body)
        item.itemLabel:SetPoint("LEFT", item, "LEFT", 20, 0)
        item.itemLabel:SetText(DUNGEON_MODES[i].name)
        item:SetScript("OnEnter", function(self) self.bg:Show() end)
        item:SetScript("OnLeave", function(self) self.bg:Hide() end)
        item:SetScript("OnClick", function()
            PowerInfusionAssignmentsDB.dungeonMode = DUNGEON_MODES[i].id
            RefreshDungButton()
            dungMenu:Hide()
            PI:QueueGlowUpdate()
        end)
        dungItems[i] = item
    end
    local function MarkDungMenu()
        local cur = PowerInfusionAssignmentsDB.dungeonMode or "off"
        for i = 1, #DUNGEON_MODES do
            local sel = DUNGEON_MODES[i].id == cur
            dungItems[i].tick:SetShown(sel)
            local col = sel and C.title or C.body
            dungItems[i].itemLabel:SetTextColor(col[1], col[2], col[3])
        end
    end
    dungButton:SetScript("OnClick", function()
        if not dungMenu:IsShown() then MarkDungMenu() end
        dungMenu:SetShown(not dungMenu:IsShown())
    end)
    RefreshDungButton()

    -- =====================================================================
    -- ALERT STYLE PANE (healer only): cooldown icon + extra effect.
    -- =====================================================================
    local style = NewPane("style")

    -- A compact labelled slider. Live-updates + previews via QueueGlowUpdate.
    local function OptSlider(parent, labelText, topAnchor, yGap, minV, maxV, step, getV, setV)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(PANE_W, 24)
        if topAnchor then
            row:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -yGap)
        else
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        end
        local lbl = Label(row, 14, C.body)
        lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        lbl:SetText(labelText)
        local readout = Label(row, 13, C.title)
        readout:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        readout:SetJustifyH("RIGHT")
        local slider = CreateFrame("Slider", nil, row)
        slider:SetPoint("LEFT", lbl, "RIGHT", 90, 0)
        slider:SetPoint("RIGHT", readout, "LEFT", -12, 0)
        slider:SetHeight(16)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        local tr = slider:CreateTexture(nil, "BACKGROUND")
        tr:SetPoint("LEFT"); tr:SetPoint("RIGHT"); tr:SetHeight(4)
        tr:SetColorTexture(C.trackBg[1], C.trackBg[2], C.trackBg[3], 1)
        local thumb = slider:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(8, 16)
        thumb:SetColorTexture(C.handle[1], C.handle[2], C.handle[3], 1)
        slider:SetThumbTexture(thumb)
        slider:SetValue(getV())
        readout:SetText(tostring(getV()))
        slider:SetScript("OnValueChanged", function(_, v)
            v = math.floor(v + 0.5)
            readout:SetText(tostring(v))
            setV(v)
            PI:QueueGlowUpdate()
        end)
        return row
    end

    -- A flat picker: a button + a drop popup of {id,name} options that writes `key`
    -- to the DB and calls onPick. Used for the anchor and extra-effect pickers.
    local DROP_X, DROP_W = 74, 220
    local function Picker(parent, labelText, items, getId, setId, onPick)
        local lbl = Label(parent, 14, C.body)
        lbl:SetText(labelText)
        local function CurrentName()
            local id = getId()
            for i = 1, #items do if items[i].id == id then return items[i].name end end
            return items[1].name
        end
        local btn = FlatButton(parent, DROP_W, 26, "", C.btnFace, C.btnHover, C.edgeCtrl, C.field)
        btn:SetPoint("LEFT", lbl, "LEFT", DROP_X, 0)
        local arrow = Label(btn, 12, C.field)
        arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        arrow:SetText("v")
        btn.label:ClearAllPoints()
        btn.label:SetPoint("LEFT", btn, "LEFT", 10, 0)
        btn.label:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
        btn.label:SetJustifyH("LEFT")
        local function Refresh() btn.label:SetText(CurrentName()) end

        local menu = CreateFrame("Frame", nil, btn)
        menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        menu:SetSize(DROP_W, #items * 22 + 6)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        Fill(menu, C.inset)
        Outline(menu, C.edgeDrop)
        menu:Hide()
        local its = {}
        for i = 1, #items do
            local item = CreateFrame("Button", nil, menu)
            item:SetSize(DROP_W - 2, 22)
            item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -3 - (i - 1) * 22)
            item.bg = Fill(item, C.btnHover); item.bg:Hide()
            item.tick = item:CreateTexture(nil, "OVERLAY")
            item.tick:SetSize(14, 14)
            item.tick:SetPoint("LEFT", item, "LEFT", 3, 0)
            item.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            item.tick:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            item.itemLabel = Label(item, 13, C.body)
            item.itemLabel:SetPoint("LEFT", item, "LEFT", 18, 0)
            item.itemLabel:SetText(items[i].name)
            item:SetScript("OnEnter", function(self) self.bg:Show() end)
            item:SetScript("OnLeave", function(self) self.bg:Hide() end)
            item:SetScript("OnClick", function()
                setId(items[i].id)
                Refresh()
                menu:Hide()
                if onPick then onPick() end
            end)
            its[i] = item
        end
        local function Mark()
            local id = getId()
            for i = 1, #items do
                local sel = items[i].id == id
                its[i].tick:SetShown(sel)
                local col = sel and C.title or C.body
                its[i].itemLabel:SetTextColor(col[1], col[2], col[3])
            end
        end
        btn:SetScript("OnClick", function()
            if not menu:IsShown() then Mark() end
            menu:SetShown(not menu:IsShown())
        end)
        Refresh()
        return lbl, btn
    end

    -- --- COOLDOWN ICON (shows the spell that was used) ---
    local ICON_OPTS = {
        { id = "cooldown", name = "Cooldown used" },
        { id = "pi",       name = "Power Infusion" },
        { id = "none",     name = "None" },
    }
    local iconLabel = Picker(style, "Icon", ICON_OPTS,
        function()
            if not PowerInfusionAssignmentsDB.showCdIcon then return "none" end
            return PowerInfusionAssignmentsDB.iconType or "cooldown"
        end,
        function(v)
            if v == "none" then
                PowerInfusionAssignmentsDB.showCdIcon = false
            else
                PowerInfusionAssignmentsDB.showCdIcon = true
                PowerInfusionAssignmentsDB.iconType = v
            end
        end,
        function() PI:QueueGlowUpdate() end)
    iconLabel:SetPoint("TOPLEFT", style, "TOPLEFT", 0, 0)

    local ANCHOR_OPTS = {
        { id = "CENTER", name = "Center" },
        { id = "TOPLEFT", name = "Top left" }, { id = "TOP", name = "Top" }, { id = "TOPRIGHT", name = "Top right" },
        { id = "LEFT", name = "Left" }, { id = "RIGHT", name = "Right" },
        { id = "BOTTOMLEFT", name = "Bottom left" }, { id = "BOTTOM", name = "Bottom" }, { id = "BOTTOMRIGHT", name = "Bottom right" },
    }
    local anchorLabel = Picker(style, "Anchor", ANCHOR_OPTS,
        function() return PowerInfusionAssignmentsDB.cdAnchor end,
        function(v) PowerInfusionAssignmentsDB.cdAnchor = v end,
        function() PI:QueueGlowUpdate() end)
    anchorLabel:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -34)

    local outsideToggle = CompactCheck(style, "Place icon on outside of frame",
        function() return PowerInfusionAssignmentsDB.cdOutside end,
        function(v) PowerInfusionAssignmentsDB.cdOutside = v end,
        function() PI:QueueGlowUpdate() end)
    outsideToggle:SetPoint("TOPLEFT", anchorLabel, "BOTTOMLEFT", 0, -34)

    local sizeRow = OptSlider(style, "Size", outsideToggle, 12, 16, 96, 2,
        function() return PowerInfusionAssignmentsDB.iconSize or 36 end,
        function(v) PowerInfusionAssignmentsDB.iconSize = v end)
    local opacityRow = OptSlider(style, "Opacity %", sizeRow, 12, 20, 100, 5,
        function() return PowerInfusionAssignmentsDB.iconAlpha or 70 end,
        function(v) PowerInfusionAssignmentsDB.iconAlpha = v end)

    local countToggle = CompactCheck(style, "Show countdown timer on the icon",
        function() return PowerInfusionAssignmentsDB.iconCountdown ~= false end,
        function(v) PowerInfusionAssignmentsDB.iconCountdown = v end,
        function() PI:QueueGlowUpdate() end)
    countToggle:SetPoint("TOPLEFT", opacityRow, "BOTTOMLEFT", 0, -12)

    -- --- EXTRA EFFECT (optional, on top of the icon) ---
    local EFFECT_OPTS = {
        { id = "none", name = "None" }, { id = "border", name = "Pulse Border" }, { id = "fill", name = "Flash Frame" },
    }
    local RefreshEffectOptions
    local glowLabel = Picker(style, "Effect", EFFECT_OPTS,
        function() return PowerInfusionAssignmentsDB.extraEffect end,
        function(v) PowerInfusionAssignmentsDB.extraEffect = v end,
        function() if RefreshEffectOptions then RefreshEffectOptions() end; PI:QueueGlowUpdate() end)
    glowLabel:SetPoint("TOPLEFT", countToggle, "BOTTOMLEFT", 0, -18)

    -- Colour swatch + effect Test preview, to the right of the Effect picker.
    local swatch = CreateFrame("Button", nil, style)
    swatch:SetSize(26, 26)
    swatch:SetPoint("LEFT", glowLabel, "LEFT", DROP_X + DROP_W + 66, 0)
    local swatchFill = swatch:CreateTexture(nil, "ARTWORK")
    swatchFill:SetPoint("TOPLEFT", 1, -1)
    swatchFill:SetPoint("BOTTOMRIGHT", -1, 1)
    Outline(swatch, C.edgeCtrl)
    local function RefreshSwatch()
        local c = PowerInfusionAssignmentsDB.glowColor
        swatchFill:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
    end
    RefreshSwatch()
    swatch:SetScript("OnClick", function()
        local function apply(r, g, b)
            PowerInfusionAssignmentsDB.glowColor = { r, g, b }
            RefreshSwatch()
            PI:QueueGlowUpdate()
        end
        local c = PowerInfusionAssignmentsDB.glowColor
        local info = {
            r = c[1], g = c[2], b = c[3],
            swatchFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); apply(r, g, b) end,
            cancelFunc = function(prev) if prev and prev.r then apply(prev.r, prev.g, prev.b) end end,
        }
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame.func = info.swatchFunc
            ColorPickerFrame.cancelFunc = info.cancelFunc
            ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
            ColorPickerFrame:Show()
        end
    end)

    local effectTest = FlatButton(style, 54, 26, "Test", C.primary, C.primaryHover, C.edgeHot, C.title)
    effectTest:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    local function RefreshEffectTestButton()
        if PI.effectTesting then
            effectTest.label:SetText("Stop")
            effectTest.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            effectTest.label:SetText("Test")
            effectTest.bg:SetColorTexture(C.primary[1], C.primary[2], C.primary[3], 1)
        end
    end
    effectTest:SetScript("OnClick", function()
        if PI.ToggleEffectTest then PI:ToggleEffectTest() end
        RefreshEffectTestButton()
    end)
    effectTest:HookScript("OnLeave", RefreshEffectTestButton)
    effectTest:HookScript("OnEnter", function()
        if PI.effectTesting then effectTest.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1) end
    end)

    -- Extra-effect options (shown only for the selected effect), anchored last so
    -- toggling them reflows nothing above.
    local borderOptions = CreateFrame("Frame", nil, style)
    borderOptions:SetPoint("TOPLEFT", glowLabel, "BOTTOMLEFT", 0, -16)
    borderOptions:SetPoint("RIGHT", style, "RIGHT", 0, 0)
    borderOptions:SetHeight(70)
    local borderThickRow = OptSlider(borderOptions, "Thickness", nil, 0, 1, 8, 1,
        function() return PowerInfusionAssignmentsDB.pixelThickness or 2 end,
        function(v) PowerInfusionAssignmentsDB.pixelThickness = v end)
    OptSlider(borderOptions, "Intensity %", borderThickRow, 12, 20, 100, 5,
        function() return PowerInfusionAssignmentsDB.glowAlpha or 90 end,
        function(v) PowerInfusionAssignmentsDB.glowAlpha = v end)

    local fillOptions = CreateFrame("Frame", nil, style)
    fillOptions:SetPoint("TOPLEFT", glowLabel, "BOTTOMLEFT", 0, -16)
    fillOptions:SetPoint("RIGHT", style, "RIGHT", 0, 0)
    fillOptions:SetHeight(70)
    OptSlider(fillOptions, "Intensity %", nil, 0, 20, 100, 5,
        function() return PowerInfusionAssignmentsDB.glowAlpha or 90 end,
        function(v) PowerInfusionAssignmentsDB.glowAlpha = v end)

    RefreshEffectOptions = function()
        local ex = PowerInfusionAssignmentsDB.extraEffect
        borderOptions:SetShown(ex == "border")
        fillOptions:SetShown(ex == "fill")
        swatch:SetShown(ex ~= "none")   -- colour only applies to the extra effect
    end
    RefreshEffectOptions()


    -- =====================================================================
    -- TRACKED COOLDOWNS PANE (healer only): custom IDs + the spell catalog.
    -- =====================================================================
    local tracked = NewPane("tracked")

    local trackMicro = Label(tracked, 11, C.micro)
    trackMicro:SetPoint("TOPLEFT", tracked, "TOPLEFT", 0, 0)
    trackMicro:SetText("TRACKED COOLDOWNS")

    local trackHint = Label(tracked, 12, C.desc, true)
    trackHint:SetPoint("TOPLEFT", trackMicro, "BOTTOMLEFT", 0, -6)
    trackHint:SetPoint("RIGHT", tracked, "RIGHT", 0, 0)
    trackHint:SetText("You'll be alerted when a watched cooldown appears. Add your own by aura (buff) ID - not the spell's ID.")

    -- Custom add row.
    local customInput, customInputBox = InsetEditBox(tracked, 120, 26, 14)
    customInputBox:SetPoint("TOPLEFT", trackHint, "BOTTOMLEFT", 0, -12)
    customInput:SetNumeric(true)

    local addButton = FlatButton(tracked, 60, 26, "Add", C.primary, C.primaryHover, C.edgeHot, C.title)
    addButton:SetPoint("LEFT", customInputBox, "RIGHT", 8, 0)

    local customHintInline = Label(tracked, 12, C.muted)
    customHintInline:SetPoint("LEFT", addButton, "RIGHT", 10, 0)
    customHintInline:SetText("custom aura ID")

    -- The catalog is long, so it lives in a mouse-wheel scroll child. Its top is
    -- re-anchored below the custom rows whenever they change.
    local trackScroll = CreateFrame("ScrollFrame", nil, tracked)
    trackScroll:SetPoint("BOTTOMRIGHT", tracked, "BOTTOMRIGHT", 0, 0)
    trackScroll:EnableMouseWheel(true)

    local trackChild = CreateFrame("Frame", nil, trackScroll)
    trackChild:SetSize(PANE_W, 10)
    trackScroll:SetScrollChild(trackChild)

    trackScroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local new = self:GetVerticalScroll() - delta * 34
        if new < 0 then new = 0 elseif new > range then new = range end
        self:SetVerticalScroll(new)
    end)

    local CHECK_H = 22
    local COL_W = math.floor((PANE_W - 8) / 2)   -- two columns of specs per class
    local checkRows = {}

    local function TrackCheck(spellID, text, x, y)
        local row = CreateFrame("Button", nil, trackChild)
        row:SetSize(COL_W - 8, CHECK_H)
        row:SetPoint("TOPLEFT", trackChild, "TOPLEFT", x, -y)

        local box = CreateFrame("Frame", nil, row)
        box:SetSize(15, 15)
        box:SetPoint("LEFT", row, "LEFT", 0, 0)
        local boxFill = Fill(box, C.inset)
        local boxEdges = Outline(box, C.edgeCtrl)
        local check = box:CreateTexture(nil, "OVERLAY")
        check:SetPoint("CENTER")
        check:SetSize(15, 15)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        check:SetVertexColor(C.onAccent[1], C.onAccent[2], C.onAccent[3])

        local lbl = Label(row, 13, C.body)
        lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
        lbl:SetText(text)

        row.Refresh = function()
            local on = PI:IsSpellTracked(spellID)
            check:SetShown(on)
            if on then
                boxFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                SetOutlineColor(boxEdges, C.edgeHot)
            else
                boxFill:SetColorTexture(C.inset[1], C.inset[2], C.inset[3], 1)
                SetOutlineColor(boxEdges, C.edgeCtrl)
            end
        end
        row:SetScript("OnClick", function()
            PI:SetSpellTracked(spellID, not PI:IsSpellTracked(spellID))
            row.Refresh()
            PI:QueueGlowUpdate()
        end)
        row.Refresh()
        checkRows[#checkRows + 1] = row
        return row
    end

    local function BuildSpecCell(entry, x, top)
        local header = Label(trackChild, 13, C.title)
        header:SetPoint("TOPLEFT", trackChild, "TOPLEFT", x, -top)
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
        if cc then header:SetTextColor(cc.r, cc.g, cc.b) end
        header:SetText(entry.spec)
        local cy = top + 20
        if #entry.cds == 0 then
            local note = Label(trackChild, 12, C.muted)
            note:SetPoint("TOPLEFT", trackChild, "TOPLEFT", x + 8, -cy)
            note:SetText("no default - add ID above")
            cy = cy + CHECK_H
        else
            for j = 1, #entry.cds do
                local cd = entry.cds[j]
                TrackCheck(cd[1], PI:GetSpellDisplayName(cd[1], cd[2]), x + 8, cy)
                cy = cy + CHECK_H
            end
        end
        return cy - top   -- cell height
    end

    local y = 4
    local ci, nCat = 1, #PI.TRACK_CATALOG
    while ci <= nCat do
        local class = PI.TRACK_CATALOG[ci].class
        local specs = {}
        while ci <= nCat and PI.TRACK_CATALOG[ci].class == class do
            specs[#specs + 1] = PI.TRACK_CATALOG[ci]
            ci = ci + 1
        end
        local col, rowTop, rowMaxH = 0, y, 0
        for s = 1, #specs do
            local cellH = BuildSpecCell(specs[s], 8 + col * COL_W, rowTop)
            if cellH > rowMaxH then rowMaxH = cellH end
            col = col + 1
            if col >= 2 then
                col, rowTop, rowMaxH = 0, rowTop + rowMaxH + 8, 0
            end
        end
        if col > 0 then rowTop = rowTop + rowMaxH + 8 end
        y = rowTop + 6
    end
    trackChild:SetHeight(math.max(y + 8, 10))

    -- Current custom IDs, rebuilt on add/remove. Rows pooled (hidden and reused).
    local customRows = {}
    local RebuildCustomList

    local function CustomRow(index)
        local row = customRows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, tracked)
        row:SetSize(PANE_W, CHECK_H)
        row.remove = FlatButton(row, 18, 18, "x", C.btnFace, C.btnHover, C.edgeCtrl, C.field)
        row.remove:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.lbl = Label(row, 13, C.body)
        row.lbl:SetPoint("LEFT", row.remove, "RIGHT", 8, 0)
        customRows[index] = row
        return row
    end

    RebuildCustomList = function()
        local custom = PowerInfusionAssignmentsDB.customSpells
        for i = 1, #custom do
            local id = custom[i]
            local row = CustomRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", customInputBox, "BOTTOMLEFT", 0, -10 - (i - 1) * CHECK_H)
            row.lbl:SetText(PI:GetSpellDisplayName(id, "Spell "..id).."  ("..id..")")
            row.remove:SetScript("OnClick", function()
                PI:RemoveCustomSpell(id)
                RebuildCustomList()
                PI:QueueGlowUpdate()
            end)
            row:Show()
        end
        for i = #custom + 1, #customRows do
            customRows[i]:Hide()
        end
        -- Re-anchor the catalog scroll below the input + however many custom rows.
        local used = 10 + #custom * CHECK_H + 12
        trackScroll:ClearAllPoints()
        trackScroll:SetPoint("TOPLEFT", customInputBox, "BOTTOMLEFT", 0, -used)
        trackScroll:SetPoint("BOTTOMRIGHT", tracked, "BOTTOMRIGHT", 0, 0)
    end

    addButton:SetScript("OnClick", function()
        if PI:AddCustomSpell(customInput:GetText()) then
            customInput:SetText("")
            RebuildCustomList()
            PI:QueueGlowUpdate()
        end
    end)
    customInput:SetScript("OnEnterPressed", function(self)
        if PI:AddCustomSpell(self:GetText()) then
            self:SetText("")
            RebuildCustomList()
            PI:QueueGlowUpdate()
        end
        self:ClearFocus()
    end)

    RebuildCustomList()

    local function RefreshTracking()
        for i = 1, #checkRows do checkRows[i].Refresh() end
        RebuildCustomList()
    end

    -- =====================================================================
    -- WINDOW PANE (everyone): behaviour toggles + panel scale.
    -- =====================================================================
    local window = NewPane("window")

    CreateToggleRow(window, 1, "Hide PI assignments in combat",
        "The assignment window is hidden while you are in combat.",
        function() return PowerInfusionAssignmentsDB.hideInCombat end,
        function(v)
            PowerInfusionAssignmentsDB.hideInCombat = v
            PI:UpdateAssignmentFrameVisibility()
        end)

    CreateToggleRow(window, 2, "Show PI assignments even if I'm not a priest",
        "Shows the window on non-priest characters, for raid leads tracking PI.",
        function() return PowerInfusionAssignmentsDB.showForNonPriest end,
        function(v)
            PowerInfusionAssignmentsDB.showForNonPriest = v
            PI:UpdateAssignmentFrameVisibility()
            PI:UpdateTickerState()
        end)

    CreateToggleRow(window, 3, "Enable whispers (guild only)",
        "Whispers your old and new assignment whenever your PI assignment changes.",
        function() return PowerInfusionAssignmentsDB.enableWhispers end,
        function(v) PowerInfusionAssignmentsDB.enableWhispers = v end)

    CreateToggleRow(window, 4, "Test mode (show fake data)",
        "Fills the window with sample assignments so you can position it.",
        function() return PowerInfusionAssignmentsDB.testMode end,
        function(v) PI:SetTestMode(v) end)

    CreateToggleRow(window, 5, "Lock frame",
        "Stops the assignment window being dragged.",
        function() return PowerInfusionAssignmentsDB.lockFrame end,
        function(v)
            PowerInfusionAssignmentsDB.lockFrame = v
            PI:UpdateFrameLock()
        end)

    -- Panel scale (sizes the on-screen PI assignment panel, not this window).
    local scaleCaption = Label(window, 12, C.desc)
    scaleCaption:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -(5 * ROW_H) - 14)
    scaleCaption:SetText("Size of the on-screen PI assignment panel (not this window)")

    local scaleRow = CreateFrame("Frame", nil, window)
    scaleRow:SetPoint("TOPLEFT", scaleCaption, "BOTTOMLEFT", 0, -8)
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

    local scaleSlider = CreateFrame("Slider", "PI_ScaleSlider", scaleRow)
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", 14, 0)
    scaleSlider:SetPoint("RIGHT", stepper, "LEFT", -14, 0)
    scaleSlider:SetHeight(20)
    scaleSlider:SetOrientation("HORIZONTAL")
    scaleSlider:SetMinMaxValues(SCALE_MIN, SCALE_MAX)
    scaleSlider:SetValueStep(SCALE_STEP)
    scaleSlider:SetObeyStepOnDrag(true)

    local scTrackEdge = scaleSlider:CreateTexture(nil, "BACKGROUND")
    scTrackEdge:SetPoint("LEFT")
    scTrackEdge:SetPoint("RIGHT")
    scTrackEdge:SetHeight(6)
    scTrackEdge:SetColorTexture(C.trackEdge[1], C.trackEdge[2], C.trackEdge[3], 1)

    local scTrackBg = scaleSlider:CreateTexture(nil, "BORDER")
    scTrackBg:SetPoint("LEFT", scTrackEdge, "LEFT", 1, 0)
    scTrackBg:SetPoint("RIGHT", scTrackEdge, "RIGHT", -1, 0)
    scTrackBg:SetHeight(4)
    scTrackBg:SetColorTexture(C.trackBg[1], C.trackBg[2], C.trackBg[3], 1)

    local scThumb = scaleSlider:CreateTexture(nil, "OVERLAY")
    scThumb:SetSize(9, 18)
    scThumb:SetColorTexture(C.handle[1], C.handle[2], C.handle[3], 1)
    scaleSlider:SetThumbTexture(scThumb)

    local scTrackFill = scaleSlider:CreateTexture(nil, "ARTWORK")
    scTrackFill:SetPoint("LEFT", scTrackBg, "LEFT", 0, 0)
    scTrackFill:SetPoint("RIGHT", scThumb, "CENTER", 0, 0)
    scTrackFill:SetHeight(4)
    scTrackFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

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

    -- =====================================================================
    -- HELP PANE (everyone): FAQ + advanced reading.
    -- =====================================================================
    local help = NewPane("help")

    local faqScroll = CreateFrame("ScrollFrame", nil, help)
    faqScroll:SetPoint("TOPLEFT", help, "TOPLEFT", 0, 0)
    faqScroll:SetPoint("BOTTOMRIGHT", help, "BOTTOMRIGHT", -12, 0)
    faqScroll:EnableMouseWheel(true)
    local faqChild = CreateFrame("Frame", nil, faqScroll)
    faqChild:SetSize(PANE_W - 12, 10)
    faqScroll:SetScrollChild(faqChild)
    faqScroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local nw = self:GetVerticalScroll() - delta * 34
        if nw < 0 then nw = 0 elseif nw > range then nw = range end
        self:SetVerticalScroll(nw)
    end)

    local faqText = Label(faqChild, 13, C.body, true)
    faqText:SetPoint("TOPLEFT", faqChild, "TOPLEFT", 0, 0)
    faqText:SetPoint("TOPRIGHT", faqChild, "TOPRIGHT", 0, 0)
    faqText:SetSpacing(3)
    faqText:SetText(
        "|cFFFFD100In raids|r\n"
        .. "- shows every priest's PI target in a movable window\n"
        .. "- warns you if two priests pick the same target, or if PI is set on a tank or healer\n"
        .. "- type !pi in raid chat to show the assignments to everyone\n"
        .. "- (healers) alerts you when your PI target uses cooldowns, so you know when to press PI\n\n"
        .. "|cFFFFD100In dungeons (5-man)|r\n"
        .. "- (healers) alerts you when a party member uses cooldowns\n"
        .. "- choose whether to watch just your PI target or every DPS, in Cooldown Alerts\n"
        .. "- the assignment window is raid-only; dungeons use the alerts only\n\n"
        .. "|cFFFFD100Setting up|r\n"
        .. "- Setup tab: tell the addon who you PI, with a macro or the mouseover method. That sets your target, shares it with other priests, and is what the alerts watch.\n"
        .. "- Sharing assignments needs every priest to run the addon; the alerts work on their own.\n"
        .. "- (healers) turn alerts on and pick what to watch in Cooldown Alerts; choose which cooldowns in Tracked Cooldowns.\n\n"
        .. "|cFFFFD100Tip|r\n- type /pi any time to open this window.")
    faqChild:SetHeight(math.max((faqText:GetStringHeight() or 400) + 10, 10))

    -- Advanced reading footer (moved out of Setup to keep onboarding clean).
    local recoHeading = Label(faqChild, 11, C.micro)
    recoHeading:SetPoint("TOPLEFT", faqText, "BOTTOMLEFT", 0, -18)
    recoHeading:SetText("FOR ADVANCED USERS")

    local recoLabel = Label(faqChild, 13, C.body, true)
    recoLabel:SetWidth(PANE_W - 12)
    recoLabel:SetPoint("TOPLEFT", recoHeading, "BOTTOMLEFT", 0, -8)
    recoLabel:SetText("The \"Advanced Power Infusion\" section of the Icy Veins guide:")

    local recoUrl, recoUrlBlock = MacroBlock(faqChild, PANE_W - 12, 40,
        "https://www.icy-veins.com/wow/shadow-priest-pve-dps-macros-addons")
    recoUrlBlock:SetPoint("TOPLEFT", recoLabel, "BOTTOMLEFT", 0, -8)

    local recoCopy = FlatButton(faqChild, 200, 26, "Select all (Ctrl+C to copy)",
        C.primary, C.primaryHover, C.edgeHot, C.title)
    recoCopy:SetPoint("TOPLEFT", recoUrlBlock, "BOTTOMLEFT", 0, -8)
    recoCopy:SetScript("OnClick", function()
        recoUrl:SetFocus()
        recoUrl:HighlightText(0)
    end)

    local function ResizeFaqChild()
        -- Grow the scroll child to include the advanced footer. String heights
        -- aren't known until the pane has laid out, so also recompute next frame.
        local h = (faqText:GetStringHeight() or 400) + 18 + 16 + 8
            + (recoLabel:GetStringHeight() or 16) + 8 + 40 + 8 + 26 + 12
        faqChild:SetHeight(math.max(h, 10))
    end
    ResizeFaqChild()
    help:SetScript("OnShow", function() C_Timer.After(0, ResizeFaqChild) end)

    -- === DERIVED STATE ===
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
        UpdateHintVisibility()
    end

    -- Also drives the Setup-tab "!" priority marker: in macro mode with no macro
    -- set (or a name that doesn't resolve), flag it so the user knows to fix it.
    -- The top status line carries the macro state, so the inline area only shows
    -- an error (macro named but not found). No duplicate "found" message.
    UpdateHintVisibility = function()
        macroHintText:Hide()
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        if mode ~= 1 then
            setupAlert:Hide()
            PI:ClearError()
            return
        end
        local macroName = PowerInfusionAssignmentsDB.macroName or ""
        if macroName == "" then
            setupAlert:Show()
            PI:ClearError()
        elseif not PI:FindMacroIndexByName(macroName) then
            setupAlert:Show()
            PI:SetError("Macro not found: " .. macroName)
        else
            setupAlert:Hide()
            PI:ClearError()
        end
    end

    -- One-line status of the thing that must be right: the PI target source.
    RefreshSetupStatus = function()
        local mode = PowerInfusionAssignmentsDB.piMode or 1
        if mode ~= 1 then
            macroStatus:SetText("|cff9ece6aReady.|r PI target set by mouseover - press your bound key on your target.")
            return
        end
        local name = PowerInfusionAssignmentsDB.macroName or ""
        if name == "" then
            macroStatus:SetText("|cffEA6767No macro set yet.|r Enter your PI macro's name below.")
        elseif PI:FindMacroIndexByName(name) then
            macroStatus:SetText("|cff9ece6aReady.|r Using macro \"" .. name .. "\".")
        else
            macroStatus:SetText("|cffEA6767Macro \"" .. name .. "\" not found.|r Check the name below.")
        end
    end

    local function RefreshToggles()
        for i = 1, #toggleRows do toggleRows[i]:Refresh() end
        for i = 1, #compactChecks do compactChecks[i].Refresh() end
    end

    -- Rebuild tab visibility + checklist when the player's spec changes.
    local specWatcher = CreateFrame("Frame")
    specWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specWatcher:SetScript("OnEvent", function()
        RefreshTabVisibility()
        RefreshSetupStatus()
    end)

    o:SetScript("OnShow", function(self)
        modeMenu:Hide()
        RefreshTabVisibility()
        RefreshToggles()
        RefreshTracking()
        RefreshEffectOptions()
        RefreshEffectTestButton()
        RefreshSetupStatus()
        UpdateModeVisibility()
        if self.edit then self.edit:ClearFocus() end
        if self.exampleMacroEdit then self.exampleMacroEdit:ClearFocus() end
        if self.mouseoverMacroEdit then self.mouseoverMacroEdit:ClearFocus() end
        scaleInput:ClearFocus()
        customInput:ClearFocus()
    end)

    -- Stop a lingering effect preview when the window closes.
    o:SetScript("OnHide", function()
        if PI.effectTesting and PI.ToggleEffectTest then
            PI:ToggleEffectTest()
            RefreshEffectTestButton()
        end
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
    o.RefreshTabVisibility = RefreshTabVisibility

    PI.options = o

    modeButton.label:SetText(PI_MODE_OPTIONS[PowerInfusionAssignmentsDB.piMode or 1])
    scaleSlider:SetValue(PowerInfusionAssignmentsDB.scale or 1)
    scaleInput:SetText(string.format("%.2f", PowerInfusionAssignmentsDB.scale or 1))
    edit:ClearFocus()
    exampleMacroEdit:ClearFocus()
    mouseoverMacroEdit:ClearFocus()
    scaleInput:ClearFocus()

    RefreshTabVisibility()
    RefreshToggles()
    RefreshSetupStatus()
    UpdateModeVisibility()
    SelectSection("setup")
end
