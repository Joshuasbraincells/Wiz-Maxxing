Made By JoshuasBrainCells

One script for battles and walking:
Autofarmer.ahk now does both and starts by itself when you double-click it:
it fights whenever a battle round is up (the Pass button shows) and otherwise
walks your wizard towards the quest goal by following the yellow quest arrow
(the walking comes from ..\AutoQuester\Walker.ahk). Keys:
	F6           the bot on / off (off: no battles, walking, potions or
	             reconnecting - it waits; while it's off, F6 and F8 only work
	             in Wizard101, and the Alt+ keys aren't taken at all)
	F8           walking on / off
	Windows+1    restart (Alt+Esc too)
	Windows+Esc  quit
It only presses movement keys while Wizard101 is the active window. Don't run
AutoQuester.ahk at the same time.

Open with Wizard101 (tray menu, or Setup.exe): a small watcher starts with
Windows (a shortcut in your Startup folder to Wiz-Maxxing.exe /watch - its
own tray icon) and opens the bot by itself when Wizard101 starts - in
standby: it does nothing till you press F6 in the game. Before that it checks
for updates (it asks only if there's a newer release). Never a second bot: one
already running is left alone. A bot opened this way and never turned on
closes when the game does, and opens again with it. The tray menu's tick (or
the watcher's own "Don't open with Wizard101 any more") turns it off.

Walking by the game's memory (navmem:1 in PlayerStats.txt, the default): the
vision helper also reads where the wizard is, which way it faces and where the
quest arrow points straight out of the game's memory - READ-ONLY: nothing in
the game is written or changed, and it sends no keys of its own. The walker
steers by it once it's checked (it agrees with the arrow on screen, or a turn
goes the way it says), uses its distance instead of the OCR'd number, walks on
by it when the arrow can't be seen (scenery, or Pigswick Academy's gold carpet,
which the see-through arrow can't be picked out from) and measures its turns.
It also follows a route the helper plans round the walls over the zone's map
(the Map window draws it in green), instead of walking into them. Whenever it can't be used it follows the arrow on screen as before
(debug.log: "the game's memory ..."). navmem:0 = only the arrow on screen.
More in ..\AutoQuester\README.txt.

You playing: while you use the keyboard or mouse yourself, the bot waits - no
battle rounds, no walking, no potions; a walking key it held is let go at once.
It carries on 10 s after you stop (handsoff in PlayerStats.txt; 0 = it never
waits). If you take over during its turn, it leaves that round to you.
Switch it on/off with the tray menu "Wait while I play" (ticked = on) or the
dashboard's "Wait for me" button; it's kept in PlayerStats.txt (handsoffon).

Updates: opening Wiz-Maxxing (Start menu, desktop, ..\Wiz-Maxxing.exe) checks
GitHub for a newer release and asks before installing it; tray menu "Check for
updates" does it any time. Needs a GitHub token once per PC (Setup.exe, "GitHub
updates"). Your settings, learned cards, potion routes and pictures are kept.
updater.log (next to Wiz-Maxxing.exe) says what it did.

Dashboard (Dashboard.ahk): a window with statistics (battles, rounds, cards
cast per card, passes, discards, kill-check hits, potions, cards learned),
what the bot sees right now (your health/mana/pips, the hand card by card - ?
for a card it doesn't know, * for a greyed-out one - enemies' health, zone,
the walker) and the log as it's written. Windows+2 or the tray menu shows /
hides it; it opens on a monitor the game isn't on and remembers where you put
it (dashboard.ini). It never takes the focus by itself. Its X (close) stops
the bot; minimise it (or Windows+2) to just put it away. Next to STATISTICS:
the CPU and RAM in use, every second - the bot (with its vision helper), the
game and the whole PC (CPU share of all cores, RAM in use).

Settings (the dashboard's Settings button, or the tray menu "Settings..."):
the mouse and the bot's waits, and how it plays its cards, in one window -
point at a setting to see what it does. Save writes them to PlayerStats.txt
(each in its own line, comments kept) and the bot uses them at once - no
restart. Defaults fills in the defaults (Save to use them).
	- The mouse and waits: Wait for me (on/off, and the seconds after you
	  stop), put the mouse back (when the bot takes the mouse - a battle
	  round, a click out of battle - it goes back to where it was once it's
	  done, unless you used the mouse or keys meanwhile), mouse speed, the
	  wait before each click (plus a random bit, so clicks aren't evenly
	  timed), the wait after clicks, before playing a round, after a discard
	  and before looking at the hand again.
	- Health: heal under %, drink a potion under %, flee out of mana/cards.
	- Card logic: boost first (traps on the boss, blades, bubble, aura, then
	  the biggest hit it can cast - as always), hit first (the biggest hit it
	  can cast as soon as it has one; boosts only in rounds it has none -
	  quick on weak mobs), or boost first on a boss you picked (Alt+1) and
	  hit first otherwise. Boosts before each hit (0 = all it has), the kill
	  check and its margin, which kinds of cards it plays at all (blades,
	  traps/Feint, bubble, aura, the wand's hit, Tower Shield, Reshuffle - a
	  kind switched off is discarded when "Discard cards it never plays" is
	  on), boosting again after each hit, counting traps when you fight bosses
	  alone, saving pips for a finishing hit, and discarding.

Executables: ..\Wiz-Maxxing.exe starts the bot (Setup.exe puts it in the Start menu
and on the desktop). Autofarmer.exe (and StatsReader.exe here, AutoQuester.exe in
..\AutoQuester) do the same as the .ahk scripts without AutoHotkey installed.
Keep each exe in its folder - it reads the pictures, PlayerStats.txt and
vision\ from there (and AutoQuester\resources\). The vision helper still needs
Python 3 with numpy and Pillow (pip install numpy pillow katsuba - katsuba only
draws the zone's walls on the zone map; Setup.exe installs all three); without
it cards are found the old way (ImageSearch) and the walker follows the arrow on
screen. Rebuild after changing a script:
double-click ..\build.cmd (needs AutoHotkey v1.1 with its compiler; close the bot first).
Ready-built: the Releases page of the GitHub repo (a zip with everything). Hover the wizard icon in the tray to see what
the walker is doing; debug.log has the battle and walking decisions in order.

Auto-reconnect (Reconnect.ahk, on from the start):
	- Disconnected (e.g. "You have been disconnected due to inactivity." after
	  about 15 minutes idle outside battle, or "Connection Lost!"): it reads
	  the game's own log, finds RECONNECT on the box and clicks it - never
	  QUIT. That logs back in without a password and puts you back where you
	  were. It first clicks with the game left in the background; if the game
	  ignores that it brings the game to the front for a moment and gives
	  focus back. If the character select screen stays up, it clicks Play
	  (with the game brought to the front: that screen ignores background
	  clicks).
	  Failed tries wait longer each time (30 s, 1, 2, 4, then 10 minutes).
	- The game closed (a crash or Quit): it asks whether to start it again
	  (yes after 60 seconds if nobody answers), starts it, types your saved
	  login into the game's login box and goes back in. It only presses Enter
	  once it can read your username back in the login box, and stops for
	  good if the game turns the login down.
	- "Client is out of date" after maintenance: it starts the launcher so it
	  can patch (it fills in the launcher's login too - not tried yet).
	Tray menu: "Auto-reconnect on/off", and "Set Wizard101 login..." to save
	your username and password for when the game has to be started again.
	The login is kept encrypted in Windows Credential Manager as
	"Wizard101Bot" (Control Panel > Credential Manager > Windows Credentials
	to see or remove it), never in a file and never in debug.log. Without
	it, only the RECONNECT part works. debug.log lines start "Reconnect:".

Window size / UI size (any resolution):
The game draws its buttons and cards bigger or smaller depending on the
window size / resolution, the Windows display scaling and Options > UI Size,
and a picture only matches at the size it was cut at. Pictures are cut at a
few sizes:
	resources\, storm\, ...  the main set: 1920x1080 window, 100% scaling,
	                         UI Size Small (UI scale 1)
	ui1.265\                 1920x1200 window at 100% scaling (UI 1.265x):
	                         Storm and Myth cards, Pass, the spellbook, the
	                         name plate, the school icons (see its README)
At any other size the bot makes its own set (PicScale.ahk): in the first
battle round at that size it reads the Pass and Flee buttons (OCR) to measure
the UI scale, checks it by making the Pass button at sizes around that, then
resizes every picture it needs from the sharpest cut set into
generated\ui<scale>\ (debug.log: "UI size: ..." and "made ..."). That first
round takes ~10 s longer; the made set is kept, so later rounds and later
runs at that size start straight away. Seen working at 2560x1440 borderless
(UI 1.14). Made pictures are found with a little more colour tolerance and
remade by themselves when a cut picture changes; delete generated\ to make
them all again. Shrinking works best, so cut new pictures at the biggest size
you play at (a ui<scale> folder: the bot finds those by itself).
The script uses whichever set's Pass button or spellbook it can see (debug.log
says "Pictures: ..."), and sizes its search areas to match. A card with no
picture in any set just counts as not in hand (debug.log says which).

Sometimes we just need a break from all that farming in wizard101
or maybe you've been questing and are just sick of it, i have just
the solution for you. I thought I'd take some time out of my life
to create a program which basically plays the game for me. With this
program, I've been able to read so many books AND get Darkmoor gear
easily. Sound Good? You say you don't like to read? Well just endure
this much and then you'll be overpowered in Wizard101 in no time.

To begin install Autohotkey from https://www.autohotkey.com then 
open the AutoFarmer.ahk file. Once its open, you should be able to see 
it in the tab menu on the Taskbar. You can then activate the script 
by pressing the key combo "Windows+1".

Now whenever you join a battle the program will take over your
mouse and create a strategy based on the cards you have. Please
note however it only has a select few cards out of the many that 
are in Wizard101. so far it mainly uses hit all spells, blades,
traps, feints, auras, enchants, towers, and bubbles

This program prioritizes cards based on priority. The priority 
chart goes in this order, feint, trap, blade, aura, hit, tower,
reshuffle, and if no other move can be found, it'll pass. So what
this means is that if there's a blade and a tower in hand, it'll use
the blade first because it has a higher priority.

Now this program isn't smart enough to figure out where a 
boss might be(If it can't do that it can't trap, feint or convert!), 
so I've added a hotkey that allows you to manually set it, the 
key combo is Alt+1, A message box will appear instructing 
the player to click where the boss is. Please be careful where you click
if you click in the wrong spot, it'll remember it and won't work correctly.

Occasionally the program chooses a ally to blade which the player
using the program disagrees with, I've added a hotkey to 
solve this issue as well. Use the key combo Alt+2 to 
manually set the "Hammers" location. Works exactly like the 
boss location.

Saving pips (pipsave, pipsavehealth in PlayerStats.txt):
When nothing in hand ends the battle this round, but a hit that would end it
- an AoE that kills every enemy, or a hit that kills the last one - costs
more pips than you have, the bot saves up for it (up to pipsave rounds,
default 3): no other hit spends pips meanwhile (the wand's free hit, blades,
traps, healing and Pass still go), and the kill check casts it the round it's
affordable. Not while your health is under pipsavehealth % (default 50); it
gives up for the battle if the pips don't come. debug.log and the dashboard
say "saving pips for ...".

Kill check:
At the start of every round the program reads each enemy's health off the
nameplates at the top of the screen and works out how much damage each hit
in your hand would do. If one of them kills every enemy it casts it right
away (the cheapest one that works - the wand's free hit first - and without
the enchant if it doesn't need it) instead of putting up more blades and
traps. A hit on one enemy (<school>.hitNtarget:1) only counts when one enemy
is left. If it can't read the
health, or no hit is enough yet, it plays exactly like before.
	- Turn on Options > Gameplay Options > "2D Combat Display" in Wizard101,
	  that's what shows the enemy nameplates.
	- Needs Windows 10 or 11 (it uses the OCR built into Windows).
	- Open PlayerStats.txt and set your damage %, and the damage of the hit
	  spells in your deck. The numbers in there are only guesses.
	- When you set the boss with Alt+1, click the boss's nameplate at the top
	  of the screen. That way the program knows which enemy your traps and
	  feints are on. In a boss fight the kill check stays off until it can
	  find the boss's nameplate.
	- Statistic mode (Alt+S) shows a box beside the game window with the
	  health it read and the damage it thinks each hit will do, handy for
	  checking your settings. It needs room beside the window (it's never
	  drawn over the game); Windows+2 in developer mode shows the same info.
	- It plays it safe rather than wasting a hit: it assumes no crits, adds a
	  safety margin, only counts blades the program put on your own wizard,
	  only counts traps if you set solotraps to 1 in PlayerStats.txt (only do
	  that if you fight bosses alone), and never counts bubbles (anyone's
	  global replaces yours).
	- It's switched off in Dual mode, since both windows share what's been
	  cast and it can't tell what has landed yet.

Stats reader (any window size, any wizard):
The kill check needs your wizard's Damage and Armor Piercing for the school it
hits with. They're read off the Spellbook's stats pages (it presses C, which
opens the book at the character page, reads Damage, Accuracy, Critical, Block
and Armor Piercing for that school, and closes the book) and kept in
PlayerStats.txt as <school>.damage, <school>.pierce, ... - one set per
school, with <school>.charid saying which character they're from. The plain
damage / pierce lines near the top are only used for a school with none.
	- AutoFarmer does it by itself: when it fights with a wizard whose
	  school has no stats yet, or whose stats are from another character of
	  that school, it reads them at the next quiet moment out of battle -
	  with Wizard101 in front and your hands off the mouse and keyboard for
	  5 s (it stops at once if you touch them, if the game loses focus or a
	  battle starts). At most once every 30 minutes per character.
	  debug.log: "Stats: ...". It knows each character's school from the
	  badge by its name plate in battle (resources\characters.txt) - and
	  when a battle shows no badge it knows (your plate in another slot can
	  show none), it goes by that: the school this character fought as
	  before, with your own plate (found by your name) as the hitter's.
	  debug.log: "no school badge found on the name plates - ..."
	- Tray menu "Read wizard stats now" (or double-click StatsReader.ahk;
	  while AutoFarmer runs, that just asks AutoFarmer to do it): read them
	  again, e.g. after changing gear.
	- StatsReader.ahk on its own (AutoFarmer not running): works out the UI
	  size and which character is logged in by itself; for a character
	  AutoFarmer has never seen fight, it takes the school with clearly the
	  highest damage. School at the top of StatsReader.ahk forces one.
Numbers are read with digit pictures resized to the UI size, checked with
Windows OCR; one that can't be read for sure keeps its old value, so it never
writes a wrong number (StatsReader.log / debug.log list every reading, and
pictures of the two pages go to %TEMP%\Wizard101 bot rounds\stats_*.bmp).

New cards (CardLearn.ahk - needs the Python vision helper):
Every round the bot reads the hand card by card. A card it has no picture
for, shown in colour (a greyed-out one - not enough pips - waits until it's
castable), is learned:
	- its type from the icon at the bottom right of its picture
	  (ui1.144\cardicons: damage = hits one enemy, aoe = hits all, heal,
	  ward = a shield), its pip cost from the yellow digit
	  (ui1.144\carddigits), its numbers from its text (OCR: "65-105" -> 65)
	- it's saved as <picture set>\learned\<id>.card.png (the whole card, for
	  you to look at) and .png (the picture the bot looks for)
	- it goes into a free slot (one whose picture was never cut), so the
	  battle code uses it like the hand-cut cards: a hit -> <school>\hit1-3,
	  only where they stay weakest to strongest (the battle casts hit3 first;
	  hit4 only for one stronger than all, as hit4 is only cast on bosses), no
	  pips -> wand, heal -> heal1/heal2, shield -> resources\tower. Its numbers
	  go into PlayerStats.txt (<school>.hitN, hitNpips, hitNtarget, ...) under
	  "Cards the bot learned by itself". The damage is read at three sizes
	  and two must agree (and make sense, low-high); if not it's written as 0,
	  so the kill check never counts on it - fix the number by hand then.
	- cards are learned per school (each wizard's own), shields for all
	- seen at another UI size, a learned card is cut again at that size
	- no free slot or an unknown type: it's only kept and recognised from then
	  on (and tried for a slot again whenever it's in hand)
Copies of a card shimmer a little, so a learned picture is cut solid from one
copy and the pixels that differ in the next copies turn see-through by
themselves. A pip cost that couldn't be read is guessed as the pips you had
(the card was castable), and brought down whenever it shows up castable with
fewer. learned\cards.txt lists everything learned; debug.log: "learned a new
card ...".
Fleeing: out of mana (less than its cheapest hit costs - every spell costs a
mana a pip - and no wand in hand) or out of cards (the deck used up) for two
rounds running, the bot can only pass for the rest of the battle, so it clicks
Flee instead, drinks a potion (none left: goes and buys some) and tries again.
PlayerStats.txt: fleeon:0 switches it off. debug.log: "fleeing: ...", "after
fleeing: ..."; the dashboard counts them next to Passed.
Discarding in normal battles: every round, after it's read the hand, the bot
right-clicks away the cards it knows it never plays - learned cards it has no
slot for (charms, globals, minions..., or one more card of a kind whose slots
are full) - so the next round draws cards it can use; at most 3 a round. Its
own cards stay, and so do cards it doesn't know yet (greyed out ones may be its
own; in colour they're learned first). Spare blades and Sharpen go once they
can't stack any more, as before. PlayerStats.txt: discardunused:0 switches it
off, discardmax: how many a round. Treasure cards it has no slot for are
discarded too. debug.log: "Discarded learned card ...".
Learn every card (dashboard button, or the tray menu): for a deck you made
to be learned - one of every card. Switch it on and start a battle (an easy
one). Each round the bot learns what's in hand, right-clicks away every card
it knows so the next round draws new ones, keeps greyed-out cards it doesn't
know until there are pips to show them in colour, heals if your health is
low, and passes - it casts nothing else. It stops by itself when the deck is
used up (two rounds with an empty hand) or nothing new has come for three
rounds, and says how many it learned; then finish or flee that battle
yourself. debug.log: "learn every card: ...".

Potions (Potions.ahk - needs the Python vision helper):
Out of battle the bot reads your health off the red globe. Under potionat %
(PlayerStats.txt, default 40) of your most health (read off your name plate in
battle) it drinks a potion (Ctrl+O). If health doesn't go up, you're out, and
it goes to buy more WITH GOLD (never Crowns):
	- By the zone's map (potionwalk:1, the default - the Settings window's
	  "Walk to the potion seller by the map"): nothing to record. Where the
	  potion sellers stand is in the game's own files (Hilda Brewer in Wizard
	  City's Commons, one in the Arcanum). Out of potions in a zone with one,
	  the bot walks to her by the zone's map (the same route planner as the
	  quest walking), presses X at her prompt, clicks Fill All (found by the
	  words on it - never with "Crown" round it), closes the window and drinks.
	  From anywhere else: a Recall (Page Up) to your Mark - leave it anywhere
	  in the Commons, it needn't be right by her - or, in Wizard City, the
	  Commons (End). Then on with the quest from there. A buying you recorded
	  at your Mark (below) is still used; potionwalk:0 for only that.
	  debug.log: "Potions: walking to the potion seller (...) by the zone's
	  map", "Fill All at ...".
	Or recorded, at your Mark:
	- Once: leave a Mark (Page Down) right next to the potion seller
	  (Hilda Brewer, Wizard City's Commons) and keep it there - don't
	  Page Down anywhere else. Then tray menu "Record potion buying...": the
	  bot recalls you to the Mark (Page Up); press X to talk, click Fill All
	  (and close the window), press F9. It's saved as routes\mark_<wizard>.txt
	  with the name on the seller's "Press X" prompt. Each wizard has its own
	  Mark, so do this once for each.
	- When out of potions: Recall (Page Up) to the Mark (none if you're at the
	  seller already), and once her prompt shows the buying, drink,
	  then walking follows the quest arrow on from the seller. Mob-loop, lore
	  and afk farming can't get back to their spot yet - it tells you. Before
	  each click it reads the screen round it - any "Crown" stops the run. A
	  battle, you touching the mouse or keyboard, or a missing loading screen
	  stops it too. Nothing recorded yet: no recall, a tray message says how
	  to set it up. No Mark or too little mana for the Recall: a tray message,
	  another try in 10 minutes. The Mark somewhere else (another zone, or no
	  seller's prompt there): nothing clicked, no more recalls for that wizard
	  till you Mark by the seller again and restart the bot (Windows+1). Not right by the seller when recording?
	  Walk there and press Page Down: the recording starts over from there.
	- Tray menu "Buy potions now" does a run straight away.
	- potionmark:0 in PlayerStats.txt: the old way instead - the bot marks your
	  spot (Page Down), goes Home (End with potionfromhome:0: the Commons),
	  walks a route you recorded with the KEYBOARD only (routes\<zone>.txt -
	  use the mount you'll farm with, a route is a timing) and recalls back.
Mark & Recall: since Nov 2024 they cost 1-10 mana and recalling keeps the
mark. Some places (dorms, houses, some dungeons) can't be marked.

Along side simply playing the game this program has certain modes
all of which include, command mode, response mode, dual mode and lore mode.
Just as a note, all of these can be turned off be re-inputing the
same key combo.

At any moment you can close the program with "Windows+Escape"

Dual mode:
Pressing the key combo Alt+D will activate this mode. When activated,
at the end of each round the program will tab out as to switch to another
instance of wizard101. Dual mode is only to be used when you're playing on
two accounts. For better consistency close everything but the two instances
of Wizard101.

Command mode:
This mode allows the use of commands from other players, especially used
for teleporting. To activate, use the key combo "Alt+C". When activated
all commands are available to other players. The phrases are as shown.
	Port: 
		When sent to the player running the program, it'll teleport to
		the playing calling.
	Afk: 
		When sent to the player running the program, it goes 
		into a "Timeout prevention sequence" which basically means it
		makes the player move so that you wont disconnect from timeout.
	Enter:
		When sent to the player running the program, 
		it'll press "X" and it's used for interacting with things, and 
		entering sigils.
	Walk:
		When sent to the player running the program, it walks
		the recipient exactly two seconds forward.
		
LoreMode:
When activated, this mode will proceed to farm lore infinitely
so long as the player has mana and or potions. The main way of getting back
to the sigil is by logging out and in, so don't get scared when it does so.
Every cycle, the program waits exactly 30 seconds for the player to regain health.
		
Response mode:
what this mode does is respond to the player issuing the command before 
initiating the command itself. I Primarily made it for shits and giggles but
it does have its uses. For instance, when a command cannot be achieved for 
whatever reason, response mode will report an error instead of it's 
normal phrase.
