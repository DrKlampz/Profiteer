# Profiteer

Find out which crafts actually make money. Profiteer reads the recipes your characters know, prices the materials and the finished item from the Auction House, and ranks every craft by profit and return on investment, across **all** of your characters.

Built for **WoW Forever** (beta client 1.60.x).

## What it does

- **Ranks your crafts.** For every recipe any of your characters knows: material cost (auction price, or the vendor price if that's cheaper) against what the finished item sells for after the auction cut. Shows profit, ROI, how many are listed, and how many you can craft right now from your bags and bank.
- **Click through to the materials.** In the results window, click a craft to search the Auction House for its materials (through Auctionator's Shopping list if you have it), shift-click to search for the finished item, and right-click to track a craft so it stays pinned at the top.
- **Works across your whole account.** One window lists each craft once, with every character who can make it.
- **Scans automatically.** Opens the Auction House, takes one full scan in the background without hitching the game, and refreshes whenever the data is stale.
- **Price history and sales estimates.** Every scan adds a snapshot, so you get a market median, a trend, and an estimated sales-per-day figure for the items you craft.
- **Item tooltips.** Lowest auction price, listing count, market median and trend, and vendor price on any scanned item.
- **Lives in the Auction House.** A Profiteer button on the Auction House window opens the ranking over it. There is also a minimap button.

## Install

Put the `Profiteer` folder in your WoW Forever `Interface/AddOns` folder. If the addon shows as out of date, tick "Load out of date AddOns" on the character select screen.

## First run

1. Log in and open each profession window once on each character. Profiteer records the recipes.
2. Open the Auction House. It scans automatically (or use `/pf scan`).
3. Type `/pf` to see the ranking. Hover a row for the full breakdown.

Bank contents are counted after you open your bank once.

## Commands

| Command | What it does |
|---|---|
| `/pf` | Open or close the ranking window |
| `/pf scan` | Full Auction House scan (AH must be open). Limited to about one per 15 minutes; `/pf scan force` tries anyway |
| `/pf shop [tracked]` | Send the materials for the top 10 (or your tracked) crafts to the AH search |
| `/pf track <craft>` | Pin or unpin a craft at the top of the list |
| `/pf top` | Copyable list of the top 25 crafts |
| `/pf chars` | Copyable list of every character Profiteer knows, with recipe counts and bag age |
| `/pf forget <name>` | Remove a character's data |
| `/pf cut <percent>` | Auction house cut used in the profit math (default 5) |
| `/pf minprofit <gold>` | Hide crafts below this profit |
| `/pf minlisted <n>` | Hide items with fewer than n units listed (default 3) |
| `/pf minsales <n>` | Hide crafts estimated to sell fewer than n per day |
| `/pf basis safe\|current` | Sell price basis: the lower of today's price and the recent median, or today's price only |
| `/pf autoscan on\|off` | Scan automatically when the Auction House opens |
| `/pf ahopen on\|off` | Open the Profiteer panel automatically with the Auction House |
| `/pf tooltip` | Turn item tooltip info on or off |
| `/pf minimap` | Show or hide the minimap button (`radius <n>` and `reset` adjust it) |
| `/pf missing` | Copyable list of crafts left out for lack of prices, with material cost and vendor sell price |
| `/pf why <craft>` | Copyable breakdown of how one craft's cost and price were worked out |
| `/pf report` | Copyable diagnostic report for bug reports |
| `/pf errors` | Show any captured errors |
| `/pf reset prices` | Clear price data and history |

## Things to know

- Recipes are only captured when you open that profession's window on that character.
- Enchanting and other crafts that don't produce a sellable item are skipped.
- The profit math does not include auction deposits or the value of your time. A high ROI can still be a slow seller, so watch the listing count and sales-per-day columns.
- The sales-per-day figure is an estimate from listings that disappear between scans; it needs a few scans over a day or so, and cancelled listings look like sales.
- Buying and posting are not included.
- Blizzard limits full auction scans to about once every 15 minutes.

## Reporting a problem

Type `/pf report`, press Ctrl+C, and paste the text into your bug report.
