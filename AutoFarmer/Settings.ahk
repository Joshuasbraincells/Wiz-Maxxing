; Settings.ahk - the Settings window (the dashboard's Settings button, or the tray menu): the mouse and the bot's
; waits, and how it plays its cards. AHK v1.1, functions and labels only; #Included by Autofarmer.ahk.
;
; Every setting is a line in PlayerStats.txt (key:value) - the window only shows them. Save writes the ones you
; changed there, each in its own line with its comment kept (one the file doesn't have yet goes at its end),
; and the bot uses them from its next click or round on: no restart. Point at a setting to see what it does.
;
; Also here: the mouse put back where it was when the bot took it (MouseGrab / MouseLetGo, mousereturn).

;The window; its help line and its note by the buttons; each setting's control (key -> hwnd), the value it
;showed (key -> value) and the help for each label and control (hwnd -> text); the help on show
global CfgHwnd, CfgHelpText, CfgNote, CfgCtls, CfgShownVals, CfgHelps, CfgHelpShown
;The view: simple (only the most used settings - CfgSimpleKeys) or all of them; changes not saved yet, kept across a
;switch of view ({key: value}); where the window was (the switch opens it there again)
global CfgSimple, CfgPending, CfgReopenX, CfgReopenY
;Where the mouse was when the bot took it (MouseGrab), whether that's kept, and when it was taken
global MouseHomeX, MouseHomeY, MouseHomeSet, MouseHomeAt
;Cards of kinds switched off discarded this round (RoundStart clears it; at most discardmax)
global DiscardOffCount

;Every setting in the window, in order: {key, label, kind: "check" (on/off), "num" (lo to hi) or "pick" (picks:
;1, 2, ...), def: its default, help}. {key: "-"} is a heading, {key: "|"} starts the second column. LoadStats
;(KillCalc.ahk) takes the defaults from here too, for a PlayerStats.txt without the line
CfgList()
	{
	static list := ""
	if (IsObject(list))
		return list
	list := []
	list.Push({key: "-", label: "THE MOUSE AND WAITS"})
	list.Push({key: "handsoffon", label: "Wait for me while I play", kind: "check", def: 1
		, help: "While you use the keyboard or mouse yourself the bot waits: no battle rounds, no walking, no potions. (The dashboard's Wait for me button switches it too.) On again, with 3 seconds, every time the bot starts - it never takes the mouse from you as it starts."})
	list.Push({key: "handsoff", label: "Wait for me: seconds after you stop", kind: "num", lo: 0, hi: 3600, def: 3
		, help: "How long after your last key press, click or mouse move the bot carries on. 0 = it never waits for you."})
	list.Push({key: "gamefront", label: "Bring Wizard101 to the front when needed", kind: "check", def: 0
		, help: "When the quest arrow shows (walking) or a battle round is up and Wizard101 isn't the window in front, the bot brings it to the front - walking, only once you've left the keyboard and mouse alone 3 s. Off: click into it yourself. Also the dashboard's 'Game to front' button."})
	list.Push({key: "hungload", label: "Restart Wizard101 stuck on a loading screen (minutes, 0 = never)", kind: "num", lo: 0, hi: 120, def: 5
		, help: "A zone change that never finishes - the game's log says it began this long ago and has written nothing but its memory notes for 3 minutes, and neither the spellbook nor a battle round has shown since: asks (yes in 60 s if nobody answers), closes Wizard101 and starts it again, logging in with the saved login (tray menu: Set Wizard101 login...). Needs Auto-reconnect on. 2026-10-23: a defeat's trip back hung 69 minutes."})
	list.Push({key: "mousereturn", label: "Put the mouse back afterwards", kind: "check", def: 1
		, help: "When the bot takes the mouse - a battle round, a click out of battle - it goes back to where it was once the bot's done (not if you've used the mouse or keys meanwhile). Off: it's left in the middle of the game."})
	list.Push({key: "mousespeed", label: "Mouse speed (0 = jump there)", kind: "num", lo: 0, hi: 100, def: 1
		, help: "How the mouse moves to what it clicks: 0 jumps straight there, 1 is the fastest glide, higher numbers glide slower (100 is the slowest)."})
	list.Push({key: "clickwait", label: "Wait before each click (ms)", kind: "num", lo: 0, hi: 5000, def: 40
		, help: "Between the mouse getting there and the click. Raise it if the game misses clicks."})
	list.Push({key: "clickrandom", label: "...plus a random wait up to (ms)", kind: "num", lo: 0, hi: 5000, def: 0
		, help: "A random 0 to this many ms more before each click, so the clicks aren't evenly timed. 0 = none."})
	list.Push({key: "clickafter", label: "Wait after clicks (% of the usual)", kind: "num", lo: 0, hi: 1000, def: 50
		, help: "The wait after a card and after its target (300 ms at 100). Lower is faster - raise it if a target click gets missed after a card."})
	list.Push({key: "roundwait", label: "Wait before playing a round (ms)", kind: "num", lo: 0, hi: 30000, def: 0
		, help: "From a round showing up (its Pass button) to the bot's first look at the hand. 0 = at once."})
	list.Push({key: "discardafter", label: "Wait after each discard (ms)", kind: "num", lo: 250, hi: 5000, def: 400
		, help: "After each right-click that discards a card from the hand, while the rest slide together (250 at the least)."})
	list.Push({key: "discardlook", label: "Wait before looking at the hand again (ms)", kind: "num", lo: 0, hi: 5000, def: 700
		, help: "After discarding, while the hand slides together, before the cards are looked at again."})
	list.Push({key: "-", label: "HEALTH"})
	list.Push({key: "healat", label: "Heal under this % of health (0 = never)", kind: "num", lo: 0, hi: 100, def: 40
		, help: "In battle: a healing card (the heal1 / heal2 pictures) on yourself when your health is under this %. 0 = never."})
	list.Push({key: "enemyspells", label: "Predict the enemies' spells", kind: "check", def: 1
		, help: "Each round: what each enemy will most likely cast - its spells off the Wizard101 wiki (Fandom), looked up once and kept; its pips guessed from the round; what it was seen casting (the game's own log) - and the chance their hits kill you this round. In debug.log ('enemy spells:') and on the dashboard (Threat; each enemy's every spell on its Cards tab). Needs the vision helper."})
	list.Push({key: "defendat", label: "...defend first at this % chance to die (0 = never)", kind: "num", lo: 0, hi: 100, def: 30
		, help: "When the chance this round's enemy hits kill you is this % or more and no hit in hand ends the battle: a heal on yourself (heal1 / heal2), else Tower Shield, before anything else. 0 = only show the odds."})
	list.Push({key: "potionat", label: "Drink a potion under this % (0 = never)", kind: "num", lo: 0, hi: 100, def: 40
		, help: "Out of battle: a potion (Ctrl+O) when your health is under this % - out of potions, the bot buys more with gold. 0 = never."})
	list.Push({key: "potionwalk", label: "Walk to the potion seller by the map", kind: "check", def: 1
		, help: "Out of potions: to Hilda Brewer in Wizard City's Commons by the zone's map - a Recall to your Mark (anywhere in the Commons) or End in Wizard City - X, Fill All, drink. No recording needed. Off: the recorded ways (tray menu Record potion buying)."})
	list.Push({key: "fleeon", label: "Flee when out of mana or cards", kind: "check", def: 1
		, help: "Out of mana (less than the cheapest hit costs, no wand) or out of cards (none left, or the deck used up and no hit in hand), two rounds running: flee, drink a potion (or buy some), and try again."})
	list.Push({key: "-", label: "WALKING"})
	list.Push({key: "collectmem", label: "Collect quest items by the game's memory", kind: "check", def: 1
		, help: "A 'Collect N <things>' goal whose things lie about the zone (Piece Of Coral in The Grotto): their places are read from the game's memory (read-only) and the nearest is walked to round walls and mobs and picked up, then the next. None seen: it roams and walks into monsters as before. Off: only that. The dashboard's map shows them as green diamonds."})
	list.Push({key: "speedhack", label: "Walk faster with Cheat Engine's speedhack", kind: "check", def: 0
		, help: "Cheat Engine (yours: installed and attached to Wizard101 by you) speeds the game up: the bot presses its speedhack hotkeys - the walking key while it walks, the 1x key for battles, talking, dialogues, shops, near the goal, getting round an obstacle, when you play, {key:bot}, and when it stops. In Cheat Engine: Settings > Hotkeys - 'Speedhack speed' entries for the two keys below, one at the speed below, one at 1, 'Disable when released' unticked (the tray menu's Speedhack items press a key 3 s after you pick them, to set them there). Attach Cheat Engine again after Wizard101 restarts: the bot checks how fast the wizard turns and stops using the speedhack for the run if the game isn't sped up. Risky: KingsIsle may notice."})
	list.Push({key: "speedfactor", label: "...the speed its walking key sets (2 = twice as fast)", kind: "num", lo: 1, hi: 50, def: 2
		, help: "The speed you gave Cheat Engine's walking key: the bot's turn and wait times are divided by it. 2-5 work best; above 5 turns are made at normal speed."})
	list.Push({key: "speedkeyfast", label: "...Cheat Engine's walking key", kind: "pick", def: 2, picks: ["F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24"]
		, help: "The key you set in Cheat Engine for the walking speed."})
	list.Push({key: "speedkeynormal", label: "...Cheat Engine's 1x key", kind: "pick", def: 1, picks: ["F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24"]
		, help: "The key you set in Cheat Engine for normal speed (1)."})
	list.Push({key: "mousesteer", label: "Turn with the mouse while walking", kind: "check", def: 1
		, help: "Walking, the wizard is turned with the mouse (the right button held, the mouse slid) - at once, so it doesn't stop at corners - when you've left the keyboard and mouse alone 3 s, out of battle, by the game's memory, no window open over the game. The mouse goes back where it was. Turns on the spot stay A/D. Off: A/D only, as before."})
	list.Push({key: "mobavoid", label: "Keep away from mobs (not the quest's)", kind: "check", def: 1
		, help: "Walking (quests, the potion seller): the route goes round the zone's mobs - read from the game's memory, read-only - so no battle starts on the way. Not the mobs the quest is about (named in its goal, or standing at it), and not while collecting. With no way round, it waits for the mob to move off (25 s at most). The dashboard's Map shows them: red dots."})
	list.Push({key: "mobshape", label: "...what they see", kind: "pick", def: 2, picks: ["A circle all round", "A semi-circle in front", "A cone in front"]
		, help: "The shape round each mob the route keeps out of - a mob notices you there. In front: which way it faces is read from the game (unknown: the whole circle), and a little room is kept all round its body. The dashboard's Map draws it."})
	list.Push({key: "mobradius", label: "...how far they notice you (game units)", kind: "num", lo: 100, hi: 3000, def: 300
		, help: "How far the shape reaches from a mob. More: safer, but narrow streets may leave no way round (then it waits for the mob to turn or move)."})
	list.Push({key: "mobcone", label: "...the cone's width (degrees; a cone only)", kind: "num", lo: 5, hi: 180, def: 60
		, help: "With 'A cone in front': how wide the cone is. Players say 50 to 120."})
	list.Push({key: "mobbody", label: "...their reach all round (semi-circle / cone)", kind: "num", lo: 60, hi: 1500, def: 120
		, help: "With a semi-circle or cone in front: how far round the rest of each mob the route keeps away too - a mob notices you beside or behind it from nearer than in front."})
	list.Push({key: "mobgrow", label: "...more after each battle a mob not the quest's starts", kind: "check", def: 1
		, help: "Caught by a mob the quest doesn't need (not collecting, not one in the goal line, not right after X at the goal): the reach is raised to where it caught you from, and a bit - its front's (how far they notice you) when it caught you in front, its reach all round when from the side or behind. 1500 at most; set them back in Settings any time."})
	list.Push({key: "mobshrink", label: "...less after 10 minutes walking without one", kind: "check", def: 1
		, help: "Every 10 minutes of walking without a mob the quest doesn't need catching the wizard, both reaches are made a tenth smaller - never below what you set yourself here (else 300 and 120) - so the routes don't go the long way round for nothing. A catch raises them again (the setting above)."})
	list.Push({key: "|"})
	list.Push({key: "-", label: "HOW IT PLAYS ITS CARDS"})
	list.Push({key: "cardlogic", label: "Card logic", kind: "pick", def: 1, picks: ["Boost first, then hit", "Hit first (fast)", "Boss: boost first - mobs: hit first"]
		, help: "Boost first: traps on the boss, blades, the bubble and aura, then the biggest hit it can cast. Hit first: the biggest hit it can cast as soon as it has one, boosting only in rounds it has none (quick on weak mobs). Boss/mobs: boost first once you've picked a boss ({key:boss}), else hit first."})
	list.Push({key: "boostmax", label: "Boosts before each hit (0 = all it has)", kind: "num", lo: 0, hi: 20, def: 0
		, help: "Boosting first: at most this many boost cards (blades, traps, bubble, aura) go before a hit it can cast. 0 = every one it has."})
	list.Push({key: "healthocr", label: "Kill check: hit at once if that kills", kind: "check", def: 1
		, help: "Reads every enemy's health off the nameplates, and if a hit in hand already kills them all it's cast at once instead of more boosts. (Options > 2D Combat Display must be on.)"})
	list.Push({key: "killmargin", label: "Kill check margin (%)", kind: "num", lo: 0, hi: 200, def: 15
		, help: "A hit only counts as a kill when its least damage is this % more than the health left (covers shields and misreads)."})
	list.Push({key: "useblades", label: "Use blades (and Sharpen)", kind: "check", def: 1
		, help: "Off: blades and Sharpen aren't played (with Discard cards it never plays on, they're discarded)."})
	list.Push({key: "usetraps", label: "Use traps and Feint on the boss (and Potent)", kind: "check", def: 1
		, help: "Off: traps, Feint and Potent aren't played (with Discard cards it never plays on, they're discarded). Traps only ever go on a boss you picked ({key:boss})."})
	list.Push({key: "usebubble", label: "Use the bubble (global)", kind: "check", def: 1
		, help: "Off: your school's bubble isn't played (with Discard cards it never plays on, it's discarded)."})
	list.Push({key: "useaura", label: "Use the aura", kind: "check", def: 1
		, help: "Off: your school's aura isn't played (with Discard cards it never plays on, it's discarded)."})
	list.Push({key: "usewand", label: "Use the wand's hit", kind: "check", def: 1
		, help: "Off: the wand's own card (e.g. Minor Clash) isn't played - and isn't counted as a hit without mana when fleeing."})
	list.Push({key: "usetower", label: "Use Tower Shield", kind: "check", def: 1
		, help: "Off: Tower Shield isn't played (with Discard cards it never plays on, it's discarded)."})
	list.Push({key: "usereshuffle", label: "Use Reshuffle", kind: "check", def: 1
		, help: "Off: Reshuffle isn't played (with Discard cards it never plays on, it's discarded)."})
	list.Push({key: "drawenchant", label: "Draw treasure cards for an enchant that kills", kind: "check", def: 0
		, help: "No hit in hand ends the battle, but one would with an enchant on it (any - Strong's +100 counted) and there's none in hand: Draw from your treasure-card deck till one comes. Draw is greyed out with 7 cards, so one card is discarded first - never a treasure card, the hit, or an enchant. Then the kill check again: the hit goes enchanted if it kills; else the enchant's kept. At most 3 draws a round, 6 a battle."})
	list.Push({key: "reboost", label: "Boost again after each hit", kind: "check", def: 0
		, help: "After each hit its blades and traps may be cast again for the next one. Off: each is cast once a battle."})
	list.Push({key: "solotraps", label: "I fight alone (count my traps)", kind: "check", def: 0
		, help: "Your traps and Feint go on the boss you picked (Alt+1), else - every battle - on the enemy with the most health. On: the kill check counts them on that enemy. Leave it off when others fight with you: their hits use your traps up without the bot seeing it."})
	list.Push({key: "pipsave", label: "Save pips for a finishing hit (rounds)", kind: "num", lo: 0, hi: 20, def: 3
		, help: "Up to this many rounds, pips are saved for a hit in hand that ends the battle once it's affordable. 0 = never."})
	list.Push({key: "discardunused", label: "Discard cards it never plays", kind: "check", def: 1
		, help: "Every round, cards in hand the bot doesn't play (and kinds switched off above) are discarded with a right-click so it draws ones it can use. Not treasure cards it learned (discarding one uses it up), nor spells set to Never discard on the dashboard's Spells tab."})
	list.Push({key: "discardmax", label: "...at most this many a round", kind: "num", lo: 0, hi: 7, def: 3
		, help: "The most cards it never plays that are discarded in one round."})
	list.Push({key: "discardunaffordable", label: "Discard hits it can't cast yet", kind: "check", def: 0
		, help: "A hit you haven't the pips for is discarded instead of kept for a later round."})
	list.Push({key: "learnupgrade", label: "Make room for stronger learned hits", kind: "check", def: 1
		, help: "A learned hit 15% or more stronger than your weakest in hit1-3 takes its place, out of battle; hit1-3 stay weakest to strongest (the cheapest, your only all-enemies hit, X-pip and hitNkeep:1 slots stay put). Undo: Forget it or change its kind on the Spells tab. One school off: <school>.learnupgrade:0."})
	list.Push({key: "-", label: "NETWORK (THE DASHBOARD'S NETWORK TAB)"})
	list.Push({key: "neton", label: "Show this bot to the others on your home network", kind: "check", def: 0
		, help: "Its state (PC, version, wizard, zone, on/off, Play for me, what it's doing, health, mana, deaths, last log line) goes to every bot on your home network with this on, and theirs shows on the dashboard's Network tab - with their log and game when you pick one. Windows asks once to let Python through its firewall: allow it on Private networks (your network has to be set to Private). Off: nothing sent or listened for."})
	list.Push({key: "netport", label: "...on the port", kind: "num", lo: 1024, hi: 65535, def: 47150
		, help: "The same on every PC. UDP for finding each other, TCP for the log, the picture and commands."})
	list.Push({key: "netpin", label: "...network PIN for commands (0 = none)", kind: "num", lo: 0, hi: 99999999, def: 0
		, help: "The Network tab's buttons (bot on, bot off, Play for me off, restart) only work between bots with the same PIN, not 0. Play for me can only be switched off from the network - on needs pimpmeout typed at that PC."})
	list.Push({key: "-", label: "UPDATES"})
	list.Push({key: "autoupdate", label: "Update by itself: look every (minutes, 0 = never)", kind: "num", lo: 0, hi: 1440, def: 10
		, help: "A new version on GitHub is downloaded while the bot plays on, then installed with no question: the bot closes itself for it once it's out of battle, nothing's loading and you've left the keyboard and mouse alone a minute (Play for me: no wait) - not during a dungeon run or a recording - and starts again as it was: on, off or in standby, Play for me, walking ({key:walk}), auto-reconnect and Learn every card as they were. Your settings, learned cards and routes are kept, as with the Updates button. A version that won't install 3 times is left to the Updates button. 0: only when you click it."})
	list.Push({key: "-", label: "ALERTS"})
	list.Push({key: "logmirror", label: "Copy the log to OneDrive (help from another PC)", kind: "check", def: 0
		, help: "debug.log is also written to your OneDrive folder (Wiz-Maxxing logs\<this PC's name>), with a picture of the game every 2 minutes and at each alert (the newest 15) - OneDrive syncs it to your other PCs, so the bot can be followed from there. Nothing else is sent anywhere."})
	list.Push({key: "alertson", label: "Discord alerts when the wizard needs you", kind: "check", def: 1
		, help: "Stuck, out of potions or mana, logged out, a quest that needs you...: a message to your Discord channel - once its webhook is set (tray menu: Discord alerts...). The same alert at most once in 10 minutes."})
	list.Push({key: "-", label: "PARTY (ONE WIZARD PER PC, SAME HOME NETWORK)"})
	list.Push({key: "partyrole", label: "This wizard in the party", kind: "pick", def: 1, picks: ["Off", "Leader - quests, the others follow", "Follower - goes where the leader goes"]
		, help: "Leader: quests as now, and waits while a follower is far, in another zone or not ready. Follower: goes where the leader goes instead of its own quest - to it, through the door it took, into its battles. Set this wizard's party name, and on a follower the leader PC's address, with the tray menu's Party.... The leader's PC asks once (Windows) to let Python through its firewall - allow it on Private networks."})
	list.Push({key: "partyport", label: "...the party's port", kind: "num", lo: 1024, hi: 65535, def: 47140
		, help: "The leader's bot listens for its followers on this port of your home network; the same on every PC in the party."})
	list.Push({key: "partynear", label: "...a follower stays this near the leader", kind: "num", lo: 80, hi: 2000, def: 250
		, help: "A follower walks to within this many game units of the leader, and walks again once the leader is twice as far."})
	list.Push({key: "partywaitdist", label: "...the leader waits for one farther than", kind: "num", lo: 300, hi: 10000, def: 800
		, help: "The leader stops while a follower is farther than this (game units), in another zone, loading or not ready."})
	list.Push({key: "partywaitmax", label: "...but for at most (s, 0 = no waiting)", kind: "num", lo: 0, hi: 900, def: 60
		, help: "How long the leader waits for one follower; after that it walks on without it till it's been near again."})
	list.Push({key: "partybattle", label: "...in a party battle this wizard is the", kind: "pick", def: 1, picks: ["Hitter - plays as now", "Blader - boosts the party's hitter", "Healer - heals the party, else boosts"]
		, help: "A battle with more of the party's wizards on your side: Hitter plays as now. Blader puts its blades on the party's hitter (the wizard set to Hitter, else the leader) and its traps on the enemy the hitter goes for, casting them again after each of its hits, Tower Shield on it, and hits only for a kill or with nothing else to do. Healer heals whichever of you is lowest under 'Heal under this %', shields them, else boosts as a blader. Each wizard's name has to be known: one battle on its own first. One school's wizard its own: <school>.partybattle:2 in PlayerStats.txt. {key:boost} on a plate: the boosts go there (a friend without the bot)."})
	return list
	}

;The settings the simple view shows - the most used ones
CfgSimpleKeys()
	{
	static keys := ""
	if (!IsObject(keys))
		{
		keys := {}
		for each, k in ["handsoffon", "gamefront", "healat", "potionat", "potionwalk", "fleeon", "enemyspells", "defendat", "mobavoid", "mousesteer", "speedhack"
			, "cardlogic", "healthocr", "drawenchant", "alertson", "partyrole", "partybattle"]
			keys[k] := 1
		}
	return keys
	}

;CfgList as the view shows it: all of it, or (simple) only CfgSimpleKeys' settings, the headings that have some under
;them, no "|" column breaks (the window's height decides)
CfgViewList()
	{
	if (!CfgSimple)
		return CfgList()
	keys := CfgSimpleKeys(), out := [], head := ""
	for each, s in CfgList()
		{
		if (s.key = "-")
			head := s
		else if (s.key != "|" && keys.HasKey(s.key))
			{
			if (IsObject(head))
				out.Push(head), head := ""
			out.Push(s)
			}
		}
	return out
	}

;A help text's keys ({key:<id>}: {key:boss} -> Alt+1...) as they're set now - the Keys tab's, Hotkeys.ahk (CfgList is
;made once, the window afresh each time it opens)
CfgKeyWords(text)
	{
	while (RegExMatch(text, "\{key:(\w+)\}", m))
		text := StrReplace(text, m, HkText(m1))
	return text
	}

;Opens the window - made afresh, with the values in use now - or brings it to the front if it's open
CfgShow()
	{
	static hooked := 0
	if (CfgHwnd && WinExist("ahk_id " CfgHwnd))
		{
		WinActivate, ahk_id %CfgHwnd%
		return
		}
	;(the help line follows the mouse: WM_MOUSEMOVE)
	if (!hooked)
		OnMessage(0x200, Func("CfgHover")), hooked := 1
	CfgCtls := {}, CfgShownVals := {}, CfgHelps := {}, CfgHelpShown := ""
	CfgSimple := ViewSimple("settings")
	Gui, Cfg:New, +HwndCfgHwnd -MaximizeBox, % "Wizard101 bot " BotVersion() " - settings"
	Gui, Cfg:Color, 1B1D22, 111317
	Gui, Cfg:Margin, 12, 10
	;(next to the dashboard when it's up, else in the middle of the main monitor - all of it on that monitor: the
	;settings in columns (CfgPlace) as tall and as many as fit it, with the help line and the buttons under them; more
	;columns than fit its width: a tab for each heading, its settings in columns inside it)
	cfgPos := "", cfgAtX := A_ScreenWidth // 2, cfgAtY := A_ScreenHeight // 2
	if (DashHwnd && DashShown)
		{
		;(not a minimised dashboard's place: -32000)
		WinGet, cfgMm, MinMax, ahk_id %DashHwnd%
		WinGetPos, cfgDx, cfgDy, , , ahk_id %DashHwnd%
		if (cfgDx != "" && cfgMm != -1)
			cfgPos := "x" cfgDx + 30 " y" cfgDy + 60 " ", cfgAtX := cfgDx + 30, cfgAtY := cfgDy + 60
		}
	;(the view switched: where the window was)
	if (CfgReopenX != "")
		cfgPos := "x" CfgReopenX " y" CfgReopenY " ", cfgAtX := CfgReopenX, cfgAtY := CfgReopenY, CfgReopenX := ""
	DashMonitorAt(cfgAtX, cfgAtY, cfgML, cfgMT, cfgMR, cfgMB)
	cfgMaxY := Max(300, Floor((cfgMB - cfgMT) * 96 / A_ScreenDPI) - 140)
	;(column n's right edge: 434 + 432 (n - 1), and the window's frame)
	cfgMaxCols := Max(1, (Floor((cfgMR - cfgML) * 96 / A_ScreenDPI) - 24 - 434) // 432 + 1)
	cfgPlan := CfgPlace(cfgMaxY, false)
	if (cfgPlan.cols > cfgMaxCols)
		{
		;(the tabs' row of buttons above the settings, its frame below them)
		cfgPlan := CfgPlace(cfgMaxY - 10, true)
		cfgTabNames := ""
		for each, cfgT in cfgPlan.tabs
			cfgTabNames .= (cfgTabNames = "" ? "" : "|") cfgT
		Gui, Cfg:Font, s9 w600 cF2F2F2, Segoe UI
		Gui, Cfg:Add, Tab3, % "x6 y8 w" 432 * cfgPlan.cols + 6 " h" cfgPlan.bottom + 2 " +Buttons -Theme", %cfgTabNames%
		}
	cfgTab := 0
	for each, cfgAt in cfgPlan.items
		{
		cfgS := cfgAt.s, cfgX := cfgAt.x, cfgY := cfgAt.y
		if (cfgAt.tab != cfgTab)
			{
			cfgTab := cfgAt.tab
			Gui, Cfg:Tab, %cfgTab%
			}
		if (cfgS.key = "-")
			{
			Gui, Cfg:Font, s9 w600 c8AB4F8, Segoe UI
			Gui, Cfg:Add, Text, % "x" cfgX " y" cfgY " w410 h18", % cfgS.label
			continue
			}
		cfgV := Stats.HasKey(cfgS.key) ? Stats[cfgS.key] : cfgS.def
		;(a wizard's own value - storm.killmargin... - is used when it fights as that school; the window doesn't
		;change it, so the help says where it is)
		cfgHelp := CfgKeyWords(cfgS.help)
		for each, cfgSch in ["storm", "fire", "ice", "life", "death", "myth", "balance"]
			if (Stats.HasKey(cfgSch "." cfgS.key))
				cfgHelp .= "  Your " cfgSch " wizard has its own: " cfgSch "." cfgS.key ":" Stats[cfgSch "." cfgS.key] " in PlayerStats.txt (change it there)."
		;(a label the mouse can be over - SS_NOTIFY - and its control right of it)
		cfgW := (cfgS.kind = "pick") ? 90 : 300
		Gui, Cfg:Font, s9 w400 cDADADA, Segoe UI
		Gui, Cfg:Add, Text, % "x" cfgX " y" cfgY + 3 " w" cfgW " h18 +0x100 HwndcfgL", % cfgS.label
		cfgCx := cfgX + cfgW + 8
		;(a change not saved before the view was switched: shown, still to be saved - cfgV stays what's in use)
		cfgNew := (IsObject(CfgPending) && CfgPending.HasKey(cfgS.key)) ? CfgPending[cfgS.key] : ""
		if (cfgS.kind = "check")
			{
			cfgV := cfgV ? 1 : 0
			Gui, Cfg:Add, Checkbox, % "x" cfgCx " y" cfgY + 3 " w18 h18 HwndcfgC Checked" (cfgNew != "" ? cfgNew : cfgV)
			}
		else if (cfgS.kind = "pick")
			{
			cfgV := Max(1, Min(cfgS.picks.Length(), Round(cfgV)))
			cfgList := ""
			for each, cfgP in cfgS.picks
				cfgList .= (cfgList = "" ? "" : "|") cfgP
			Gui, Cfg:Add, DropDownList, % "x" cfgCx " y" cfgY " w312 AltSubmit HwndcfgC Choose" (cfgNew != "" ? cfgNew : cfgV), %cfgList%
			}
		else
			{
			cfgV := Round(cfgV)
			Gui, Cfg:Add, Edit, % "x" cfgCx " y" cfgY " w70 h22 Number Right HwndcfgC", % cfgNew != "" ? cfgNew : cfgV
			;(0x80: no thousands commas)
			Gui, Cfg:Add, UpDown, % "Range" cfgS.lo "-" cfgS.hi " 0x80 HwndcfgU", % cfgNew != "" ? cfgNew : cfgV
			CfgHelps[cfgU + 0] := cfgHelp
			}
		CfgCtls[cfgS.key] := cfgC, CfgShownVals[cfgS.key] := cfgV
		CfgHelps[cfgL + 0] := cfgHelp, CfgHelps[cfgC + 0] := cfgHelp
		}
	if (cfgTab)
		Gui, Cfg:Tab
	cfgY := cfgPlan.bottom + (cfgTab ? 14 : 6)
	Gui, Cfg:Font, s9 w400 c9AA0A6, Segoe UI
	cfgHelpW := 432 * cfgPlan.cols - 32
	CfgPending := ""
	Gui, Cfg:Add, Text, x12 y%cfgY% w%cfgHelpW% h36 vCfgHelpText, % "Point at a setting to see what it does. Each is a line in PlayerStats.txt: Save writes them there and the bot uses them at once - no restart." (CfgSimple ? " These are the most used ones - All settings shows the rest." : "")
	cfgY += 44
	Gui, Cfg:Font, s9 w400 c000000, Segoe UI
	Gui, Cfg:Add, Button, x12 y%cfgY% w90 h26 Default gCfgSave, Save
	Gui, Cfg:Add, Button, x+8 yp w90 h26 gCfgDefaults, Defaults
	Gui, Cfg:Add, Button, x+8 yp w150 h26 gCfgOpenFile, Open PlayerStats.txt
	Gui, Cfg:Add, Button, x+8 yp w90 h26 gCfgGuiClose, Close
	Gui, Cfg:Add, Button, x+8 yp w110 h26 gCfgViewToggle, % CfgSimple ? "All settings" : "Fewer settings"
	Gui, Cfg:Font, s9 w400 cB9E2B9, Segoe UI
	Gui, Cfg:Add, Text, x+14 yp+5 w370 h18 vCfgNote
	Gui, Cfg:Show, % cfgPos "AutoSize", % "Wizard101 bot " BotVersion() " - settings"
	;(all of it on that monitor - its Save button too: moved up and left as far as it needs)
	WinGetPos, cfgWx, cfgWy, cfgWw, cfgWh, ahk_id %CfgHwnd%
	if (cfgWx != "")
		{
		cfgNx := Max(cfgML, Min(cfgWx, cfgMR - cfgWw)), cfgNy := Max(cfgMT, Min(cfgWy, cfgMB - cfgWh))
		if (cfgNx != cfgWx || cfgNy != cfgWy)
			WinMove, ahk_id %CfgHwnd%, , %cfgNx%, %cfgNy%
		}
	}

;Where each of CfgList's settings and headings goes in the window: {items: [{s: the setting, x, y, tab}], cols: the
;most columns, bottom: the lowest y used, tabs: their names}. Down in columns from the top, a new one at "|" and
;wherever the next wouldn't end above maxY (a heading goes with its first setting). tabbed: each heading starts a
;tab of its own (named after it; the heading itself not shown), the settings under the tabs' buttons, "|" left out
CfgPlace(maxY, tabbed)
	{
	top := tabbed ? 44 : 12
	plan := {items: [], cols: 1, bottom: top, tabs: []}
	x := 12, y := top, col := 1
	for each, s in CfgViewList()
		{
		if (s.key = "|")
			{
			if (!tabbed && y > top)
				x += 432, y := top, col += 1
			continue
			}
		if (s.key = "-" && tabbed)
			{
			name := s.label
			StringLower, name, name
			plan.tabs.Push(Format("{:U}", SubStr(name, 1, 1)) SubStr(name, 2)), x := 12, y := top, col := 1
			continue
			}
		if (y > top && y + (s.key = "-" ? 8 + 26 + 28 : 28) > maxY)
			x += 432, y := top, col += 1
		;(a gap above a heading that isn't the first)
		if (s.key = "-" && y > top)
			y += 8
		plan.items.Push({s: s, x: x, y: y, tab: plan.tabs.Length()})
		y += (s.key = "-") ? 26 : 28
		plan.bottom := Max(plan.bottom, y), plan.cols := Max(plan.cols, col)
		}
	return plan
	}

;The help for what the mouse is over: a label (SS_NOTIFY) or a control in the window
CfgHover(wParam, lParam, msg, hwnd)
	{
	if (A_Gui != "Cfg" || !IsObject(CfgHelps))
		return
	cfgT := CfgHelps.HasKey(hwnd + 0) ? CfgHelps[hwnd + 0] : ""
	if (cfgT = "" || cfgT == CfgHelpShown)
		return
	CfgHelpShown := cfgT
	GuiControl, Cfg:, CfgHelpText, %cfgT%
	}

;Writes the settings changed in the window to PlayerStats.txt and reads them all again (used from now on).
;A number outside its range is brought into it; one that isn't a number is left as it was
CfgSaveNow()
	{
	cfgPairs := [], cfgSaid := "", cfgFixed := ""
	for each, cfgS in CfgList()
		{
		if (!CfgCtls.HasKey(cfgS.key))
			continue
		cfgC := CfgCtls[cfgS.key]
		GuiControlGet, cfgV, Cfg:, %cfgC%
		if (cfgS.kind = "num")
			{
			cfgV := Trim(cfgV)
			if cfgV is not integer
				{
				cfgFixed .= ", " cfgS.key " (not a number - left as it was)"
				GuiControl, Cfg:, %cfgC%, % CfgShownVals[cfgS.key]
				continue
				}
			if (cfgV < cfgS.lo || cfgV > cfgS.hi)
				{
				cfgV := Max(cfgS.lo, Min(cfgS.hi, cfgV))
				cfgFixed .= ", " cfgS.key " (" cfgS.lo " to " cfgS.hi ": " cfgV ")"
				GuiControl, Cfg:, %cfgC%, %cfgV%
				}
			}
		cfgV += 0
		if (cfgV != CfgShownVals[cfgS.key])
			cfgPairs.Push([cfgS.key, cfgV]), cfgSaid .= ", " cfgS.key " " CfgShownVals[cfgS.key] " -> " cfgV
		}
	if (!cfgPairs.Length())
		{
		GuiControl, Cfg:, CfgNote, % "Nothing changed" (cfgFixed = "" ? "" : " - " SubStr(cfgFixed, 3))
		return
		}
	;(the mobs' reach you set yourself: the least the shrink after quiet walking comes back down to - Vision.ahk
	;MobShrinkTick)
	for each, cfgKv in cfgPairs.Clone()
		if (cfgKv[1] = "mobradius" || cfgKv[1] = "mobbody")
			cfgPairs.Push([cfgKv[1] "floor", cfgKv[2]])
	if (!CfgWrite(cfgPairs))
		{
		GuiControl, Cfg:, CfgNote, Couldn't write PlayerStats.txt - nothing was saved
		DebugLog("Settings: couldn't write PlayerStats.txt - nothing was saved")
		return
		}
	for each, cfgKv in cfgPairs
		CfgShownVals[cfgKv[1]] := cfgKv[2]
	;(the tray menu's tick and the dashboard's Wait for me button)
	HandsOffShow()
	DebugLog("Settings saved (used from now on): " SubStr(cfgSaid, 3) (cfgFixed = "" ? "" : " | " SubStr(cfgFixed, 3)))
	GuiControl, Cfg:, CfgNote, % "Saved " cfgPairs.Length() " change" (cfgPairs.Length() = 1 ? "" : "s") " - used from now on" (cfgFixed = "" ? "" : " (" SubStr(cfgFixed, 3) ")")
	}

;Every setting's default in the window (saved only with Save)
CfgFillDefaults()
	{
	for each, cfgS in CfgList()
		{
		if (!CfgCtls.HasKey(cfgS.key))
			continue
		cfgC := CfgCtls[cfgS.key]
		if (cfgS.kind = "pick")
			GuiControl, Cfg:Choose, %cfgC%, % cfgS.def
		else
			GuiControl, Cfg:, %cfgC%, % cfgS.def
		}
	GuiControl, Cfg:, CfgNote, Defaults filled in - Save to use them
	}

;Sets key:value lines in PlayerStats.txt - in their own lines (every one, if a key is in more than one), their
;comments kept; one the file doesn't have yet at its end, under a heading - and reads the settings again.
;False if the file couldn't be written
CfgWrite(pairs)
	{
	cfgWas := A_IsCritical
	Critical
	cfgPath := A_WorkingDir "\PlayerStats.txt"
	cfgText := ""
	if (FileExist(cfgPath))
		{
		FileRead, cfgText, %cfgPath%
		if (ErrorLevel)
			return CfgUncritical(cfgWas, false)
		}
	cfgLines := StrSplit(StrReplace(cfgText, "`r"), "`n")
	if (cfgLines.Length() && cfgLines[cfgLines.Length()] = "")
		cfgLines.Pop()
	cfgHead := "; ---- Set in the Settings window (the dashboard's Settings button) ----"
	for each, cfgKv in pairs
		{
		cfgFound := false
		for cfgI, cfgLn in cfgLines
			if (RegExMatch(cfgLn, "i)^(\s*\Q" cfgKv[1] "\E\s*:\s*)[^;\s]*(.*)$", cfgM))
				cfgLines[cfgI] := cfgM1 cfgKv[2] cfgM2, cfgFound := true
		if (cfgFound)
			continue
		cfgHas := false
		for cfgI, cfgLn in cfgLines
			if (cfgLn == cfgHead)
				cfgHas := true
		if (!cfgHas)
			cfgLines.Push(""), cfgLines.Push(cfgHead)
		cfgLines.Push(cfgKv[1] ":" cfgKv[2])
		}
	cfgOut := ""
	for cfgI, cfgLn in cfgLines
		cfgOut .= cfgLn "`r`n"
	FileDelete, %cfgPath%.tmp
	FileAppend, %cfgOut%, %cfgPath%.tmp
	if (ErrorLevel)
		return CfgUncritical(cfgWas, false)
	FileMove, %cfgPath%.tmp, %cfgPath%, 1
	if (ErrorLevel)
		return CfgUncritical(cfgWas, false)
	LoadStats(true)
	return CfgUncritical(cfgWas, true)
	}

;Critical off again unless it was on before (wasOn); returns result
CfgUncritical(wasOn, result)
	{
	if (!wasOn)
		Critical, Off
	return result
	}

;---- The mouse back where it was ----

;Remembers where the mouse is as the bot takes it (a battle round, a click out of battle) - unless that's
;remembered already: it goes back once, when the bot's done (MouseLetGo). True if it was taken now. Not with
;mousereturn:0 (the Settings window's "Put the mouse back afterwards")
MouseGrab()
	{
	;(one taken over 10 minutes ago and never given back is stale: taken afresh)
	if ((MouseHomeSet && A_TickCount - MouseHomeAt < 600000) || !Stat("mousereturn"))
		return false
	MouseGetPos, MouseHomeX, MouseHomeY
	MouseHomeSet := 1, MouseHomeAt := A_TickCount
	return true
	}

;Puts the mouse back where MouseGrab found it - not if you've used the keyboard or mouse since (you're there:
;it's yours) - and forgets it. 1 if it's back there, -1 if it was left to you, 0 if nothing was taken (or
;mousereturn:0)
MouseLetGo()
	{
	if (!MouseHomeSet)
		return 0
	MouseHomeSet := 0
	if (!Stat("mousereturn"))
		return 0
	if (UserIdle() < A_TickCount - MouseHomeAt)
		return -1
	MouseGetPos, mouseNowX, mouseNowY
	;(on the game, going off it: over the scene first - Wizard101 keeps showing the button the mouse last left it from
	;as hovered (Pass: white, and the next round's Pass isn't known by its picture)
	if ((mouseNowX != MouseHomeX || mouseNowY != MouseHomeY) && MouseOnGame(mouseNowX, mouseNowY) && !MouseOnGame(MouseHomeX, MouseHomeY))
		{
		MouseMove, ScreenX, GameTop + Round(GameH * 0.4), 0
		Sleep, 60
		}
	if (mouseNowX != MouseHomeX || mouseNowY != MouseHomeY)
		MouseMove, MouseHomeX, MouseHomeY, 0
	return 1
	}

;Whether screen point x, y is on the game's picture (GameLeft.. - its client area)
MouseOnGame(x, y)
	{
	return x >= GameLeft && x < GameLeft + GameW && y >= GameTop && y < GameTop + GameH
	}

;---- How it plays its cards ----

;Hit first this round, before any boost? (cardlogic: 2 = hit first, 3 = hit first unless a boss is picked)
CardHitFirst()
	{
	cardWay := Stat("cardlogic")
	return (cardWay = 2 || (cardWay = 3 && BossChoosen != 1))
	}

;May a boost card go this round? Not once boostmax of them have gone since the last hit while a hit can be
;cast (boostmax 0: no limit; nothing to hit with: boosting is all it can do)
CardBoostOk()
	{
	cardMax := Stat("boostmax")
	if (cardMax <= 0 || BoostRun < cardMax || !CardHitReady())
		return true
	DebugLog("  " BoostRun " boost" (BoostRun = 1 ? "" : "s") " since the last hit (boostmax " cardMax "): hitting now")
	return false
	}

;A hit in hand (hit4 only on a picked boss) you can pay for and aren't saving pips against (not the wand's)
CardHitReady()
	{
	return (hit4 == 1 && BossChoosen = 1 && CardHitCanGo("hit4")) || (hit3 == 1 && CardHitCanGo("hit3"))
		|| (hit2 == 1 && CardHitCanGo("hit2")) || (hit1 == 1 && CardHitCanGo("hit1"))
		;(a learned hit in no slot: cast when none of these can go - CastLearnedHit)
		|| (PipsNow >= 0 && PipSaveFor = "" && LearnHitReady())
	}

;(pips unknown - your nameplate not found - isn't "can pay": boosting isn't held back for a hit that may not go)
CardHitCanGo(name)
	{
	return PipsNow >= 0 && Affordable(name) && (PipSaveFor = "" || PipSaveFor = name)
	}

;The biggest hit in hand it can cast (hit4 only on a picked boss) - not the wand's - else a learned hit in no slot
;(CastLearnedHit). True if one was cast. With the game's hand read this look, the planned hit first (KillCalc.ahk
;BoostPick - the one dealing the most with the boosts in hand and on, the user 2026-10-24), then the others as ever
CastBestHit()
	{
	global
	local cbhP
	cbhP := PlanHit
	if (BoostMemOk && RegExMatch(cbhP, "^hit[1-4]$") && (cbhP != "hit4" || BossChoosen = 1))
		if (%cbhP% == 1 && UseHit(cbhP, %cbhP%, hitschool))
			{
			BoostRun := 0
			return true
			}
	if ((hit4 == 1) && (BossChoosen = 1) && UseHit("hit4", hit4, hitschool))
		|| ((hit3 == 1) && UseHit("hit3", hit3, hitschool))
		|| ((hit2 == 1) && UseHit("hit2", hit2, hitschool))
		|| ((hit1 == 1) && UseHit("hit1", hit1, hitschool))
		|| CastLearnedHit()
		{
		BoostRun := 0
		return true
		}
	return false
	}

;Cards of a kind switched off in the Settings window (useblades, usetraps...) are never played: with
;discardunused on they're discarded like the others it never plays - at most discardmax a round, and not while
;you play. Returns how many were
DiscardSwitchedOff()
	{
	global
	local did := 0, dsoK
	if (Stat("discardunused") != 1 || DiscardOffCount >= Stat("discardmax") || PlayerActing())
		return 0
	;(each school's blades and traps found, the group's - KillCalc.ahk BoostSearch: SbFound, GbFound)
	if (!Stat("useblades"))
		{
		for dsoK in SbFound
			if (BoostKind(dsoK) = "blade")
				did += DiscardOffOne("blade", SubStr(dsoK, 1, InStr(dsoK, "/") - 1))
		for dsoK in GbFound
			if (BoostKind(dsoK) = "blade")
				did += DiscardOffOne(dsoK, "resources")
		if (blade3 == 1)
			did += DiscardOffOne("blade3", "resources")
		if (blade4 == 1)
			did += DiscardOffOne("blade4", "resources")
		if (sharpen == 1)
			did += DiscardOffOne("sharpen", "resources")
		}
	if (!Stat("usetraps"))
		{
		for dsoK in SbFound
			if (BoostKind(dsoK) = "trap")
				did += DiscardOffOne("trap", SubStr(dsoK, 1, InStr(dsoK, "/") - 1))
		for dsoK in GbFound
			if (BoostKind(dsoK) = "trap")
				did += DiscardOffOne(dsoK, "resources")
		if (trap3 == 1)
			did += DiscardOffOne("trap3", "resources")
		if (feint == 1)
			did += DiscardOffOne("feint", "resources")
		if (potent == 1)
			did += DiscardOffOne("potent", "resources")
		}
	if (!Stat("usebubble") && bubble == 1)
		did += DiscardOffOne("bubble", hitschool)
	if (!Stat("useaura") && aura == 1)
		did += DiscardOffOne("aura", hitschool)
	if (!Stat("usetower") && tower == 1)
		did += DiscardOffOne("tower", "resources")
	if (!Stat("usereshuffle") && reshuffle == 1)
		did += DiscardOffOne("reshuffle", "resources")
	if (did)
		DebugLog("  (discarded " did " card" (did = 1 ? "" : "s") " of kinds switched off in the Settings window)")
	return did
	}

;One card of a kind switched off discarded, while the round's discardmax allows (DiscardOffCount)
DiscardOffOne(title, dir)
	{
	if (DiscardOffCount >= Stat("discardmax"))
		return 0
	n := DiscardCard(title, dir)
	DiscardOffCount += n
	return n
	}

CfgSave:
	;(not halfway through while the bot writes PlayerStats.txt itself: StatsSet is Critical too)
	Critical
	CfgSaveNow()
	return

CfgDefaults:
	CfgFillDefaults()
	return

CfgOpenFile:
	Run, notepad.exe "%A_WorkingDir%\PlayerStats.txt"
	return

;Simple / all settings (dashboard.ini [view] settings): the window made again in the other view, where it was - changes
;not saved yet kept (CfgPending), still to be saved
CfgViewToggle:
	CfgPending := {}
	for CfgVKey, CfgVC in CfgCtls
		{
		GuiControlGet, CfgVVal, Cfg:, %CfgVC%
		if (CfgVVal != CfgShownVals[CfgVKey])
			CfgPending[CfgVKey] := CfgVVal
		}
	;(to the simple view with changes to settings it doesn't show: saved or undone first - they'd be lost)
	CfgVHid := 0
	if (!CfgSimple)
		for CfgVKey in CfgPending
			CfgVHid += CfgSimpleKeys().HasKey(CfgVKey) ? 0 : 1
	if (CfgVHid)
		{
		GuiControl, Cfg:, CfgNote, % "Save first - " CfgVHid " change(s) to settings the simple view doesn't show"
		CfgPending := ""
		return
		}
	CfgVCount := CfgPending.Count()
	WinGetPos, CfgReopenX, CfgReopenY, , , ahk_id %CfgHwnd%
	IniWrite, % CfgSimple ? 0 : 1, %A_ScriptDir%\dashboard.ini, view, settings
	Gui, Cfg:Destroy
	CfgHwnd := 0
	CfgShow()
	if (CfgVCount)
		GuiControl, Cfg:, CfgNote, % CfgVCount " change(s) not saved yet - Save to use them"
	return

CfgGuiClose:
CfgGuiEscape:
	Gui, Cfg:Destroy
	CfgHwnd := 0
	return
