# BattleText Forever

**Scrolling combat text for World of Warcraft: Forever.**

BattleText Forever puts the fight on your screen: your hits scroll on one side, the damage you take on the other, heals under your character, and loot and experience in the middle. It's built for Forever's addon rules, in the spirit of the classic scrolling combat text addons.

---

## Features

- **Your hits**, tinted by school, with the spell's name and icon when the game lets BattleText tell which spell it was. Crits are bigger and hold in place for a moment, and rapid hits of one spell add up ("Swipe 135 (x3)").
- **What happens to you**, in its own area: the damage you take, and the attacks you dodge, parry, block or resist.
- **Heals**, the ones you get and the ones you do, in their own Healing area under your character (or with the damage, if you prefer).
- **Notifications**: combat, experience, reputation, honor, loot, money, skill ups, a paladin's seals going on and coming off, and (if you turn it on) your buffs.
- **Ability alerts**: "Overpower!" when your target dodges you, "Revenge!" when you dodge, parry or block, "Riposte!" and "Counterattack!" when you parry (with the talent), "Execute!" and "Hammer of Wrath!" when your target is low enough, and procs: the ones the game lights up on your action bars (like Clearcasting), and Missile Barrage, Revelation, Hot Streak, Fingers of Frost and Brain Freeze when the game lets BattleText see the buff.
- **Combo points**: "2 CP" as they build, "5 CP: Finish it!" when you have them all.
- **Cooldowns ready**: "Kick ready" when a spell of yours comes off a cooldown of 8 seconds or more.
- **Interrupts**: "Interrupted Frostbolt" when you or your pet stop an enemy's cast.
- **Dispels**: "Dispelled Deadly Poison" when you cleanse a friend or yourself, "Purged ..." when you take a buff off an enemy, "Stole ..." with Spellsteal. Tick one box in the Combat Log for it: right-click the Combat Log tab, then Settings, Message Types, Auras, **Dispels**. Without that box, BattleText shows the cure spell you cast ("Cleanse") but can't tell what it took off.
- **Fight summary**: when a fight ends, your damage, DPS and healing ("4,820 damage (127 DPS), 1,200 healed in 38s"). Type `/btf last` to see that fight spell by spell: hits, crits, total, share and biggest hit.
- **Your own rules for a spell**: hide a spell you don't want to see, or give it a color of its own (Spells tab).
- **Four text areas** you can drag anywhere on screen, each with its own movement (Scroll, Pop, Fountain or Horizontal), and your pick of which kinds of text go to which area.
- **Your look**: 23 fonts (plus any your other addons share through LibSharedMedia), a separate font for crits if you like, an outline (thin or thick) or a drop shadow, text and crit size, a smallest crit (smaller ones show as normal hits), bigger text for bigger hits, short numbers (12.3k), scroll speed and distance, your own colors, and for each area its own size, opacity and direction (up or down, straight or curved), and left, centered or right text for the side areas.
- **Your choice of what's shown.** Turn any kind of text off, hide your auto attacks, icons and spell names per area, hide small hits and heals, and hide the game's own numbers so nothing shows twice.
- **Sounds** if you want them, on your crits and killing blows: pick from 18 of the game's sounds (Crit, Impact, Anvil, Battle horn, Boss defeated, Cheers, Epic loot...), or any your other addons share through LibSharedMedia.
- **Low health and low mana warnings** if you want them: a big "Low health!" or "Low mana!" with a sound as you drop low, so you notice in time. You pick the sound, and how low your mana goes before it warns.
- **Settings per character** if you want them, starting from a copy of your shared ones, and **share your settings** with a friend as a line of text.

## Installation

Install it with the CurseForge app, or download the file and unzip it into your WoW: Forever `Interface\AddOns` folder. Then restart the game or type `/reload`.

## Using it

- **Your hits show as soon as you log in**: on your target, and on the mobs attacking you or your pet.
- **BattleText starts by itself.** When you log in, it turns on the game's combat lines, which let it name the ticks of your bleeds and tell your hits from everyone else's (see Good to know). If a fight ends and no line came (a chat addon can get in the way), a **Start BattleText** button shows at the top of the screen and a line in chat says so (turn off **Remind me to click Start** in the options to stop that line). Click it once and you're set until you log out. You can bind a key to it, or put `/click BattleTextForeverStart` at the top of a macro you press anyway; once started, that does nothing. Right-click the button to hide it until you log in again.
- **Move the text.** Turn on **Move the text areas** in the options (or type `/btf unlock`) and drag the four boxes where you want them. Closing the options locks them again.
- **See it without fighting.** Type `/btf test`, or right-click the minimap button.
- **Open the options.** Type `/btf`, or left-click the minimap button.

### Options window

The options have the same look as TauntMaster Forever, ToppedOff Forever and Outfitter Forever: tabs down the left and a switch for each setting. Point at a setting's name for what it does; a setting that does nothing with your other choices is greyed out.


| Tab | What's there |
|---|---|
| **General** | Show BattleText, move the text areas, hide the game's own numbers, minimap button, remind me to click Start, login message, settings for this character only, show sample text, reset positions, reset all, share settings (export and import) |
| **Text** | Font (a list of 23, plus fonts other addons share through LibSharedMedia), crit font, outline and crit outline (none, thin, thick or shadow), text size, crit size, short numbers (12.3k), size by hit, icon zoom, smallest crit |
| **Motion** | Crits stay in place, add up rapid hits, time on screen, area height, how long ticks and area hits add up |
| **Outgoing** | Damage, misses, auto attacks, pet, damage shields, name seal hits, icons, names, hide hits below a number, DoTs and area spells; Appearance: size, opacity, movement, alignment, scroll upward and curved scrolling |
| **Incoming** | Damage, avoids, "(blocked)" on partly blocked hits, power gains, icons, names; Warnings: low health and low mana, each with its own sound, and the mana line; Appearance: size, opacity, movement, alignment, scroll upward and curved scrolling |
| **Healing** | Heals you get, heals you do, show overhealing, icons, names, show who you healed, hide heals below a number; Appearance: size, opacity, movement and scroll upward |
| **Notifications** | Show: combat, killing blows, experience, reputation, honor, loot, money, skill ups, seals, buffs, ability alerts, combo points, dispels, fight summary, cooldowns ready, interrupts, icons, crit sound and kill sound (each with its own pick of sound). Appearance: size, opacity, movement and scroll upward |
| **Layout** | Which area each kind of text shows in: your hits, your misses, heals you do, damage you take, attacks you avoid, heals you get, power gains, notifications |
| **Spells** | Type a spell's name to put it on your list, then hide it or give it its own color |
| **Colors** | The color of your hits, spells, misses, damage you take, avoids, power gains, heals, notifications, combat and killing blows, experience, loot, seals, buffs, ability alerts, combo points, dispels, low health and low mana; reset colors |

### Keybindings

Go to **Options → Keybindings → BattleText Forever**:

| Binding | Does |
|---|---|
| **Start BattleText** | Same as clicking the Start button |
| **Open options** | Opens or closes the options window |

### Slash commands

| Command | Does |
|---|---|
| `/btf` | Open or close the options |
| `/btf test` | Show sample text |
| `/btf lock` · `/btf unlock` | Lock or unlock the text areas |
| `/btf reset` | Put the text areas back where they started |
| `/btf resetall` | Put every setting back to how it started (asks first) |
| `/btf on` · `/btf off` | Turn the text on or off |
| `/btf debug` | Start or stop recording the combat lines the game sends (for bug reports; it turns itself off when you log in) |
| `/btf copy` | Show the recorded lines in a box you can copy from |
| `/btf last` | Your last fight, spell by spell |
| `/btf check` | Check the spells, texts and icons BattleText uses against your game, and report anything missing |
| `/btf gear` | Show what BattleText read from the gear you're wearing (then `/btf copy`) |
| `/btf export` · `/btf import` | Share your settings as a line of text, or take someone else's |

`/battletext` works too.

## Good to know

WoW: Forever doesn't let addons read the combat log. The game tells an addon **what happened to a unit** (it took 27 damage, it dodged), but not **who did it** or **with which spell**. BattleText works from that:

- **Your hits are read from the unit you hit**: your target, and the mobs attacking you or your pet. An area spell (Fire Nova, Arcane Explosion, Swipe...) also shows on every other mob it hits at the same moment. Turn on **enemy nameplates** to see your hits on the ones you aren't targeting.
- **Alone, until the game's combat lines are flowing, every hit on those units is shown as yours**, so another player hitting the same mob shows up too. The exception is a mob someone else tagged that isn't after you or your pet: its hits are theirs and aren't shown.
- **BattleText turns on the game's combat lines when you log in** (or, if that doesn't work, after you click Start BattleText). From then on the game tells BattleText *when* you did something, and only that many hits are shown, so other people's are left out, alone or in a group (now and then a number may still be someone else's hit that landed at the same moment as yours). Alone, on a mob your pet is fighting, every hit still shows: your pet's hits can't be told from anyone else's (they aren't marked). Keep the Combat Log's filter on **My actions** (the default).
- **Spell names and icons** show for:
  - hits that land the instant you cast (instant attacks and spells with no travel time);
  - spells that fly to their target and land a moment later: Fireball, Frostbolt, Frostfire Bolt, Pyroblast, Arcane Wrath, Shadow Bolt, Soul Fire, Wrath, Starfire, Lightning Bolt, Chain Lightning, Hammer of Wrath and Arcane Shot (and the burn Fireball, Frostfire Bolt and Pyroblast leave);
  - the ticks of your damage-over-time spells (Rake, Rip, Rend, Moonfire, Corruption, Shadow Word: Pain and the like). Bleeds need the combat lines;
  - channeled spells (Arcane Missiles, Mind Flay, Drain Life, Drain Soul, Wrack, Blizzard, Rain of Fire, Hurricane, Volley, Hellfire, Tranquility, Penance) and spells that keep burning an area (Consecration, Flamestrike, Magma, Fire Nova and Searing Totems), on every mob they hit;
  - explosives you throw (Engineering's dynamite, bombs and grenades, Goblin Sapper Charge), on every mob they hit;
  - your ranged attacks: Auto Shot, Shoot (bow, gun, crossbow or wand) and Throw, as they land. Your swings get your main hand weapon's icon (or the Attack icon with nothing in your hands);
  - your gear's **"Chance on hit"** damage (Shadowfang, Thunderfury and the like) and weapon enchants that hurt (Fiery Weapon, Icy Chill, Lifestealing, Unholy Weapon), named after the item or enchant; and a rogue's poisons (Instant, Wound and Deadly Poison), with the poison's name and icon;
  - your **damage shields**: buffs (Thorns, Lightning Shield, Retribution Aura, Fire Shield), as soon as they hit, and gear that hurts whoever strikes you (named after the item). Turn off **Damage shields** in the options to hide these;
  - a paladin's **seal** (Righteousness, Command): its Holy damage landing with your swing. Turn off **Name seal hits** in the options to show it as a plain number.

  Other hits show as a plain number in their school's color.
- **Seals in a fight.** The game hides your buffs during a fight, so a seal coming off is worked out: a new seal replaces it, or its time runs out (Judgement leaves it on).
- **Buffs** (off unless you turn them on) show when they go on or come off. The game hides your buffs during a fight: there, a buff you put on yourself (Slice and Dice, Evasion, Sprint...) shows as you cast it, and the rest of what changed, including when those ran out, shows when the fight ends. Food, drink, and buffs with no time limit (mounts, auras, stances) aren't shown, and nothing is shown when you die.
- **The last swing on a mob may not show**: the game stops reporting a unit the moment it dies.
- **Damage you take has no spell names.**
- **The fight summary counts what BattleText can read.** When the game hides a hit's number, it isn't in the total. Killing blows (and their sound) need the game to let BattleText read its combat lines.
- **Auto attacks off**: without the game's combat lines, a physical hit BattleText can't name counts as a swing and is hidden too.
- When the game does let BattleText read the Combat Log's lines, they're used instead: every hit then has its spell, and your pet's hits are marked.

## Troubleshooting

- **No numbers for your hits.** Target what you're hitting, or turn on enemy nameplates. In a group, click **Start BattleText** if it shows.
- **A bleed's ticks have no name.** Click **Start BattleText** if it shows.
- **Start BattleText does nothing.** A chat addon that replaces the game's chat window (like Chattynator) hides the game's Combat Log tab, which the button opens, and there's no real way around that. Your hits still show without it, but other people's hits on your target may show as yours, and bleed ticks have no name. Right-click the button to hide it. The button also goes away by itself if the combat lines start some other way.
- **Other people's hits show as mine.** Click **Start BattleText** if it shows, and keep the Combat Log's filter on **My actions**. Alone, a mob your pet is fighting still shows every hit on it.
- **Numbers show twice.** Turn on **Hide the game's own numbers** in the options.
- **Something isn't shown.** Type `/btf debug`, fight for a moment, then type `/btf copy` and copy the lines into a bug report. Type `/btf debug` again to stop.
- **A spell or icon looks wrong.** Type `/btf check`, then `/btf copy`, and add the report to a bug report.
- **Your gear's hits have no name** (a cloak or ring that hits back, a weapon's "Chance on hit", a poison), or the wrong one. Type `/btf gear` out of combat, then `/btf copy`, and add it to a bug report. This helps most when your game isn't in English.
- **The text is in the wrong place.** Type `/btf unlock` and drag the boxes, or `/btf reset`.

## Feedback and bug reports

Found a bug or have an idea? Please [submit it on GitHub](https://github.com/severd8/battletextforever/issues/new/choose). A short form asks for your class, your Combat Log filter and any error message. You'll need a free GitHub account. Otherwise, feel free to leave a comment on the CurseForge page.

## Translations

BattleText shows its options, chat messages and on-screen words in your game's language when a translation is in (spell and item names always are, since they come from the game). Anything not translated yet shows in English. Korean is in progress. To help with your language, fill in its file in the addon's `Locales` folder (`deDE.lua` German, `frFR.lua` French, `esES.lua`/`esMX.lua` Spanish, `itIT.lua` Italian, `ptBR.lua` Portuguese, `ruRU.lua` Russian, `koKR.lua` Korean, `zhCN.lua`/`zhTW.lua` Chinese). Each line is the English text, then yours after the `=`. Send it on CurseForge or GitHub.

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
