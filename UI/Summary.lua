-- Summary tab: KPI tiles plus income/spending breakdown for the last 30 days.
-- Also hosts small data helpers shared by the other views.
local _, ns = ...
local UI, W, U, L, C, CB = ns.UI, ns.Widgets, ns.Util, ns.Ledger, ns.Categories, ns.CostBasis

--- Category filter honoring the "include bank transfers" setting.
function UI.CatFilter()
    local transfers = ns.db.settings.includeTransfers
    return function(cat)
        if C.IsNeutral(cat) then return false end
        return transfers or not C.IsTransfer(cat)
    end
end

--- Split a { [cat] = amount } table into per-group income (pos) and spending (neg).
function UI.SplitByGroup(byCat)
    local pos, neg = {}, {}
    for cat, a in pairs(byCat) do
        local g = C.Group(cat)
        if a > 0 then pos[g] = (pos[g] or 0) + a elseif a < 0 then neg[g] = (neg[g] or 0) + a end
    end
    return pos, neg
end

--- Sorted { { group = info, value = abs amount } } from a group table.
function UI.GroupItems(tbl)
    local items = {}
    for key, v in pairs(tbl) do
        if v ~= 0 then items[#items + 1] = { group = C.GroupInfo(key), value = math.abs(v) } end
    end
    table.sort(items, function(a, b) return a.value > b.value end)
    return items
end

local TILES = { "Today", "Last 7 days", "Last 30 days", "AH profit (all time)", "Top source (30 days)", "Net worth" }

function UI.CreateSummary(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tiles = {}
    for i, label in ipairs(TILES) do
        local tile = W.Panel(f)
        tile:SetHeight(72)
        tile.label = W.Text(tile, "GameFontNormalSmall", label:upper())
        tile.label:SetPoint("TOPLEFT", 12, -12)
        tile.label:SetPoint("RIGHT", -8, 0)
        tile.label:SetJustifyH("LEFT")
        tile.label:SetWordWrap(false)
        tile.value = W.Text(tile, "GameFontHighlightLarge")
        tile.value:SetPoint("BOTTOMLEFT", 12, 12)
        tile.value:SetPoint("RIGHT", -8, 0)
        tile.value:SetJustifyH("LEFT")
        tile.value:SetWordWrap(false)
        f.tiles[i] = tile
    end

    -- Net worth tile: hover for the breakdown.
    local nwTile = f.tiles[#TILES]
    nwTile:EnableMouse(true)
    nwTile:SetScript("OnEnter", function(self)
        local nw = ns.Inventory.NetWorth()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Net worth on " .. (ns.realm or "this realm"))
        GameTooltip:AddDoubleLine("Gold (all characters)", U.FormatMoney(nw.gold), 1, 0.82, 0, 1, 1, 1)
        for _, w in ipairs({ { "bags", "Items in your bags" }, { "bank", "Items in your bank" }, { "alts", "Items on alts" }, { "warband", "Warband bank" } }) do
            if (nw.where[w[1]] or 0) > 0 then GameTooltip:AddDoubleLine(w[2], U.FormatMoney(nw.where[w[1]]), 1, 0.82, 0, 1, 1, 1) end
        end
        if #nw.top > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Most valuable", 1, 0.82, 0)
            for i = 1, math.min(5, #nw.top) do
                GameTooltip:AddDoubleLine(U.ItemName(nw.top[i].id) or ("item:" .. nw.top[i].id), U.FormatMoney(nw.top[i].value), 1, 1, 1, 1, 1, 1)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Items at AH price after the cut, or vendor price when better (junk and soulbound: vendor). Bank and alts as of their last scan.", 0.55, 0.58, 0.64, true)
        GameTooltip:Show()
    end)
    nwTile:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function Breakdown(title)
        local p = W.Panel(f)
        p.title = W.Text(p, "GameFontNormal", title)
        p.title:SetPoint("TOPLEFT", 14, -12)
        p.total = W.Text(p, "GameFontHighlight")
        p.total:SetPoint("TOPRIGHT", -14, -12)
        p.rows = {}
        for i = 1, #C.groups do
            local row = CreateFrame("Frame", nil, p)
            row:SetHeight(22)
            row:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 26)
            row:SetPoint("RIGHT", -14, 0)
            row.bar = row:CreateTexture(nil, "BACKGROUND")
            row.bar:SetPoint("TOPLEFT")
            row.bar:SetPoint("BOTTOMLEFT")
            row.label = W.Text(row, "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 8, 0)
            row.value = W.Text(row, "GameFontHighlightSmall")
            row.value:SetPoint("RIGHT", -6, 0)
            p.rows[i] = row
        end
        return p
    end
    f.income = Breakdown("Income by source (30 days)")
    f.spend = Breakdown("Spending by source (30 days)")

    f.session = W.Text(f, "GameFontHighlightSmall")
    f.session:SetPoint("BOTTOMLEFT", 2, 2)

    function f:Layout()
        local w = self:GetWidth()
        local gap = 12
        local tw = (w - gap * (#self.tiles - 1)) / #self.tiles
        for i, tile in ipairs(self.tiles) do
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", (i - 1) * (tw + gap), 0)
            tile:SetWidth(tw)
        end
        local half = (w - gap) / 2
        self.income:ClearAllPoints()
        self.income:SetPoint("TOPLEFT", 0, -84)
        self.income:SetPoint("BOTTOM", 0, 26)
        self.income:SetWidth(half)
        self.spend:ClearAllPoints()
        self.spend:SetPoint("TOPRIGHT", 0, -84)
        self.spend:SetPoint("BOTTOM", 0, 26)
        self.spend:SetWidth(half)
        if self:IsVisible() then self:Refresh() end -- breakdown bar widths depend on panel width
    end
    f:SetScript("OnSizeChanged", f.Layout)

    local function FillBreakdown(panel, groupTbl, sign)
        local items = UI.GroupItems(groupTbl)
        local total, maxV = 0, 0
        for _, it in ipairs(items) do
            total = total + it.value
            maxV = math.max(maxV, it.value)
        end
        panel.total:SetText(U.FormatMoney(sign * total, true))
        local width = panel:GetWidth() - 28
        for i, row in ipairs(panel.rows) do
            local it = items[i]
            if it then
                local g = it.group
                row.label:SetText(g.label)
                row.value:SetText(("%s  |cff999999%.0f%%|r"):format(U.FormatMoney(it.value), total > 0 and it.value / total * 100 or 0))
                row.bar:SetColorTexture(g.color[1], g.color[2], g.color[3], 0.30)
                row.bar:SetWidth(math.max(1, width * it.value / maxV))
                row:Show()
            else
                row:Hide()
            end
        end
    end

    local function SetTile(i, text)
        f.tiles[i].value:SetText(text)
    end

    function f:Refresh()
        local chars = ns:ScopeCharTables()
        local filter = UI.CatFilter()
        local now = time()
        local today = L.Sum(chars, U.DayKeys(1, now), nil, filter)
        local week = L.Sum(chars, U.DayKeys(7, now), nil, filter)
        local month = L.Sum(chars, U.DayKeys(30, now), nil, filter)
        SetTile(1, U.FormatMoney(L.Net(today), true))
        SetTile(2, U.FormatMoney(L.Net(week), true))
        SetTile(3, U.FormatMoney(L.Net(month), true))

        local ahProfit = 0
        for _, flip in pairs(CB.MergeFlips(chars)) do ahProfit = ahProfit + CB.Profit(flip) end
        SetTile(4, U.FormatMoney(ahProfit, true))

        local pos, neg = UI.SplitByGroup(month)
        local top = UI.GroupItems(pos)[1]
        SetTile(5, top and ("|cff%02x%02x%02x%s|r"):format(top.group.color[1] * 255, top.group.color[2] * 255,
            top.group.color[3] * 255, top.group.label) or "|cff999999none|r")

        local nw = ns.Inventory.NetWorth()
        SetTile(6, U.FormatMoney(nw.total))

        FillBreakdown(self.income, pos, 1)
        FillBreakdown(self.spend, neg, -1)

        local M = ns.Money
        self.session:SetText(("This session: %s   |cff999999(unattributed: %s)|r"):format(
            U.FormatMoney(M.session or 0, true), U.FormatMoney(M.sessionOther or 0)))
    end

    return f
end
