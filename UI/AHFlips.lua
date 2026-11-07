-- AH panel "Flips" page: items whose current lowest price is well below their usual daily low, so buying
-- now and relisting near the usual price should clear a profit after the AH cut. Clicking one opens it on
-- the Buy tab with live listings. Everything here comes from saved price history: an estimate, not advice.
local _, ns = ...
local UI, W, U, P, CB, S = ns.UI, ns.Widgets, ns.Util, ns.Prices, ns.CostBasis, ns.AHScan
local T = W.Theme

local MARGINS = { { key = 0.1, label = "10%" }, { key = 0.2, label = "20%" }, { key = 0.35, label = "35%" }, { key = 0.5, label = "50%" } }
local MAX_AGE = 3 * 3600 -- only prices seen in the last 3 hours count as "current"
local MIN_PROFIT = 100   -- at least 1s per item after the cut
local GREEN = { 0.38, 1, 0.38 }

local function Name(r)
    if not r.name then r.name = r.e.n or U.ItemName(r.id) end
    return r.name or ("item:" .. r.id)
end

function UI.CreateAHFlips(parent, setStatus, openItem)
    local f = CreateFrame("Frame", nil, parent)
    f.minMargin = 0.2

    -- Filters: name and AH category. They only narrow the list below (no server requests).
    -- The category choice is kept between sessions, by label: ns.db.flipsFilter = { cat?, sub? }
    f.search = W.EditBox(f, 180, false, "Filter by name...")
    f.search:SetPoint("TOPLEFT")
    f.search:HookScript("OnTextChanged", function() if f.list then f:ApplyFilter() end end)
    local cats = S.CategoryTree()
    local catOpts = { { key = "all", label = "All categories" } }
    for i, c in ipairs(cats) do catOpts[#catOpts + 1] = { key = i, label = c.label } end
    local function SaveFilter()
        ns.db.flipsFilter = { cat = f.cat and f.cat.label, sub = f.sub and f.sub.label }
    end
    f.catDrop = W.Dropdown(f, 130, function(key)
        f.cat, f.sub = cats[key], nil
        f:UpdateSubOptions()
        SaveFilter()
        f:ApplyFilter()
    end)
    f.catDrop:SetOptions(catOpts)
    f.catDrop:SetPoint("LEFT", f.search, "RIGHT", 6, 0)
    f.subDrop = W.Dropdown(f, 130, function(key)
        f.sub = f.cat and f.cat.subs[key] or nil
        SaveFilter()
        f:ApplyFilter()
    end)
    f.subDrop:SetPoint("LEFT", f.catDrop, "RIGHT", 6, 0)
    function f:UpdateSubOptions()
        local opts = { { key = "all", label = self.cat and "All subcategories" or "Subcategory" } }
        local value = "all"
        for i, sc in ipairs(self.cat and self.cat.subs or {}) do
            opts[#opts + 1] = { key = i, label = sc.label }
            if sc == self.sub then value = i end
        end
        self.subDrop:SetOptions(opts)
        self.subDrop:SetValue(value)
        self.subDrop:SetEnabled(#opts > 1)
    end
    -- Restore the saved category (labels can disappear if the game's list changes: then it's "all").
    local saved = ns.db.flipsFilter or {}
    local catValue = "all"
    for i, c in ipairs(cats) do
        if c.label == saved.cat then
            f.cat, catValue = c, i
            for _, sc in ipairs(c.subs) do if sc.label == saved.sub then f.sub = sc end end
        end
    end
    f.catDrop:SetValue(catValue)
    f:UpdateSubOptions()

    local label = W.Text(f, "label", "MIN MARGIN")
    label:SetPoint("TOPLEFT", 0, -39)
    f.marginSeg = W.Segmented(f, MARGINS, function(v)
        f.minMargin = v
        f:Refresh()
    end, 46)
    f.marginSeg:SetPoint("LEFT", label, "RIGHT", 8, 0)
    f.marginSeg:SetValue(f.minMargin)
    f.countFS = W.Text(f, "mutedSm")
    f.countFS:SetPoint("LEFT", f.marginSeg, "RIGHT", 12, 0)
    f.countFS:SetPoint("RIGHT")
    f.countFS:SetJustifyH("LEFT")
    f.countFS:SetWordWrap(false)

    local list = W.List(f, {
        { title = "Item", get = function(r)
            return U.ItemIcon(r.id) .. (P.IsFavorite(r.id) and (P.FAV_ICON .. " ") or "") .. Name(r)
        end, sortValue = function(r) return Name(r):lower() end },
        { title = "Now", width = 60, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.now) end,
          sortValue = function(r) return r.now end },
        { title = "Usual", width = 60, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.usual) end,
          sortValue = function(r) return r.usual end },
        { title = "Profit/ea", width = 66, align = "RIGHT", get = function(r)
            return U.FormatGoldShort(r.profit), GREEN[1], GREEN[2], GREEN[3]
        end, sortValue = function(r) return r.profit end },
        { title = "Margin", width = 52, align = "RIGHT", get = function(r) return ("%.0f%%"):format(r.margin * 100) end,
          sortValue = function(r) return r.margin end },
        -- ESTIMATE of demand: units leaving the AH per day (includes expirations/cancellations).
        { title = "Est./day", width = 62, align = "RIGHT", get = function(r)
            local v = U.PerDay(r.est)
            return v or "-", T.muted[1], T.muted[2], T.muted[3]
        end, sortValue = function(r) return r.est or -1 end },
    }, 20)
    list:SetPoint("TOPLEFT", 0, -66)
    list:SetPoint("BOTTOMRIGHT", 0, 40)
    list.sortCol, list.sortDesc = 4, true
    list.empty:SetText("No flips right now. Prices need a few days of history and a recent Scan or search.")
    list.onClick = function(r) openItem(r.id) end
    list.onEnter = function(row, r)
        local cut = CB.CutRate(ns.db)
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        if not pcall(GameTooltip.SetItemByID, GameTooltip, r.id) then GameTooltip:AddLine(Name(r)) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Lowest now", U.FormatMoney(r.now), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(("Usual low (median, %d days)"):format(r.days), U.FormatMoney(r.usual), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(("Relist at usual, after %s cut"):format(CB.CutLabel(cut)),
            U.FormatMoney(r.usual * (1 - cut)), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Profit per item", U.FormatMoney(r.profit, true), 1, 0.82, 0, 1, 1, 1)
        if r.est then
            GameTooltip:AddDoubleLine("Market activity (estimate)", U.PerDay(r.est), 1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Price seen", U.Ago(r.e.t), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open on the Buy tab and check how many are actually this cheap.", 0.6, 0.63, 0.68, true)
        GameTooltip:Show()
    end
    f.list = list

    local note = W.Text(f, "mutedSm",
        "Estimates from your saved prices, so they're only as fresh as your last Scan or search. Deposits are refunded on a sale but lost if it doesn't sell.")
    note:SetPoint("BOTTOMLEFT", 2, 4)
    note:SetPoint("RIGHT", -2, 0)
    note:SetJustifyH("LEFT")

    function f:Refresh()
        self.marginSeg:SetValue(self.minMargin)
        local rows = P.FlipCandidates({
            cut = CB.CutRate(ns.db), minMargin = self.minMargin, minProfit = MIN_PROFIT, maxAge = MAX_AGE, minDays = 3,
        })
        self.rows = rows
        self:ApplyFilter()
    end

    --- Narrow the candidates from the last Refresh to the name and category filters (no recompute).
    function f:ApplyFilter()
        local rows = self.rows or {}
        local text = (self.search:GetText() or ""):lower()
        local filters = (self.sub and self.sub.filters) or (self.cat and self.cat.filters)
        local shown = {}
        for _, r in ipairs(rows) do
            if (text == "" or Name(r):lower():find(text, 1, true)) and S.ItemMatches(r.id, filters) then
                shown[#shown + 1] = r
            end
        end
        list:SetData(shown)
        local filtered = text ~= "" or filters ~= nil
        list.empty:SetText(filtered and #rows > 0 and "No flips match these filters."
            or "No flips right now. Prices need a few days of history and a recent Scan or search.")
        local last = ns.db.lastFullScan
        self.countFS:SetText(("%s   |cff8c94a3prices from the last 3h; last full scan %s|r"):format(
            filtered and ("%d of %d candidates"):format(#shown, #rows) or ("%d candidates"):format(#rows),
            last and U.Ago(last) or "never"))
    end

    local pending = false
    ns:Register("PRICES_UPDATED", function()
        if pending or not f:IsVisible() then return end
        pending = true
        C_Timer.After(1, function()
            pending = false
            if f:IsVisible() then f:Refresh() end
        end)
    end)
    f:SetScript("OnShow", function() f:Refresh() end)
    return f
end
