-- Charts tab: daily income/spending stacked bars + share-of-income and share-of-spending bars.
-- Click a group (a bar, a share segment or a legend row) to see that group's own categories day by day.
-- Other modes: net worth (gold + items) and AH profit (sales after the cut, minus what the items cost you and
-- the deposits you lost, per day; from CostBasis' daily AH results).
local _, ns = ...
local UI, W, U, L, C, Charts, CB = ns.UI, ns.Widgets, ns.Util, ns.Ledger, ns.Categories, ns.Charts, ns.CostBasis

local PERIODS = { 7, 30, 90 }
local CHART_TOP = -56 -- below the controls row and the title/total row
local SHARE_SPACE = 138
local MUTED = { 0.55, 0.58, 0.64 }

--- A group's color, lighter or darker for the i-th of n categories, so they stay apart in one chart.
local function Shade(color, i, n)
    local f = n <= 1 and 1 or (1.25 - 0.6 * (i - 1) / (n - 1))
    return { math.min(1, color[1] * f), math.min(1, color[2] * f), math.min(1, color[3] * f) }
end

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

    -- Gold flow (income/spending), net worth (gold + items) or AH profit over time.
    f.mode = "flow"
    f.modeSeg = W.Segmented(f, {
        { key = "flow", label = "Gold flow" },
        { key = "worth", label = "Net worth" },
        { key = "ah", label = "AH profit" },
    }, function(key)
        f.mode = key
        f:Layout()
        f:Refresh()
    end, 76)
    f.modeSeg:SetPoint("TOPRIGHT", 0, 0)

    -- Second row: what's shown (with a way back from one group) and its total.
    f.back = W.Button(f, "< All categories", 112, function() f:Drill(nil) end)
    f.back:SetPoint("TOPLEFT", 0, -30)
    f.titleFS = W.Text(f, "GameFontNormal")
    f.titleFS:SetPoint("TOPLEFT", 0, -34)
    f.titleFS:SetJustifyH("LEFT")
    f.netFS = W.Text(f, "GameFontHighlight")
    f.netFS:SetPoint("TOPRIGHT", -4, -34)

    local chart = Charts.CreateStackedBar(f)
    f.chart = chart
    f.chartFull = nil

    f.incomeShare = Charts.CreateShareBar(f, "Income share")
    f.spendShare = Charts.CreateShareBar(f, "Spending share")

    -- Clicking a group opens it (gold flow, all categories only).
    local function OpenGroup(g)
        if f.mode == "flow" and not f.drill and g and C.groupByKey[g.key] then f:Drill(g.key) end
    end
    local function Hint(g)
        if f.mode == "flow" and not f.drill and g and C.groupByKey[g.key] then
            return "Click to see " .. g.label .. " by category"
        end
    end
    chart.onClick, chart.clickHint = OpenGroup, Hint
    f.incomeShare.onClick, f.incomeShare.clickHint = OpenGroup, Hint
    f.spendShare.onClick, f.spendShare.clickHint = OpenGroup, Hint

    function f:Drill(groupKey)
        self.drill = groupKey
        GameTooltip:Hide()
        self:Refresh()
    end

    function f:Layout()
        -- Net worth and AH profit use the whole height (no share bars).
        local full = self.mode ~= "flow"
        if full ~= self.chartFull then
            self.chartFull = full
            self.chart:ClearAllPoints()
            self.chart:SetPoint("TOPLEFT", 0, CHART_TOP)
            self.chart:SetPoint("BOTTOMRIGHT", 0, full and 0 or SHARE_SPACE)
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

    local function SetTitle(text, showBack)
        f.back:SetShown(showBack)
        f.titleFS:ClearAllPoints()
        if showBack then
            f.titleFS:SetPoint("LEFT", f.back, "RIGHT", 10, 0)
        else
            f.titleFS:SetPoint("TOPLEFT", 0, -34)
        end
        f.titleFS:SetText(text)
    end

    ---------------------------------------------------------------------------
    -- Net worth
    ---------------------------------------------------------------------------
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
        self.chart.noData:SetText("No net worth snapshots in this period")
        self.chart:SetData(days, WORTH_GROUPS)
        SetTitle("Net worth", false)
        local nw = ns.Inventory.NetWorth()
        self.netFS:SetText(("Now: %s"):format(U.FormatMoney(nw.total)))
    end

    ---------------------------------------------------------------------------
    -- AH profit
    ---------------------------------------------------------------------------
    local AH_GROUPS = {
        { key = "sales", label = "Sales (after the cut)", color = { 0.22, 0.80, 0.74 } },
        { key = "refund", label = "Deposits refunded", color = { 0.55, 0.88, 0.82 } },
        { key = "cost", label = "Cost of the items sold", color = { 0.88, 0.34, 0.30 } },
        { key = "dep", label = "Deposits paid", color = { 0.98, 0.58, 0.24 } },
    }
    local function AHTip(day, g, val)
        local d = day.ah
        local profit = CB.DayProfit(d)
        local tip = {
            { left = day.label },
            { left = g.label, right = U.FormatMoney(math.abs(val)), r = g.color[1], g = g.color[2], b = g.color[3] },
            { left = " " },
            { left = "Sales (after the cut)", right = U.FormatMoney(d.s) },
            { left = "Cost of the items sold", right = U.FormatMoney(-d.c, true) },
            { left = "Deposits (paid - refunded)", right = U.FormatMoney(d.dr - d.dp, true) },
            { left = "Profit", right = U.FormatMoney(profit, true),
              r = profit >= 0 and 0.38 or 1, g = profit >= 0 and 1 or 0.38, b = 0.38 },
            { left = "Items sold", right = tostring(d.n) },
        }
        if d.nc > 0 then
            tip[#tip + 1] = { left = ("%d sold with no known cost (counted as free)"):format(d.nc), r = 1, g = 0.6, b = 0.2 }
        end
        if d.x and d.x > 0 then
            tip[#tip + 1] = { left = ("Not counted: %s from sales with no item recorded"):format(U.FormatMoney(d.x)),
                r = MUTED[1], g = MUTED[2], b = MUTED[3] }
        end
        if d.est then
            tip[#tip + 1] = { left = "Rebuilt from older records: cost is the item's average", r = MUTED[1], g = MUTED[2], b = MUTED[3] }
        end
        return tip
    end

    function f:RefreshAH()
        local keys = U.DayKeys(self.period)
        local daily = CB.AHDaily(ns:ScopeCharTables(), keys)
        local days = {}
        local profit, sold, sales, noCost, any = 0, 0, 0, 0, false
        for i, key in ipairs(keys) do
            local d = daily[key]
            local day = { key = key, label = U.ShortDate(key), pos = {}, neg = {}, ah = d }
            if d then
                any = true
                day.pos.sales = d.s > 0 and d.s or nil
                day.pos.refund = d.dr > 0 and d.dr or nil
                day.neg.cost = d.c > 0 and -d.c or nil
                day.neg.dep = d.dp > 0 and -d.dp or nil
                profit, sold, sales, noCost = profit + CB.DayProfit(d), sold + d.n, sales + d.s, noCost + d.nc
            end
            days[i] = day
        end
        self.chart.tipFn = AHTip
        self.chart.noData:SetText("No auction sales or deposits in this period")
        self.chart:SetData(days, AH_GROUPS)
        SetTitle(any and ("%d items sold for %s after the cut%s"):format(sold, U.FormatMoney(sales),
            noCost > 0 and (" |cffff9933(%d with no known cost)|r"):format(noCost) or "") or "AH profit", false)
        self.netFS:SetText(("Profit (%d days): %s"):format(self.period, U.FormatMoney(profit, true)))
    end

    ---------------------------------------------------------------------------
    -- Gold flow: all groups, or one group by category
    ---------------------------------------------------------------------------
    local function CatItems(tbl, infoByCat)
        local items = {}
        for cat, v in pairs(tbl) do
            if v ~= 0 and infoByCat[cat] then items[#items + 1] = { group = infoByCat[cat], value = math.abs(v) } end
        end
        table.sort(items, function(a, b) return a.value > b.value end)
        return items
    end

    function f:RefreshGroup(group, chars, keys)
        local cats = C.CatsInGroup(group.key)
        local infos, byCat, set = {}, {}, {}
        for i, c in ipairs(cats) do
            local info = { key = c.key, label = c.label, color = Shade(group.color, i, #cats) }
            infos[i], byCat[c.key], set[c.key] = info, info, true
        end
        local daily = L.Daily(chars, keys, nil, function(cat) return set[cat] end)
        local days, totalPos, totalNeg = {}, {}, {}
        for i, key in ipairs(keys) do
            local pos, neg = {}, {}
            for cat, a in pairs(daily[key]) do
                if a > 0 then pos[cat] = a elseif a < 0 then neg[cat] = a end
            end
            days[i] = { key = key, label = U.ShortDate(key), pos = pos, neg = neg }
            for cat, v in pairs(pos) do totalPos[cat] = (totalPos[cat] or 0) + v end
            for cat, v in pairs(neg) do totalNeg[cat] = (totalNeg[cat] or 0) + v end
        end
        self.chart.noData:SetText("No " .. group.label .. " activity in this period")
        self.chart:SetData(days, infos)
        self.incomeShare:SetData(CatItems(totalPos, byCat))
        self.spendShare:SetData(CatItems(totalNeg, byCat))
        SetTitle(group.label .. " by category", true)
        self.netFS:SetText(("Net (%d days): %s"):format(self.period, U.FormatMoney(L.Net(totalPos) + L.Net(totalNeg), true)))
    end

    function f:Refresh()
        self.periodSeg:SetValue(self.period)
        self.modeSeg:SetValue(self.mode)
        local flow = self.mode == "flow"
        self.transfers:SetShown(flow)
        self.incomeShare:SetShown(flow)
        self.spendShare:SetShown(flow)
        if self.mode == "worth" then return self:RefreshWorth() end
        if self.mode == "ah" then return self:RefreshAH() end
        self.chart.tipFn = nil
        self.transfers:SetChecked(ns.db.settings.includeTransfers)

        local chars = ns:ScopeCharTables()
        local keys = U.DayKeys(self.period)
        local group = self.drill and C.groupByKey[self.drill]
        -- A hidden group (bank transfers turned off) can't stay open.
        if group and (group.neutral or (group.transfer and not ns.db.settings.includeTransfers)) then
            self.drill, group = nil, nil
        end
        if group then return self:RefreshGroup(group, chars, keys) end

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
        self.chart.noData:SetText("No gold activity in this period")
        self.chart:SetData(days, groups)
        self.incomeShare:SetData(UI.GroupItems(totalPos))
        self.spendShare:SetData(UI.GroupItems(totalNeg))
        SetTitle("Income and spending  |cff8c94a3(click a group to see its categories)|r", false)
        self.netFS:SetText(("Net (%d days): %s"):format(self.period, U.FormatMoney(L.Net(totalPos) + L.Net(totalNeg), true)))
    end

    f:Layout()
    return f
end
