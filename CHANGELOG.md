# Changelog

## 0.8.2
- Ledger fix: the Unrealized total counted a stack's price once instead of for every item in it (a 150-stack priced at 1s98c each counted as 1s98c, not 2g97s), so it came out far too low. Stacks are now priced per item times the quantity, and item names show correctly.
- Ledger fix: gold mailed between your own characters is now always recognized as a transfer (not income and not spending). It no longer depends on the game call that sets the gold, the receiving character now books it too, and gold already recorded as mail in and mail out is paired up and corrected once.
- Ledger fix: auction deposits are matched to the auctions being created, so a slow posting no longer shows up as "AH purchases".
- Ledger: new "Unrealized: listed, not sold yet" section. For each character it shows how many auctions you have up, their total asking price and an estimate after the AH cut, any sold items whose gold is still in the mail, and your biggest listings. It updates every time you open the auction house.
- Crafts: new "Buy up to" column and tooltip section. Walks each material up the AH price ladder from your last scan and tells you how many crafts you can buy materials for before the next one stops paying (and how much of each material, at what top price, and the total profit). Notes when the AH simply runs out of a material.
- Search: partial words and any word order now match, with the best name matches listed first.

## 0.8.1
- Ledger character dropdown now shows "Name - Realm", so same-named characters on different realms are told apart.

## 0.8.0
- New gold ledger: Profiteer now tracks every copper in and out, across all your characters, by source. Coming in: AH sales, returned deposits, vendor sales, quest rewards, looted coin, mail gold. Going out: AH deposits, the AH cut, AH purchases, vendor purchases, repairs, postage/COD, training, flights.
- Overhead and net profit are worked out for you (deposits kept after refunds + sale fees + repairs + flights + training).
- Also tracked: trades, bank slot purchases, gold mailed between your own characters and guild bank deposits/withdrawals (shown as "moved", not earned or spent), a best-sellers list from your sale invoices, gold on hand per character, gold per hour for the session, and a check that tells you if any change in your gold isn't explained by the ledger.
- The ledger is a tab in the Profiteer window (Crafts | Ledger): today / 7 days / 30 days / all time, per character or all, headline numbers, income and spending by source with percentages, an auction house breakdown (sales made, average sale, fees, deposits lost), overhead, best sellers, per character, per day, gold on hand and the cross-check. `/pf ledger [today|week|month|all]` opens it; `/pf ledger text` gives a copyable version; `/pf ledger reset` clears it.
- Ledger fixes: gold on hand no longer drops to 0 for characters you log out on; the headline is now "Net cash flow" with a "net before buying stock" line; unsold listings' deposits are shown as "not returned yet"; `/pf ledger log` lists the last recorded changes and what each was filed under.
- Search box on the Crafts tab: type part of a craft, material, profession or character name. Adding a new file: restart the game once.

## 0.7.9
- Items a vendor sells are now costed at the vendor price (even when an Auction House listing is cheaper, since vendor stock is unlimited) and are left out of the AH search when you click a craft. Vendor prices are learned whenever you open a vendor that sells the item in unlimited stock; the tooltip shows "Vendor buy price".

## 0.7.8
- Windows no longer bleed through each other: clicking a Profiteer window raises it, with its text and rows, above other addon windows (Baggie, etc.).

## 0.7.7
- Clicking a craft now searches for the finished item as well as its materials.

## 0.7.6
- The Profiteer window no longer closes when you click a craft to search the AH, so you can keep clicking down the list.

## 0.7.5
- Crafts that lose money are shown again (they were hidden because the minimum profit was 0). New "Hide money-losing" checkbox; `/pf minprofit` turns it on.

## 0.7.4
- Crafts with no AH price (nothing listed, reagent price missing) are no longer hidden: they show at the bottom of the list in grey with a "-" for profit, and the tooltip says why they are not ranked. The header counts priced and unpriced crafts.

## 0.7.3
- Release packaging: Wago upload fix.

## 0.7.2
- Release packaging fix: the Wago upload now runs from GitHub.

## 0.7.1
- The Profiteer window now opens beside the Auction House instead of on top of it, and can be dragged anywhere; it remembers where you put it (/pf ahbutton resets button and window).
- The AH "Profiteer" button drags more reliably (left or right button) and sits above the other AH widgets.

## 0.7.0
- Every craft now counts its materials both ways. A bar can be bought or smelted from ore, cloth bolts can be bought or made from cloth: whichever is cheaper is the cost used for the craft's profit, and the tooltip shows "or buy" with the ore/cloth prices and whether it beats the bar.
- Clicking a craft searches the AH for the bar and the ore (Handful of Copper Bolts: Copper Bar, Copper Ore), including crafts several steps deep (Bronze Bar: Copper Ore, Tin Ore).
- Works for any intermediate your characters' recipes make, plus a built-in list of the common bars and bolts.

## 0.6.3
- Fixed click-through searching for the wrong item name. Profiteer was saving a recipe's name as the item's name, so crafts that use smelted bars searched for "Smelt Copper" instead of "Copper Bar". It now uses the game's real item names everywhere, and repairs names saved by earlier versions on the first login.
- `/pf why` and `/pf track` still find a craft by its recipe name (for example "smelt copper").

## 0.6.2
- The TOC now carries the Wago project ID, so the Wago app recognizes a manually installed copy of Profiteer and offers updates for it.

## 0.6.1
- The addon now lists only Forever's interface numbers (16001 to 16003), so the addon list and Wago no longer show a Retail version.

## 0.6.0
- Work from a craft straight to its materials. In the results window: **click** a row to search the Auction House for that craft's materials, **shift-click** to search for the finished item, **right-click** to track it. Searches go to Auctionator's Shopping list when it is installed, otherwise to the Auction House's own search bar, otherwise to a copyable list of names.
- Tracked crafts are pinned to the top of the list with a gold `*` and ignore the minimum-profit and minimum-listings filters.
- New **Shop top 10** and **Shop tracked** buttons send the materials for several crafts at once.
- New `/pf shop [tracked]` and `/pf track <craft>` commands.

## 0.5.8
- `/pf top` and `/pf chars` now open in a copyable window too. `/pf top` lists the top 25 crafts with who can make each, cost, net sale price, profit, ROI, listings and sales per day.

## 0.5.7
- `/pf missing` and `/pf why <craft>` now open in a copyable window (Ctrl+C, scroll with the mouse wheel) instead of printing to chat.
- `/pf missing` also shows each skipped craft's material cost and vendor sell price where known, sorted alphabetically.

## 0.5.6
- New `/pf missing` command lists the crafts left out of the ranking for lack of prices, and why (nothing listed for the finished item, or which reagent has no price).
- Thin markets are easier to spot: a Listed count under 10 now shows in orange.

## 0.5.5
- Pressing Scan too soon after the last full scan no longer leaves the window waiting on a request Blizzard will ignore. It now says how long until the next scan is allowed. `/pf scan force` tries anyway.

## 0.5.4
- Reagent costs now ignore a lone lowball listing. If the cheapest listing is less than half the next-cheapest price, the reagent is costed at the reference price instead.
- Hover tooltips in the results window open on whichever side has room, so they no longer run off the edge of the screen.

## 0.5.3
- New `/pf why <craft>` command: shows how one craft's material cost and sale price were worked out, including every item option for each reagent. Useful for checking a number that looks wrong.

## 0.5.2
- Fixed prices being read per stack instead of per unit. Stacked items (cloth, herbs, ammo, bolts) were inflated by their stack size. Old price data is cleared automatically.
- Items with fewer than 3 units listed are now hidden by default, since a single listing is not a market price. Change it with `/pf minlisted <n>`.
- The results window now has a solid background, so nameplates and world text no longer show through the rows.

## 0.5.1 (first public beta)
- Ranks every craft your characters know by profit and ROI, using auction prices and vendor prices.
- Works across all characters on the account, with per-character "can craft now" counts from bags and bank.
- Automatic full Auction House scan when the AH opens, read out in small slices so the game never hitches.
- Price history, market median and trend, and estimated sales per day.
- Item tooltips with auction price, listings, median, trend and vendor price.
- Profiteer button on the Auction House window, plus a draggable minimap button.
- `/pf report` and `/pf errors` for diagnostics.
- Not included yet: buying and posting from inside the addon.
