# Changelog

## 0.12.44

- Fixed the sale sound always playing the game's vendor coin sound whatever you picked: when the game did not confirm a sound file had played, Profiteer assumed it failed and played the fallback instead

## 0.12.43

- Fixed "<character> no longer has Cooking, so those recipes were removed" appearing for a profession the character still has: when a section of the skills list was collapsed, its skills were counted as missing. Now Profiteer skips the check when the list is incomplete, and only removes a profession after it is missing twice in a row 30 seconds apart (the game's list is sometimes briefly wrong)

## 0.12.42

- Changed: the Plan tab now shows how much of each made material you need in all and how much of that you already have, and what one craft uses. For 37 Copper Modulators: 74 bolts use 74 bars, plus 37 bars in the craft, 111 bars in all, of which you smelt only what you do not already hold

## 0.12.41

- Changed: the window the minimap button opens now shows only the Crafts, Shopping and Ledger tabs. Plan and Cancelling are in the auction house tabs. Clicking a craft in that window fills the Shopping tab
- New: a Plan tab. Clicking a craft opens it there instead of the Shopping list. Type how many you want to make (or use the -10, +10, +100 buttons) and it lists, in order, what to buy at the auction house with the number of stacks, how many of each intermediate (bars, bolts) to make and from what, and how many of the craft to make, with the cost against your gold. "Shop for these" sends the buy list to the Shopping tab. The number starts at the most you can make with the gold you have
- New: a craft's Shopping list now says the cheapest way to cover the whole craft and what it costs in total, in green when you can afford it and red when you cannot. The rows for a material and for what it is made from are alternatives, so the rows you do not need for that plan show "or skip" instead of an amount to buy. Everything bought of one item is priced as one walk up its price ladder
- Fixed: in the Shopping pane the amount to buy for a material needed by more than one part of a craft was too low. Copper Ore for a Copper Modulator counted the bars and the bolts as the same ore and showed 464, when it is 660 (186 for the bars, 474 for the bolts) less what you have. The amount now adds up across the whole craft
- New: in the Shopping pane, when you open a craft's materials, the item you select now says where it goes. For example Copper Ore shows how much is for the Copper Bars the craft uses and how much is for the bars that become its Copper Bolts, with the total, what you have and what to buy. Bars you already hold are counted against the direct use first
- New: a "Profit if bought" column next to "Buy up to" in the Crafts list. It shows the total profit you would make if you bought up to that many crafts' worth of materials, made them all and sold them. Orange when the buying stops because the auction house runs out or you run out of gold. You can sort by it

## 0.12.40

- New: tooltips for things you open (clams, crates, lockboxes, bags of goods) and mage scrolls you decipher now show what they have given you and how often, with the average amount and what that is worth. The odds are learned from your own openings, because nobody publishes them for most of these. Until you have opened one, the tooltip says nothing is recorded yet. Turn it off in the options. Deciphered scrolls are read from your bags, and openings that gave nothing show as "Nothing" so the odds add up

## 0.12.39

- Fixed: the Shopping list for a craft could show the same material twice (for example Copper Ore with two different amounts). Each material is one row now
- Fixed: the Shopping pane flashed and showed the wrong prices while Live prices was running. Live prices now pauses while you are on another tab and carries on when you go back to Crafts, and the Shopping pane ignores other items' search results

## 0.12.38

- Cancelling tab: click any column heading to sort by it (item, quantity, your price, lowest, over by, undercut price, total value, status, time left). Click again to reverse, a third time for the default order (undercut auctions first). The choice is remembered

## 0.12.37

- Cost now and Sells now show a ticker-style arrow and percent: how far today's lowest price is above or below the average. Green up-arrow on what you sell means a better price, red down-arrow a worse one; for materials a green down-arrow means cheaper than average and a red up-arrow dearer. A grey dash means within 1% of the average
- The two columns are wider to fit them

## 0.12.36

- Shopping lists menu is tidied: your lists and the ready-made ones are shown, and the consumable lists are folded into one heading per profession (click a heading to open or fold it). Searching opens everything that matches
- "First Aid" and "FirstAid" no longer appear as two separate groups

## 0.12.35

- Hover a column heading in the Crafts list to see what it means (average, now, profit, listed, sold/day and so on) as well as the sort hint

## 0.12.34

- Live prices now run by themselves, once each time you open the auction house, as soon as the Crafts tab is showing and no scan is running (starred crafts first). Turn it off in the settings
- Price spike warning: when today's lowest price is more than 50% above the average, Sells now gets an orange "!", Profit now turns orange, and the tooltip explains that Profit uses the cautious price
- Big numbers in Listed and Sold/day are shortened (57227 shows as 57k) so they fit their columns; the tooltip says that the sales estimate counts items, not listings, which makes busy stackable goods read very high
- The tooltip now says the average is the 14-day median

## 0.12.33

- Crafts list: new "Profit now" column, what one craft would make if you bought the materials and sold the result at today's lowest listings (green profit, red loss). It sits beside Profit, which still uses the cautious price. Sortable

## 0.12.32

- Crafts list: the Cost and Sells columns now show the real average, the 14-day median of what the item has been listed at (today's price where there are fewer than 3 scans), beside the live "now" columns. Before, "Sells" showed the lower of the average and today's price, so it matched the live price whenever the market was below its average, which was most of the time. Materials made from raw materials are averaged the same way
- Profit and ROI still use the cautious price (the lower of the average and the next-lowest listing), so a one-day price spike cannot inflate a craft; the columns can now differ from it, and the tooltip says which price was used
- Sells now shows green when today's price is more than 10% above the average and orange when more than 10% below; Cost now the other way round (green cheaper, orange dearer)

## 0.12.31

- Live prices: your starred (favorite) crafts are looked up first, the finished item and every material, so they are always covered when the run is capped. Then come shopping-list items you favorited in the auction house, then the crafts shown. A run now covers up to 100 items

## 0.12.30

- Live prices: the result is now shown under the list and stays there ("Live prices: 38 of 40 updated 1m ago, 2 got no answer"). Before, the list redrawing at the end wrote over the message, so it looked as if nothing had happened
- Live prices: an item the auction house does not answer, or that the server drops, is asked for again at the end instead of being given up on, and a run no longer stalls waiting for a "ready" signal that already went by. Items that still got no answer are written to the issue log by name

## 0.12.29

- Crafts list: new "Cost now" and "Sells now" columns show today's lowest listings (materials bought or made the cheapest way, and the finished item net of the AH cut) next to the figures profit is worked out from. "Cost" and "Sells (net)" are not live: the sell side uses the lower of the AH reference price (the next-lowest price, so one lowball listing cannot skew it) and the 14-day median. A "now" figure shows orange when it is worse than the one used
- Craft tooltip: each material shows its lowest listing now when it differs, and the sell block lists the lowest listing, the reference price, the median and the price used, each labeled
- The new columns can be sorted

## 0.12.28

- New ready-made shopping lists for every consumable, split by the profession that makes them and then by kind (for example Alchemy: Potions, Alchemy: Elixirs, Alchemy: Flasks, Cooking: Food and drink, First Aid: Bandages, Engineering: Other, Blacksmithing: Other for sharpening stones). They are built from every craft Profiteer knows plus the recipes your characters have opened, ordered by the skill needed, so new ones show up on their own. Also two mage-only scroll lists, with nothing a vendor sells: the learnable scrolls (Liminal Passage, Polymorph: Odd Melon, Reintegration, Minor Evocation, Comprehension, Arcane Accuracy, Arcane Power, Arcane Protection, Arcane Recovery, The Blade, Geomancy, Spatial Mending, Cryoblast) and the unread "Scroll: ..." drops you decipher with a Comprehension Charm. Pick them from the Shopping lists menu in the Shopping tab

## 0.12.27

- Fixed the look background (your chosen art and color) only flashing up for a moment when you switched to Profiteer's tabs in the auction house, then disappearing. It now stays

- New: prices stay fresh while the auction house is open. Profiteer quietly re-checks the crafts shown, their materials and your saved shopping lists, oldest price first, one item every few seconds. It only runs while you are on the Crafts or Ledger tab, so it never replaces results you are reading or buying from, and it pauses while a scan or Live prices is running and for a few seconds after you search yourself. It never asks faster than the game allows. Turn it off in the options or with /pf rolling off

## 0.12.26

- Internal update to the shared window look code. Nothing you will notice changed


## 0.12.25

- Fixed "Waiting for you in the mail" and the unrealized totals being far too high: the game gives a stack's whole price and Profiteer multiplied it by the stack size again (a stack of 200 bars counted 200 times). Older saved snapshots are corrected too
- Fixed a character-name leftover (like "Hatchett") being picked as the realm when the game doesn't report the realm yet at login. Only realm names the game has really reported are trusted now
- Hovering a craft, a shopping list item, a price row in the Shopping results or one of your auctions now shows the game's real item tooltip (your own tooltip settings included), with Profiteer's profit and price details underneath

## 0.12.24

- Fixed Profiteer making a separate data set from part of a character's name (so only one character showed in Crafts). It now only uses the real realm name, and ignores any remembered realm that has no scanned prices

## 0.12.23

- Fixed Profiteer mixing PvP and PvE: the add-on chose which realm's data to use before the game had said which realm you are on, and could pick the one from your last login. It now checks again as soon as the realm is known and switches to the right one. (Data already saved in the wrong place stays where it is for now.)
- The Ledger character list no longer spills out of its window: characters on your current realm show by name alone, and the list widens to fit longer names
- The issue log no longer fills up with notes about shirts, tabards and bags, which can't be disenchanted

## 0.12.22

- Tooltips for items you can craft now list the materials with each one's price (vendor or auction house, whichever is cheaper), the total, what the item sells for at the auction house (before and after the cut) and to a vendor, and the profit per craft. Can be switched off in the options.

## 0.12.21

- New Level up window (Alt+right-click the minimap button, or the Level up button on a profession window): shows the cheapest craft that is sure to give you a skill point, using auction prices and what you already hold. Yellow crafts are listed after, marked not certain; green and grey ones are never suggested

## 0.12.20

- If the auction house's own search hangs on "Searching...", Profiteer now writes down why (read it with /issues profiteer)

## 0.12.19

- Redrawn anarchy symbol with a hand-brushed, worn look
- Ledger tab redesigned: sections are cards laid out in two columns with larger text, headers and striped rows
- Smoother, cleaner drawings of several background symbols, plus a calligraphic version of every symbol
- Saved data is found again when the game reports an empty realm name
- Crafts: a character saved twice is listed once in the Crafters column

## 0.12.18

- New background symbols: sword, crossed swords, shield, sun and paw print
- The background symbol can now be rotated and mirrored

## 0.12.17

- New background symbols: Celtic cross, anarchy, peace sign, skull and crossbones, radiation, atom, infinity, lightning bolt, anchor, Helm of Awe, valknut, Eye of Providence, triskele and fleur-de-lis
- The background symbol can now be moved left, right, up and down, and resized
- Picking a color for a piece of artwork now turns its own-color option on, so the color changes at once

## 0.12.16
- Item tooltips warn when a vendor would pay more for an item than the auction house would (after the cut). It can be switched off in the options.
- Disenchant odds now show on the first hover after a reload too.

## 0.12.15
- Item tooltips show disenchant odds for weapons and armor (what you can get, the chance of each, and what it is worth at auction). The odds are close estimates. Can be switched off in the options.
- The auction house tabs show the window background you pick instead of covering it.

## 0.12.14
- Every piece of artwork (corners, crest, edge pattern, title banner, divider, middle emblem) can now have its own color. New "Your file" emblem slots show your own faction, race and city images from the Media folder.

## 0.12.13
- More emblems: religious, Wiccan, Pagan, Druid, Satanic and occult symbols from many faiths, and the names are tidied.
- The artwork can have a color of its own (Artwork section): corners, crest, edges, banner, divider and the middle emblem.
- The close button in the top right can be restyled (the game's X, boxed, plain, red, filled or hidden) with its own size and color.
- The game-icon emblems (faction crests, race and city icons) are removed; looks that used them show your class emblem.
- Fixed the list preview staying open after a pick; the divider under the title no longer runs through the search row.

## 0.12.12
- Emblem list: Pinnacle star, Sunburst, Crown, Crossed swords, Flame and Compass rose; the game's own race sigils and city banners (Stormwind, Orgrimmar and the rest); religious symbols (cross, Celtic cross, Star of David, crescent and star, Wheel of Dharma, yin and yang, ankh, lotus, hamsa, triquetra, torii gate).
- Pointing at an entry in the emblem, corner, crest, edge, banner and divider lists shows a small preview of it.
- The Horde and Alliance crests use the game's round PvP emblem; the title banner is centered with the title.

## 0.12.11
- Gradients: pick both colors, each end's opacity, vertical, horizontal, diagonal, middle-out or center-to-borders, over or instead of the background texture; plus a theme with its own emblem, corners, crest and edge for every talent spec, and a "My spec" automatic theme.
- Look profiles: save your look under a name and switch between saved looks at any time; every character remembers which profile it wears (Look panel, top).
- World of Warcraft flavored art, all optional: nine class themes (Warrior to Druid) with an original emblem, corner pieces, crest and colors for each class, plus a "My class (automatic art)" theme that picks yours; Blue and gold kingdom, Red and iron war camp, Moonlit grove and Plaguelands themes; new spiked corners, horn, crescent and skull crests, and an iron spike edge. The emblem in the middle of the window can also show your class or your talent tree using the game's own icons. Find them in the window options under Colors > Theme and Artwork.
- More optional artwork for the window box: ornament strips along the edges (rope, chain, pearls, runes, vine), a banner behind the title (ribbon, riveted plaque, scroll, jeweled plate), a divider with an ornament under the title, and a faint emblem in the middle of the window (compass rose, shield, laurel wreath, star, runic rings). All in the new Artwork section of the window options; the eight art themes now use them, and the crest sits above the top edge.
- New optional artwork in the window look: seven textured backgrounds (wood planks, aged paper, arcane starfield, runed slate, riveted iron, damask tapestry, dragon scales), five carved corner pieces (filigree, vines, runes, iron plates, arcane sigil), four crests for the top edge (winged, jeweled, scrollwork, crown), and eight ready-made art themes (Arcane library, Dwarven forge, Elven glade, Old tome, Runestone, Royal court, Dragonscale, Oak lodge). Pick them in the window options (Colors > Theme, Background, Border > Corner artwork and Crest). Everything is off until you choose it and syncs between your add-ons like the rest of the look.
- Works completely on its own; other add-ons' saved data is only read when that add-on is loaded. The ledger's mail row is now called 'Mail / COD'.
- Removed the add-on-to-add-on theming hooks and cross-add-on names from the window look code; the shared look sync between your add-ons works the same.
- The "Pulse the flair" option now also pulses the edge finish (soft, bevel, double line and glow), not just the corner studs.

## 0.12.10
- Look sync: the first time your add-ons meet, they now all take on the same look right away instead of waiting for you to change something.

## 0.12.9
- Your custom look is now shared with your other add-ons: change colors, background, border or opacity in one and the rest follow (the newest change wins). It is on by default; untick "Sync my look with my other add-ons" in the Look window to turn it off.

## 0.12.8
- Crafts: Ctrl+right-click a row to remove its profession from a crafter who no longer has it (it asks for each crafter on the row). The automatic clean-up of dropped professions still only runs for the character you are logged in on.

## 0.12.7
- After a full scan is refused because the game limits them, the status line now counts down to the next scan you are allowed to run.

## 0.12.6
- Shopping lists: the Fish list is now "Fish and cooking" and also has the common cooking ingredients (meats and spices), so you can price check them from the same list.

## 0.12.5
- Shopping lists: the ready-made lists are grouped by what goes together. "Herbs and alchemy" now has the herbs plus vials and the elemental reagents, "Ores, stone and bars" has ores, stone and the bars, and "Cloth, leather and hides" has all the cloth, bolts and leather. Gems, Enchanting materials and Fish stay as they were.

## 0.12.4
- Fix: a character who dropped a profession is no longer listed as a crafter for it. Profiteer now compares each character's saved recipes with the professions they have, and removes the ones they no longer have (it tells you in chat when it does).

## 0.12.3
- Fix: a chat line whose text the game hides (it happens in some places, like dungeons) no longer causes a selling-window error.

## 0.12.2
- Fix: a character with a first and last name (like Dr Flamel) was also listed under just the first word ("Dr"), so the Crafters column showed things like "Dr, Dr Hatchet". The two entries are now merged into the real name.

## 0.12.1
- Items that are not listed at the last scan (armor, weapons and other one-offs) now show their last seen price in the tooltip, kept for 60 days. It is stored apart from the scan prices, so profit figures are unaffected.

## 0.12.0
- Auction scan: when the server does not answer a full scan, the message now says about how many minutes until the next one is allowed.
- A craft you learn now moves into your learned crafts right away (also when learned from a trainer or recipe), without reopening the profession window.
- Shopping > Crafts now lists every craft of every profession from a built-in catalog, not just recipes you have opened.
- Shopping tab: a new Crafts drop-down lists every craft of every profession, each profession in its own section (click to open), with a search box. Click a craft to put its materials on the shopping list. It shows all crafts whatever the Crafts tab filters are set to; ones with no AH price are grey.
- Crafts tab: the bottom row is tidier. The status line no longer sits tight against the window edge, and the search box no longer overlaps the Live prices button.

## 0.11.1
- Fonts: the font pack now ships inside this add-on (Fonts folder), so the separate Look Fonts add-on is no longer needed, and there are about 60 more fonts to pick from under Look > Font.

## 0.11.0
- Fix: Shopping tab no longer sticks on "Buying...". It now says "Not enough gold" when the price is more than you carry, and gives up with a message if the auction house never answers.
- New: **Live prices** button on the Crafts tab. With the auction house open, it searches each item on the current page (the crafts shown plus their materials) one at a time, the same search the Shopping tab uses, and updates their prices to what is listed right now. Much faster than a full scan and more accurate. Click again to stop. Up to 60 items at a time.

## 0.10.0
- Prices and characters are now kept separately for each realm, so a PvP realm and a PvE realm never mix. Auction House prices, price history, listings, characters, recipes, inventory, your listed auctions, the sales ledger and gold worth are all per realm. Settings, the look, item names and vendor prices stay shared. The window title shows PvE or PvP.
- Existing data moves to the realm you used most; other realms start fresh and fill in the first time you open the auction house there.

## 0.9.1
- New: sale sound options (Kaching), scan diagnostics and sender tracing, two-part character name fix, /issues log.

## 0.9.0
- Auction House: the Auctions page header no longer runs off the window; tab contents scale with a new slider (smaller by default) so lists fit; the Cancelling tab shows more (gap to the lowest price, relist price, total).
- Recipe tracker: a recipe item's tooltip (Recipe, Pattern, Formula, Plans...) lists which of your characters already know it, which could still learn it, and which have no such profession. Names are saved whenever a profession window opens (enchants included), and a recipe you learn from an item is marked right away. Open each character's profession windows once to fill it in. Switch off under Look > tooltips.
- Characters window (shift-click the minimap button): delete a character's saved data, and characters removed from your character list are spotted and cleaned up automatically.

## 0.8.10
- Crafts: also lists profitable recipes no character has learned yet (captured from each profession window you open). Turn off under Profit and prices. They are left out of shopping plans.

## 0.8.9
- Crafts: new Profession column you can sort by.
- Costs use the cheapest route (AH vs vendor, every alternate material), and materials on your alts count as owned.
- Shopping: the all-together total no longer double counts a bolt/bar and its raw materials.

## 0.8.8
- Shop top 10: picks the ten crafts that earn the most with your gold, splits your gold across them, and shows planned spend and each craft's cost.
- Shopping: your gold is shown at the bottom left; the Buy quantity follows the selected row.

## 0.8.7
- Shop top 10: each craft gets its own heading with its count (e.g. Spidersilk Boots x2), its materials underneath, and craftable materials broken into their raw materials, indented.
- Shop top 10: one shared gold budget across the list, so what you can afford adds up; crafts you can't afford are left out.

## 0.8.6
- Auction House: every Profiteer tab now fills the window, with the same height as the game's own tabs.
- Shopping: each item shows its lowest known price; lists scale to the window.
- Crafts: search box moved to the bottom right.

## 0.8.5
- Auction House: keep Blizzard's native Buy, Sell and Auctions tabs, remove Profiteer's redundant Auction House and Selling tabs, and fit the remaining Profiteer tabs beside the native tabs.
- Native auction handoff: open Blizzard's Sell tab and leave item selection and auction creation in the game UI. Profiteer's Selling tab is no longer available.
- Non-stackable items: classify duplicate copies as item auctions rather than commodity auctions.

## 0.8.4
- Shopping list: clicking a craft now lists every material that can itself be crafted both ways, the made item and its raw materials (copper bar and copper ore, a bolt of cloth and its cloth, and anything your characters have captured), so you can buy whichever is cheaper.

## 0.8.3
- "Buy up to" now stops at the gold you have on this character (turn off with "Limit Buy up to to the gold I have" in options), and the tooltip says when gold is the limit. Reagent lines in the tooltip show the price each as well as the total for the recipe (for example 2x Frilled Lichen 1g30s @ 65s each).

## 0.8.2
- New: window customization. Alt-click the minimap button to restyle each window separately (or all together): background textures, colors with copy/paste, opacity sliders, border styles, fonts, scale and position lock. Over 50 fonts to pick from (install the LookFonts folder for the bundled ones; SharedMedia fonts show up too). Off until you tick "Use a custom look"; unticking restores the original.
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
- Windows no longer bleed through each other: clicking a Profiteer window raises it, with its text and rows, above other addon windows.

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
