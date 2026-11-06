-- Charts tab: daily income/spending stacked bars + share-of-income and share-of-spending bars.
local _, ns = ...
local UI, W, U, L, C, Charts = ns.UI, ns.Widgets, ns.Util, ns.Ledger, ns.Categories, ns.Charts

local PERIODS = { 7, 30, 90 }

function UI.CreateChartsView(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.period = 30

    local opts = {}
    for _, days in ipairs(PERIODS) do opts[#opts + 1] = { key = days, label = days .. " days" } end
    f.periodSeg = W.Segmented(f, opts, function(days)
        f.period = days
        f:Refresh()
    end, 66)
    f.periodSeg:SetPoint("TOPLEFT", 0, 0)
    local prev = f.periodSeg

    f.transfers = W.Check(f, "Include bank transfers", function(checked)
        ns.db.settings.includeTransfers = checked and true or false
        ns:Fire("LEDGER_UPDATED")
    end)
    f.transfers:SetPoint("LEFT", prev, "RIGHT", 18, 0)

    -- Gold flow (income/spending) or net worth (gold + items) over time.
    f.mode = "flow"
    f.modeSeg = W.Segmented(f, {
        { key = "flow", label = "Gold flow" },
        { key = "worth", label = "Net worth" },
    }, function(key)
        f.mode = key
        f:Layout()
        f:Refresh()
    end, 80)
    f.modeSeg:SetPoint("LEFT", f.transfers.label, "RIGHT", 18, 0)

    f.netFS = W.Text(f, "GameFontHighlight")
    f.netFS:SetPoint("TOPRIGHT", -4, -6)

    local chart = Charts.CreateStackedBar(f)
    chart:SetPoint("TOPLEFT", 0, -38)
    chart:SetPoint("BOTTOMRIGHT", 0, 138)
    f.chart = chart
    f.chartFull = false

    f.incomeShare = Charts.CreateShareBar(f, "Income share")
    f.spendShare = Charts.CreateShareBar(f, "Spending share")

    function f:Layout()
        -- Net worth uses the whole height (no share bars).
        local full = self.mode == "worth"
        if full ~= self.chartFull then
            self.chartFull = full
            self.chart:ClearAllPoints()
            self.chart:SetPoint("TOPLEFT", 0, -38)
            self.chart:SetPoint("BOTTOMRIGHT", 0, full and 0 or 138)
        end
        local half = (self:GetWidth() - 24) / 2
        self.incomeShare:ClearAllPoints()
        self.incomeShare:SetPoint("BOTTOMLEFT", 0, 0)
        self.incomeShare:SetSize(half, 118)
        self.spendShare:ClearAllPoints()
        self.spendShare:SetPoint("BOTTOMRIGHT", 0, 0)
        self.spendShare:SetSize(half, 118)
    end
    f:SetScript("OnSizeChanged", f.Layout)

    local WORTH_GROUPS = {
        { key = "nw_items", label = "Items", color = { 0.40, 0.70, 1.00 } },
        { key = "nw_gold", label = "Gold", color = { 1, 0.78, 0.25 } },
    }
    local function WorthTip(day, g, val, total)
        return {
            { left = day.label },
            { left = g.label, right = U.FormatMoney(val), r = g.color[1], g = g.color[2], b = g.color[3] },
            { left = "Net worth", right = U.FormatMoney(total.pos) },
        }
    end

    function f:RefreshWorth()
        local days = {}
        for i, h in ipairs(ns.Inventory.History(self.period)) do
            days[i] = { key = h.key, label = U.ShortDate(h.key), pos = { nw_gold = h.gold, nw_items = h.items }, neg = {} }
        end
        self.chart.tipFn = WorthTip
        self.chart:SetData(days, WORTH_GROUPS)
        local nw = ns.Inventory.NetWorth()
        self.netFS:SetText(("Net worth now: %s"):format(U.FormatMoney(nw.total)))
    end

    function f:Refresh()
        self.periodSeg:SetValue(self.period)
        self.modeSeg:SetValue(self.mode)
        local worth = self.mode == "worth"
        self.transfers:SetShown(not worth)
        self.incomeShare:SetShown(not worth)
        self.spendShare:SetShown(not worth)
        if worth then return self:RefreshWorth() end
        self.chart.tipFn = nil
        self.transfers:SetChecked(ns.db.settings.includeTransfers)

        local chars = ns:ScopeCharTables()
        local keys = U.DayKeys(self.period)
        local daily = L.Daily(chars, keys, nil, UI.CatFilter())
        local days = {}
        local totalPos, totalNeg = {}, {}
        for i, key in ipairs(keys) do
            local pos, neg = UI.SplitByGroup(daily[key])
            days[i] = { key = key, label = U.ShortDate(key), pos = pos, neg = neg }
            for g, v in pairs(pos) do totalPos[g] = (totalPos[g] or 0) + v end
            for g, v in pairs(neg) do totalNeg[g] = (totalNeg[g] or 0) + v end
        end
        local groups = {}
        for _, g in ipairs(C.groups) do
            if not g.neutral and (ns.db.settings.includeTransfers or not g.transfer) then groups[#groups + 1] = g end
        end
        self.chart:SetData(days, groups)
        self.incomeShare:SetData(UI.GroupItems(totalPos))
        self.spendShare:SetData(UI.GroupItems(totalNeg))
        self.netFS:SetText(("Net (%d days): %s"):format(self.period, U.FormatMoney(L.Net(totalPos) + L.Net(totalNeg), true)))
    end

    return f
end
