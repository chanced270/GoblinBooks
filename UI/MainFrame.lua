-- Main window: header (scope toggle, export), sidebar navigation, and the active view.
local _, ns = ...
local UI, W, U = ns.UI, ns.Widgets, ns.Util
local T = W.Theme

local TABS = {
    { key = "summary", label = "Summary", create = function(p) return UI.CreateSummary(p) end },
    { key = "charts", label = "Charts", create = function(p) return UI.CreateChartsView(p) end },
    { key = "ah", label = "Auction P/L", create = function(p) return UI.CreateAHTable(p) end },
    { key = "ledger", label = "Ledger", create = function(p) return UI.CreateLedgerList(p) end },
    { key = "prices", label = "AH Prices", create = function(p) return UI.CreatePricesView(p) end },
    { key = "crafting", label = "Crafting", create = function(p) return UI.CreateCraftingView(p) end },
}

local SIDEBAR_W = 168
local frame

local function PaintNav(b)
    local active = frame.current == b.key
    b.indicator:SetShown(active)
    W.SetColor(b.bg, active and T.accent or { 1, 1, 1 }, active and 0.10 or (b.hover and 0.05 or 0))
    if active then
        b.text:SetTextColor(T.text[1], T.text[2], T.text[3])
    elseif b.hover then
        b.text:SetTextColor(T.text[1], T.text[2], T.text[3])
    else
        b.text:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
    end
end

local function NavButton(parent, tab)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(34)
    b.key = tab.key
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.indicator = b:CreateTexture(nil, "ARTWORK")
    b.indicator:SetPoint("TOPLEFT")
    b.indicator:SetPoint("BOTTOMLEFT")
    b.indicator:SetWidth(3)
    W.SetColor(b.indicator, T.accent)
    b.text = W.Text(b, "heading", tab.label)
    b.text:SetPoint("LEFT", 18, 0)
    b:SetScript("OnEnter", function(s) s.hover = true PaintNav(s) end)
    b:SetScript("OnLeave", function(s) s.hover = false PaintNav(s) end)
    b:SetScript("OnClick", function() UI:SelectTab(tab.key) end)
    return b
end

local function Create()
    local s = ns.db.settings
    s.window = s.window or {}
    local f = W.Window("GoblinBooksMainFrame", 880, 540, "GoblinBooks", s.window)
    W.MakeResizable(f, 760, 440)

    -- Header: icon + title on the left, controls on the right.
    local icon = f.header:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\GoblinBooks\\Media\\mark")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 16, 0)
    f.title:ClearAllPoints()
    f.title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    local sub = W.Text(f.header, "mutedSm", "Gold ledger")
    sub:SetPoint("LEFT", f.title, "RIGHT", 10, -1)

    f.exportBtn = W.Button(f.header, "Export CSV", 96, function() UI:ShowExport() end, true)
    f.exportBtn:SetPoint("RIGHT", f.close, "LEFT", -12, 0)

    f.scope = W.Segmented(f.header, {
        { key = "char", label = "Character" },
        { key = "account", label = "Account" },
    }, function(key)
        ns.db.settings.accountView = key == "account"
        UI:Refresh()
    end, 80)
    f.scope:SetPoint("RIGHT", f.exportBtn, "LEFT", -10, 0)

    -- Link to GoblinTrades (gathering, sources, gold per hour) when it's installed.
    if GoblinTradesAPI and GoblinTradesAPI.Open then
        f.tradesBtn = W.Button(f.header, "|TInterface\\Icons\\INV_Pick_02:14:14:0:0:64:64:5:59:5:59|t GoblinTrades", 116,
            function() GoblinTradesAPI.Open() end)
        f.tradesBtn:SetPoint("RIGHT", f.scope, "LEFT", -10, 0)
        f.tradesBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Open GoblinTrades")
            GameTooltip:AddLine("Gathering sessions, item sources and gold per hour.", 0.6, 0.63, 0.68, true)
            GameTooltip:Show()
        end)
        f.tradesBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Sidebar.
    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR_W)
    local sbg = side:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(0, 0, 0, 0.18)
    local sline = W.Divider(side, true)
    sline:SetPoint("TOPRIGHT")
    sline:SetPoint("BOTTOMRIGHT")

    local navLabel = W.Text(side, "label", "VIEWS")
    navLabel:SetPoint("TOPLEFT", 18, -16)

    f.navButtons = {}
    for i, tab in ipairs(TABS) do
        local b = NavButton(side, tab)
        b:SetPoint("TOPLEFT", 0, -34 - (i - 1) * 36)
        b:SetPoint("RIGHT", -1, 0)
        f.navButtons[i] = b
    end

    local goldLabel = W.Text(side, "label", "GOLD ON HAND")
    goldLabel:SetPoint("BOTTOMLEFT", 18, 52)
    f.goldFS = W.Text(side, "large")
    f.goldFS:SetPoint("TOPLEFT", goldLabel, "BOTTOMLEFT", 0, -6)
    f.goldFS:SetPoint("RIGHT", -10, 0)
    f.goldFS:SetJustifyH("LEFT")
    f.goldFS:SetWordWrap(false)
    -- Sold auctions whose gold is on its way to the mailbox.
    f.pendingFS = W.Text(side, "mutedSm")
    f.pendingFS:SetPoint("TOPLEFT", f.goldFS, "BOTTOMLEFT", 0, -5)
    f.pendingFS:SetPoint("RIGHT", -10, 0)
    f.pendingFS:SetJustifyH("LEFT")
    f.pendingFS:SetWordWrap(true)
    local gline = W.Divider(side)
    gline:SetPoint("BOTTOMLEFT", goldLabel, "TOPLEFT", 0, 14)
    gline:SetPoint("RIGHT", -18, 0)

    -- Content area.
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", side, "TOPRIGHT", 18, -18)
    f.content:SetPoint("BOTTOMRIGHT", -18, 18)

    f.views = {}
    f:SetScript("OnShow", function() UI:Refresh() end)
    f:HookScript("OnHide", W.CloseMenu)
    f:Hide()
    return f
end

function UI:SelectTab(key)
    frame.current = key
    for _, b in ipairs(frame.navButtons) do PaintNav(b) end
    for _, tab in ipairs(TABS) do
        local view = frame.views[tab.key]
        if tab.key == key and not view then
            view = tab.create(frame.content)
            view:SetAllPoints()
            frame.views[tab.key] = view
        end
        if view then view:SetShown(tab.key == key) end
    end
    UI:Refresh()
end

function UI:Refresh()
    if not frame or not frame:IsShown() then return end
    frame.scope:SetValue(ns.db.settings.accountView and "account" or "char")
    frame.goldFS:SetText(U.FormatMoney(GetMoney()))
    local pending = ns.AuctionHouse:PendingSales()
    if #pending > 0 then
        local total, nextLeft, inMail = 0, nil, 0
        for _, p in ipairs(pending) do
            total = total + p.amount
            local left = p.eta - time()
            if left <= 0 then inMail = inMail + 1 elseif not nextLeft or left < nextLeft then nextLeft = left end
        end
        local when = nextLeft and ("next in %dm"):format(math.max(1, math.floor(nextLeft / 60))) or "in your mailbox"
        frame.pendingFS:SetText(("+%s from %d sale%s, %s"):format(U.FormatGoldShort(total), #pending,
            #pending == 1 and "" or "s", when))
    else
        frame.pendingFS:SetText("")
    end
    local view = frame.views[frame.current]
    if view and view.Refresh then view:Refresh() end
end

function UI:Toggle()
    if not ns.char then return end
    frame = frame or Create()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        if not frame.current then UI:SelectTab("summary") end
    end
end

-- Debounced refresh while the window is open.
local pending = false
local function QueueRefresh()
    if pending or not frame or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        UI:Refresh()
    end)
end
ns:Register("LEDGER_UPDATED", QueueRefresh)
ns:Register("PRICES_UPDATED", QueueRefresh)
ns:Register("PENDING_SALES", QueueRefresh)
ns:Register("NETWORTH_UPDATED", QueueRefresh)
