-- GoblinTheme: the shared flat, dark look used by GoblinBooks and GoblinUI.
-- Theme colors, fonts, text, buttons, segmented toggles, dropdowns, inputs, checkboxes, cards,
-- windows, and a virtualized multi-column list.
--
-- Embedded library: each addon ships an identical copy and the newest MINOR wins. Edit the copy in
-- GoblinUI/Libs/ and run tools/deploy.ps1, which copies it into GoblinBooks/Libs/.
local MINOR = 4
if GoblinTheme and (GoblinTheme.MINOR or 0) >= MINOR then return end

local W = {}
W.MINOR = MINOR
GoblinTheme = W

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------
local T = {
    bg       = { 0.067, 0.071, 0.086, 0.97 },
    surface  = { 0.094, 0.100, 0.122, 1 },
    card     = { 1, 1, 1, 0.035 },
    border   = { 1, 1, 1, 0.07 },
    text     = { 0.92, 0.93, 0.95 },
    muted    = { 0.55, 0.58, 0.64 },
    accent   = { 1, 0.78, 0.25 },
    onAccent = { 0.08, 0.07, 0.05 },
    hover    = { 1, 1, 1, 0.06 },
}
W.Theme = T

local FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
W.FLAT = FLAT

local BODY_FONT, TITLE_FONT = "Fonts\\ARIALN.TTF", "Fonts\\FRIZQT__.TTF"

local function MakeFont(name, file, size, color)
    -- Reuse the font object if another copy of the library already made it.
    local fo = _G[name] or CreateFont(name)
    fo:SetFont(file, size, "")
    fo:SetTextColor(color[1], color[2], color[3])
    fo:SetShadowColor(0, 0, 0, 0.6)
    fo:SetShadowOffset(1, -1)
    return name
end

local F = {
    title   = MakeFont("GoblinThemeFontTitle", TITLE_FONT, 14, T.accent),
    heading = MakeFont("GoblinThemeFontHeading", BODY_FONT, 14, T.text),
    body    = MakeFont("GoblinThemeFontBody", BODY_FONT, 13, T.text),
    large   = MakeFont("GoblinThemeFontLarge", BODY_FONT, 14, T.text),
    value   = MakeFont("GoblinThemeFontValue", BODY_FONT, 20, T.text),
    label   = MakeFont("GoblinThemeFontLabel", BODY_FONT, 11, T.muted),
    muted   = MakeFont("GoblinThemeFontMuted", BODY_FONT, 13, T.muted),
    mutedSm = MakeFont("GoblinThemeFontMutedSmall", BODY_FONT, 11, T.muted),
    accent  = MakeFont("GoblinThemeFontAccent", BODY_FONT, 13, T.accent),
    dark    = MakeFont("GoblinThemeFontDark", BODY_FONT, 13, T.onAccent),
    close   = MakeFont("GoblinThemeFontClose", BODY_FONT, 20, T.muted),
}
W.Fonts = F

-- Legacy Blizzard template names used by the views map onto theme fonts.
local FONT_MAP = {
    GameFontHighlightSmall = F.body,
    GameFontNormalSmall    = F.label,
    GameFontNormal         = F.heading,
    GameFontHighlight      = F.large,
    GameFontHighlightLarge = F.value,
    GameFontDisable        = F.muted,
    GameFontDisableSmall   = F.mutedSm,
}

local function SetColor(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1) end
local function Backdrop(f, bg, border)
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end
W.SetColor, W.Backdrop = SetColor, Backdrop

function W.Text(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", FONT_MAP[font] or F[font] or font or F.body)
    if text then fs:SetText(text) end
    return fs
end

function W.Panel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop(FLAT)
    Backdrop(f, T.card, T.border)
    return f
end

function W.Divider(parent, vertical)
    local t = parent:CreateTexture(nil, "BORDER")
    SetColor(t, T.border)
    if vertical then t:SetWidth(1) else t:SetHeight(1) end
    return t
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function PaintButton(b)
    if not b:IsEnabled() then
        Backdrop(b, { 1, 1, 1, 0.02 }, { 1, 1, 1, 0.04 })
    elseif b.primary then
        Backdrop(b, { T.accent[1], T.accent[2], T.accent[3], b.hover and 0.28 or 0.16 },
            { T.accent[1], T.accent[2], T.accent[3], 0.55 })
    else
        Backdrop(b, { 1, 1, 1, b.hover and 0.10 or 0.05 }, { 1, 1, 1, b.hover and 0.16 or 0.09 })
    end
end

function W.Button(parent, text, width, onClick, primary)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 90, 24)
    b:SetBackdrop(FLAT)
    b.primary = primary
    b:SetNormalFontObject(primary and F.accent or F.body)
    b:SetHighlightFontObject(primary and F.accent or F.body)
    b:SetDisabledFontObject(F.muted)
    b:SetText(text)
    b:SetScript("OnEnter", function(s) s.hover = true PaintButton(s) end)
    b:SetScript("OnLeave", function(s) s.hover = false PaintButton(s) end)
    b:HookScript("OnEnable", PaintButton)
    b:HookScript("OnDisable", PaintButton)
    if onClick then b:SetScript("OnClick", onClick) end
    PaintButton(b)
    return b
end

function W.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    SetColor(b.bg, { 1, 0.3, 0.3 }, 0)
    b.x = W.Text(b, "close", "\195\151") -- U+00D7 multiplication sign
    b.x:SetPoint("CENTER", 0, 1)
    b:SetScript("OnEnter", function(s)
        SetColor(s.bg, { 1, 0.3, 0.3 }, 0.25)
        s.x:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function(s)
        SetColor(s.bg, { 1, 0.3, 0.3 }, 0)
        s.x:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
    end)
    b:SetScript("OnClick", onClick)
    return b
end

---------------------------------------------------------------------------
-- Segmented control: options = { { key, label } }; onSelect(key). segW is each segment's minimum width;
-- a segment grows to fit its label. SetLabel(key, text) changes a label (e.g. to add a count) and re-fits.
---------------------------------------------------------------------------
function W.Segmented(parent, options, onSelect, segW)
    segW = segW or 70
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop(FLAT)
    Backdrop(f, { 0, 0, 0, 0.25 }, T.border)
    f:SetSize(#options * segW + 4, 26)
    f.buttons = {}

    local function Paint(b)
        local on = f.value == b.key
        SetColor(b.bg, T.accent, on and 0.9 or (b.hover and 0.08 or 0))
        if on then
            b.text:SetTextColor(T.onAccent[1], T.onAccent[2], T.onAccent[3])
        elseif b.hover then
            b.text:SetTextColor(T.text[1], T.text[2], T.text[3])
        else
            b.text:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
        end
    end

    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(segW, 22)
        b:SetPoint("TOPLEFT", 2 + (i - 1) * segW, -2)
        b.key = opt.key
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.text = W.Text(b, "body", opt.label)
        b.text:SetPoint("CENTER")
        b:SetScript("OnEnter", function(s) s.hover = true Paint(s) end)
        b:SetScript("OnLeave", function(s) s.hover = false Paint(s) end)
        b:SetScript("OnClick", function()
            if f.value == opt.key then return end
            f:SetValue(opt.key)
            if onSelect then onSelect(opt.key) end
        end)
        f.buttons[i] = b
    end

    function f:SetValue(key)
        self.value = key
        for _, b in ipairs(self.buttons) do Paint(b) end
    end

    --- Sizes each segment to fit its label (at least segW) and the control to fit them all.
    function f:Layout()
        local x = 2
        for _, b in ipairs(self.buttons) do
            local w = math.max(segW, math.ceil(b.text:GetStringWidth()) + 18)
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -2)
            x = x + w
        end
        self:SetWidth(x + 2)
    end

    function f:SetLabel(key, text)
        for _, b in ipairs(self.buttons) do
            if b.key == key then b.text:SetText(text) end
        end
        self:Layout()
    end

    f:Layout()
    f:SetValue(nil)
    return f
end

---------------------------------------------------------------------------
-- Dropdown: SetOptions({ { key, label, color? } }), SetValue(key); onSelect(key)
---------------------------------------------------------------------------
local menu, blocker
local function CloseMenu()
    if menu then menu:Hide() end
    if blocker then blocker:Hide() end
end
W.CloseMenu = CloseMenu

local function OpenMenu(owner)
    if not menu then
        blocker = CreateFrame("Button", nil, UIParent)
        blocker:SetAllPoints(UIParent)
        blocker:SetFrameStrata("FULLSCREEN_DIALOG")
        blocker:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(blocker:GetFrameLevel() + 10)
        menu:EnableMouse(true)
        menu:SetBackdrop(FLAT)
        Backdrop(menu, T.surface, { 1, 1, 1, 0.14 })
        menu.items = {}
    end
    local opts = owner.options or {}
    for i, opt in ipairs(opts) do
        local item = menu.items[i]
        if not item then
            item = CreateFrame("Button", nil, menu)
            item:SetHeight(22)
            item.hl = item:CreateTexture(nil, "HIGHLIGHT")
            item.hl:SetAllPoints()
            SetColor(item.hl, T.hover)
            item.swatch = item:CreateTexture(nil, "ARTWORK")
            item.swatch:SetSize(8, 8)
            item.swatch:SetPoint("LEFT", 10, 0)
            item.text = W.Text(item, "body")
            item.text:SetPoint("LEFT", 24, 0)
            item.text:SetPoint("RIGHT", -8, 0)
            item.text:SetWordWrap(false) -- one line per item; the menu widens to fit instead
            item.text:SetJustifyH("LEFT")
            menu.items[i] = item
        end
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", 1, -4 - (i - 1) * 22)
        item:SetPoint("RIGHT", -1, 0)
        SetColor(item.swatch, opt.color or T.muted, opt.color and 1 or 0.4)
        item.text:SetText(opt.label)
        if opt.key == owner.value then
            item.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        else
            item.text:SetTextColor(T.text[1], T.text[2], T.text[3])
        end
        item:SetScript("OnClick", function()
            CloseMenu()
            owner:SetValue(opt.key)
            if owner.onSelect then owner.onSelect(opt.key) end
        end)
        item:Show()
    end
    for i = #opts + 1, #menu.items do menu.items[i]:Hide() end
    -- Wide enough for the longest label (swatch + padding), and kept on screen.
    local widest = 0
    for i = 1, #opts do widest = math.max(widest, menu.items[i].text:GetStringWidth()) end
    local width = math.max(owner:GetWidth(), 160, math.ceil(widest) + 24 + 14)
    menu:SetSize(width, #opts * 22 + 8)
    menu:SetClampedToScreen(true)
    menu:ClearAllPoints()
    -- Open toward the side with room: right-aligned when the owner is in the right half of the screen.
    local right = owner:GetRight()
    if right and right > UIParent:GetWidth() / 2 then
        menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    else
        menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    end
    blocker:Show()
    menu:Show()
end

function W.Dropdown(parent, width, onSelect)
    local d = W.Button(parent, "", width)
    d.onSelect = onSelect
    d.label = W.Text(d, "body")
    d.label:SetPoint("LEFT", 10, 0)
    d.label:SetPoint("RIGHT", -22, 0)
    d.label:SetJustifyH("LEFT")
    d.label:SetWordWrap(false)
    d.arrow = d:CreateTexture(nil, "ARTWORK")
    d.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    d.arrow:SetSize(12, 12)
    d.arrow:SetPoint("RIGHT", -8, -2)
    d.arrow:SetVertexColor(T.muted[1], T.muted[2], T.muted[3])
    d:SetScript("OnClick", function(self)
        if menu and menu:IsShown() then CloseMenu() else OpenMenu(self) end
    end)
    d:HookScript("OnHide", CloseMenu)

    function d:SetOptions(opts) self.options = opts end
    function d:SetValue(key)
        self.value = key
        for _, o in ipairs(self.options or {}) do
            if o.key == key then self.label:SetText((self.prefix or "") .. o.label) end
        end
    end
    return d
end

---------------------------------------------------------------------------
-- Text input (placeholder optional)
---------------------------------------------------------------------------
local function PaintEdit(e)
    local focus = e:HasFocus()
    Backdrop(e, { 0, 0, 0, 0.35 }, focus and { T.accent[1], T.accent[2], T.accent[3], 0.7 } or { 1, 1, 1, 0.14 })
    if e.placeholder then e.placeholder:SetShown(not focus and e:GetText() == "") end
end

function W.EditBox(parent, width, numeric, placeholder)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width or 120, 24)
    e:SetBackdrop(FLAT)
    e:SetFontObject(F.body)
    e:SetTextInsets(8, 8, 0, 0)
    e:SetAutoFocus(false)
    if numeric then e:SetNumeric(true) end
    if placeholder then
        e.placeholder = W.Text(e, "muted", placeholder)
        e.placeholder:SetPoint("LEFT", 8, 0)
    end
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEditFocusGained", function(s) s:HighlightText() PaintEdit(s) end)
    e:SetScript("OnEditFocusLost", function(s) s:HighlightText(0, 0) PaintEdit(s) end)
    e:HookScript("OnTextChanged", PaintEdit)
    PaintEdit(e)
    return e
end

--- Gold / silver / copper input. GetValue() -> copper; SetValue(copper); onChange(copper) on user edits.
function W.MoneyInput(parent, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(200, 24)
    local coins = {
        { w = 84, icon = "Interface\\MoneyFrame\\UI-GoldIcon", max = 7 },
        { w = 38, icon = "Interface\\MoneyFrame\\UI-SilverIcon", max = 2 },
        { w = 38, icon = "Interface\\MoneyFrame\\UI-CopperIcon", max = 2 },
    }
    f.boxes = {}
    local prev
    for i, c in ipairs(coins) do
        local e = W.EditBox(f, c.w, true)
        e:SetMaxLetters(c.max)
        e:SetJustifyH("RIGHT")
        e:SetTextInsets(4, 6, 0, 0)
        if prev then e:SetPoint("LEFT", prev, "RIGHT", 18, 0) else e:SetPoint("LEFT") end
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(c.icon)
        icon:SetSize(13, 13)
        icon:SetPoint("LEFT", e, "RIGHT", 3, 0)
        e:HookScript("OnTextChanged", function(_, user)
            if user and onChange then onChange(f:GetValue()) end
        end)
        e:SetScript("OnTabPressed", function()
            local nextBox = f.boxes[i % #coins + 1]
            nextBox:SetFocus()
        end)
        f.boxes[i] = e
        prev = e
    end
    function f:GetValue()
        local g = tonumber(self.boxes[1]:GetText()) or 0
        local s = tonumber(self.boxes[2]:GetText()) or 0
        local c = tonumber(self.boxes[3]:GetText()) or 0
        return g * 10000 + s * 100 + c
    end
    function f:SetValue(copper)
        copper = math.max(0, math.floor((copper or 0) + 0.5))
        local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
        self.boxes[1]:SetText(g > 0 and tostring(g) or "")
        self.boxes[2]:SetText(s > 0 and tostring(s) or "")
        self.boxes[3]:SetText(c > 0 and tostring(c) or "")
    end
    return f
end

---------------------------------------------------------------------------
-- Checkbox
---------------------------------------------------------------------------
function W.Check(parent, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(16, 16)
    cb:SetBackdrop(FLAT)
    Backdrop(cb, { 0, 0, 0, 0.3 }, { 1, 1, 1, 0.22 })
    local tick = cb:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)
    SetColor(tick, T.accent)
    cb:SetCheckedTexture(tick)
    local fs = W.Text(cb, "body", label)
    fs:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.label = fs
    cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 10), -4, -4)
    cb:SetScript("OnEnter", function(s) Backdrop(s, { 0, 0, 0, 0.3 }, { T.accent[1], T.accent[2], T.accent[3], 0.7 }) end)
    cb:SetScript("OnLeave", function(s) Backdrop(s, { 0, 0, 0, 0.3 }, { 1, 1, 1, 0.22 }) end)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked()) end)
    return cb
end

---------------------------------------------------------------------------
-- Window: flat frame with a draggable header and close button.
-- state (optional) = table to persist { x, y, w, h } into.
---------------------------------------------------------------------------
function W.Window(name, width, height, title, state)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    -- LOW strata keeps action bars (MEDIUM) drawn above the window, so spells can still be dragged onto them.
    f:SetFrameStrata("LOW")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:SetBackdrop(FLAT)
    Backdrop(f, T.bg, { 1, 1, 1, 0.10 })
    tinsert(UISpecialFrames, name)

    local shadow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetColorTexture(0, 0, 0, 0.3)
    shadow:SetPoint("TOPLEFT", -6, 6)
    shadow:SetPoint("BOTTOMRIGHT", 6, -6)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(46)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    SetColor(hbg, T.surface)
    local line = W.Divider(header)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    f.header = header

    local function SaveState()
        if not state then return end
        state.x, state.y = f:GetLeft(), f:GetTop()
        state.w, state.h = f:GetWidth(), f:GetHeight()
    end
    f.SaveState = SaveState

    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SaveState()
    end)

    f.title = W.Text(header, "title", title)
    f.title:SetPoint("LEFT", 16, 0)

    f.close = W.CloseButton(header, function() f:Hide() end)
    f.close:SetPoint("RIGHT", -10, 0)

    if state and state.x then
        f:SetSize(state.w or width, state.h or height)
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", state.x, state.y)
    else
        f:SetPoint("TOP", 0, -90) -- upper part of the screen, clear of the action bars
    end
    return f
end

--- Adds a bottom-right resize grip to a window.
function W.MakeResizable(f, minW, minH)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(minW, minH) elseif f.SetMinResize then f:SetMinResize(minW, minH) end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetAlpha(0.6)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if f.SaveState then f.SaveState() end
    end)
    return grip
end

---------------------------------------------------------------------------
-- Virtual list
-- columns = { { title, width? (nil = flexible), align?, get(item) -> text, r?, g?, b?, sortValue?(item) } }
---------------------------------------------------------------------------
local ListMixin = {}
local SCROLLBAR_W = 6
local HEADER_H = 24

function ListMixin:Layout()
    local width = self:GetWidth() - SCROLLBAR_W - 8
    if width <= 0 then return end
    local fixed, flex = 0, 0
    for _, col in ipairs(self.columns) do
        if col.width then fixed = fixed + col.width else flex = flex + 1 end
    end
    local flexW = flex > 0 and math.max(40, (width - fixed - 8 * #self.columns) / flex) or 0
    self.colX, self.colW = {}, {}
    local x = 8
    for i, col in ipairs(self.columns) do
        local w = col.width or flexW
        self.colX[i], self.colW[i] = x, w
        local h = self.headers[i]
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", self.header, "TOPLEFT", x, 0)
        h:SetSize(w, HEADER_H)
        x = x + w + 8
    end

    local bodyH = self:GetHeight() - HEADER_H - 2
    local count = math.max(0, math.floor(bodyH / self.rowHeight))
    for i = 1, count do
        local row = self.rows[i] or self:CreateRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -2 - (i - 1) * self.rowHeight)
        row:SetPoint("RIGHT", self, "RIGHT", -SCROLLBAR_W - 4, 0)
        row:SetHeight(self.rowHeight)
        for c, cell in ipairs(row.cells) do
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", self.colX[c], 0)
            cell:SetWidth(self.colW[c])
        end
    end
    for i = count + 1, #self.rows do self.rows[i]:Hide() end
    self.numRows = count
    self:Refresh()
end

function ListMixin:CreateRow(i)
    local row = CreateFrame("Button", nil, self)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    SetColor(hl, T.accent, 0.08)
    row.sel = row:CreateTexture(nil, "BORDER")
    row.sel:SetAllPoints()
    SetColor(row.sel, T.accent, 0.16)
    row.sel:Hide()
    row.cells = {}
    for c, col in ipairs(self.columns) do
        local cell = W.Text(row, "body")
        cell:SetJustifyH(col.align or "LEFT")
        cell:SetWordWrap(false)
        row.cells[c] = cell
    end
    local list = self
    row:SetScript("OnEnter", function(r)
        if r.item and list.onEnter then list.onEnter(r, r.item) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(r)
        if r.item and list.onClick then
            list.onClick(r.item)
            list:Refresh()
        end
    end)
    self.rows[i] = row
    return row
end

function ListMixin:UpdateHeaders()
    for i, col in ipairs(self.columns) do
        local fs = self.headers[i].text
        local title = col.title:upper()
        if self.sortCol == i then
            fs:SetText(title .. (self.sortDesc and "  v" or "  ^"))
            fs:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        else
            fs:SetText(title)
            fs:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
        end
    end
end

function ListMixin:Refresh()
    local n = #self.data
    local maxOffset = math.max(0, n - (self.numRows or 0))
    if self.offset > maxOffset then self.offset = maxOffset end
    for i = 1, self.numRows or 0 do
        local row = self.rows[i]
        local item = self.data[self.offset + i]
        row.item = item
        if item then
            for c, col in ipairs(self.columns) do
                local text, r, g, b = col.get(item)
                row.cells[c]:SetText(text or "")
                row.cells[c]:SetTextColor(r or T.text[1], g or T.text[2], b or T.text[3])
            end
            row.sel:SetShown(self.isSelected and self.isSelected(item) or false)
            row:Show()
        else
            row:Hide()
        end
    end
    self.updatingBar = true
    self.bar:SetMinMaxValues(0, maxOffset)
    self.bar:SetValue(self.offset)
    self.bar:SetShown(maxOffset > 0)
    self.updatingBar = false
    if self.empty then self.empty:SetShown(n == 0) end
    self:UpdateHeaders()
end

function ListMixin:SetOffset(v)
    local maxOffset = math.max(0, #self.data - (self.numRows or 0))
    v = math.max(0, math.min(maxOffset, math.floor(v + 0.5)))
    if v ~= self.offset then
        self.offset = v
        self:Refresh()
    end
end

function ListMixin:Sort()
    local col = self.sortCol and self.columns[self.sortCol]
    if not col or not col.sortValue then return end
    local desc = self.sortDesc
    -- Each row's sort value once (sortValue can be costly, e.g. a price lookup), not once per comparison.
    local keys = {}
    for _, item in ipairs(self.data) do keys[item] = col.sortValue(item) end
    table.sort(self.data, function(a, b)
        local va, vb = keys[a], keys[b]
        if va == vb then return false end
        if desc then return va > vb end
        return va < vb
    end)
end

function ListMixin:SetData(data)
    self.data = data or {}
    self:Sort()
    self:Refresh()
end

function W.List(parent, columns, rowHeight)
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    list:SetBackdrop(FLAT)
    Backdrop(list, T.card, T.border)
    Mixin(list, ListMixin)
    list.columns, list.rowHeight = columns, rowHeight or 20
    list.data, list.rows, list.headers, list.offset = {}, {}, {}, 0

    local header = CreateFrame("Frame", nil, list)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -SCROLLBAR_W - 4, -1)
    header:SetHeight(HEADER_H)
    local sep = W.Divider(header)
    sep:SetPoint("BOTTOMLEFT")
    sep:SetPoint("BOTTOMRIGHT")
    list.header = header

    for i, col in ipairs(columns) do
        local h = CreateFrame("Button", nil, header)
        local fs = W.Text(h, "label", col.title:upper())
        fs:SetAllPoints()
        fs:SetJustifyH(col.align or "LEFT")
        h.text = fs
        if col.sortValue then
            h:SetScript("OnClick", function()
                if list.sortCol == i then list.sortDesc = not list.sortDesc else list.sortCol, list.sortDesc = i, true end
                list:Sort()
                list:Refresh()
            end)
            h:SetScript("OnEnter", function() if list.sortCol ~= i then fs:SetTextColor(T.text[1], T.text[2], T.text[3]) end end)
            h:SetScript("OnLeave", function() list:UpdateHeaders() end)
        end
        list.headers[i] = h
    end

    local bar = CreateFrame("Slider", nil, list)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLLBAR_W)
    bar:SetPoint("TOPRIGHT", -3, -HEADER_H - 4)
    bar:SetPoint("BOTTOMRIGHT", -3, 3)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.04)
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = bar:GetThumbTexture()
    thumb:SetVertexColor(1, 1, 1, 0.22)
    thumb:SetSize(SCROLLBAR_W, 36)
    bar:SetScript("OnEnter", function() thumb:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.7) end)
    bar:SetScript("OnLeave", function() thumb:SetVertexColor(1, 1, 1, 0.22) end)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetScript("OnValueChanged", function(_, v)
        if not list.updatingBar then list:SetOffset(v) end
    end)
    list.bar = bar

    local empty = W.Text(list, "muted", "No data yet")
    empty:SetPoint("CENTER")
    list.empty = empty

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, d) self:SetOffset(self.offset - d * 3) end)
    -- BackdropTemplate owns OnSizeChanged; hook instead of replacing it.
    list:HookScript("OnSizeChanged", function(self) self:Layout() end)
    return list
end
