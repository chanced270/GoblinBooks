# GoblinBooks

A World of Warcraft (WoW Forever / Mainline API) addon that keeps a gold ledger:

- **Where gold comes from and goes:** looted gold, quests, vendor sales and purchases, repairs, auction house, mail, trade, flights, trainers, transmog, barber, and guild/warband bank. Anything it can't attribute goes to **Other**.
- **Auction house profit/loss with cost basis:** each item's FIFO purchase cost (from AH or vendor buys) is matched against the sale invoice. Crafting carries cost forward: the recorded cost of the reagents you use moves into what you craft (e.g. bought Linen Cloth into Bolts of Linen Cloth), so selling crafted items shows the real profit. Profit = sale − AH cut − cost − deposits (+ refunded deposits).
- **Crafting profit calculator:** open a profession window and GoblinBooks saves your known recipes, for all your characters. The **Crafting** tab shows each recipe's reagent cost, what the result sells for, profit and margin, plus the market-activity estimate for the result. Reagent cost uses the cheapest of the AH market price and the vendor price (recorded when you visit merchants). The result's value is the better of the AH, after your measured cut, or the vendor. Reagents without a price are flagged. Click a reagent to open it on the AH Buy tab while the auction house is open. **Shopping list:** pick a recipe, enter how many crafts, and click **Add to shopping list**. The **Shopping list** view adds up the reagents and shows need, have (bags and bank), what's still missing, and the cheapest source. On the AH Buy page, the **Shopping** button lists what's still missing; clicking an item opens it with the missing quantity filled in.
- **Buy a full stack at vendors:** shift-left-click an item at a vendor to get a confirmation for a full stack instead of the small quantity box. It shows the price each, the total, and caps the amount to what you can afford and what the vendor has (rounded to the vendor's bundle size, e.g. arrows sold in 200s). Change the amount or click **Max**, then **Buy** (or Enter); Escape cancels. Items bought with currencies or tokens keep the standard behavior; shift-click with the chat box open still links the item. Turn it off in Options.
- **Tooltips:** vendor and AH prices, and AH vs vendor, for items. Junk (gray) items are flagged "sell to a vendor" instead, since they rarely sell on the AH; the Sell page, AH Prices tab and GoblinTrades do the same, and Flips skips them. Hold **Shift** over an item in your bags to see the totals for every stack of it you're carrying.
- **Alts and net worth:** GoblinBooks remembers what each character has in its bags, and in its bank (including reagent bank and bank tabs) as of the last bank visit, plus the warband bank. Item tooltips show **Owned** (bags, bank, warband) and **Alts** counts; the crafting shopping list has an **Alts** column ("mail them over"). The Summary tab's **Net worth** tile adds every realm character's gold to everything they own, valued at the AH price after your cut or the vendor price when better (junk and soulbound items at vendor price); hover it for the breakdown and most valuable stacks. Charts has a **Net worth** view with a daily history.
- **Deals watcher:** the AH window's **Deals** tab keeps searching your watch list (items you **Watch** on the Buy tab, plus favorites and shopping-list reagents if enabled) about once a second, and lists listings at or under your limit: a max price per item, or by default 70% of the usual price (Options). It plays a sound for new deals. One big **Buy** button buys the selected deal: commodities get a price quote first and a confirm click (a quote above your limit is refused); other items take two clicks. Purchases are recorded as cost as usual. The server limits searches, so a cycle over 30 items takes about 30-60 seconds; there's no way to see new listings the instant they're posted.
- **Charts:** a daily stacked bar chart (income above the zero line, spending below), plus income and spending share bars and a summary dashboard.
- **Auction house panel:** replaces the standard AH window with a large window that you can move (drag the header) and resize, and that has **Buy | Sell | Auctions** tabs. Click **Dock** to show it as a side panel next to the Blizzard window instead, or **Expand** to go back. In the full window, selecting an item on Buy or Sell shows a price chart over time: the daily lowest price over 14, 30 or 60 days, with the average and the vendor price. A **Listings** toggle switches it to the cheapest current listings and their quantities. It lists the sellable items in your bags with their market value. Pick one to see the current listings and a suggested undercut price, plus the total listing price, deposit and return (total minus deposit), what you keep if it sells (after the AH cut, which is measured from your sale mails; check it with `/gb cut`. The deposit is refunded on a sale), profit against your cost basis, and the comparison with vendoring. Then post it in one click. If the deposit is more than the listing is worth, the Post button turns red and asks for a second click. The **Auctions** page lists your auctions and flags any that have been undercut (**Check prices** searches each one). Each auction also shows its **P/L** if it sells at its price: what you keep after the AH cut minus your recorded cost (deposits aren't counted since a sale refunds them; items with no recorded cost are marked `*` and count as free), with a total for everything listed. Sold auctions show how long until their gold reaches the mailbox ("Sold · 42m", then "in mail"); the main window shows the gold on its way under gold on hand, and chat tells you once it should have arrived. The delay is the auction's own countdown when the client gives one, otherwise learned from your sale mails (1 hour until then). A sale is only spotted when your auctions list shows it, i.e. at the auction house. You can cancel an auction from there. The **Buy** page searches the AH by name and/or **category and subcategory**. Star an item to add it to your **Favorites**: the Favorites button lists them, and clicking one loads its current listings. In the main window, **AH Prices** has a Favorites-only filter and an **Open in AH** button that jumps to the item on the Buy tab while the AH is open. The Buy page also compares each listing with the item's 7-day average, warning you when a price is well above it. It buys commodities by quantity, using the server's exact price quote and a confirm click, and other items by picking a listing and clicking twice. What you pay is recorded as cost basis for profit tracking. For non-commodity auctions you can also **bid**. The Auctions page has a **Bids** view that shows whether you are winning or outbid, with a one-click minimum re-bid. **Sell-through (exact):** for your own auctions, GoblinBooks tracks what you posted and how it ended (sold, expired or cancelled, from the mailbox) and how long items take to sell. It shows on the Sell page and in the Auction P/L tab. **Market activity (estimate):** other players' sales aren't visible, so the addon estimates them from drops in the listed quantity between complete counts (Scans, browse searches, fully loaded item searches). That count includes expired and cancelled auctions, so it's labeled an estimate everywhere (Prices tab, charts, Sell page, Flips). **Flips:** the Flips tab lists items whose current lowest price is well below their usual daily low (median of the previous 14 days). Buying them and relisting near the usual price should clear your chosen margin after the AH cut. Click one to open it on the Buy tab and check how many are actually that cheap. **Full scan** records the lowest price of every item on the AH (the server allows one every 15 minutes). While it runs, the Scan button shows the percentage with a progress bar under it (hover it for the details and the last scan's result).
- **AH price history:** every browse or search you do, in the GoblinBooks panel or the Blizzard UI, is recorded per realm: the latest lowest price plus a daily low. You can view it in the **AH Prices** tab (search box and 30-day chart). Item tooltips show the vendor price and, for tradeable items, the AH lowest price and 7-day average.

- **Bids are not spending, and outbid refunds are not income.** Gold you bid is filed under *AH bids (held)*, which never counts as income or spending in the summary or charts. If you are outbid, the returned gold releases the hold. If you win, the held amount becomes an *AH purchase* when you collect the item from the mailbox.

## How it works

Every `PLAYER_MONEY` change is recorded as ledger entries that **sum exactly to the delta**, so the ledger always reconciles with your actual gold. Each change is attributed in this order:

1. **Expectations from API hooks**, e.g. `RepairAllItems`, `TakeInboxMoney` with a sale invoice, `C_AuctionHouse.ConfirmCommoditiesPurchase`, `SendMail`. These carry item and amount detail.
2. **The most recently opened window or interaction** (merchant, mailbox, AH, trade, taxi, ...). It lingers for a moment after closing, because gold often arrives late.
3. **Other.**

When attribution arrives after the gold itself (`QUEST_TURNED_IN`, group-loot `CHAT_MSG_MONEY`), the matching *Other* entry gets reclassified. Chat text is never parsed.

## Install

Install from CurseForge, or copy the `GoblinBooks` folder into `World of Warcraft/_forever_/Interface/AddOns/`. Optional companions: GoblinTrades (gathering and gold per hour) and GoblinClass (class coach); GoblinUI is not required.

## Usage

| Command | |
|---|---|
| `/gb` | Toggle the window (or click the minimap button, or use the addon compartment) |
| `/gb minimap` | Show or hide the minimap button (left-click opens, right-click settings, drag to move) |
| `/gb debug` | Print each gold change and its category |
| `/gb reconcile` | Session ledger vs. actual gold, plus the unattributed amount |
| `/gb export` | Export the ledger as CSV (copy out of the game) |
| `/gb deposit` | Whether the WoW Forever minimum-deposit bug (deposits under 1s charged 1s) is still happening, from your own posts |
| `/gb cut` | Show the AH cut measured from your sale mails, with the per-sale range |
| `/gb perf` | Times what GoblinBooks does: type it, do the slow thing (open the AH, scan...), type it again for the slowest events |
| `/gb resetwindow` | Move the windows back to their default position and size (main window after `/reload`, AH window next time it opens) |
| `/gb options` | Settings: account view, bank transfers in charts, retention |
| `/gb reset confirm` | Wipe this character's data |

Raw entries are kept for 90 days by default; daily totals (used by the charts) are kept forever.

## Known limits

- Gold that changes while GoblinBooks isn't running (addon disabled, another tool) is booked at the next login as *Other: Changed while offline*, so the ledger always matches your gold.
- Items you looted or crafted have no recorded cost, so they count as free. The AH table marks them with `*`.
- Non-commodity AH purchases get their cost basis when you collect the purchase mail.
- If two money sources fire at the same moment, one may be attributed to the other's window. The amount is always correct; only the category can be off.

## Development

Run the tests (non-UI modules against WoW API stubs, plain Lua 5.1+) from the repo root:

```
lua tests/run.lua
```

GitHub runs them on every push. `Libs/GoblinTheme.lua` is the shared GoblinBooks theme; its master copy lives in GoblinUI, and the workspace's `tools/deploy.ps1` keeps the copies in sync.

## Releasing

1. Add a section for the new version at the top of `CHANGELOG.md`.
2. Commit, then tag and push: `git tag v0.1.1` and `git push --follow-tags`.

The **Release** workflow runs the tests, builds the zip with the BigWigs packager (the version comes from the tag through `@project-version@` in the TOC) and uploads it to CurseForge with the changelog. It needs the repo secret `CF_API_KEY` and the `## X-Curse-Project-ID:` line in `GoblinBooks.toc`.
