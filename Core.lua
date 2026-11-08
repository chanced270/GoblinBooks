-- GoblinBooks: core namespace, event dispatch, internal callbacks, saved variables, slash commands.
local ADDON, ns = ...
ns.ADDON = ADDON
ns.VERSION = 5 -- saved-variable schema version

local DEFAULT_SETTINGS = {
    ahFlips = false,      -- show the Flips page in the auction house window
    retentionDays = 90,   -- raw ledger entries older than this are pruned (daily rollups are kept forever)
    debug = false,        -- print every gold change and its category to chat
    accountView = false,  -- UI shows all characters instead of the current one
    includeTransfers = false, -- include bank deposits/withdrawals in charts
    priceHistoryDays = 60, -- AH price history kept per item
    tooltipPrices = true,  -- show AH prices in item tooltips
    ahPanel = true,        -- show the GoblinBooks panel next to the auction house
    minimapButton = true,  -- show the minimap button
    minimapAngle = 220,    -- its position around the minimap (degrees)
    ahReplace = true,      -- full-window mode: cover (and hide) the Blizzard auction house window
    undercut = 1,          -- copper below the lowest competitor when suggesting a price
    postDuration = 2,      -- 1 = 12h, 2 = 24h, 3 = 48h
    dealsPct = 0.7,        -- deals: default limit as a share of the usual price
    dealsSound = true,     -- deals: sound + taskbar flash when a new deal appears
    dealsFavorites = true, -- deals: also watch favorites
    dealsShopping = true,  -- deals: also watch shopping-list reagents still needed
    merchantStackBuy = true, -- shift-click a vendor item: confirm buying a full stack
    scanMode = "full",       -- Scan button: "full" (snapshot) or a category scan ("crafting", "all")
}

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------
function ns:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100GoblinBooks|r: " .. msg)
end

---------------------------------------------------------------------------
-- WoW event dispatch (multiple handlers per event, safe registration)
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

--- Register a handler for a game event. Returns false if the client does not know the event.
function ns:On(event, fn)
    local list = handlers[event]
    if not list then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return false end
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

-- One failing handler must not stop the others; errors still reach the default error handler.
local function SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- /gb perf: time spent in each event and internal callback while it's on.
---------------------------------------------------------------------------
local clock = debugprofilestop
local function Timed(name, start)
    local ms = clock() - start
    local s = ns.perf[name]
    if not s then
        s = { n = 0, total = 0, max = 0 }
        ns.perf[name] = s
    end
    s.n, s.total = s.n + 1, s.total + ms
    if ms > s.max then s.max = ms end
end

function ns:PerfToggle()
    if not clock then ns:Print("timing isn't available in this client") return end
    if not ns.perf then
        ns.perf, ns.perfStart = {}, GetTime()
        ns:Print("timing on. Do the slow thing (open the AH, scan...), then type /gb perf again.")
        return
    end
    local rows = {}
    for name, s in pairs(ns.perf) do rows[#rows + 1] = { name = name, s = s } end
    table.sort(rows, function(a, b) return a.s.total > b.s.total end)
    ns:Print(("timing over %.0fs, slowest first (total ms / calls / worst single ms):"):format(GetTime() - ns.perfStart))
    for i = 1, math.min(12, #rows) do
        local r = rows[i]
        ns:Print(("  %s: %.0f ms / %d / %.0f ms"):format(r.name, r.s.total, r.s.n, r.s.max))
    end
    if #rows == 0 then ns:Print("  nothing ran") end
    ns.perf = nil
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    local start = ns.perf and clock()
    for i = 1, #list do SafeCall(list[i], event, ...) end
    if start then Timed(event, start) end
end)

---------------------------------------------------------------------------
-- Internal callbacks (e.g. "LEDGER_UPDATED")
---------------------------------------------------------------------------
local callbacks = {}
function ns:Register(name, fn)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], fn)
end

function ns:Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    local start = ns.perf and clock()
    for i = 1, #list do SafeCall(list[i], ...) end
    if start then Timed("(GoblinBooks) " .. name, start) end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local MIGRATIONS = {
    -- 2: GoblinBooks replaces the Blizzard AH window by default.
    [2] = function(db) if db.settings then db.settings.ahReplace = true end end,
    -- 3: drop "Changed while offline" entries booked by the logout bug (gold read as 0 while logging out,
    -- so the next login counted the whole balance again), and forget the bad saved balance.
    [3] = function(db)
        for _, c in pairs(db.chars or {}) do
            local kept = {}
            for _, e in ipairs(c.entries or {}) do
                if e.n == "Changed while offline" then
                    if c.daily then ns.Ledger.AddDaily(c, e.t, e.c, -e.a) end
                else
                    kept[#kept + 1] = e
                end
            end
            c.entries = kept
            if c.lastMoney == 0 then c.lastMoney = nil end
        end
    end,
    -- 4: several AH sale mails taken at once arrive as one gold change, which matched no single mail and
    -- was booked as "Mail received" (no sender). Those landed within a minute of other AH sales: move
    -- them to AH sales. (Which items they were can't be recovered.)
    [4] = function(db)
        for _, c in pairs(db.chars or {}) do
            local list = c.entries or {}
            for idx, e in ipairs(list) do
                if e.c == "mail_in" and e.a > 0 and not e.s and not e.n then
                    local nearSale = false
                    for j = math.max(1, idx - 30), math.min(#list, idx + 30) do
                        local o = list[j]
                        if o.c == "ah_sale" and math.abs(o.t - e.t) <= 60 then nearSale = true break end
                    end
                    if nearSale and c.daily then
                        ns.Ledger.Reclassify(c, e, "ah_sale", nil, "Auction sales (several mails at once)")
                    end
                end
            end
        end
    end,
    -- 5: daily AH results (char.ahDaily) for the AH profit chart, rebuilt from the ledger's raw entries.
    [5] = function(db)
        for _, c in pairs(db.chars or {}) do ns.CostBasis.BackfillDaily(c) end
    end,
}

local function NewChar()
    return { entries = {}, daily = {}, lots = {}, flips = {}, nameToID = {}, awaiting = {}, heldBids = {}, ahDaily = {} }
end

function ns:EnsureChar(c)
    c = c or NewChar()
    for k, v in pairs(NewChar()) do
        if c[k] == nil then c[k] = v end
    end
    return c
end

function ns:InitDB()
    GoblinBooksDB = GoblinBooksDB or {}
    local db = GoblinBooksDB
    db.version = db.version or ns.VERSION
    for v = db.version + 1, ns.VERSION do
        if MIGRATIONS[v] then MIGRATIONS[v](db) end
        db.version = v
    end
    db.chars = db.chars or {}
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    ns.db = db
end

function ns:InitChar()
    local name, realm = UnitFullName("player")
    realm = realm or GetNormalizedRealmName() or GetRealmName()
    local key = realm .. "-" .. name
    local c = ns:EnsureChar(ns.db.chars[key])
    c.class = select(2, UnitClass("player"))
    ns.db.chars[key] = c
    ns.char, ns.charKey, ns.realm = c, key, realm
end

--- Characters in the current UI scope: list of { key = "Realm-Name", char = table }.
function ns:ScopeChars()
    local out = {}
    if ns.db.settings.accountView then
        for key, c in pairs(ns.db.chars) do out[#out + 1] = { key = key, char = c } end
        table.sort(out, function(a, b) return a.key < b.key end)
    elseif ns.char then
        out[1] = { key = ns.charKey, char = ns.char }
    end
    return out
end

function ns:AllCharTables()
    local out = {}
    for _, c in pairs(ns.db.chars) do out[#out + 1] = c end
    return out
end

function ns:ScopeCharTables()
    local out = {}
    for i, sc in ipairs(ns:ScopeChars()) do out[i] = sc.char end
    return out
end

ns:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    ns:InitDB()
end)

ns:On("PLAYER_LOGIN", function()
    ns:InitChar()
    local removed = ns.Ledger.Prune(ns.char, ns.db.settings.retentionDays, time())
    if removed > 0 and ns.db.settings.debug then
        ns:Print(("pruned %d old ledger entries"):format(removed))
    end
    ns.Money:Start()
    ns:Fire("READY")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
    "/gb - toggle the GoblinBooks window",
    "/gb debug - toggle printing every gold change",
    "/gb reconcile - compare the session ledger with your actual gold",
    "/gb export - export the ledger as CSV",
    "/gb options - open settings",
    "/gb prune - prune old raw entries now",
    "/gb resetwindow - move the windows back to their default position and size",
    "/gb cut - show the AH cut measured from your sale mails",
    "/gb minimap - show or hide the minimap button",
    "/gb deposit - is the WoW Forever 1s minimum-deposit bug still happening?",
    "/gb perf - time what GoblinBooks does (type it, do the slow thing, type it again)",
    "/gb scanlog - what happened during the last AH scans (requests, data, timeouts)",
    "/gb postlog - your recent AH posts and what the server did with them (listed, error, no answer)",
    "/gb reset confirm - wipe this character's data",
}

SLASH_GOBLINBOOKS1 = "/gb"
SLASH_GOBLINBOOKS2 = "/goblinbooks"
SlashCmdList.GOBLINBOOKS = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" then
        ns.UI:Toggle()
    elseif cmd == "debug" then
        ns.db.settings.debug = not ns.db.settings.debug
        ns:Print("debug " .. (ns.db.settings.debug and "on" or "off"))
    elseif cmd == "reconcile" then
        ns.Money:Reconcile()
    elseif cmd == "export" then
        ns.UI:ShowExport()
    elseif cmd == "options" or cmd == "config" then
        ns:OpenOptions()
    elseif cmd == "minimap" then
        ns.db.settings.minimapButton = not ns.db.settings.minimapButton
        ns.UI:UpdateMinimapButton()
        ns:Print("minimap button " .. (ns.db.settings.minimapButton and "shown" or "hidden"))
    elseif cmd == "deposit" then
        local c = ns.db.depositCheck
        if not c then
            ns:Print("no small-deposit posts checked yet; assuming the WoW Forever bug (deposits under 1s are charged 1s).")
        elseif c.last == "bug" then
            ns:Print(("minimum-deposit bug still active: last check estimated %s, charged %s (%s)."):format(
                ns.Util.FormatMoney(c.estimate), ns.Util.FormatMoney(c.actual), ns.Util.Ago(c.t)))
        else
            ns:Print(("minimum-deposit bug looks fixed: last check estimated and charged %s (%s)."):format(
                ns.Util.FormatMoney(c.actual), ns.Util.Ago(c.t)))
        end
    elseif cmd == "cut" then
        local CB, U = ns.CostBasis, ns.Util
        local s = CB.CutStats(ns.db)
        if not s.rate then
            ns:Print(("no AH sales recorded yet; estimates assume a %s cut. Collect a sale mail and check again."):format(CB.CutLabel(CB.DEFAULT_CUT)))
        elseif s.cut == 0 then
            ns:Print(("no AH cut is being taken: %d sales, %s revenue, 0 cut."):format(s.sold, U.FormatMoney(s.revenue)))
        else
            ns:Print(("AH cut is %.2f%% (%s of %s across %d items sold)."):format(s.rate * 100, U.FormatMoney(s.cut),
                U.FormatMoney(s.revenue), s.sold))
            if s.samples > 0 then
                ns:Print(("per-sale range over the last %d sale mails: %.2f%% to %.2f%%"):format(s.samples, s.lo * 100, s.hi * 100))
            end
        end
    elseif cmd == "resetwindow" then
        ns.db.settings.window = {}
        ns.db.settings.ahWindow = nil
        ns:Print("window positions reset (main window after /reload, auction house window next time you open it)")
    elseif cmd == "perf" then
        ns:PerfToggle()
    elseif cmd == "scanlog" then
        local log = ns.db.scanLog or {}
        if #log == 0 then ns:Print("no scans logged yet") end
        for i = math.max(1, #log - 14), #log do
            local e = log[i]
            ns:Print(("%s  %s%s"):format(date("%H:%M:%S", e.t), e.e, e.d and ("  |cff8c94a3" .. e.d .. "|r") or ""))
        end
    elseif cmd == "postlog" then
        if ns.UI.PrintPostLog then ns.UI.PrintPostLog() else ns:Print("open the auction house once first") end
    elseif cmd == "prune" then
        local n = ns.Ledger.Prune(ns.char, ns.db.settings.retentionDays, time())
        ns:Print(("pruned %d entries"):format(n))
    elseif cmd == "reset" then
        if rest == "confirm" then
            ns.db.chars[ns.charKey] = nil
            ns:InitChar()
            ns:Fire("LEDGER_UPDATED")
            ns:Print("character data wiped")
        else
            ns:Print("type '/gb reset confirm' to wipe this character's data")
        end
    else
        for _, line in ipairs(HELP) do ns:Print(line) end
    end
end

---------------------------------------------------------------------------
-- Addon compartment (minimap addon menu)
---------------------------------------------------------------------------
function GoblinBooks_OnAddonCompartmentClick()
    ns.UI:Toggle()
end

function GoblinBooks_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button or MinimapCluster, "ANCHOR_LEFT")
    GameTooltip:AddLine("GoblinBooks")
    if ns.Money and ns.Money.sessionStart then
        GameTooltip:AddDoubleLine("This session", ns.Util.FormatMoney(ns.Money.session, true), 1, 1, 1)
    end
    GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function GoblinBooks_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
