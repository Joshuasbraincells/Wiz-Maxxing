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

Discord alerts (tray menu "Discord alerts..."): when the wizard needs you, a
message goes to your Discord channel - stuck (walking stopped), a teleport that
doesn't work, no quest arrow, waiting at the quest goal, a collect quest that
needs you, out of potions with none to be had, "Crowns" seen in a potion run,
out of mana, a wizard it doesn't know, the backpack full, or it can't get back
into the game (a login turned down, patching, the launcher). It says what's
wrong, the zone and the time - never a login or a screenshot. Set it up: in
Discord the channel's settings > Integrations > Webhooks > New Webhook > Copy
Webhook URL, then paste it into "Discord alerts..." (typed hidden; kept in
Windows Credential Manager as "Wiz-Maxxing Discord webhook", never in a file
or debug.log) - a test message is sent. Empty: another test; OFF: removed.
The same alert at most once in 10 minutes; alertson:0 (the Settings window)
switches them off. debug.log: "Discord: ...".

The log on OneDrive (Settings: "Copy the log to OneDrive", logmirror:1): debug.log
is also written to your OneDrive folder, Wiz-Maxxing logs\<this PC's name>\,
with a picture of the game every 2 minutes and at each alert (snap_*.jpg, the
newest 15) - OneDrive syncs it, so the bot on one PC can be followed from
another. Off by default; nothing else is sent anywhere.

Dungeon farming (the dashboard's Dungeons tab): record a run once - stand
outside the dungeon by its sigil, click "Record a run" and play it (X at the
sigil, to the boss, fighting on the way, back out to where you started), then
press F9 and name it. Pick it and click Run (so many times, or 0 = until you
stop it): the bot walks the same way by the zone's map, presses X where you
did, fights every battle (the bot on, F6), Spaces through dialogues and starts
over. F8 pauses it. Somewhere the run doesn't go (a potion run, a defeat), or
stuck for good: it stops and says why (the tab, debug.log "Dungeons: ...",
Discord). Runs are kept in dungeons\<name>.txt (updates keep them). Needs the
vision helper and the game's memory, like walking by the map.

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

Faster walking with Cheat Engine's speedhack (Settings: "Walk faster with
Cheat Engine's speedhack", off unless you switch it on): Cheat Engine - yours,
installed and attached to Wizard101 by you - speeds the game up; the bot only
presses its speedhack hotkeys (F13-F24, keys no keyboard has): the walking key
while it walks, the 1x key for battles (pressed at every round), talking,
dialogues, shops, near the goal, collecting, dungeon runs, a teleport ahead,
getting round an obstacle, when you play, F6 and when it stops. Its turn and
wait times are divided by the speed; above 5x turns are made at 1x. In Cheat
Engine: Settings > Hotkeys, two "Speedhack speed" entries - the walking speed
(speedfactor) and 1 - with "Disable when released" unticked; the tray menu's
"Speedhack: press its ... key in 3 s" items press a key while you're in its
hotkey box. If the wizard doesn't turn faster (Cheat Engine not attached after
Wizard101 restarts, the key not taking) the bot stops using it for the run
("speed: off for this run" in debug.log). Risky: KingsIsle may notice.
Mobs (mobavoid:1, the default - Settings: "Keep away from mobs"): the helper
also reads the zone's mobs out of the game's memory (read-only) and the route
keeps out of what each one sees, so no battle starts on the way: Settings,
"...what they see" (mobshape) - a semi-circle in front (the default), a
circle all round, or a cone in front (mobcone degrees wide) - mobradius (300)
far; which way each faces is read from the game too, and a little room is
kept all round its body. Players put the cone at 50 to 120 degrees; to
measure what they really see, each
battle's first round logs which mob started it, how far away you were and how
many degrees off its facing ("Caught by ..." in debug.log). Not
the mobs the quest is about: those named in its goal line ("Defeat 3 Lost
Souls"), or standing at its goal; and not while collecting. With no way round
(a narrow street), the wizard stands still till the mob moves off - 25 s at
most, then it walks on past it. Never inside one's reach or sight, though (a
mob walked up, or the wizard came out of a battle there): it walks out of it
first - along the route if that leads out, else the shortest way out (never
nearer the mob) on the quest's side - backing straight out when the way out is
behind, never standing still turning in it - and only then waits. A battle
starting (the wizard held or turned by the game) no longer stops it steering
by the game's memory; while it doesn't, it keeps to the route by the arrow, and
with no route at all it won't walk the arrow's straight way into a mob's reach
(20 s at most) or back up into one. The walk to the potion seller keeps away from
all of them. The dashboard's Map shows them: red dots with a faint ring (kept
away from: its shape), the quest's amber, the nearest ones named.

Mobs that catch you anyway (mobgrow:1): each battle a mob the quest doesn't
need starts (not collecting, not one named in the goal line, not right after X
at the goal, not a dungeon run that fights everything, not while you play)
widens the reach the route keeps out of - to where it caught you from, and 25
more (20 at the least; 1500 at most): how far they notice you (mobradius) when
it caught you in front of it, their reach all round (mobbody - a semi-circle or
cone's sides and back, 120 at first) when from the side or behind. debug.log
says so under "Caught by ..."; set them back in Settings any time.

Bring Wizard101 to the front (gamefront:0 - the dashboard's "Game to front"
button, the tray menu, Settings): with Wizard101 not the window in front, the
bot brings it there when the quest arrow shows (walking - once you've left the
keyboard and mouse alone 3 s, so what you type elsewhere doesn't end up in the
game) or a battle round is up. It brings the window forward; it never clicks in
it to do so.

You playing: while you use the keyboard or mouse yourself, the bot waits - no
battle rounds, no walking, no potions; a walking key it held is let go at once.
It carries on 10 s after you stop (handsoff in PlayerStats.txt; 0 = it never
waits). If you take over during its turn, it leaves that round to you.
Switch it on/off with the tray menu "Wait while I play" (ticked = on) or the
dashboard's "Wait for me" button; it's kept in PlayerStats.txt (handsoffon).

Updates: opening Wiz-Maxxing (Start menu, desktop, ..\Wiz-Maxxing.exe) checks
GitHub for a newer release and asks before installing it; tray menu "Check for
updates" does it any time - so does the dashboard's Updates button (top right),
which says live whether a newer version is out ("Update to v..."; it looks it up
45 s after the bot starts and every 2 hours, out of the bot's way). The version
is in the windows' titles, the tray menu's first line and the dashboard's
STATISTICS. Needs a GitHub token once per PC (Setup.exe, "GitHub updates").
Your settings, learned cards, potion routes and pictures are kept.
updater.log (next to Wiz-Maxxing.exe) says what it did.

Party (Settings > PARTY; tray menu Party...): up to 4 wizards, one per PC on the
same home network. One is the Leader - it quests as now, and stops while a
follower is far (partywaitdist), in another zone, loading or not ready, for
partywaitmax s at most. The others are Followers - instead of their own quest
they walk to the leader (stopping partynear from it), into its battles (where
it stood when the battle started), and through the door it took (its last spot
in the zone, then on the way it was going). Set each wizard's party name, and on
each follower the leader PC's name or IP, with Party... (kept in party.ini). The
leader's PC asks once to let Python through Windows' firewall - allow it on
Private networks (the home network has to be set to Private). The bots share
only where each wizard is and what it's doing - nothing one sends makes another
press or click anything. Still to come: teleport to friend when the leader is
somewhere a door doesn't lead (the follower waits and says so), and battle roles.
In a battle with more than one of your wizards, a bot doesn't save the school it
read for its character (which name plate is its own isn't sure yet).

Report a bug (the dashboard's button, top right, or the tray menu): say what
went wrong; Send posts it as an issue on the Wiz-Maxxing repo on GitHub, with
the version, this PC's name, the screen, what the dashboard's STATISTICS and
WHAT IT SEES show and (ticked) the end of debug.log - anything that looks
secret (a Discord webhook, a GitHub token, password=...) blanked out. It uses
the updates' GitHub token, which needs Issues: Read and write as well: on
github.com, Settings > Developer settings > Fine-grained tokens > the
Wiz-Maxxing token > Edit > Repository permissions > Issues: Read and write >
Update (the same token keeps working - nothing to change on the PCs). Closing
the window keeps what you typed until it's sent.

Simple and advanced views: the dashboard's bottom-right button switches it -
simple shows what the bot is doing and seeing (STATISTICS, WHAT IT SEES) with
the main buttons, advanced adds the hand's cards, the live log and its buttons.
The Settings window's "All settings" / "Fewer settings" switches it between the
most used settings and all of them (changes not saved yet are kept). Each is
remembered (dashboard.ini [view]); a new install starts simple, one that ran
before starts advanced.

Dashboard (Dashboard.ahk): a window with statistics (battles, rounds, cards
cast per card, passes, discards, kill-check hits, potions, cards learned),
what the bot sees right now (your health/mana/pips, the hand card by card - ?
for a card it doesn't know, * for a greyed-out one - enemies' health, zone,
the walker) and the log as it's written. Windows+2 or the tray menu shows /
hides it; it opens on a monitor the game isn't on and remembers where you put
it (dashboard.ini). It never takes the focus by itself. Its X (close) stops
the bot; minimise it (or Windows+2) to just put it away. Next to STATISTICS:
the CPU and RAM in use, every second - the bot (with its vision helper), the
game and the whole PC (CPU share of all cores, RAM in use). Its tabs: Bot (all
that), Dungeons (below) and Spells (the cards it learned - see "Learned spells"
under New cards; tray menu "Learned spells" opens it there).

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

Smart App Control (Windows 11 - "Smart App Control blocked"): it blocks the
bot's exes (they aren't signed) and can't be told to allow them. Run the bot as
scripts instead: install AutoHotkey v1.1 from autohotkey.com (Download > v1.1),
then open ..\Wiz-Maxxing.ahk (not Wiz-Maxxing.exe) - and Setup.ahk for Setup.
Started as a script, everything the bot starts is a script too, by the same
AutoHotkey (the bot, the update check, "Open with Wizard101", Setup's
shortcuts) - never one of the exes. If the vision helper (Python) can't start
there either, cards are found the old way and walking follows the arrow on
screen; the only other way is turning Smart App Control off (Windows Security
> App & browser control - on most PCs it can't be turned back on).

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

Enemy spells (enemyspells:1 - Settings, HEALTH): each round the bot works out
what each enemy will most likely cast and the chance their hits kill you this
round - in debug.log ("enemy spells: ...") and on the dashboard (Threat).
	- Who's fighting and what each cast comes from the game's own log
	  (Bin\WizardClient.log, only read): it names every slot of the circle
	  and each caster's spell each round, passes too.
	- Each creature's spells, pips and damage come from the Wizard101 wiki on
	  Fandom (Wizard101 Central's blocks bots), looked up once and kept in
	  wiki\cache.json for a month; a creature's first battle may show
	  "looking it up". Its pips are guessed from the round (mobs pick a card
	  at random and pass if they can't afford it, so they save up).
	- Every enemy cast seen is counted for its creature (wiki\casts.json),
	  so the odds sharpen with every battle against it.
	- defendat (30): when the chance their hits kill you is that % or more
	  and no hit in hand ends the battle (the kill check goes first), a heal
	  on yourself, else Tower Shield, goes before anything else. 0 = only
	  show the odds. A hit at one target is counted at you 1 in however many
	  wizards are on your side.

Enchants (Strong, Giant, Monstrous, Gargantuan, Colossal, Epic - treasure cards
too) go on the hit about to be cast, a learned hit in no slot as well; an
enchant or a treasure card is never discarded.

Kill check:
At the start of every round the program reads each enemy's health off the
nameplates at the top of the screen and works out how much damage each hit
in your hand would do. If one of them kills every enemy it casts it right
away (the cheapest one that works - the wand's free hit first - and without
the enchant if it doesn't need it) instead of putting up more blades and
traps. A hit on one enemy (<school>.hitNtarget:1) only counts when one enemy
is left. If it can't read the
health, or no hit is enough yet, it plays exactly like before.
	- Draw treasure cards for an enchant that kills (the Settings window, off
	  unless you switch it on): when no hit ends the battle but one would with
	  an enchant on it (any - Strong's +100 counted, drawneed) and there's none
	  in hand, it draws from your treasure-card deck (DRAW, between Pass and
	  Flee) till an enchant comes, then runs the kill check again. Draw is
	  greyed out with 7 cards, so one card it knows is discarded first - never
	  a treasure card, a card it doesn't know or a greyed one, the hit, an
	  enchant, or one you said never to discard. At most drawround (3) draws a
	  round, drawmax (6) a battle; Draw greyed out with room in hand (no treasure
	  cards left): not again for 30 minutes. Never with "Crown" read by the
	  buttons, nor while you play. debug.log: "draw: ...".
	- Enchants: Epic, Colossal, Gargantuan, Monstrous, Giant and Strong (the
	  damage each adds: enchant4, 3, 2, 7, 6, 5 in PlayerStats.txt) - the best
	  in hand goes on the hit. Monstrous, Giant and Strong are learned from the
	  card ("+175 to 1 spell") the first time one's in hand.
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
Every round the bot reads the hand card by card. Only a box that looks like a
card is used (the edge between its picture and its text, the yellow pip digit,
no big white patch, a type icon the helper knows): the deck's back ("Cards 6 of
13"), the round's timer, the floor or a popup over the hand are never learned
or discarded (vision\vision.log lists each box it turned down, and why). A
card it has no picture for, shown in colour (a greyed-out one - not enough
pips - waits until it's castable), is learned:
	- its type from the icon at the bottom right of its picture
	  (ui1.144\cardicons: damage = hits one enemy, aoe = hits all, heal,
	  ward = a shield or a trap, charm = a blade, manip), its pip cost from
	  the yellow digit (ui1.144\carddigits and vision\digits - a digit read
	  is trusted over the pips you had), its kind and numbers from its text
	  (OCR at three sizes, two must agree: "65-105" -> 65; a misread range
	  like "805-345" is put right when only one fix makes sense)
	- kinds it knows: a hit on one enemy or all (with a part over time:
	  only the part up front counts), a heal, a shield (-50%), a trap (+N%
	  with the shield icon), a blade (+N% with the charm icon), an aura
	  (+N% to all spells, or your school's, for some rounds) - and kinds it
	  doesn't play: damage over time only, stun, dispel, prism (convert),
	  "Clear", X-pip spells, weaknesses. Those are kept and recognised, never
	  cast; one it can't be sure of is kept as "unsure" till it's seen at a
	  size where it reads
	- it's saved as <picture set>\learned\<id>.card.png (the whole card, for
	  you to look at) and .png (the picture the bot looks for)
	- it goes into a free slot (one whose picture was never cut), so the
	  battle code uses it like the hand-cut cards: a hit -> <school>\hit1-3,
	  only where they stay weakest to strongest (the battle casts hit3 first;
	  hit4 only for one stronger than all, as hit4 is only cast on bosses), no
	  pips -> wand, heal -> heal1/heal2, shield -> resources\tower, a trap ->
	  resources\trap3 (only "+N% to next spell" at the % PlayerStats.txt has
	  for trap3), an aura -> <school>\aura (only at its aura %), a blade as
	  before (blade3, or your school's blade, at their %). Its numbers
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
fewer - a pip digit read off the card is never changed that way.
learned\cards.txt lists everything learned (with its name, if you gave it
one, and its flags: tc = a treasure card, user = set by you, hold = never
discarded...); debug.log: "learned a new card ...".
Put right by itself, once a run, as soon as the vision helper is up and the
bot is out of battle (nothing is ever deleted - it's moved to backups\):
	- every learned card not checked yet is checked like a card in hand; one
	  that isn't a card (the deck's back, the timer, an empty spot - older
	  versions learned some) is moved out of the list, pictures and line, to
	  backups\learned junk\. Its pips are put right from the digit too.
	- a copy of a learned card's picture in a slot that isn't its own is
	  taken out of that slot (what was there before put back, else the copy
	  moved to backups\learned strays\), with that slot's lines in
	  PlayerStats.txt.
Stronger hits (Settings: "Make room for stronger learned hits", learnupgrade,
on): a learned hit 15% or more stronger than the weakest of hit1-3 takes its
place - out of battle only, never in a round. hit1-3 are then kept weakest to
strongest (the battle casts hit3 first), the cheapest one stays when the new
one costs more, and so does your only all-enemies hit when the new one hits
one enemy. Only slots whose damage and pips are in PlayerStats.txt are
moved; X-pip slots (hitNpips:0) and ones you pin with <school>.hitNkeep:1
stay where they are; a treasure card may take a free slot but never pushes
out a deck spell; the new card needs two OCR reads that agreed (or the
number you typed on the Spells tab) and its pips read off it. Before anything
moves, the three slots' pictures (every picture set's) and their
PlayerStats.txt lines are copied to backups\hits <school> <date-time> (<card
id>)\. Forget the new card on the Spells tab, or change its kind, and it's
all put back while the slots still hold what it left there and you haven't
changed their numbers since (otherwise just the new card comes out, and
debug.log names the backup folder). <school>.learnupgrade:0
switches it off for one school. Updates keep the pictures it moved.
Learned spells (the dashboard's Spells tab, or tray menu "Learned spells"):
every card the bot learned, with its kind, school, pips (3? = guessed),
number, where it's used (or why not), the text it read, whether it's a
treasure card, when and at what size it was learned. Pick one to see its
picture. Pick one or more and:
	- Change kind...: what it really is. It's taken out of its slot (a hit
	  that made room for itself puts the hits it moved back) and gets the
	  slot the new kind fits, if one is free. "Not used" keeps it in the list
	  and out of use.
	- Edit...: its name, its number (a hit's least damage, a heal, the % of a
	  blade, trap, shield or aura) and its pips - e.g. a misread number.
	- Forget: out of the list, its pictures to backups\learned forgotten\. A
	  real card is learned again the next time it's in hand.
	- Never discard: it stays in hand even when the bot doesn't play it.
	- Show picture, Open folder, Moved away... (opens what's in backups\:
	  non-cards, forgotten spells, the hits moved to make room), Refresh.
	The bot makes these changes from its own loop as soon as it's out of
	battle (the status line says when some are waiting); what you set is
	never changed by the learner itself. debug.log: "Spells: ...".
Fleeing: out of mana (less than its cheapest hit costs - every spell costs a
mana a pip - and no wand in hand) or out of cards (the deck used up - a hand
read where none of the boxes looked like a card doesn't count - or no hit in
a hand of fewer than 7 cards: the deck's used up and heals and blades can't
end the battle) for two rounds running, the bot can only pass for the rest of the battle, so it clicks
Flee instead, drinks a potion (none left: goes and buys some) and tries again.
PlayerStats.txt: fleeon:0 switches it off. debug.log: "fleeing: ...", "after
fleeing: ..."; the dashboard counts them next to Passed.
Learned hits in no slot: the bot casts by slot (hit1-4), and a treasure card
never gets one - so when no hit1-3 can go, it casts the strongest learned hit
in hand you can pay for (e.g. a Sandstorm treasure card), a target for a
one-enemy hit; one that doesn't go isn't tried again that battle till there
are more pips. Not thrown away while no hit1-3 can go. learnedhits:0 in
PlayerStats.txt switches it off.
Discarding in normal battles: every round, after it's read the hand, the bot
right-clicks away the cards it knows it never plays - learned cards of a kind
it doesn't play (stun, dispel, damage over time...) or one more card of a kind
whose slots are full - so the next round draws cards it can use; at most 3 a
round. Its own cards stay (also one it learned again at another UI size: where
the battle's own search finds one of its cards, nothing is discarded), and so
do cards it doesn't know yet and learned ones whose kind it couldn't tell. Spare blades and Sharpen go once they
can't stack any more, as before. PlayerStats.txt: discardunused:0 switches it
off, discardmax: how many a round. Learned treasure cards are never discarded
(that would use them up), nor spells set to Never discard on the Spells tab.
debug.log: "Discarded learned card ... - a kind the bot doesn't play: stun".
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
	  "Walk to the potion seller by the map"): nothing to record. The only
	  potion seller is Hilda Brewer in Wizard City's Commons (her spot is in
	  the game's own files). Out of potions anywhere else, the bot leaves a
	  Mark (Page Down) where it is, goes Home (the Home key - outside Wizard
	  City) and to the Commons (End), walks to her by the zone's map (the same
	  route planner as the quest walking), presses X at her prompt, clicks
	  Fill All (found by the words on it - never with "Crown" round it),
	  drinks one, Fills All again, and Recalls (Page Up) back to the Mark to
	  carry on. In the Commons already: no Mark, no Recall. Your house must be
	  in Wizard City (the Dorm is) - else it goes back and tells you. End
	  goes nowhere inside the Dorm, so it walks out its door to Ravenwood
	  first (the way out is in the game's files); End going nowhere there
	  too (it seems to take mana), it walks through Ravenwood's door to the
	  Commons. A Recall takes mana: one that doesn't work keeps the Mark
	  for the next run. With no
	  potions and none to be had it rests (no walking) till health is back.
	  A buying you recorded at your Mark (below) is still used; potionwalk:0
	  for only that.
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
