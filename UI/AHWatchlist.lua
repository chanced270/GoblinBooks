-- AH panel "Watchlist" page: your watched items with your price limit, the usual price and the lowest price
-- seen (green when it's at or under your limit). Select one to set a max price or a share of usual, remove
-- it, or open it on the Buy tab. Items are added with Watch on the Buy tab.
local _, ns = ...
local UI, W, U, P = ns.UI, ns.Widgets, ns.Util, ns.Prices
local T = W.Theme

local GREEN = { 0.38, 1, 0.38 }

local function Name(id) return U.ItemName(id) or ns.Watchlist.Watch()[id] and ns.Watchlist.Watch()[id].n or ("item:" .. id) end
local Icon = U.ItemIcon

function UI.CreateAHWatchlist(parent, setStatus, openItem)
    local WL = ns.Watchlist
    local f = CreateFrame("Frame", nil, parent)

    f.countFS = W.Text(f, "mutedSm", "")
    f.countFS:SetPoint("TOPLEFT", 2, -6)
    f.countFS:SetPoint("RIGHT")
    f.countFS:SetJustifyH("LEFT")
    f.countFS:SetWordWrap(false)

    local function Lowest(id)
        local e = P.Get(id)
        return e and e.p, e and e.t
    end

    local list = W.List(f, {
        { title = "Item", get = function(id) return Icon(id) .. Name(id) end, sortValue = function(id) return Name(id):lower() end },
        { title = "Limit", width = 96, align = "RIGHT", get = function(id)
            local thr, how, pct = WL.Threshold(id)
            if not thr then return "no price yet", T.muted[1], T.muted[2], T.muted[3] end
            if how == "max" then return U.FormatGoldShort(thr) .. " max" end
            return ("%s (%d%%)"):format(U.FormatGoldShort(thr), math.floor(pct * 100 + 0.5))
        end, sortValue = function(id) return WL.Threshold(id) or math.huge end },
        { title = "Usual", width = 58, align = "RIGHT", get = function(id)
            local u = WL.Usual(id)
            return u and U.FormatGoldShort(u) or "-", T.muted[1], T.muted[2], T.muted[3]
        end, sortValue = function(id) return WL.Usual(id) or math.huge end },
        { title = "Lowest", width = 62, align = "RIGHT", get = function(id)
            local low = Lowest(id)
            if not low then return "-", T.muted[1], T.muted[2], T.muted[3] end
            local thr = WL.Threshold(id)
            if thr and low <= thr then return U.FormatGoldShort(low), GREEN[1], GREEN[2], GREEN[3] end
            return U.FormatGoldShort(low)
        end, sortValue = function(id) return Lowest(id) or math.huge end },
    }, 20)
    list:SetPoint("TOPLEFT", 0, -26)
    list:SetPoint("BOTTOMRIGHT", 0, 44)
    list.empty:SetText("Nothing watched. On the Buy tab, select an item and click Watch.")
    list.onClick = function(id)
        f.sel = id
        local w = WL.Watch()[id]
        f.maxInput:SetValue(w and w.max or 0)
        f.pctBox:SetText(w and w.pct and tostring(math.floor(w.pct * 100 + 0.5)) or "")
        f:UpdateButtons()
    end
    list.isSelected = function(id) return id == f.sel end
    list.onEnter = function(row, id)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetItemByID, GameTooltip, id)
        local low, t = Lowest(id)
        local thr = WL.Threshold(id)
        GameTooltip:AddLine(" ")
        if low then GameTooltip:AddDoubleLine("Lowest seen", ("%s  |cff8c94a3%s|r"):format(U.FormatMoney(low), U.Ago(t)), 1, 0.82, 0, 1, 1, 1) end
        if thr then GameTooltip:AddDoubleLine("Your limit", U.FormatMoney(thr), 1, 0.82, 0, 1, 1, 1) end
        GameTooltip:AddLine("Prices come from your scans and searches. Click to edit the limit, or open it on the Buy tab.",
            0.55, 0.58, 0.64, true)
        GameTooltip:Show()
    end
    f.list = list

    -- Edit row: max price or %, Save, Remove, Open on Buy tab.
    local edit = CreateFrame("Frame", nil, f)
    edit:SetPoint("BOTTOMLEFT")
    edit:SetPoint("BOTTOMRIGHT")
    edit:SetHeight(34)
    local maxLabel = W.Text(edit, "label", "MAX")
    maxLabel:SetPoint("LEFT", 0, 0)
    f.maxInput = W.MoneyInput(edit)
    f.maxInput:SetPoint("LEFT", maxLabel, "RIGHT", 6, 0)
    local orLabel = W.Text(edit, "label", "OR %")
    orLabel:SetPoint("LEFT", f.maxInput, "RIGHT", 14, 0)
    f.pctBox = W.EditBox(edit, 40, true)
    f.pctBox:SetMaxLetters(2)
    f.pctBox:SetPoint("LEFT", orLabel, "RIGHT", 6, 0)
    f.openBtn = W.Button(edit, "Buy tab", 64, function()
        if f.sel and openItem then openItem(f.sel) end
    end)
    f.openBtn:SetPoint("RIGHT")
    f.removeBtn = W.Button(edit, "Remove", 64, function()
        if not f.sel then return end
        setStatus(("No longer watching %s."):format(Name(f.sel)))
        WL.RemoveWatch(f.sel)
        f.sel = nil
        f:Refresh()
    end)
    f.removeBtn:SetPoint("RIGHT", f.openBtn, "LEFT", -6, 0)
    f.saveBtn = W.Button(edit, "Save", 56, function()
        local id = f.sel
        if not id then return end
        WL.AddWatch(id)
        local w = WL.Watch()[id]
        local max = f.maxInput:GetValue()
        local pct = tonumber(f.pctBox:GetText())
        w.max = max > 0 and max or nil
        w.pct = pct and pct > 0 and pct / 100 or nil
        setStatus(("Watching %s: %s"):format(Name(id), w.max and ("max " .. U.FormatMoney(w.max))
            or ("%d%% of usual"):format(math.floor((w.pct or ns.db.settings.dealsPct or 0.7) * 100 + 0.5))))
        f:Refresh()
    end, true)
    f.saveBtn:SetPoint("RIGHT", f.removeBtn, "LEFT", -6, 0)

    function f:UpdateButtons()
        local id = self.sel
        self.saveBtn:SetEnabled(id ~= nil)
        self.removeBtn:SetEnabled(id ~= nil and WL.IsWatched(id))
        self.openBtn:SetEnabled(id ~= nil)
    end

    function f:Refresh()
        local items = WL.Items()
        if self.sel and not WL.IsWatched(self.sel) then self.sel = nil end
        list:SetData(items)
        local under = 0
        for _, id in ipairs(items) do
            local low, thr = Lowest(id), WL.Threshold(id)
            if low and thr and low <= thr then under = under + 1 end
        end
        self.countFS:SetText(#items == 0 and "" or ("%d watched%s   |cff8c94a3lowest prices from your last Scan or search|r"):format(
            #items, under > 0 and ("   |cff60ff60%d at or under your limit|r"):format(under) or ""))
        self:UpdateButtons()
    end

    ns:Register("WATCHLIST_UPDATED", function() if f:IsVisible() then f:Refresh() end end)
    ns:Register("PRICES_UPDATED", function() if f:IsVisible() then list:Refresh() end end)
    f:SetScript("OnShow", function(self) self:Refresh() end)
    return f
end
