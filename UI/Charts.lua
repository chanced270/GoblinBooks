-- Texture-based charts: a diverging stacked bar chart (income up, spending down) and a 100% share bar.
local _, ns = ...
local W, U = ns.Widgets, ns.Util
local Charts = {}
ns.Charts = Charts

local abs, floor, ceil, max = math.abs, math.floor, math.ceil, math.max

function Charts.NiceStep(range, ticks)
    if range <= 0 then return 10000 end
    local raw = range / ticks
    local mag = 10 ^ floor(math.log10(raw))
    local norm = raw / mag
    local step = (norm <= 1 and 1) or (norm <= 2 and 2) or (norm <= 5 and 5) or 10
    return max(1, step * mag)
end

-- Simple pool of reusable children.
local function Pool(create)
    local pool = { items = {}, used = 0 }
    function pool:Acquire()
        self.used = self.used + 1
        local item = self.items[self.used]
        if not item then
            item = create()
            self.items[self.used] = item
        end
        item:Show()
        return item
    end
    function pool:ReleaseAll()
        for i = 1, #self.items do self.items[i]:Hide() end
        self.used = 0
    end
    return pool
end

local function ShowTooltip(owner, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, l in ipairs(lines) do
        if l.right then
            GameTooltip:AddDoubleLine(l.left, l.right, l.r or 1, l.g or 1, l.b or 1, 1, 1, 1)
        else
            GameTooltip:AddLine(l.left, l.r or (i == 1 and 1 or 0.8), l.g or (i == 1 and 0.82 or 0.8), l.b or (i == 1 and 0 or 0.8))
        end
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Stacked bar chart
-- SetData(days, groups): days = { { key, label, pos = { [groupKey] = copper > 0 }, neg = { [groupKey] = copper < 0 } } },
-- groups = ordered group infos
---------------------------------------------------------------------------
function Charts.CreateStackedBar(parent)
    local f = CreateFrame("Frame", nil, parent)
    local plot = CreateFrame("Frame", nil, f)
    plot:SetPoint("TOPLEFT", 60, -8)
    plot:SetPoint("BOTTOMRIGHT", -8, 18)
    f.plot = plot

    local zero = plot:CreateTexture(nil, "OVERLAY")
    zero:SetColorTexture(1, 1, 1, 0.45)
    zero:SetHeight(1)
    f.zero = zero

    f.noData = W.Text(plot, "GameFontDisable", "No gold activity in this period")
    f.noData:SetPoint("CENTER")

    f.segs = Pool(function()
        local seg = CreateFrame("Frame", nil, plot)
        seg.tex = seg:CreateTexture(nil, "ARTWORK")
        seg.tex:SetAllPoints()
        seg:EnableMouse(true)
        seg:SetScript("OnEnter", function(self)
            self.tex:SetAlpha(1)
            if self.tip then ShowTooltip(self, self.tip) end
        end)
        seg:SetScript("OnLeave", function(self)
            self.tex:SetAlpha(0.85)
            GameTooltip:Hide()
        end)
        seg:SetScript("OnMouseUp", function(self)
            if f.onClick and self.group then f.onClick(self.group, self.day) end
        end)
        return seg
    end)
    f.gridLines = Pool(function()
        local t = plot:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 0.07)
        t:SetHeight(1)
        return t
    end)
    f.yLabels = Pool(function()
        local fs = W.Text(f, "GameFontDisableSmall")
        fs:SetJustifyH("RIGHT")
        fs:SetWidth(54)
        return fs
    end)
    f.xLabels = Pool(function() return W.Text(f, "GameFontDisableSmall") end)

    function f:SetData(days, groups)
        self.days, self.groups = days, groups
        self:Render()
    end

    function f:Render()
        local days, groups = self.days, self.groups
        local pw, ph = plot:GetWidth(), plot:GetHeight()
        self.segs:ReleaseAll()
        self.gridLines:ReleaseAll()
        self.yLabels:ReleaseAll()
        self.xLabels:ReleaseAll()
        if not days or pw <= 0 or ph <= 0 then return end

        local maxPos, maxNeg = 0, 0
        local totals = {}
        for i, day in ipairs(days) do
            local pos, neg = 0, 0
            for _, v in pairs(day.pos) do pos = pos + v end
            for _, v in pairs(day.neg) do neg = neg - v end
            totals[i] = { pos = pos, neg = neg }
            maxPos, maxNeg = max(maxPos, pos), max(maxNeg, neg)
        end
        self.noData:SetShown(maxPos == 0 and maxNeg == 0)

        local step = Charts.NiceStep(maxPos + maxNeg, 4)
        local top, bottom = ceil(maxPos / step) * step, ceil(maxNeg / step) * step
        if top + bottom == 0 then top = step end
        local scale = ph / (top + bottom)
        local zeroY = bottom * scale

        -- Gridlines and y labels.
        local v = -bottom
        while v <= top + 0.5 do
            local y = zeroY + v * scale
            local line = self.gridLines:Acquire()
            line:ClearAllPoints()
            line:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y)
            line:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, y)
            local label = self.yLabels:Acquire()
            label:ClearAllPoints()
            label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -4, y)
            label:SetText(U.FormatGoldShort(v))
            v = v + step
        end
        zero:ClearAllPoints()
        zero:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, zeroY)
        zero:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, zeroY)

        -- Bars.
        local n = #days
        local slot = pw / n
        local barW = max(2, slot * 0.72)
        local labelEvery = max(1, ceil(n / max(1, floor(pw / 42))))
        for i, day in ipairs(days) do
            local x = (i - 1) * slot + (slot - barW) / 2
            local up, down = 0, 0
            local net = totals[i].pos - totals[i].neg
            for pass = 1, 2 do
            for _, g in ipairs(groups) do
                local val = (pass == 1 and day.pos or day.neg)[g.key]
                if val and val ~= 0 then
                    local h = abs(val) * scale
                    local seg = self.segs:Acquire()
                    seg:ClearAllPoints()
                    if val > 0 then
                        seg:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x, zeroY + up)
                        up = up + h
                    else
                        seg:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", x, zeroY - down)
                        down = down + h
                    end
                    seg:SetSize(barW, max(1, h))
                    seg.tex:SetColorTexture(g.color[1], g.color[2], g.color[3])
                    seg.tex:SetAlpha(0.85)
                    seg.group, seg.day = g, day
                    seg.tip = self.tipFn and self.tipFn(day, g, val, totals[i]) or {
                        { left = day.label },
                        { left = g.label, right = U.FormatMoney(val, true), r = g.color[1], g = g.color[2], b = g.color[3] },
                        { left = "Day income", right = U.FormatMoney(totals[i].pos) },
                        { left = "Day spending", right = U.FormatMoney(-totals[i].neg) },
                        { left = "Day net", right = U.FormatMoney(net, true) },
                    }
                    if self.clickHint then
                        local hint = self.clickHint(g)
                        if hint then seg.tip[#seg.tip + 1] = { left = hint, r = 0.55, g = 0.58, b = 0.64 } end
                    end
                end
            end
            end
            if (n - i) % labelEvery == 0 then
                local label = self.xLabels:Acquire()
                label:ClearAllPoints()
                label:SetPoint("TOP", plot, "BOTTOMLEFT", x + barW / 2, -3)
                label:SetText(day.label)
            end
        end
    end

    f:SetScript("OnSizeChanged", function(self) self:Render() end)
    return f
end

---------------------------------------------------------------------------
-- Share bar: horizontal 100% bar with a legend.
-- SetData(items): items = { { group = groupInfo, value = copper (>0) } }
---------------------------------------------------------------------------
function Charts.CreateShareBar(parent, title)
    local f = CreateFrame("Frame", nil, parent)
    local titleFS = W.Text(f, "GameFontNormal", title)
    titleFS:SetPoint("TOPLEFT", 0, 0)
    f.totalFS = W.Text(f, "GameFontHighlightSmall")
    f.totalFS:SetPoint("TOPRIGHT", 0, -2)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 0, -18)
    bar:SetPoint("TOPRIGHT", 0, -18)
    bar:SetHeight(16)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.06)
    f.bar = bar

    f.segs = Pool(function()
        local seg = CreateFrame("Frame", nil, bar)
        seg.tex = seg:CreateTexture(nil, "ARTWORK")
        seg.tex:SetAllPoints()
        seg:EnableMouse(true)
        seg:SetScript("OnEnter", function(self) if self.tip then ShowTooltip(self, self.tip) end end)
        seg:SetScript("OnLeave", function() GameTooltip:Hide() end)
        seg:SetScript("OnMouseUp", function(self) if f.onClick and self.group then f.onClick(self.group) end end)
        return seg
    end)
    f.legend = Pool(function()
        local row = CreateFrame("Frame", nil, f)
        row:SetHeight(14)
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(self) if f.onClick and self.group then f.onClick(self.group) end end)
        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(10, 10)
        row.swatch:SetPoint("LEFT")
        row.text = W.Text(row, "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.swatch, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT")
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        return row
    end)

    function f:SetData(items)
        self.items = items
        self:Render()
    end

    function f:Render()
        self.segs:ReleaseAll()
        self.legend:ReleaseAll()
        local items = self.items or {}
        local total = 0
        for _, it in ipairs(items) do total = total + it.value end
        self.totalFS:SetText(U.FormatMoney(total))
        local width = bar:GetWidth()
        if total <= 0 or width <= 0 then return end

        local x = 0
        local colW = width / 2
        for i, it in ipairs(items) do
            local g = it.group
            local pct = it.value / total
            local w = width * pct
            local seg = self.segs:Acquire()
            seg:ClearAllPoints()
            seg:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
            seg:SetSize(max(1, w - 1), bar:GetHeight())
            seg.tex:SetColorTexture(g.color[1], g.color[2], g.color[3], 0.9)
            seg.group = g
            seg.tip = {
                { left = g.label },
                { left = "Amount", right = U.FormatMoney(it.value) },
                { left = "Share", right = ("%.1f%%"):format(pct * 100) },
            }
            if self.clickHint then
                local hint = self.clickHint(g)
                if hint then seg.tip[#seg.tip + 1] = { left = hint, r = 0.55, g = 0.58, b = 0.64 } end
            end
            x = x + w

            local row = self.legend:Acquire()
            row.group = g
            local col, line = (i - 1) % 2, floor((i - 1) / 2)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", col * colW, -6 - line * 15)
            row:SetWidth(colW - 8)
            row.swatch:SetColorTexture(g.color[1], g.color[2], g.color[3])
            row.text:SetText(("%s  |cffffffff%s|r  |cff999999%.0f%%|r"):format(g.label, U.FormatGoldShort(it.value), pct * 100))
        end
    end

    f:SetScript("OnSizeChanged", function(self) self:Render() end)
    return f
end
