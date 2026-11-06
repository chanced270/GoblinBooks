-- CSV export of the ledger (current scope and filter) into a copyable text box.
local _, ns = ...
local UI, W, U, L, C = ns.UI, ns.Widgets, ns.Util, ns.Ledger, ns.Categories

local function CsvField(v)
    v = tostring(v or "")
    if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end

function UI.BuildCSV()
    local lines = { "time,character,category,group,amount_copper,amount_gold,item_id,quantity,detail" }
    local rows = L.Entries(ns:ScopeChars(), UI.LedgerFilter())
    for i = #rows, 1, -1 do -- oldest first
        local e, who = rows[i].e, rows[i].who
        lines[#lines + 1] = table.concat({
            date("%Y-%m-%d %H:%M:%S", e.t), CsvField(who), e.c, C.Group(e.c), e.a, U.GoldDecimal(e.a),
            e.i or "", e.q or "", CsvField(UI.EntryDetail(e)),
        }, ",")
    end
    return table.concat(lines, "\n"), #rows
end

local frame
local function Create()
    local f = W.Window("GoblinBooksExportFrame", 640, 440, "CSV Export")
    f:SetFrameStrata("DIALOG")
    local hint = W.Text(f.header, "mutedSm", "Ctrl+A to select all, Ctrl+C to copy")
    hint:SetPoint("LEFT", f.title, "RIGHT", 12, -1)

    local box = W.Panel(f)
    box:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 16, -16)
    box:SetPoint("BOTTOMRIGHT", -16, 16)
    W.Backdrop(box, { 0, 0, 0, 0.3 }, W.Theme.border)

    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", -10, 10)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, d)
        s:SetVerticalScroll(math.max(0, math.min(s:GetVerticalScrollRange(), s:GetVerticalScroll() - d * 40)))
    end)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(W.Fonts.body)
    edit:SetTextColor(0.85, 0.87, 0.9)
    edit:SetWidth(588)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -y
        if y < top then scroll:SetVerticalScroll(y) elseif y + h > top + view then scroll:SetVerticalScroll(y + h - view) end
    end)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    return f
end

function UI:ShowExport()
    frame = frame or Create()
    local text, n = UI.BuildCSV()
    frame.edit:SetText(text)
    frame:Show()
    frame.edit:SetFocus()
    frame.edit:HighlightText()
    ns:Print(("exported %d entries"):format(n))
end
