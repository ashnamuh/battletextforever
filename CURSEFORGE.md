# BattleText Forever

**Scrolling combat text for World of Warcraft: Forever.**

Your hits scroll on one side, the damage you take on the other, heals under your character, and loot and experience in the middle. Built for Forever's addon rules, in the spirit of the classic scrolling combat text addons.

> **Bugs or ideas?** Please post them on [GitHub](https://github.com/severd8/battletextforever/issues/new/choose), where I can keep track of them.

---

## Features

- **Your hits**, tinted by school, with the spell's name and icon. Crits are bigger, and rapid hits of one spell add up ("Swipe 135 (x3)").
- **Damage you take** and the attacks you dodge, parry, block or resist, in their own area. Magic hits show their school ("-120 Shadow" in purple), so you know when to pop a Shadow Ward or a resistance potion.
- **Heals** you get and heals you do, under your character.
- **Notifications**: combat, experience, reputation, honor, loot, money, skill ups, seals and (if you want) buffs.
- **Ability alerts**: Overpower, Revenge, Riposte, Execute, Hammer of Wrath and procs like Clearcasting or Hot Streak.
- **Combo points, cooldowns ready, interrupts and dispels**.
- **Fight summary**: damage, DPS and healing when a fight ends. `/btf last` shows it spell by spell.
- **Low health and low mana warnings**, with a sound.
- **Crit and killing blow sounds** if you want them.
- **Make it yours**: four text areas you can drag anywhere, each with its own movement (Scroll, Pop, Fountain or Horizontal). 23 fonts (plus LibSharedMedia), sizes, colors, outlines, short numbers (12.3k), and hide or recolor any spell.
- **Per-character settings** if you want them, and share your settings with a friend as a line of text.
- **Translations**: shows in your game's language where a translation is in.

## Installation

Install it with the CurseForge app, or download the file and unzip it into your WoW: Forever `Interface\AddOns` folder. Then restart the game or type `/reload`.

## Getting started

- **It starts by itself** when you log in. If a **Start BattleText** button ever shows at the top of the screen, click it once.
- **Move the text**: type `/btf unlock` and drag the boxes.
- **Try it out**: type `/btf test`, or right-click the minimap button.
- **Options**: type `/btf`, or left-click the minimap button. Point at any setting to see what it does.

## Slash commands

| Command | Does |
|---|---|
| `/btf` | Open the options |
| `/btf test` | Show sample text |
| `/btf unlock` · `/btf lock` | Move or lock the text areas |
| `/btf reset` | Put the text areas back |
| `/btf last` | Your last fight, spell by spell |
| `/btf debug` · `/btf copy` | Record combat lines for a bug report, then copy them |

## Good to know

WoW: Forever doesn't let addons read the combat log, so BattleText reads what happens to the units around you:

- **Your hits show on your target** and on mobs attacking you or your pet. Turn on **enemy nameplates** to see hits on the others too.
- **Other players' hits are left out** once the game's combat lines are on (BattleText does this at login). Keep the Combat Log's filter on **My actions**.
- **Most spells show their name and icon**. A few hits show as a plain number in their school's color, and damage you take has no spell names.

## Troubleshooting

- **No numbers for your hits**: target what you're hitting, or turn on enemy nameplates.
- **Numbers show twice**: turn on **Hide the game's own numbers** in the options.
- **Start BattleText does nothing**: a chat addon like Chattynator hides the Combat Log tab it needs. Your hits still show; right-click the button to hide it.
- **Something's missing or wrong**: type `/btf debug`, fight for a moment, then `/btf copy` and add the lines to a bug report.

## Feedback and bug reports

Found a bug or have an idea? Please [submit it on GitHub](https://github.com/severd8/battletextforever/issues/new/choose), or leave a comment here on CurseForge.

## Support the addon

BattleText Forever is free. If you enjoy it, you can [leave a small tip on Ko-fi](https://ko-fi.com/tauntmasterforever). Thank you!

## All addons by me

- **TauntMaster Forever**: one-click taunts off your healers and DPS, for tanks.
- **ToppedOff Forever**: reminds you when buffs, food, reagents, ammo or gear need topping off.
- **Outfitter Forever**: save your gear as outfits and switch between them with one click, or let them change by themselves.
- **BattleText Forever**: scrolling combat text for your hits, heals and the damage you take.
- **AuctionHouse Forever**: a bigger Auction House window, so long item names stop getting cut off.
- **GatherPath Forever**: the shortest gathering route through your GatherMate2 herb and ore nodes, on the world map and minimap.
- **ARS Forever** (Azeroth Revenue Service): see how much gold a player has made and the most they've ever held, for you and anyone you inspect.

## License

MIT

The fonts in the `Fonts` folder are open fonts, unmodified, each under its own licence (in the addon's `Fonts/Licenses` folder): Anton, Archivo Black, Bangers, Barlow Condensed, Bebas Neue, Cinzel Decorative, Fira Sans, Lato, Metamorphous, New Rocker, Poppins, Press Start 2P, PT Sans Narrow, Rajdhani and Russo One (SIL Open Font License 1.1), Luckiest Guy and Permanent Marker (Apache License 2.0), and Ubuntu (Ubuntu Font Licence 1.0).
