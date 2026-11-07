# GoblinBooks changelog

## 0.1.1

### Fixed
- Full scan no longer shows **Failed** when the server is slow to answer. A big auction house can take over a minute before the data starts arriving; the scan used to give up after 60 seconds and ignore the data when it came. It now waits up to 3 minutes (the Scan button shows how long), and still uses data that arrives after that.
- Closing the auction house while a scan is waiting now ends it with a clear message.

## 0.1.0 — First release

### Gold ledger
- Records every gold change and attributes it to its source: looted gold, quests, vendor sales and purchases, repairs, auction house, mail, trade, flights, trainers, transmog, barber, and guild/warband bank. Anything it can't attribute goes to **Other**.
- The ledger always adds up to your actual gold; `/gb reconcile` shows the check.
- **Summary** tab: today, last 7 and 30 days, all-time AH profit, top source and net worth, plus income and spending by source.
- **Charts**: daily stacked bars (income above the zero line, spending below) and a net worth history.
- **Ledger** tab with every entry, and CSV export (`/gb export`).
- AH bids are held, not spent; outbid refunds aren't counted as income.
- Account-wide view of all your characters, or just the current one.

### Auction house
- A large, resizable auction window with **Buy**, **Sell**, **Auctions**, **Flips** and **Deals** pages, or docked beside the standard window.
- **Real profit per sale**: each item's purchase cost (FIFO, from AH or vendor buys) is matched against the sale, after the AH cut and deposits. Crafting moves reagent costs into what you make.
- **Sell**: your bag items with their market value, a suggested undercut price, deposit, what you keep after the cut, profit against your cost and the vendor comparison; post in one click.
- **Auctions**: undercut detection (**Check prices**), P/L if everything sells, cancel, bids with one-click re-bid, and when sold gold will reach your mailbox.
- **Buy**: search by name and category, favorites, a warning when a listing is well above the 7-day average, commodity purchases with a price quote and confirmation.
- **Price history** from every search and browse, a **full scan** (once every 15 minutes) with its progress on the Scan button, and price charts over 14, 30 or 60 days.
- **Flips**: items listed well below their usual price.
- **Deals**: watches your list (plus favorites and shopping-list reagents) and alerts you when something is listed under your limit.
- Sell-through for your own auctions, and an estimate of market activity for everything else.
- The AH cut is measured from your own sale mails (`/gb cut`).

### Crafting
- Saves your recipes when you open a profession window, for all your characters.
- Profit per craft: reagent cost (cheapest of AH and vendor) against what the result sells for.
- **Shopping list**: queue crafts and see what you still need, what you and your alts already have, and where to buy it.

### Characters and net worth
- Remembers what each character carries in bags and bank, plus the warband bank.
- Net worth for the realm: gold plus items, valued at AH or vendor price.

### Quality of life
- Item tooltips: vendor and AH prices, 7-day average, what you own and what your alts hold. Hold Shift to price every stack in your bags.
- Shift-click a vendor item to buy a full stack, with one confirmation.
- Minimap button and addon compartment entry.
- `/gb perf` times what GoblinBooks is doing, for tracking down slowdowns.

### Known limits
- Gold that changes while GoblinBooks isn't running is booked at the next login as *Other: Changed while offline*.
- Items you looted or crafted from unrecorded materials have no cost, so they count as free (marked `*`).
- Other players' sales aren't visible to addons, so market activity is an estimate.
- If two gold changes happen at the same moment, one may be filed under the other's category. The amount is always right.
