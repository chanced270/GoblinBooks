-- Ledger categories and the chart groups they roll up into.
local _, ns = ...
local C = {}
ns.Categories = C

-- Ordered chart groups. Colors chosen to stay distinguishable on a dark background.
C.groups = {
    { key = "loot",     label = "Loot",          color = { 0.96, 0.76, 0.19 } },
    { key = "quest",    label = "Quests",        color = { 0.36, 0.62, 0.98 } },
    { key = "ah",       label = "Auction House", color = { 0.22, 0.80, 0.74 } },
    { key = "vendor",   label = "Vendor",        color = { 0.47, 0.80, 0.38 } },
    { key = "repair",   label = "Repairs",       color = { 0.88, 0.34, 0.30 } },
    { key = "mail",     label = "Mail",          color = { 0.70, 0.53, 0.94 } },
    { key = "trade",    label = "Trade",         color = { 0.95, 0.55, 0.76 } },
    { key = "services", label = "Services",      color = { 0.98, 0.58, 0.24 } },
    { key = "bank",     label = "Bank transfers", color = { 0.55, 0.63, 0.72 }, transfer = true },
    -- Gold held by the AH for open bids. Never income or spending: it's still yours until you win.
    { key = "held",     label = "AH bids (held)", color = { 0.45, 0.50, 0.58 }, neutral = true },
    { key = "other",    label = "Other",         color = { 0.60, 0.60, 0.60 } },
}

C.groupByKey = {}
for i, g in ipairs(C.groups) do
    g.order = i
    C.groupByKey[g.key] = g
end

C.cats = {
    loot        = { label = "Looted gold",      group = "loot" },
    quest       = { label = "Quest",            group = "quest" },
    vendor_sell = { label = "Vendor sale",      group = "vendor" },
    vendor_buy  = { label = "Vendor purchase",  group = "vendor" },
    repair      = { label = "Repair",           group = "repair" },
    ah_sale     = { label = "AH sale",          group = "ah" },
    ah_buy      = { label = "AH purchase",      group = "ah" },
    ah_deposit  = { label = "AH deposit",       group = "ah" },
    mail_in     = { label = "Mail received",    group = "mail" },
    mail_out    = { label = "Mail sent",        group = "mail" },
    postage     = { label = "Postage",          group = "mail" },
    trade_in    = { label = "Trade received",   group = "trade" },
    trade_out   = { label = "Trade given",      group = "trade" },
    flight      = { label = "Flight",           group = "services" },
    training    = { label = "Training",         group = "services" },
    transmog    = { label = "Transmog",         group = "services" },
    barber      = { label = "Barber",           group = "services" },
    guildbank   = { label = "Guild bank",       group = "bank" },
    warbank     = { label = "Warband bank",     group = "bank" },
    ah_bid      = { label = "AH bid held",      group = "held" },
    other       = { label = "Other",            group = "other" },
}

function C.Group(cat)
    return (C.cats[cat] or C.cats.other).group
end

function C.Label(cat)
    return (C.cats[cat] or C.cats.other).label
end

function C.GroupInfo(groupKey)
    return C.groupByKey[groupKey] or C.groupByKey.other
end

--- Neutral categories are excluded from income, spending, and charts no matter the settings.
function C.IsNeutral(cat)
    local g = C.groupByKey[C.Group(cat)]
    return g and g.neutral or false
end

function C.IsTransfer(cat)
    return C.GroupInfo(C.Group(cat)).transfer == true
end
