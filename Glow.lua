-- The alert visuals, painted on/around the engine's aura button. Two INDEPENDENT
-- things, either or both:
--   * Cooldown icon -- the ACTUAL cooldown's icon (e.g. Combustion), shown by
--     revealing the engine button's own icon texture, sized + anchored (9-point,
--     inside or just outside the cell), with an engine-driven countdown number.
--   * Extra effect -- a Pulse Border or Flash Frame over the whole cell.
--
-- We can never READ which spell the (secret) aura is, but the engine paints the
-- real icon onto its button for us. Crucially the button is NOT forbidden during
-- the initializeFrame callback (forbidden is applied only after it returns), so
-- that -- and any out-of-combat re-decorate -- is when we size/anchor it. Every
-- op is still pcall-guarded because the button is forbidden the rest of the time.
-- The extra effect + countdown live on our own `holder` frame (never forbidden).
-- Our own engine; informed by, not copied from, the reference addon.
local _, PI = ...

local function GlowColor()
    local c = PowerInfusionAssignmentsDB and PowerInfusionAssignmentsDB.glowColor
    if type(c) == "table" and type(c[1]) == "number" then
        return c[1], c[2] or 1, c[3] or 1, 0.9
    end
    return 0.847, 0.706, 0.416, 0.9
end

local function Forbidden(frame)
    if not frame or not frame.IsForbidden then return false end
    local ok, v = pcall(frame.IsForbidden, frame)
    if not ok then return true end
    return v == true
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PI_ICON = "Interface\\Icons\\Spell_Holy_PowerInfusion"

local function GlowAlpha()
    local db = PowerInfusionAssignmentsDB
    return ((db and db.glowAlpha) or 90) / 100
end

-- === Anchor maths: place the icon region on the cell per the 9-point anchor,
-- inside the cell, or (cdOutside) just outside that edge. Returns the SetPoint
-- args (iconPoint, cellPoint, dx, dy) including the user's nudge offset. ==========
local OPPOSITE = {
    CENTER = "CENTER",
    TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
    TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT",
    BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT",
}

local function IconAnchorPoints()
    local db = PowerInfusionAssignmentsDB
    local a = (db and db.cdAnchor) or "CENTER"
    local x = (db and db.iconX) or 0
    local y = (db and db.iconY) or 0
    if db and db.cdOutside and a ~= "CENTER" then
        -- The icon's FAR point touches the cell's anchor point, so it hangs
        -- just outside that edge/corner.
        return OPPOSITE[a] or "CENTER", a, x, y
    end
    return a, a, x, y
end

-- Strata ordering, lowest to highest, for lifting a region above a cell.
local STRATA_ORDER = {
    "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}
local STRATA_INDEX = {}
for i = 1, #STRATA_ORDER do STRATA_INDEX[STRATA_ORDER[i]] = i end

-- Put `frame` one strata above `cell` (and a high frame level within it) so it
-- draws over the cell's own health/status textures. Strata dominates frame level,
-- so this is robust across frame addons regardless of their internal levels.
local function RaiseAboveCell(frame, cell)
    local strata = "MEDIUM"
    if cell and cell.GetFrameStrata then
        local ok, s = pcall(cell.GetFrameStrata, cell)
        if ok and type(s) == "string" and STRATA_INDEX[s] then strata = s end
    end
    local up = STRATA_ORDER[math.min(#STRATA_ORDER, (STRATA_INDEX[strata] or 3) + 1)]
    pcall(frame.SetFrameStrata, frame, up)
    pcall(frame.SetFrameLevel, frame, 200)
end

-- ===== Extra effect: Flash Frame -- a translucent tint over the whole cell. =====
local function EnsureFill(holder)
    if holder.piaFill then return holder.piaFill end
    local t = holder:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    t:SetAllPoints(holder)
    local grp = holder:CreateAnimationGroup()
    grp:SetLooping("BOUNCE")
    local a = grp:CreateAnimation("Alpha")
    a:SetFromAlpha(0.5)
    a:SetToAlpha(1)
    a:SetDuration(0.6)
    a:SetSmoothing("IN_OUT")
    holder.piaFillAnim = grp
    holder.piaFill = t
    return t
end

local function HideFill(holder)
    if holder.piaFillAnim then pcall(holder.piaFillAnim.Stop, holder.piaFillAnim) end
    if holder.piaFill then pcall(holder.piaFill.Hide, holder.piaFill) end
end

local function PaintFill(holder)
    local r, g, b = GlowColor()
    local t = EnsureFill(holder)
    t:SetVertexColor(r, g, b, math.min(0.6, GlowAlpha() * 0.6))
    t:Show()
    pcall(holder.SetAlpha, holder, 1)
    if holder.piaFillAnim then pcall(holder.piaFillAnim.Play, holder.piaFillAnim) end
end

-- ===== Extra effect: Pulse Border -- a thin coloured outline hugging the cell. =====
local BORDER_KEYS = { "top", "bottom", "left", "right" }

local function EnsureBorder(holder)
    if holder.piaBorder then return holder.piaBorder end
    local e = {}
    for i = 1, #BORDER_KEYS do
        local t = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(WHITE)
        e[BORDER_KEYS[i]] = t
    end
    local grp = holder:CreateAnimationGroup()
    grp:SetLooping("BOUNCE")
    local a = grp:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.6)
    a:SetSmoothing("IN_OUT")
    holder.piaBorderAnim = grp
    holder.piaBorder = e
    return e
end

local function HideBorder(holder)
    if holder.piaBorderAnim then pcall(holder.piaBorderAnim.Stop, holder.piaBorderAnim) end
    if holder.piaBorder then
        for i = 1, #BORDER_KEYS do pcall(holder.piaBorder[BORDER_KEYS[i]].Hide, holder.piaBorder[BORDER_KEYS[i]]) end
    end
end

local function PaintBorder(holder)
    local r, g, b = GlowColor()
    local a = GlowAlpha()
    local db = PowerInfusionAssignmentsDB
    local th = (db and db.pixelThickness) or 2
    local e = EnsureBorder(holder)
    e.top:ClearAllPoints();    e.top:SetPoint("TOPLEFT");        e.top:SetPoint("TOPRIGHT");        e.top:SetHeight(th)
    e.bottom:ClearAllPoints(); e.bottom:SetPoint("BOTTOMLEFT");  e.bottom:SetPoint("BOTTOMRIGHT");  e.bottom:SetHeight(th)
    e.left:ClearAllPoints();   e.left:SetPoint("TOPLEFT", 0, -th);   e.left:SetPoint("BOTTOMLEFT", 0, th);   e.left:SetWidth(th)
    e.right:ClearAllPoints();  e.right:SetPoint("TOPRIGHT", 0, -th); e.right:SetPoint("BOTTOMRIGHT", 0, th); e.right:SetWidth(th)
    for i = 1, #BORDER_KEYS do
        local t = e[BORDER_KEYS[i]]
        t:SetColorTexture(r, g, b, a)
        t:Show()
    end
    pcall(holder.SetAlpha, holder, 1)
    if holder.piaBorderAnim then pcall(holder.piaBorderAnim.Play, holder.piaBorderAnim) end
end

-- ===== Countdown number (engine-driven) + the preview PI-icon fallback. =====
-- The number's TEXT is written by the engine via the button's SetDurationText
-- (bound in BindCountdown) so we never read the secret aura. The fontstring lives
-- on our holder and is centred over whatever region shows the icon.
-- The holder is a child of the (forbidden) aura button, so the fontstring is
-- forbidden too: every op must be pcall-guarded, like the rest of the paint path.
local function EnsureCountText(holder)
    if holder.piaCountText then return holder.piaCountText end
    local ok, fs = pcall(holder.CreateFontString, holder, nil, "OVERLAY")
    if not ok or not fs then return nil end
    pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    pcall(fs.SetTextColor, fs, 1, 1, 1, 1)
    pcall(fs.SetShadowColor, fs, 0, 0, 0, 1)
    pcall(fs.SetShadowOffset, fs, 1, -1)
    holder.piaCountText = fs
    return fs
end

local function PositionCountText(holder, anchorRegion)
    local db = PowerInfusionAssignmentsDB
    local fs = EnsureCountText(holder)
    if not fs then return end
    local size = (db and db.iconSize) or 36
    pcall(fs.ClearAllPoints, fs)
    pcall(fs.SetPoint, fs, "CENTER", anchorRegion, "CENTER", 0, 0)
    pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", math.max(10, math.floor(size * 0.5)), "OUTLINE")
    pcall(fs.SetShown, fs, (db and db.iconCountdown) ~= false)
end

-- Preview only: a PI icon on the holder (there is no engine button, so we can't
-- show the real cooldown icon in the Test preview -- this is a stand-in).
local function EnsurePIIcon(holder)
    if holder.piaIcon then return holder.piaIcon end
    local t = holder:CreateTexture(nil, "OVERLAY")
    t:SetTexture(PI_ICON)
    holder.piaIcon = t
    return t
end

local function HidePIIcon(holder)
    if holder.piaIcon then pcall(holder.piaIcon.Hide, holder.piaIcon) end
    if holder.piaCountText then pcall(holder.piaCountText.Hide, holder.piaCountText) end
end

local function PaintPreviewIcon(holder)
    local db = PowerInfusionAssignmentsDB
    local t = EnsurePIIcon(holder)
    local size = (db and db.iconSize) or 36
    t:SetSize(size, size)
    t:ClearAllPoints()
    local ip, cp, dx, dy = IconAnchorPoints()
    t:SetPoint(ip, holder, cp, dx, dy)
    t:SetAlpha(((db and db.iconAlpha) or 100) / 100)
    t:Show()
    PositionCountText(holder, t)
    if holder.piaCountText and (db and db.iconCountdown) ~= false then
        pcall(holder.piaCountText.SetText, holder.piaCountText, "5")
    end
end

local function HideAllStyles(holder)
    HidePIIcon(holder)
    HideFill(holder)
    HideBorder(holder)
end

-- Draw the selected EXTRA effect on the holder (used by both real + preview).
local function PaintExtraEffect(holder)
    local extra = PowerInfusionAssignmentsDB and PowerInfusionAssignmentsDB.extraEffect
    if extra == "border" then
        pcall(PaintBorder, holder)
    elseif extra == "fill" then
        pcall(PaintFill, holder)
    end
end

-- Preview paint (Test button): extra effect + the PI-icon stand-in on the holder.
-- `holder` here may be a forbidden object, so guard everything.
function PI:PaintGlow(holder)
    if not holder then return end
    pcall(HideAllStyles, holder)
    PaintExtraEffect(holder)
    if PowerInfusionAssignmentsDB.showCdIcon then
        pcall(PaintPreviewIcon, holder)
    end
end

-- ===== Icon on OUR holder texture. =====
-- We can't touch the engine's (forbidden) button icon, so we draw the icon on a
-- texture on our own holder (raised above the cell, so it is visible and fully
-- sizable/anchorable -- the part that always worked). Two modes (db.iconType):
--   "cooldown" -> the ACTUAL spell art. We hand our texture to the button via
--      SetIcon: exactly like SetDurationText writes the (secret) duration into our
--      fontstring, SetIcon draws the (secret) aura icon into our texture, with us
--      never reading it. If SetIcon isn't available/won't bind, we fall back to
--      the Power Infusion icon so there is always a visible cue.
--   "pi"       -> always the Power Infusion icon (unbind any engine icon first).
local function EnsureCdIcon(holder)
    if holder.piaCdIcon then return holder.piaCdIcon end
    local ok, t = pcall(holder.CreateTexture, holder, nil, "OVERLAY")
    if not ok or not t then return nil end
    holder.piaCdIcon = t
    return t
end

local function PaintCooldownIcon(button, holder)
    local db = PowerInfusionAssignmentsDB
    local t = EnsureCdIcon(holder)
    if not t then return nil end
    local size = (db and db.iconSize) or 36
    pcall(t.ClearAllPoints, t)
    local ip, cp, dx, dy = IconAnchorPoints()
    pcall(t.SetPoint, t, ip, holder, cp, dx, dy)
    pcall(t.SetSize, t, size, size)
    pcall(t.SetAlpha, t, ((db and db.iconAlpha) or 100) / 100)
    if db and db.iconType == "pi" then
        -- Always the Power Infusion icon: drop any engine icon binding first so it
        -- doesn't keep drawing the real spell over our texture.
        if button.piaIconBound and button.ClearIcon then
            pcall(button.ClearIcon, button)
            button.piaIconBound = nil
        end
        pcall(t.SetTexture, t, PI_ICON)
    else
        -- The actual spell art via SetIcon (mirrors SetDurationText). Bind once; if
        -- it isn't available, fall back to the PI icon so there is always a cue.
        local bound = false
        if button.SetIcon then
            if not button.piaIconBound then
                button.piaIconBound = pcall(button.SetIcon, button, t) or nil
            end
            bound = button.piaIconBound == true
        end
        if not bound then
            pcall(t.SetTexture, t, PI_ICON)
        end
    end
    pcall(t.Show, t)
    return t
end

local function HideCooldownIcon(button, holder)
    if button and button.piaIconBound and button.ClearIcon then
        pcall(button.ClearIcon, button)
        button.piaIconBound = nil
    end
    if holder.piaCdIcon then pcall(holder.piaCdIcon.Hide, holder.piaCdIcon) end
end

-- Formatter so the engine writes just the number (no "s"/"m" suffix).
local numberFormatter
local function NumberFormatter()
    if numberFormatter ~= nil then return numberFormatter or nil end
    numberFormatter = false
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
        local ok, fmt = pcall(C_StringUtil.CreateNumericRuleFormatter)
        if ok and fmt then
            local down = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
            pcall(fmt.AddBreakpoint, fmt, { threshold = 0, step = 1, rounding = down, format = "%.0f" })
            pcall(fmt.AddBreakpoint, fmt, { threshold = 60, step = 1, rounding = down, format = "%.0f", components = { { div = 60 } } })
            numberFormatter = fmt
        end
    end
    return numberFormatter or nil
end

local function BindCountdown(button, holder)
    local db = PowerInfusionAssignmentsDB
    local want = db.showCdIcon and db.iconCountdown ~= false
    if want and button.SetDurationText and holder.piaCountText then
        if not button.piaCountBound then
            local opts = {}
            local fmt = NumberFormatter()
            if fmt then opts.textFormatter = fmt end
            local ok = pcall(button.SetDurationText, button, holder.piaCountText, opts)
            button.piaCountBound = ok or nil
        end
    elseif button.piaCountBound and button.ClearDurationText then
        pcall(button.ClearDurationText, button)
        button.piaCountBound = nil
    end
end

-- Attach or refresh the alert on an aura button, covering `cell`. Called when the
-- engine first builds the button (initializeFrame; button not yet forbidden) and
-- again out of combat, so style/size/anchor changes take hold.
function PI:DecorateGlowButton(button, cell)
    if not button or Forbidden(button) then return end
    if not cell or Forbidden(cell) then return end
    local db = PowerInfusionAssignmentsDB

    -- Holder (cell-sized) hosts the extra effect + the countdown number. It is our
    -- own frame, so we can draw on it even when the button is forbidden.
    local holder = button.piaHolder
    if not holder then
        local ok
        ok, holder = pcall(CreateFrame, "Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
        if not ok or not holder then
            ok, holder = pcall(CreateFrame, "Frame", nil, button)
        end
        if not ok or not holder then return end
        holder:EnableMouse(false)
        button.piaHolder = holder
    end

    pcall(holder.ClearAllPoints, holder)
    local okTL = pcall(holder.SetPoint, holder, "TOPLEFT", cell, "TOPLEFT")
    local okBR = pcall(holder.SetPoint, holder, "BOTTOMRIGHT", cell, "BOTTOMRIGHT")
    if not (okTL and okBR) then
        pcall(holder.SetPoint, holder, "CENTER", cell, "CENTER")
        pcall(holder.SetSize, holder, 40, 40)
    end
    RaiseAboveCell(holder, cell)

    -- Extra effect (border/fill) frames the whole cell via the holder.
    pcall(HideAllStyles, holder)   -- clears any leftover preview icon too
    PaintExtraEffect(holder)

    -- Cooldown icon on our holder texture (real art via SetIcon, else PI icon).
    if db.showCdIcon then
        local iconTex = PaintCooldownIcon(button, holder)
        PositionCountText(holder, iconTex or holder)   -- number centred on the icon
    else
        HideCooldownIcon(button, holder)
        if holder.piaCountText then pcall(holder.piaCountText.Hide, holder.piaCountText) end
    end

    BindCountdown(button, holder)
end

-- ===== Standalone preview hosts for the Effect TEST preview (no aura engine).
-- Parented to UIParent (never forbidden), pooled so we can preview EVERY watched
-- cell at once. The real notify glow rides the aura button (above). =====
local previewHosts = {}

local function AcquirePreviewHost(i)
    local h = previewHosts[i]
    if h then return h end
    local ok
    ok, h = pcall(CreateFrame, "Frame", nil, UIParent)
    if not ok or not h then return nil end
    h:EnableMouse(false)
    h:SetFrameStrata("HIGH")
    previewHosts[i] = h
    return h
end

function PI:StopCellGlow()
    for i = 1, #previewHosts do
        HideAllStyles(previewHosts[i])
        pcall(previewHosts[i].Hide, previewHosts[i])
    end
end

local function PreviewOne(h, cell)
    pcall(h.ClearAllPoints, h)
    if not pcall(h.SetAllPoints, h, cell) then
        pcall(h.SetPoint, h, "CENTER", cell, "CENTER")
        pcall(h.SetSize, h, 40, 40)
    end
    RaiseAboveCell(h, cell)
    PI:PaintGlow(h)
    pcall(h.Show, h)
end

function PI:StartCellGlow(cell)
    if not cell or Forbidden(cell) then return end
    local h = AcquirePreviewHost(1)
    if h then PreviewOne(h, cell) end
end

function PI:ShowTestGlows(cells)
    local n = 0
    for i = 1, #cells do
        local cell = cells[i]
        if cell and not Forbidden(cell) then
            n = n + 1
            local h = AcquirePreviewHost(n)
            if h then PreviewOne(h, cell) end
        end
    end
    for i = n + 1, #previewHosts do
        HideAllStyles(previewHosts[i])
        pcall(previewHosts[i].Hide, previewHosts[i])
    end
    return n
end

-- Test preview fallback when solo (no raid/party cell): a fixed box on screen.
local testBox
function PI:StartTestBoxGlow()
    if not testBox then
        testBox = CreateFrame("Frame", nil, UIParent)
        testBox:SetSize(90, 44)
        testBox:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end
    PI:StartCellGlow(testBox)
end
