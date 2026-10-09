# Changelog

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
