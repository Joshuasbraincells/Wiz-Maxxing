#InstallMouseHook
#InstallKeybdHook
#SingleInstance force

;All the pictures are found relative to this folder, however the script was started (shortcut, editor, ...)
SetWorkingDir, %A_ScriptDir%

;The wizard icon in the tray and on the dashboard (built into the exe; run as a script, set here)
if (!A_IsCompiled && FileExist(A_ScriptDir "\..\assets\wizard.ico"))
	Menu, Tray, Icon, %A_ScriptDir%\..\assets\wizard.ico

;All ImageSearch/Mouse coordinates are absolute screen coordinates, offset from the game's client area (see UpdateGameRect)
CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
CoordMode, ToolTip, Screen

;Battles (this script) and quest walking (..\AutoQuester\Walker.ahk) run together in one loop and
;start by themselves: fight when a battle round is up, otherwise follow the quest arrow.
;  F6           the bot on / off (off: no battles, walking, potions or reconnecting). Opened by the game -
;               "Open with Wizard101", /standby - it starts off and waits for F6
;  F8           walking on / off
;  Windows+1    restart (also Alt+Esc)
;  Windows+Esc  quit
;Disconnected: it clicks the game's RECONNECT, and if the game closes it can start it and log back in
;(Reconnect.ahk). Tray menu: "Auto-reconnect on/off" and "Set Wizard101 login..." (the login it uses then)
OnExit("WalkerQuit")
;No standard tray menu: its "Pause Script" would freeze the walker with a key held down
Menu, Tray, NoStandard
Menu, Tray, Add, Bot on/off (F6), MenuBotToggle
Menu, Tray, Add, Walking on/off (F8), MenuWalk
Menu, Tray, Add, Wait while I play, MenuHandsOff
Menu, Tray, Add, Auto-reconnect on/off, MenuReconnect
Menu, Tray, Add, Set Wizard101 login..., MenuLogin
Menu, Tray, Add, Discord alerts..., MenuAlerts
Menu, Tray, Add, Dashboard (Windows+2), MenuDash
Menu, Tray, Add, Settings..., MenuSettings
Menu, Tray, Add, Map of the zone, MenuMap
Menu, Tray, Add, Check for updates, MenuUpdates
Menu, Tray, Add, Open with Wizard101 (in standby - F6 starts it), MenuWatch
Menu, Tray, Add, Read wizard stats now, MenuStats
Menu, Tray, Add, Record potion buying..., MenuPotionRoute
Menu, Tray, Add, Buy potions now, MenuPotionRun
Menu, Tray, Add, Learn every card (a deck of one of each), MenuLearnAll
Menu, Tray, Add, Restart (Windows+1), MenuRestart
Menu, Tray, Add, Exit (Windows+Esc), MenuExit
Menu, Tray, Default, Walking on/off (F8)
SetTimer, StartBot, -300
return

;(F6 / F8 while the bot is off - standby, paused: only in Wizard101, not taken from other programs)
#If BotOn || WinActive("ahk_exe WizardGraphicalClient.exe")
F6::
MenuBotToggle:
BotToggle()
return

F8::
MenuWalk:
WalkToggle()
return
#If

;"Open with Wizard101": a watcher started with Windows opens the bot when the game starts (..\Watch.ahk)
MenuWatch:
SplitPath, A_ScriptDir, , watchRoot
watchOn := !WatchIsOn()
if (WatchSet(watchRoot, watchOn))
	TrayTip, Wizard101 bot, % watchOn ? "The bot now opens by itself when Wizard101 starts - in standby: F6 starts it." : "The bot won't open by itself with Wizard101 any more.", 6, 1
else
	TrayTip, Wizard101 bot, Couldn't change "Open with Wizard101" (the Startup folder's shortcut)., 6, 2
WatchShow()
return

MenuReconnect:
ReconnectToggle()
return

MenuHandsOff:
HandsOffToggle()
return

MenuLearnAll:
LearnAllToggle()
return

MenuStats:
StatsWanted := 1
TrayTip, Wizard101 bot, Reading your stats at the next quiet moment out of battle (hands off the mouse and keys for 5 s)., 5, 1
return

MenuDash:
DashToggle()
return

;The Settings window (Settings.ahk): the mouse, the waits, how it plays its cards
MenuSettings:
CfgShow()
return

;The map window (Dashboard.ahk): a top-down picture of the zone, the wizard and the quest goal
MenuMap:
DashMapToggle()
return

;(Wiz-Maxxing /check - the exe, or the script when this runs as one: asks GitHub; if you update, it closes this and
;starts the new one)
MenuUpdates:
BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/check", A_ScriptDir "\..")
return

MenuPotionRoute:
PotionRecordStart()
return

MenuPotionRun:
WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
Sleep, 500
;(the mouse back where it was afterwards - mousereturn)
mouseOwn := MouseGrab()
PotionRun()
if (mouseOwn)
	MouseLetGo()
return

MenuLogin:
ReconnectSetLogin()
return

;Discord alerts when the wizard needs you (Alerts.ahk): the webhook set, tested or removed
MenuAlerts:
AlertSetup()
return

#1::
MenuRestart:
BotRestart()
return

MenuExit:
ExitApp

StartBot:
global on := 1
;The bot on (F6): off, it does nothing - no battles, walking, potions or reconnecting. Opened by the game in
;standby (/standby: "Open with Wizard101") it starts off; never turned on, the game closing closes it too
global BotOn := 1, BotStandby := 0, BotEverOn := 1, BotGameSeenAt := A_TickCount
for each, botArg in A_Args
	if (botArg = "/standby")
		BotOn := 0, BotStandby := 1, BotEverOn := 0
	else if (botArg = "/off")
		BotOn := 0
if (BotOn)
	TrayTip, Wizard101 bot, Running: battles and quest walking. F6 pauses it`, F8 turns walking on/off - Windows+Esc quits., 4
else
	TrayTip, Wizard101 bot, Ready - Wizard101 started. Press F6 to start the bot (battles`, quest walking`, potions)., 8

;Kill calculator (KillCalc.ahk): settings from PlayerStats.txt, enemy health read off the screen,
;and the blades/traps/aura/bubble we've put up this battle
global Stats := {}
global EnemyHP := ""
global BossSlot := 0
global HealthStatus := ""
global AppliedBlades := {}
global BossTraps := {}
global AuraRounds := 0
;Hits we put an enchant on that haven't been cast yet (they keep the enchant): title -> enchant level
global EnchantedHits := {}
;Saving pips for a hit that ends the battle (KillCalc.ahk PlanPips): the hit ("" none), rounds saved so far,
;given up this battle; and your health % off your name plate, and the round it was read in
;(PipSaveBare: the wand's free hit is fine meanwhile; PipSaveTarget/LastPips/Stall: counting the rounds
;saved; PipOrbs: pip orb slots filled, from PipValue)
global PipSaveFor := "", PipSaveRounds := 0, PipSaveGaveUp := 0, OwnHpPct := 0, OwnHpRound := -1
global PipSaveBare := 0, PipSaveTarget := "", PipSaveLastPips := -1, PipSaveStall := 0, PipOrbs := 0
;You're at the keyboard and mouse right now (PlayerActing): the bot waits. PlayerTookRound: you played (part
;of) a round of this battle - the bot's record of blades/traps may be wrong, so no kill check till it ends.
;RoundLeft: the bot left the round that's up to you (seeing it again isn't a new round)
global PlayerActive := 0, PlayerTookRound := 0, RoundLeft := 0, RoundAgain := 0
;When the spellbook (out of battle only) was last seen - the walker's "no battle on" (BotNoBattle)
global BookSeenAt := 0
;Your pips this round, read off your nameplate (-1 = couldn't read)
global PipsNow := -1
;Boost cards cast since the last hit (Settings.ahk CardBoostOk: boostmax)
global BoostRun := 0
global BossMax := 0
global DualBattle := 0
LoadStats()

;Misc Initilization
global inbattle := 0
global roundnumber := 0
global battles := 0
global BossChoosen := 0
;The boss picked with Alt+1, from the game window's top left in UI scale 1 pixels (BossX/BossY are
;worked out from it each round, so a moved or resized window still finds it)
global BossRelX := 0, BossRelY := 0
;Enemy nameplates found this round, left to right ({x, y} on screen; KillCalc's ReadEnemyHealth)
global EnemyPlates := []
global boosts := 0
global afk := 0
global bossX := 0
global bossY := 0
global afk := 0

;Screen variable initilization
;Game* is the Wizard101 client area in screen coordinates, ScreenX/ScreenY is its center
global GameExe := "WizardGraphicalClient.exe"
global GameClass := "Wizard Graphical Client"
;Colour tolerance for card pictures (cards shimmer a little between rounds)
global CardTol := 20
;The game draws its UI bigger or smaller with the window size, the Windows display scaling and its
;UI Size setting, and ImageSearch only finds a picture at the size it was cut at. So there's a set of
;pictures per UI size: the main one (resources\, storm\, ... cut at a 1920x1080 window, UI Size
;Small) and a ui<scale> folder for each other size, e.g. ui1.265\ (1920x1200 window at 100%
;scaling: the UI 1.265 times as big). A ui folder only needs the pictures cut at its size; for the
;rest the main picture is used (it won't match at that size, so that card counts as not in hand).
;The set whose Pass button or spellbook is on screen is used (UsePicSet), and every pixel distance
;below is times UiScale. At a size with no pictures cut for it, the bot makes a set itself from the
;cut ones (PicScale.ahk: generated\ui<scale>\)
global PicSets := []
global PicSet := 1
global PicDir := A_WorkingDir
global UiScale := 1.0
global LastSetTry := 0
;Half the width of the area searched for cards in hand (a full 7-card hand is about 580 px wide at
;UI scale 1). Set by UsePicSet
global HandHalf := 400
;Half the distance between two cards in hand: when a card leaves the hand the rest slide this far
;(41 at UI scale 1). Set by UsePicSet
global HalfPitch := 41
global GameLeft := 0
global GameTop := 0
global GameW := A_ScreenWidth
global GameH := A_ScreenHeight
global GameRight := A_ScreenWidth
global GameBottom := A_ScreenHeight
global ScreenX := A_ScreenWidth / 2
global ScreenY := A_ScreenHeight / 2
UpdateGameRect()

;debug.log: what the script sees and decides each round (starts fresh every start / restart; the last
;run's is kept as debug.previous.log - e.g. to see why a wizard died before you restarted)
FileMove, %A_ScriptDir%\debug.log, %A_ScriptDir%\debug.previous.log, 1
;The dashboard: statistics, what the bot sees, the log as it's written (Dashboard.ahk; Windows+2)
DashInit()
HandsOffShow()
BotOnShow()
WatchShow()
DebugLog("Started. Game area " GameLeft "," GameTop " " GameW "x" GameH)
LoadPicSets()
if (!DetectPicSet())
	UsePicSet(1)
LastBeat := 0
SeenOut := 0

;Quest walking: on from the start (F8 switches it off and on)
if (WalkerInit("Wizard101 bot"))
	{
	Walking := 1
	DebugLog("Walking on (F8 switches it off)")
	}
else
	DebugLog("Walking off: couldn't load the quest arrow shapes (AutoQuester\resources\arrow_refs.txt)")

;Auto-reconnect (Reconnect.ahk): on from the start (tray menu switches it off and on)
ReconnectInit()

;Stats (StatsRead.ahk): read by itself out of battle when the school it fights with has none yet, or
;when asked (tray menu, or StatsReader.ahk started while this runs - it sends message 0x5555)
global StatsWanted := 0
OnMessage(0x5555, "StatsAsked")

;The Python vision helper (Vision.ahk): finds the cards in hand and school badges; ImageSearch if it
;can't run
VisionStart()
OnExit("VisionOnExit")

;Initializes modes
global commandmode := 0
global dualmode := 0
global responcemode := 0
global devmode := 0
global loremode := 0
global boostlimitmode := 0
global dualhittermode := 0
global statsmode := 0
global loopmode := 0

;Sleep timings
global Tick := 100
global Buffer := 300
global Half := 600
global Second := 1100
global Five := 5000
global Ten := 10000
global Loading := 15000 

ResetUsed()	

;Checks if in battle
TestRound:
loop,
{
	;Off (F6) - or opened by the game in standby: nothing till F6 (no battles, walking, potions or reconnecting).
	;Opened in standby and never turned on: Wizard101 closing closes the bot too (it opens again with the game)
	if (!BotOn)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		BlockInput, MouseMoveOff
		if (BotStandby && !BotEverOn)
			{
			Process, Exist, %GameExe%
			if (ErrorLevel)
				BotGameSeenAt := A_TickCount
			else if (A_TickCount - BotGameSeenAt > 15000)
				{
				DebugLog("Wizard101 closed while the bot was waiting for F6 - closing the bot (it opens again with the game)")
				ExitApp
				}
			}
		Sleep, 300
		continue
		}
	UpdateGameRect()
	if (A_TickCount - LastBeat > 10000)
		{
		LastBeat := A_TickCount
		WinGetTitle, activeTitle, A
		DebugLog("Watching for a round. Active window: " activeTitle " | game area " GameLeft "," GameTop " " GameW "x" GameH)
		}
	;You're playing (a key, click or mouse move of yours in the last handsoff seconds): the bot waits - no
	;battle rounds, no walking, no potions; it lets go of any walking key at once
	if (PlayerActing())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(never your mouse frozen while you play - Alt+1/Alt+2/Windows+3 turn the block back on)
		BlockInput, MouseMoveOff
		if (inbattle == 1 && !PlayerTookRound)
			PlayerTookRound := 1, DebugLog("  (you're playing in this battle: no kill check till it ends - the bot can't know which blades and traps are left)")
		;(the round left to you is over once its Pass button goes)
		if (RoundLeft)
			{
			ImageSearch, gx, gy, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\roundstart.png")
			if (ErrorLevel)
				RoundLeft := 0
			}
		Sleep, 200
		continue
		}
	;Disconnected, or the game closed: get back online first (no battles or walking meanwhile)
	if (ReconnectCheck())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		Sleep, 300
		continue
		}
	ImageSearch, roundX, roundY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\roundfinish.png")
	bookSeen := (ErrorLevel = 0)
	if (bookSeen)
		BookSeenAt := A_TickCount
	if (ErrorLevel = 0)
		{
		if (!SeenOut)
			{
			DebugLog("Out of battle (spellbook visible)")
			SeenOut := 1
			}
		if (inbattle = 1)
			{
			battles++
			}
		;(the mouse, if any of this takes it - potions, stats - goes back where it was at the end: mousereturn)
		MouseGrab()
		checkafk()
		;Fled a battle out of mana or cards (Flee.ahk): a potion first (or a run to buy some), then on as usual
		FleeAfter()
		checkmana()
		CommandAfk()
		CommandEnter()
		CommandWalk()
		CommandPort()
		CommandOff()
		CommandReload()
		ResetVariables() 
		ResetUsed()	
		StatsAuto()
		;Low on health: a potion, or a run to buy more (Potions.ahk)
		PotionCheck()
		MouseLetGo()
		gosub, mobloop
		gosub, LoreLoop
		}
	ImageSearch, startX, startY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\roundstart.png")
	;Kept, since writing the log line below resets ErrorLevel (which would start a round that isn't there)
	startErr := ErrorLevel
	if (startErr = 2 && !PicError)
		{
		DebugLog("Can't open " PicPath("resources\roundstart.png") " - the pictures aren't where the script expects them")
		PicError := 1
		}
	If (startErr = 0)
		{
		;A battle round is up: stop walking first (a key could still be held from the last step)
		if (KeysDown || HeldW)
			ReleaseKeys()
		RoundAgain := RoundLeft, RoundLeft := 0
		if (RoundAgain)
			{
			;(the round the bot left to you, still up: not a new round)
			DebugLog("Round start again (the round left to you is still up): Pass button at " startX - GameLeft "," startY - GameTop)
			Goto, RoundStart
			}
		DebugLog("Round start: Pass button at " startX - GameLeft "," startY - GameTop)
		SeenOut := 0
		if (dualmode == 1)
			{
			roundnumber++
			roundnumber := %roundnumber% / 2
			} else
				{
				roundnumber++
				}
		Goto, RoundStart
		}
	;Neither the spellbook nor the Pass button: maybe the game's UI is another size now (the window
	;or the display scaling changed), so every few seconds look with the other picture sets - and if
	;none fits and a round is up, measure the UI size and make a set for it
	if (!bookSeen && A_TickCount - LastSetTry > 3000)
		{
		LastSetTry := A_TickCount
		if (DetectPicSet(true) || DetectUiScale())
			continue
		}
	;No battle round to play right now: take a step towards the quest goal (with no quest arrow
	;on screen, e.g. during the battle's spell animations, it just lets go of the keys and waits).
	;Not while afk, mob-loop or lore farming: those move the wizard themselves
	if (afk || loopmode || loremode)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		}
	else
		WalkStep()
}

RoundStart:

;A wait before playing a new round (roundwait, the Settings window) - then, as the round's look began: you may
;have started playing meanwhile (the round's yours - nothing's been taken yet), or the round may be over
if (!RoundAgain && Stat("roundwait") > 0)
	{
	Sleep, % Stat("roundwait")
	UpdateGameRect()
	if (PlayerActing())
		{
		DebugLog("  you're playing (during the wait before the round) - leaving this round to you")
		RoundLeft := 1
		if (!PlayerTookRound)
			PlayerTookRound := 1
		Goto, TestRound
		}
	ImageSearch, rwX, rwY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\roundstart.png")
	if (ErrorLevel)
		Goto, TestRound
	}
;(a walker notice mustn't cover what the battle reads)
WalkNoteHide()
;(where the mouse is now: it goes back there when the round's done - mousereturn)
MouseGrab()
BlockInput, MouseMove
CenterMouse()

;The Alt+1 boss where the window and UI size are now (the nameplates are drawn from its top left)
if (BossChoosen == 1)
	BossX := GameLeft + Round(BossRelX * UiScale), BossY := GameTop + Round(BossRelY * UiScale)

global inbattle = 1
LearnedThisRound := 0, LastHandAnswer := "", DiscardedUnused := 0, DiscardOffCount := 0

;Both windows share one record of blades/traps in dual mode, so the kill check is off for that whole battle
if (dualmode == 1)
	{
	DualBattle := 1
	}

;Finds the player
global playerX := 0
global playerY := 0
global player := 1

ImageSearch, playerX, playerY, GameLeft, GameTop + GameH / 4, GameRight, GameBottom, % PicOpt("resources\player.png")
if (ErrorLevel = 0)
	{
	player := 1
	} else if (ErrorLevel = 1)
		{
		ImageSearch, playerX, playerY, GameLeft, GameTop + GameH / 4, GameRight, GameBottom, % PicOpt("resources\player2.png")
		if (Errorlevel = 0)
			{
			player := 1
			}
		} else 
			{
			Goto, TestHammer
			}
		
;Find player school

global school := ""
global schoolX := 0
global schoolY := 0

if (player == 1)
	school := BestBadge(playerX - Px(100), playerY - Px(100), playerX + Px(250), playerY + Px(250), schoolX, schoolY)

;Checks who's hammer
TestHammer:

global hitter := 0
global hitschool := ""
global hammerX := 0
global hammerY := 0
global hitterX := 0
global hitterY := 0

;(the school whose badge matches best: a badge made at another size roughly matches the others too)
if (Manual != 1)
	{
	hitschool := BestBadge(GameLeft, GameTop + GameH * 3 // 4, GameRight, GameBottom, hitterX, hitterY, playerX, playerY)
	hitter := BadgeNumber(hitschool)
	}

hammerX = %hitterX%
hammerY = %hitterY%

;No school badge found on the name plates - your plate in another slot can show none (seen with a 1280x1024
;window, the left plate): the school this character was seen fighting with before (resources\characters.txt,
;by its CharID in the game's log), and your own plate - found by your name - as the hitter's (a solo battle)
if (hitter = 0) && (Manual != 1) && (player == 1)
	{
	knownSchool := StatsSchoolOf(StatsCharID())
	if (BadgeNumber(knownSchool))
		{
		hitschool := knownSchool, hitter := BadgeNumber(knownSchool)
		hammerX := playerX + Px(25), hammerY := playerY + Px(8)
		if (school = "")
			school := knownSchool
		DebugLog("  no school badge found on the name plates - this character fought as " knownSchool " before: using that, with your own plate as the hitter's")
		}
	}

;A character the bot has no pictures for (no school icon it knows on the screen, e.g. a new wizard of
;another school): leave the round to you rather than passing it, and keep a picture of the round so
;that character's name, school icon and cards can be cut from it
if (hitter = 0) && (Manual != 1)
	{
	BlockInput, MouseMoveOff
	savedTo := SaveRoundPicture()
	;(the mouse back once the picture's taken)
	MouseLetGo()
	DebugLog("  no school icon the bot knows - leaving this round to you" (savedTo = "" ? "" : " (picture of it: " savedTo ")"))
	TrayTip, Wizard101 bot, The bot doesn't know this wizard's school yet - play this round yourself., 5, 1
	AlertSend("school", "a wizard it doesn't know", "No school icon the bot knows on the name plates - the round is left to you (a new wizard? its pictures get cut from the round pictures it saves).")
	;Wait for the round to be played (the Pass button goes), then watch for the next one
	unknownFrom := A_TickCount
	Loop
		{
		Sleep, 500
		UpdateGameRect()
		ImageSearch, unknownX, unknownY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\roundstart.png")
		if (ErrorLevel != 0 || A_TickCount - unknownFrom > 180000)
			break
		}
	Goto, TestRound
	}
	
if (hitschool = "balance")
	{
	blade2 := 0
	trap2 := 0
	} else if (hitter <= 2)
	{
	if Tri("elemental", "blade")
		{
		blade2 := 1
		} else if (Tri("elemental", "trap"))
			{
			trap2 := 1
			} else 
				{
				blade2 := 0
				trap2 := 0
				}
	} else
		{
		if Tri("spirit", "blade")
			{
			blade2 := 1
			} else if (Tri("spirit", "trap"))
				{
				trap2 := 1
				} else 
					{
					blade2 := 0
					trap2 := 0
					}
		}	

if (Manual = 1)
	{
	hammerX = %ManualX%
    hammerY = %ManualY%
	}
	
;Looks at the hand (and again after discarding, since the cards shift)
if (!RoundAgain)
	Discards := 0
FindCards:

;Enchants (and a fresh look at the hand for the vision helper)
VisionForget()
FindEnchant()

;Finds cards avaliable

global sharpen := 0
Find("sharpen", sharpen, SharpX, SharpY, "resources") 
 
global potent := 0
Find("potent", potent, PotentX, PotentY, "resources") 

global blade := 0
Find("blade", blade, BladeX, BladeY, hitschool)

global blade3 := 0
Find("blade3", blade3, Blade3X, Blade3Y, "resources")
 
global blade4 := 0
Find("blade4", blade4, Blade4X, Blade4Y, "resources")

global trap := 0
Find("trap", trap, trapX, trapY, hitschool)

global trap3 := 0
Find("trap3", trap3, trap3X, trap3Y, "resources")

global aura := 0
Find("aura", aura, auraX, auraY, hitschool)

global tower := 0
Find("tower", tower, towerX, towerY, "resources")

global reshuffle := 0
Find("reshuffle", reshuffle, reshuffleX, reshuffleY, "resources")

global feint := 0
Find("feint", feint, feintX, feintY, "resources")

global bubble := 0
Find("bubble", bubble, bubbleX, bubbleY, hitschool)

global convert := 0
Find("convert", convert, convertX, convertY, hitschool)
if NeedsConvert()
	{
	NeedsConvert := 1
	}
	
;Finds hit specific cards
if (hitter != 0)
	{
	global hit4 := 0
	Find("hit4", hit4, hit4X, hit4Y, hitschool)
	
	global hit3 := 0
	Find("hit3", hit3, hit3X, hit3Y, hitschool)
	
	global hit2 := 0
	Find("hit2", hit2, hit2X, hit2Y, hitschool)
	
	global hit1 := 0
	Find("hit1", hit1, hit1X, hit1Y, hitschool)

	;The wand's own card (an item card from the wand, e.g. Minor Clash: no pips)
	global wand := 0
	Find("wand", wand, wandX, wandY, hitschool)

	;Healing cards (heal1 / heal2 pictures in the school's folder), used when your health is low
	global heal1 := 0
	Find("heal1", heal1, heal1X, heal1Y, hitschool)
	global heal2 := 0
	Find("heal2", heal2, heal2X, heal2Y, hitschool)
	}

;How many pips you have (the game doesn't grey out cards you can't afford)
PipsNow := PipValue()
DebugLog("  pips=" PipsNow)
DebugLog("  player=" player " at " playerX - GameLeft "," playerY - GameTop " school=" school " | hitter=" hitschool " at " hammerX - GameLeft "," hammerY - GameTop " | enchant=" enchant)
;(which school the logged-in character is, for StatsReader: the badge by its own name plate - the
;hitter can be an ally)
StatsNoteSchool(school)
DebugLog("  cards: hit1-4=" hit1 hit2 hit3 hit4 " wand=" wand " heal1-2=" heal1 heal2 " blade=" blade " blade2=" blade2 " blade3=" blade3 " blade4=" blade4 " sharpen=" sharpen " trap=" trap " trap2=" trap2 " trap3=" trap3 " potent=" potent " feint=" feint " aura=" aura " bubble=" bubble " convert=" convert " tower=" tower " reshuffle=" reshuffle)

;Cards in hand the bot has no picture for yet: learned (CardLearn.ahk); one that went into a free slot is
;used this round, so look at the hand again
if (Manual != 1) && (!LearnedThisRound)
	{
	LearnedThisRound := 1
	if (LearnCards())
		Goto, FindCards
	}

;Discard (right-click) cards that can't help this battle, then look at the hand again (not while learning
;every card: that discards everything it knows): first, once a round, the cards it never plays (learned, in no
;slot - CardLearn.ahk DiscardUnused, off the hand as the helper read it), then spare blades and Sharpen
;(and cards of kinds switched off in the Settings window: Settings.ahk DiscardSwitchedOff)
if (!LearnAll) && (Discards < 3) && (DiscardUnused() + DiscardSpare() + DiscardSwitchedOff())
	{
	Discards++
	s(Stat("discardlook"))
	Goto, FindCards
	}

CenterMouse()

;Our aura only lasts a few rounds
if (AuraRounds > 0 && !RoundAgain)
	{
	AuraRounds--
	}

;Turned off (F6) during the round: it's left - nothing more cast, the mouse given back
if (!BotOn)
	{
	DebugLog("  bot off (F6) - leaving this round")
	RoundLeft := 1
	MouseLetGo()
	BlockInput, MouseMoveOff
	Goto, TestRound
	}

;You started playing while the bot looked at the hand: the round is yours
if (PlayerActing())
	{
	DebugLog("  you're playing - leaving this round to you")
	RoundLeft := 1
	if (!PlayerTookRound)
		PlayerTookRound := 1, DebugLog("  (no kill check till this battle ends - the bot can't know which blades and traps you use)")
	Goto, EndRound
	}

;Out of mana or cards - it could only pass for the rest of the battle: flee, and try again (Flee.ahk)
if FleeCheck()
	Goto, EndRound

;Learning every card (dashboard button / tray menu): no casting but a heal when low - learn, discard what
;it knows so the next round draws new cards, pass (CardLearn.ahk LearnAllRound)
if (LearnAll)
	{
	if (player == 1) && ((heal1 == 1) || (heal2 == 1)) && OwnHealthLow()
		{
		if (heal1 == 1) && UseHeal("heal1", heal1, hitschool)
			Goto, EndRound
		if (heal2 == 1) && UseHeal("heal2", heal2, hitschool)
			Goto, EndRound
		}
	LearnAllRound()
	Click("pass", pass, "resources")
	Goto, EndRound
	}

;Kill check: read every enemy's health and, if a hit in hand already kills them all, cast it now instead of boosting more
global KillHit := ""
global KillEnchant := 0
PipSaveFor := ""
if (hitter != 0) && (DualBattle != 1) && (!PlayerTookRound) && (Stat("healthocr") == 1) && ((hit1 == 1) || (hit2 == 1) || (hit3 == 1) || (hit4 == 1) || (wand == 1 && Stat("usewand")))
	{
	if (ReadEnemyHealth())
		{
		;(nothing ends it now: is a hit that would worth saving pips for? KillCalc.ahk PlanPips)
		if (!FindLethalHit(KillHit, KillEnchant))
			PlanPips()
		}
	ShowKillInfo()
	DebugLog("  kill check: " HealthText() " -> " (KillHit = "" ? "no lethal hit" : KillHit (KillEnchant ? " with enchant" : "")))
	CenterMouse()
	if (KillHit != "")
		{
		if UseHit(KillHit, %KillHit%, hitschool, KillEnchant)
			{
			;(a saved-for hit went out: the next save counts afresh)
			PipSaveRounds := 0, PipSaveTarget := "", PipSaveStall := 0, BoostRun := 0
			Goto, EndRound
			}
		}
	}

;Low on health (under healat % of it, PlayerStats.txt): a healing card on yourself before anything else
if (player == 1) && ((heal1 == 1) || (heal2 == 1)) && OwnHealthLow()
	{
	if (heal1 == 1) && UseHeal("heal1", heal1, hitschool)
		Goto, EndRound
	if (heal2 == 1) && UseHeal("heal2", heal2, hitschool)
		Goto, EndRound
	}

;How it plays its cards (the Settings window: cardlogic, boostmax, use...): hit first - before any boost - when
;the card logic says so (Settings.ahk CardHitFirst); boosts only up to boostmax before a hit it can cast
;(CardBoostOk); kinds switched off aren't played. BoostRun counts the boosts since the last hit
;Turned off (F6) during the round: it's left - nothing more cast, the mouse given back
if (!BotOn)
	{
	DebugLog("  bot off (F6) - leaving this round")
	RoundLeft := 1
	MouseLetGo()
	BlockInput, MouseMoveOff
	Goto, TestRound
	}
HitsTried := 0
if CardHitFirst()
	{
	HitsTried := 1
	if CastBestHit()
		Goto, EndRound
	}
BoostOk := CardBoostOk()

;Automatic Battle code
if (feint == 1) && (BossChoosen == 1) && BoostOk && Stat("usetraps") && UseTrap("feint", feint, Used1, Used2, "resources")
	{
	BoostRun++
	Goto, EndRound
	} else if (convert == 1) && (NeedsConvert == 1) && (BossChoosen == 1) && UseConvert("convert", convert, hitschool)
		{
		Goto, EndRound
		} else if (trap == 1) && (BossChoosen == 1) && BoostOk && Stat("usetraps") && UseTrap("trap", trap, used3, used4, hitschool)
			{
			BoostRun++
			Goto, EndRound
			} else if (trap2 == 1) && (BossChoosen == 1) && BoostOk && Stat("usetraps") && UseTrap(traptype, %traptype%, used5, used6, "resources")
				{
				BoostRun++
				Goto, EndRound
				} else if (trap3 == 1) && (BossChoosen == 1) && BoostOk && Stat("usetraps") && UseTrap("trap3", trap3, used7, used8, "resources")
					{
					BoostRun++
					Goto, EndRound
					} else if (trap4 == 1) && (BossChoosen == 1) && BoostOk && Stat("usetraps") && UseTrap("trap4", trap4, used9, used10, "resources")
						{
						BoostRun++
						Goto, EndRound
						} else if (blade == 1) && BoostOk && Stat("useblades") && UseBlade("blade", blade, used11, used12, hitschool)
							{
							BoostRun++
							Goto, EndRound
							} else if (blade2 == 1) && BoostOk && Stat("useblades") && UseBlade(bladetype, %bladetype%, used13, used14, "resources")
								{
								BoostRun++
								Goto, EndRound
								} else if (blade3 == 1) && BoostOk && Stat("useblades") && UseBlade("blade3", blade3, used15, used16, "resources")
									{
									BoostRun++
									Goto, EndRound
									}  else if (blade4 == 1) && BoostOk && Stat("useblades") && UseBlade("blade4", blade4, used17, used18, "resources")
										{
										BoostRun++
										Goto, EndRound
										} else if (bubble == 1) && BoostOk && Stat("usebubble")
											{
											if Click("bubble", bubble, hitschool)
												BoostRun++
											} else if (aura == 1) && BoostOk && Stat("useaura")
												{
												if Click("aura", aura, hitschool)
													{
													AuraRounds := 4
													BoostRun++
													}
												} else if (!HitsTried) && CastBestHit()
													{
													Goto, EndRound
													} else if (wand == 1) && Stat("usewand") && UseHit("wand", wand, hitschool)
														{
														BoostRun := 0
														Goto, EndRound
														} else if (tower == 1) && Stat("usetower")
															{
															UseOnSelf("tower", tower, "resources")
															} else if (reshuffle == 1) && Stat("usereshuffle")
																{
																UseOnHammer("reshuffle", reshuffle, "resources")
																ResetUsed()
																} else if Click("pass", pass, "resources")
																	{
																	Goto, EndRound
																	}
EndRound:
DebugLog("Round done")
;The mouse back where it was when the round began (mousereturn, the Settings window), else off the cards - not
;if you've used the mouse or keys meanwhile (MouseLetGo -1: it's yours)
if (MouseLetGo() = 0)
	CenterMouse()
BlockInput, MouseMoveOff
	
Switch()
	
Goto, TestRound
	
;Functions
;You're playing: a key, a click or a mouse move of yours (not the bot's own: A_TimeIdlePhysical leaves those
;out) in the last handsoff seconds (PlayerStats.txt, default 10; 0 = never wait for you), while "Wait while
;I play" is on (HandsOffOn). Logged when it starts and ends; PlayerActive tells the dashboard
PlayerActing()
	{
	static logged := 0
	secs := Stats.HasKey("handsoff") ? Stats["handsoff"] : 10
	acting := (HandsOffOn() && secs > 0 && A_TimeIdlePhysical < secs * 1000)
	;(the bot's own hotkeys aren't you playing: the key itself, and for Alt+1 / Alt+2 / Windows+3 the click
	;on the boss / player that follows within 10 s)
	if (acting && A_ThisHotkey != "")
		{
		lastInput := A_TickCount - A_TimeIdlePhysical, keyAt := A_TickCount - A_TimeSinceThisHotkey
		if (lastInput >= keyAt - 50 && lastInput <= keyAt + (RegExMatch(A_ThisHotkey, "^(!1|!2|#3)$") ? 11000 : 600))
			acting := false
		}
	if (acting && !logged)
		DebugLog("You're playing - the bot waits until you've left the keyboard and mouse alone for " secs " s"), logged := 1
	else if (!acting && logged)
		{
		DebugLog("You've stopped - the bot carries on")
		logged := 0
		;(the walker starts its watch afresh: you may have moved, and the time you played isn't it being stuck)
		if (IsFunc("WalkReset"))
			Func("WalkReset").Call()
		}
	PlayerActive := acting
	return acting
	}

;The bot on / off (F6, the tray menu, the dashboard's button): off, the main loop does nothing; keys held let go
BotToggle()
	{
	BotOn := !BotOn
	if (BotOn)
		{
		BotEverOn := 1
		;(turned on in a battle: what was played meanwhile isn't known - no kill check till it ends, and the boss
		;picked again with Alt+1)
		if (inbattle == 1)
			PlayerTookRound := 1, BossChoosen := 0, DebugLog("  (turned on in a battle: no kill check till it ends - Alt+1 the boss again for traps)")
		;(the walker starts afresh: the wizard may have moved meanwhile)
		if (IsFunc("WalkReset"))
			Func("WalkReset").Call()
		DebugLog("Bot on (F6) - battles, quest walking and potions")
		TrayTip, Wizard101 bot, On - battles`, quest walking and potions. F6 pauses it., 4, 1
		}
	else
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		BlockInput, MouseMoveOff
		DebugLog("Bot off (F6) - it does nothing till F6 again")
		TrayTip, Wizard101 bot, Off - the bot does nothing till you press F6 again., 4, 1
		}
	BotOnShow()
	}

;A restart (Windows+1, Alt+Esc, the tray menu) that keeps the bot off or in standby - Reload drops the arguments
BotRestart()
	{
	arg := (BotStandby && !BotEverOn) ? "/standby" : (!BotOn ? "/off" : "")
	if (arg = "")
		{
		Reload
		return
		}
	if (A_IsCompiled)
		Run, "%A_ScriptFullPath%" /restart %arg%, %A_ScriptDir%, UseErrorLevel
	else
		Run, "%A_AhkPath%" /restart "%A_ScriptFullPath%" %arg%, %A_ScriptDir%, UseErrorLevel
	}

;The tray menu's tick and the dashboard's button for the bot on / off
BotOnShow()
	{
	if (BotOn)
		Menu, Tray, Check, Bot on/off (F6)
	else
		Menu, Tray, Uncheck, Bot on/off (F6)
	if (IsFunc("DashBotShow"))
		Func("DashBotShow").Call(BotOn)
	}

;The tray menu's tick for "Open with Wizard101"
WatchShow()
	{
	if (WatchIsOn())
		Menu, Tray, Check, Open with Wizard101 (in standby - F6 starts it)
	else
		Menu, Tray, Uncheck, Open with Wizard101 (in standby - F6 starts it)
	}

;For the walker: no battle on - the spellbook (it only shows out of battle) seen in the last 2 s
BotNoBattle()
	{
	return A_TickCount - BookSeenAt < 2000
	}

;"Wait while I play" (tray menu, dashboard button): handsoffon in PlayerStats.txt, on unless it's 0
HandsOffOn()
	{
	return !(Stats.HasKey("handsoffon") && !Stats["handsoffon"])
	}

;Turns "Wait while I play" on/off and keeps it in PlayerStats.txt (handsoffon)
HandsOffToggle()
	{
	waitOn := !HandsOffOn()
	if (!StatsSet([["handsoffon", waitOn ? 1 : 0]]))
		Stats["handsoffon"] := waitOn ? 1 : 0
	HandsOffShow()
	DebugLog("Wait while I play: " (waitOn ? "on - the bot waits while you use the keyboard or mouse" : "off - the bot carries on while you play"))
	TrayTip, Wizard101 bot, % "Wait while I play: " (waitOn ? "ON - the bot waits while you use the keyboard or mouse." : "OFF - the bot carries on even while you play."), 4, 1
	}

;The tray menu's tick and the dashboard button's label
HandsOffShow()
	{
	waitOn := HandsOffOn()
	if (waitOn)
		Menu, Tray, Check, Wait while I play
	else
		Menu, Tray, Uncheck, Wait while I play
	if (IsFunc("DashHandsShow"))
		Func("DashHandsShow").Call(waitOn)
	}

;Moves the mouse to x, y and clicks, quickly: mousespeed (0 = jump there, 1 = fastest glide; it used to
;be 5), clickwait ms before the click (used to be 150) plus up to clickrandom ms, and after it `after` ms
;times clickafter % (PlayerStats.txt, the Settings window; it used to wait the whole of it)
ClickAt(x, y, after := 0)
	{
	;(not in a battle round: the mouse goes back where it was after the click - mousereturn)
	ownGrab := MouseGrab()
	MouseMove, x, y, MouseSpeedNow()
	Sleep, % Stats.HasKey("clickwait") ? Stats["clickwait"] : 40
	;(and a random bit more: clickrandom)
	if (Stat("clickrandom") > 0)
		{
		Random, clickExtra, 0, % Stat("clickrandom")
		Sleep, %clickExtra%
		}
	Click
	if (after)
		AfterClick(after)
	if (ownGrab)
		MouseLetGo()
	}

;A wait after a click: ms times clickafter % (PlayerStats.txt; lower is faster)
AfterClick(ms)
	{
	Sleep, % Round(ms * (Stats.HasKey("clickafter") ? Stats["clickafter"] : 50) / 100)
	}

MouseSpeedNow()
	{
	return Stats.HasKey("mousespeed") ? Stats["mousespeed"] : 1
	}

CenterMouse()
	{
	UpdateGameRect()
	Mousemove, ScreenX, ScreenY + Px(100), MouseSpeedNow()
	}

;A pixel distance measured at UI scale 1 (a 1920x1080 window, UI Size Small), at the UI size in use
Px(n)
	{
	return Round(n * UiScale)
	}

;Full path of a picture (e.g. "storm\hit1.png") in the picture set for the UI size in use; the main
;one if that set has no picture of its own for it (logged once)
PicPath(rel)
	{
	static missing := {}
	if (PicDir != A_WorkingDir)
		{
		;(a made set: the picture made at its size, see PicMake)
		p := PicSets[PicSet].gen ? PicMake(rel, PicSets[PicSet]) : PicDir "\" rel
		if (p != "" && FileExist(p))
			return p
		;A cut set without this picture: one made at its size from the other sets
		if (!PicSets[PicSet].gen)
			{
			p := PicMake(rel, {dir: GenRoot "\ui" Round(UiScale, 3), scale: UiScale})
			if (p != "" && FileExist(p))
				return p
			}
		if (!missing.HasKey(PicDir "|" rel))
			{
			missing[PicDir "|" rel] := 1
			DebugLog("  (no " rel " at UI size " Round(UiScale, 3) " and none to make it from - using the main picture, which won't match at this size)")
			}
		}
	return A_WorkingDir "\" rel
	}

;Switches to picture set i and sizes the search areas to its UI scale
UsePicSet(i)
	{
	PicSet := i, PicDir := PicSets[i].dir, UiScale := PicSets[i].scale
	HandHalf := Px(400), HalfPitch := Px(41)
	DebugLog("Pictures: " (i = 1 ? "main set (UI scale 1)" : SubStr(PicDir, StrLen(A_WorkingDir) + 2) " (UI scale " Round(UiScale, 3) (PicSets[i].gen ? ", made from the cut pictures" : "") ")") " - card area +-" HandHalf " px, card spacing " 2 * HalfPitch " px")
	}

;Finds the Wizard101 client area on screen so searches follow the window when it's moved or resized
UpdateGameRect()
	{
	WinGet, hwnd, ID, A
	WinGet, proc, ProcessName, ahk_id %hwnd%
	WinGetClass, cls, ahk_id %hwnd%
	if (proc != GameExe) || (cls != GameClass)
		{
		;Active window isn't the game (e.g. one of our popups, or the game's short-lived D3DProxyWindow),
		;use the top-most real Wizard101 window instead
		WinGet, gameHwnd, ID, ahk_class %GameClass% ahk_exe %GameExe%
		if (!gameHwnd)
			{
			;Game not open: keep the last known position rather than measuring some other window
			return
			}
		hwnd := gameHwnd
		}
	if (!hwnd)
		{
		return
		}
	VarSetCapacity(rect, 16, 0)
	VarSetCapacity(pt, 8, 0)
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rect)
	DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", &pt)
	w := NumGet(rect, 8, "Int")
	h := NumGet(rect, 12, "Int")
	if (w <= 0 || h <= 0)
		{
		;Minimized, keep the last known position
		return
		}
	GameLeft := NumGet(pt, 0, "Int")
	GameTop := NumGet(pt, 4, "Int")
	GameW := w
	GameH := h
	GameRight := GameLeft + w
	GameBottom := GameTop + h
	ScreenX := GameLeft + w // 2
	ScreenY := GameTop + h // 2
	}

TestSchool(class)
	{
	ImageSearch, schoolX, schoolY, playerX - Px(100), playerY - Px(100), playerX + Px(250), playerY + Px(250), % PicOpt(class "\" class ".png")
	if (Errorlevel = 0)
		{
		school := class
		return true
		} else {
			return false
			}
	}
	
Tri(type1, type2) 
	{
	global
	visionHit := VisionFind("resources", type1 type2, typeX, typeY)
	if (visionHit = -1)
		{
		ImageSearch, typeX, typeY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), % PicOpt("resources\" type1 type2 ".png", CardTol)
		visionHit := (ErrorLevel = 0)
		}
	if (visionHit = 1)
		{
		%type2%2X := typeX
		%type2%2Y := typeY
		if (type1 = "elemental")
			{
			bladetype := "elementalblade"
			traptype := "elementaltrap"
			} else if (type1 = "spirit")
				{
				bladetype := "spiritblade"
				traptype := "spirittrap"
				}
		return true
		} else 
			{
			return false
			}
	}

ErrorBox(ByRef funcN, ByRef dir, ByRef title)
	{
	if (devmode == 1)
		{
		n1 := "Error in " . funcN . " Function"
		n2 := "Directory: " PicPath(dir "\" title ".png")
		MsgBox, 4, %n1%, %n2%`n`nWould You like to continue running script?, 5
		IfMsgBox, Yes
			{
			return
			}
		IfMsgBox, No
			{
			ExitApp
			}
		IfMsgBox, Timeout
			{
			return
			}
		}
	}
	
Find(title, ByRef card, ByRef X, ByRef Y, ByRef dir)
	{
	global
	;(the vision helper, if it's running: 1 found, 0 not in hand)
	visionHit := VisionFind(dir, title, X, Y)
	if (visionHit >= 0)
		{
		card := visionHit
		return
		}
	ImageSearch, X, Y, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(150), % PicOpt(dir "\" title ".png", CardTol)
	if (Errorlevel == 0)	
		{
		card := 1
		} else if (Errorlevel == 1)
			{
			card := 0
			} else if (Errorlevel == 2)
				{
				ErrorBox("Find", dir, title)
				}
	}
	
Click(ByRef title, ByRef click, ByRef dir)
	{
	global
	Find(title, click, clickX, clickY, dir)
	DebugLog("  " A_ThisFunc " " title ": found=" click " at " clickX - GameLeft "," clickY - GameTop)
	if (click == 1)
		{
		ClickAt(clickX + Px(5), clickY + Px(5), 100)
		return true
		} else 
			{
			return false
			}
	}
	
UseOnSelf(ByRef title, ByRef card, ByRef dir) 
	{
	global
	Find(title, card, foundX, foundY, dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " foundX - GameLeft "," foundY - GameTop)
	
	if (card == 1)
		{
		ClickAt(foundX, foundY, 150)
		ClickAt(playerX, playerY, 150)
		}
	}
	
UseOnHammer(ByRef title, ByRef card, ByRef dir) 
	{
	global
	Find(title, card, foundX, foundY, dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " foundX - GameLeft "," foundY - GameTop)
	
	if (card == 1)
		{
		ClickAt(foundX, foundY, 150)
		ClickAt(hammerX, hammerY, 150)
		}
	}
	
UseBlade(ByRef title, ByRef blade, ByRef Use1, ByRef Use2, ByRef dir) 
	{
	global
	Find(title, blade, foundX, foundY, dir)
	DebugLog("  " A_ThisFunc " " title ": found=" blade " at " foundX - GameLeft "," foundY - GameTop)
	
	;The hand may have re-centred since FindCards (a discard or a used enchant)
	Find("sharpen", sharpen, SharpX, SharpY, "resources")
	if (sharpen == 1) && (blade == 1) && (Use1 != 1)
		{
		boostX := SharpX
		ClickAt(SharpX, SharpY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()	
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has
		BoostSettle(n, foundX, foundY, boostX)
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox("UseBlade", dir, title)
			}
			ClickAt(foundX, foundY, 150)
		if (title != "blade4")
			{
			ClickAt(hammerX, hammerY, 200)
			}
		boosts++
		Use1 := 1
		if BladeOnUs(title)
			{
			AddBoost(AppliedBlades, title, Stat("sharpen"))
			}
		return true
		} else if (blade == 1) && (Use2 != 1)
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was
			keepX := foundX, keepY := foundY
			ImageSearch, foundX, foundY, GameLeft, GameTop, GameRight, GameBottom, % PicOptFile(n, CardTol)
			if (ErrorLevel)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox("UseBlade", dir, title)
				}
				ClickAt(foundX, foundY, 150)
			if (title != "blade4")
				{
				ClickAt(hammerX, hammerY, 200)
				}
			boosts++
			Use2 := 1
			if BladeOnUs(title)
				{
				AddBoost(AppliedBlades, title, 0)
				}
			return true
			} else
				{
				return false
				}
	}

UseTrap(ByRef title, ByRef trap, ByRef Use1, ByRef Use2, ByRef dir) 
	{
	global
	Find(title, trap, foundX, foundY, dir)
	DebugLog("  " A_ThisFunc " " title ": found=" trap " at " foundX - GameLeft "," foundY - GameTop)
	
	;The hand may have re-centred since FindCards (a discard or a used enchant)
	Find("potent", potent, PotentX, PotentY, "resources")
	if (BossChoosen == 1) && (potent == 1) && (trap == 1) && (Use1 != 1)
		{
		boostX := PotentX
		ClickAt(potentX, potentY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()	
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has
		BoostSettle(n, foundX, foundY, boostX)
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox("UseTrap", dir, title)
			}
		ClickAt(foundX, foundY, 150)
		ClickAt(bossX, bossY, 200)
		boosts++
		Use1 := 1
		AddBoost(BossTraps, title, Stat("potent"))
		return true
		} else if (BossChoosen == 1) && (trap == 1) && (Use2 != 1)
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was
			keepX := foundX, keepY := foundY
			ImageSearch, foundX, foundY, GameLeft, GameTop, GameRight, GameBottom, % PicOptFile(n, CardTol)
			if (ErrorLevel)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox("UseTrap", dir, title)
				}
			ClickAt(foundX, foundY, 150)
			ClickAt(bossX, bossY, 200)
			boosts++
			Use2 := 1
			AddBoost(BossTraps, title, 0)
			return true
			} else 
				{
				return false
				}
	}
	
UseConvert(ByRef title, ByRef convert, ByRef dir) 
	{
	global
	CenterMouse()
	Find(title, convert, foundX, foundY, dir)
	DebugLog("  " A_ThisFunc " " title ": found=" convert " at " foundX - GameLeft "," foundY - GameTop)
	ClickAt(foundX, foundY, 150)
	ClickAt(bossX, bossY, 200)
	}
	
UseHit(ByRef title, ByRef hit, ByRef dir, useEnchant := 1)
	{
	global
	;Saving pips for a hit that ends the battle (PlanPips): no other hit spends them. The wand's card is free,
	;but it uses up blades, traps and an enchant: only when the saved hit kills without them, unenchanted
	if (PipSaveFor != "" && title != PipSaveFor && (title != "wand" || !PipSaveBare))
		{
		DebugLog("  " title ": not cast - saving pips for " PipSaveFor)
		return false
		}
	if (PipSaveFor != "" && title = "wand")
		useEnchant := 0
	Find(title, hit, foundX, foundY, dir)
	DebugLog("  " A_ThisFunc " " title ": found=" hit " at " foundX - GameLeft "," foundY - GameTop)

	;Can you pay for it yet? If not, keep it for a later round (no click, no enchant used on it)
	if (hit == 1) && !Affordable(title)
		{
		DebugLog("  " title " costs more pips than you have (" PipsNow "): keeping it for later")
		hit := 0
		return false
		}
	;The hand may have re-centred since FindCards (a discard or a used enchant)
	if (useEnchant)
		FindEnchant()
	if (useEnchant) && (enchant >= 1) && (hit == 1) && !EnchantedHits[title]
		{
		EnchantedHits[title] := enchant
		boostX := enchantX
		ClickAt(enchantX, enchantY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()	
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has
		BoostSettle(n, foundX, foundY, boostX)
		;The enchant card is used up and the hand has shifted
		FindEnchant()
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox("UseHit", dir, title)
			}
		ClickAt(foundX, foundY)
		HitTarget(title, dir)
		return CastResult(title, hit, dir, 1)
		} else if (hit == 1)
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was
			keepX := foundX, keepY := foundY
			ImageSearch, foundX, foundY, GameLeft, GameTop, GameRight, GameBottom, % PicOptFile(n, CardTol)
			if (ErrorLevel)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox("UseHit", dir, title)
				}
			ClickAt(foundX, foundY)
			HitTarget(title, dir)
			return CastResult(title, hit, dir, 0)
			} else
				{
				return false
				}
	}	
	
;Your own health off your name plate (the red cur/max under your name), read by OCR at two sizes that
;must agree. True if it's under healat % (PlayerStats.txt, default 40). Logged each round it's read
OwnHealthLow()
	{
	global
	local x, y, w, h, t, a, pct, limit, votes, key, n, best, bestN, zoom
	x := playerX - Px(8), y := playerY + Px(20), w := Px(110), h := Px(24)
	;(the game's digits fool OCR now and then - B for 8, a 3 for an 8 - so it reads at four sizes and
	;takes what at least two of them read)
	votes := {}, best := "", bestN := 0
	for each, zoom in [2, 3, 4, 5]
		{
		t := OcrRect(x, y, w, h, "en", zoom, ownLines, 1)
		if (ErrorLevel)
			continue
		t := StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(t, "B", "8"), "O", "0"), "o", "0"), "S", "5"), "l", "1"), "I", "1")
		a := ParseHealth(t)
		if (!IsObject(a) || a.Length() != 1)
			continue
		key := a[1].cur "/" a[1].max, n := votes.HasKey(key) ? votes[key] + 1 : 1, votes[key] := n
		if (n > bestN)
			best := a, bestN := n
		}
	if (bestN < 2)
		{
		DebugLog("  own health: couldn't read it for sure")
		return false
		}
	a := best
	;(your most health, for the potions out of battle)
	PotionNoteMax(a[1].max)
	limit := Stats.HasKey("healat") ? Stats["healat"] : 40
	pct := Round(100 * a[1].cur / a[1].max)
	;(for saving pips: not while your health is low)
	OwnHpPct := pct, OwnHpRound := roundnumber
	;(healing on a misread wastes the card - e.g. 775 read as 75 by two sizes - so a low reading needs
	;three of the four sizes to agree)
	if (pct < limit && bestN < 3)
		{
		DebugLog("  own health: read " a[1].cur "/" a[1].max " only " bestN " times out of 4 - not sure enough to heal")
		return false
		}
	DebugLog("  own health: " a[1].cur "/" a[1].max " (" pct "%)" (pct < limit ? " - under " limit "%: healing" : ""))
	return pct < limit
	}

;A healing card on yourself: the card, then your own name plate (a heal for one wizard asks who; one that
;heals only you or everyone doesn't, and the extra click does nothing). True if it was cast
UseHeal(title, ByRef card, dir)
	{
	global
	Find(title, card, foundX, foundY, dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " foundX - GameLeft "," foundY - GameTop)
	if (card != 1)
		return false
	if !Affordable(title)
		{
		DebugLog("  " title " costs more pips than you have (" PipsNow ")")
		return false
		}
	ClickAt(foundX, foundY, 300)
	ClickAt(playerX, playerY)
	return CastResult(title, card, dir, 0)
	}

;A hit that strikes one enemy (<school>.hitNtarget:1 in PlayerStats.txt, e.g. Scarab) waits for a target
;after its card is clicked: click the boss if one was picked (Alt+1), else the enemy with the least
;health, else the leftmost one (their nameplates along the top). All-enemy hits need nothing
HitTarget(title, dir)
	{
	global
	local key, i, e, pick, tx, ty
	key := dir "." title "target"
	if (!Stats.HasKey(key) || Stats[key] != 1)
		return
	if (BossChoosen == 1)
		tx := BossX, ty := BossY, pick := "the boss"
	else if (EnemyPlates.Length())
		{
		pick := 1
		if (IsObject(EnemyHP) && EnemyHP.Length() = EnemyPlates.Length())
			for i, e in EnemyHP
				if (e.cur < EnemyHP[pick].cur)
					pick := i
		tx := EnemyPlates[pick].x, ty := EnemyPlates[pick].y
		pick := "enemy " pick " of " EnemyPlates.Length() (IsObject(EnemyHP) ? " (" EnemyHP[pick].cur " health)" : "")
		}
	else
		{
		DebugLog("  " title " needs a target, but no enemy nameplate was found to click")
		return
		}
	AfterClick(300)
	ClickAt(tx, ty)
	DebugLog("  " title ": clicked " pick " as the target at " tx - GameLeft "," ty - GameTop)
	}

Switch()
	{
	if (dualmode == 1)
		{
		Send, {Alt down}
		Send, {Tab down}
		Send, {Alt up}
		Send, {Tab up}
		}
	}
	
s(time) 
	{
	Sleep, time
	}
	
Respond(Text) 
	{
	if (responcemode == 1)
		{
		BlockInput, Send
		Send, {r}
		s(100)
		SendInput {Raw}%Text%
		Send, {Enter}
		}
	}
	
Spam(key)
	{
	Send, {%key%}
	Send, {%key%}
	Send, {%key%}
	}
	
ResetUsed()
	{
	;Assume-global so used1..used20 are the battle code's flags, not locals that vanish on return
	global
	local n := 0
	while (n <= 20)
		{
		used%n% := 0
		n++
		}
	}
	
ResetVariables() 
	{
	global
	inbattle := 0
	roundnumber := 0
	playerX := 0
	playerY := 0
	Player := ""
	BossChoosen := 0
	boosts := 0
	BoostRun := 0
	sharpen := 0 
	potent := 0
	blade := 0
	blade2 := 0
	blade3 := 0
	blade4 := 0
	trap := 0
	trap2 := 0
	trap3 := 0
	trap4 := 0
	feint := 0
	aura := 0
	enchant := 0 
	reshuffle := 0
	hit1 := 0
	hit2 := 0
	hit3 := 0
	hit4 := 0
	EnchantedHits := {}
	PipSaveFor := "", PipSaveRounds := 0, PipSaveGaveUp := 0, PipSaveTarget := "", PipSaveStall := 0, PipSaveLastPips := -1
	PlayerTookRound := 0, RoundLeft := 0, RoundAgain := 0
	OwnHpPct := 0, OwnHpRound := -1
	tower := 0  
	hitter := 0
	hitschool := ""
	hammerX := 0
	hammerY := 0
	hitterX := 0
	hitterY := 0
	school := ""
	schoolX := 0
	schoolY := 0
	bladetype := ""
	traptype := ""
	bossX := 0
	bossY := 0
	AppliedBlades := {}
	BossTraps := {}
	AuraRounds := 0
	EnemyHP := ""
	BossSlot := 0
	BossMax := 0
	DualBattle := 0
	HealthStatus := ""
	ToolTip,,,, 20
}
	
NeedsConvert()
	{
	if (BossChoosen == 1)
		{
		ImageSearch, nX, nY, BossX - Px(100), BossY - Px(100), BossX + Px(100), BossY + Px(100), % PicOpt(dir "\convertN.png", 100)
		if (Errorlevel == 0)
			{
			return true
			}
		}
	}
	
LockMove(ByRef direction)
	{
	Send, {%direction% down}
	s(50)
	Send, {Shift down}
	s(50)
	Send, {%direction% up}
	s(50)
	Send, {Shift up}
	}
	
Log()
	{
	Send, {Esc}
	s(1000)
	UpdateGameRect()
	ImageSearch, logX, logY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\log.png")
	if (Errorlevel == 0)
		{
		ClickAt(logX, logY)
		} else if (Errorlevel == 2)
			{
			ErrorBox("Log", dir, title)
			}
	s(5000)
	}
	
Join()
	{
	UpdateGameRect()
	ImageSearch, joinX, joinY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\join.png")
	if (Errorlevel == 0)
		{
		ClickAt(joinX, joinY)
		} else if (Errorlevel == 2)
			{
			ErrorBox("Join", dir, title)
			}
	s(5000)
	}

UsePotion()
	{
	UpdateGameRect()
	ImageSearch, potionX, potionY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\potion.png")
	ClickAt(potionX, potionY)
	}

CheckAfk()
	{
	if (afk == 1)
		{
		;Waits for you to press w/a/s/d, checking for a disconnect every second meanwhile
		Loop
			{
			Input , OutputVar, T1, {w} {a} {s} {d}, w, a, s, d
			if (Errorlevel != "Timeout")
				break
			ReconnectCheck()
			}
		afk := 0
		}
	}
return

Afk()
	{
	if (afk == 0)
		{
		LockMove("a")
		afk := 1
		}
	}

checkmana()
	{
	if (afk == 0)
		{
		ImageSearch, manaX, manaY, GameLeft, ScreenY, GameLeft + GameW / 4, GameBottom, % PicOpt("resources\manaempty.png")
		if (Errorlevel == 0)
			{
			;(a potion first - or a run to buy some - so it can carry on; only then keep the character from timing out)
			if (Stat("fleeon") && FleeRefillMana("no mana"))
				return
			Respond("Error, It Seems I Have No Mana. Preventing Timeout.")
			AlertSend("mana", "out of mana", "No mana and no potion to be had - the bot has stopped (kept from timing out).")
			afk()
			}
		}
	}
	
mobloop:
if (loopmode == 1)
	{	
	Send, {s down}
	s(1000)
	Send, {s up}
	ImageSearch, inventoryX, inventoryY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\full.png")
	if (Errorlevel == 0)
		{
		Respond("Error, Inventory Full. Preventing Time out.")
		AlertSend("inventory", "backpack full", "The backpack is full - mob-loop farming has stopped (kept from timing out).")
		afk()
		loopmode := 0
		return
		}	
	s(5000)
	Send, {w down}
	s(1000)
	Send, {w up} 
	}
return
	
LoreLoop:
	{
	if ((loremode == 1) && (dualmode == 0))
		{
		num := Mod(%battles% + 1, 50)
		if (num == 0)
			{
			UsePotion()
			}	
		log()	
		join()
		s(5000)
		Spam("x")
		s(16000)
		LockMove("w")
		s(5000)
		} else if ((loremode == 1) && (dualmode == 1))
			{
			;Joins Battles with same wizard you started the loop in
			BlockInput, MouseMove
			num := Mod(%battles% + 1, 50)
			if (num == 0)
				{
				UsePotion()
				Switch()
				s(500)
				UsePotion()
				Switch()
				}	
			log()
			switch()
			centermouse()
			log()
			join()
			switch()
			centermouse()
			join()
			switch()
			s(30000)
			Spam("x")
			Switch()
			s(1000)
			Spam("x")
			s(17000)
			LockMove("w")
			Switch()
			s(1000)
			LockMove("w")
			s(5000)
			switch()
			BlockInput, MouseMoveOff
			return
			} else 
				{
				return
				}
	} 
return

NewStaticGui(ByRef Text, ByRef x, ByRef y, ByRef w, ByRef h) 
	{
	box := " x" . x . " y" . y . " w" . w . " h" . h 
	Gui,1:Add, Text, %box%, %Text%
	Gui,1:Show, AutoSize Center, AutoFarmer
	}

NewTempGui(ByRef timeout, ByRef Text, ByRef x, ByRef y, ByRef w, ByRef h) 
	{
	box := " x" . x . " y" . y . " w" . w . " h" . h 
	Gui,1:Add, Text, %box%, %Text%
	Gui,1:Show, AutoSize Center, AutoFarmer
	Sleep, timeout
	Gui,1:Destroy
	}
	
ModeBox(ByRef mode, ByRef name, ByRef x, ByRef y, ByRef w, ByRef h)
	{
	
	if ((inbattle == 1) && (mode != 1))
		{
		NewTempGui(1500, "Please Don't turn modes on while in combat", 10, 10, 210, 30)
		}	
	
	if (mode == 0) && (inbattle == 0)
		{
		gui = Turning On %name% Mode.
		NewTempGui(1000, gui, x, y, w, h)
		mode := 1
		} else if (mode == 1)
			{
			gui = Turning Off %name% Mode.
			NewTempGui(1000, gui, x, y, w, h)
			mode := 0
			}
	}
	
;(the modes and picks below - Alt+D, Alt+S, Alt+1... - only while the bot is on: off, their keys go to whatever
;program has them)
#If BotOn
$#!d::
if (on == 1)
	{
	ModeBox(devmode, "Developer", 10, 10, 144, 30)
	}
return

!l::
if (on == 1)
	{
	MsgBox, 1, AutoFarmer: Lore Mode, Please make sure you're standing next to the lore sigil when activating this mode.`n`nPress Ok to continue.
	ifMsgBox, ok
		{
		ModeBox(loremode, "Lore", 10, 10, 140, 30)
		}
	ifMsgBox, cancel
		{
		return
		}
	ifMsgBox, timeout
		{
		return
		}
	}
return

$!d::
if (on == 1)
	{
	MsgBox, 1, AutoFarmer: Dual Mode, Please make sure that, when activating this mode two Wizard101 instances are open and that, when "Alt+Tab" is pressed it'll switch bewteen them.`n`nPress Ok to continue.
	ifMsgBox, ok
		{
		ModeBox(dualmode, "Dual", 10, 10, 120, 30)
		}
	ifMsgBox, cancel
		{
		return
		}
	}
return
		
!c::
if (on == 1)
	{
	ModeBox(commandmode, "Command", 10, 10, 144, 30)
	}
return

$!s::
if (on == 1)
	{
	ModeBox(statsmode, "Statistic", 10, 10, 140, 30)
	}
return

!r::
if (on == 1)
	{
	ModeBox(responcemode, "Responce", 10, 10, 140, 30)
	}
return
	
!1::
if ((on == 1) && (inbattle == 1))
	{
	BlockInput, MouseMoveOff
	NewStaticGui("Please Select Boss Location.", 10, 10, 140, 30)
	KeyWait, LButton, D, 10
		If (Errorlevel = 0)
			{
			global BossChoosen = 1
			MouseGetPos, BossX, bossY
			UpdateGameRect()
			BossRelX := (BossX - GameLeft) / UiScale, BossRelY := (BossY - GameTop) / UiScale
			;A newly picked boss starts with no traps counted
			BossMax := 0
			BossTraps := {}
			Gui, 1:Destroy
			}
	BlockInput, MouseMove
	CenterMouse()
	}
return

!e::
if (on == 1)
	{
	ModeBox(loopmode, "Loop", 10, 10, 140, 30)
	}
return

!2::
if ((on == 1) && (inbattle == 1))
	{
	BlockInput, MouseMoveOff
	NewStaticGui("Please Select Hammer Location.", 10, 10, 140, 30)
	KeyWait, LButton, D, 10
		If (Errorlevel == 0)
			{
			Manual = 1
			MouseGetPos, ManualX, ManualY
			hitschool := BestBadge(ManualX - Px(75), ManualY - Px(75), ManualX + Px(75), ManualY + Px(75), schoolX, schoolY)
			hitter := BadgeNumber(hitschool)
			Gui, 1:Destroy
			BlockInput, MouseMove
			CenterMouse()
			}

}
return

#3::
if ((on == 1) && (inbattle == 1))
	{
	BlockInput, MouseMoveOff
	NewStaticGui("Please Select New Player Location.", 10, 10, 140, 30)
	KeyWait, LButton, D, 10
		If (Errorlevel = 0)
			{
			global ManualPlayer := 1
			MouseGetPos, ManualPlayerX, ManualPlayerY
			Gui, 1:Destroy
			}	
	BlockInput, MouseMove
	CenterMouse()
	}
return
#If

GuiClose:
Gui, Destroy
	
#2::
;Windows+2: the dashboard (Dashboard.ahk) - in dev mode, the info box below
if (devmode != 1)
	{
	DashToggle()
	return
	}
if (devmode == 1)
{
HealthInfo := HealthText()
MsgBox,
( 
GENERAL:
Window:(X:%GameLeft% Y:%GameTop% %GameW%x%GameH%)
InBattle:(%inbattle%)
Battles:(%battles%)
Round:(%roundnumber%) 
Player:(%player%)
Hammer:(%hitschool% (X:%hammerX% Y:%hitterY%)) 
Boss:(%BossChoosen%:(X:%BossX% Y:%BossY%))
Enemy Health:(%HealthInfo%)
Boosts(%boosts%:%boostlimit%)

CARDS: 
Sharpen:(%sharpen%) 
Potent:(%potent%)
Blade:(%blade%) 
Blade2:(%blade2%:(%bladetype%)) 
Balanceblade:(%blade3%)
Bladestorm:(%blade4%)
Convert(%convert%)
Trap:(%trap%)  
Trap2:(%trap2%:(%traptype%))
Trap3:(%trap3%)
Feint:(%feint%) 
Aura:(%aura%) 
Enchant:(%enchant%) 
Active Hits:(%hit4%:%hit3%:%hit2%:%hit1%) 
Tower:(%tower%)  
Reshuffle:(%reshuffle%)

     USED:
 F(%used2%)   pF(%used1%) 
B1(%Used12%) sB1(%Used11%)  
B2(%Used14%) sB2(%Used13%)
B3(%Used16%) sB3(%Used15%)
B4(%Used18%) sB4(%Used17%)
T1(%Used4%)  pT1(%Used3%)
T2(%Used6%)  pT2(%Used5%)
T3(%Used8%)  pT3(%Used7%)
T4(%Used10%) pT4(%Used9%)

MODES: 
Developer(%devmode%) Command(%commandmode%) 
Respond(%responsemode%) Dual(%dualmode%)
Lore(%loremode%)
)
}
return

CommandOff()
	{
	global
	if ((devmode == 1) && (commandmode == 1)) 
		{
		ImageSearch, offX, offY, GameLeft, GameBottom - Px(25), GameLeft + GameW / 4 + Px(20), GameBottom, % PicOpt("resources\off.png", 120)
		if (ErrorLevel == 0) 
			{			
			Respond("Shutting Down.")
			ExitApp
			} else if (Errorlevel == 2)
				{
				ErrorBox("CommandOff", dir, title)
				}
		}
	}
	
CommandReload()
	{
	global
	if ((devmode == 1) && (commandmode == 1)) 
		{
		;Requires devmode to be on to reloaded script manually
		ImageSearch, relX, relY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, % PicOpt("resources\rel.png", 120)
		if (ErrorLevel == 0) 
			{
			Respond("Reloading Script.")
			BotRestart()
			} else if (Errorlevel == 2)
				{
				ErrorBox("CommandReload", dir, title)
				}
		}
	}

CommandHit()
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, X, Y, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, % PicOpt("resources\PlayerHit.png", 120)
		if (Errorlevel == 0)
			{
			Respond("Okay, Ill OverRide The Automatic Battle Sequence.")
			if ((hit == 1) || (hit2 == 1) || (hit3 == 1) || (hit4 == 1))
				{
				if (hit4 == 1) && (BossChoosen = 1)
					{
					UseHit("hit4", hit4, hitschool)
					} else if (hit3 == 1)
						{
						UseHit("hit3", hit3, hitschool)
						} else if (hit2 == 1)
							{
							UseHit("hit2", hit2, hitschool)
							} else if (hit1 == 1)
								{
								UseHit("hit1", hit1, hitschool)
								} else 
									{
									Respond("It Seems There Are No Hits In Hand, I'll Pass Instead.")
									Click("pass", pass, "resources")
									}
				}
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandHit", dir, title)
					}
		}
	}
	
CommandPass()
	{	
	global
	if (commandmode == 1)
		{
		ImageSearch, PlayerPassX, PlayerPassY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, % PicOpt("resources\PlayerPass.png", 120)
		if (ErrorLevel == 0)
			{
			Respond("Alright, Ill Pass Instead.")
			ClickAt(passX, passY)
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandPass", dir, title)
					return false
					} 
		}
	}
	
CommandWalk()
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, walkX, walkY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, % PicOpt("resources\walk.png", 120)
		if (ErrorLevel == 0) 
			{
			Respond("I'm Not A Dog, But Ill Do It Anyways")
			Send, {w Down}
			Sleep, 2000
			Send, {w Up}
			Sleep, %Ten%
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandWalk", dir, title)
					return false
					}
		}
	}
	
CommandEnter()
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, enterX, enterY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, % PicOpt("resources\enter.png", 120)
		if (ErrorLevel == 0) 
			{
			Respond("Entering Sigil. Make Sure You Have The Right Deck On.")
			Send, {x}
			Sleep, %Tick%
			Send, {x}
			Sleep, %Tick%
			Send, {x}
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandEnter", dir, title)
					return false
					}
		} 
	}
	
CommandAfk()
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, afkX, afkY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, % PicOpt("resources\afk.png", 120)
		if (ErrorLevel == 0)
			{
			Respond("Okay, I'll Prevent Time Out Until Further Notice.")
			afk()
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandAfk", dir, title)
					return false
					}
		}
	}
	
CommandPort() 
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, wordportX, wordportY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, % PicOpt("resources\wordport.png", 120)
		if (ErrorLevel == 0)
			{
		
			Send, {/}
			Sleep, %Tick%
			Send, {BS}
			Sleep, %Tick%
			Send, {Enter}
			Sleep, %Half%
			
			ImageSearch, checkX, checkY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\check.png")
			if (Errorlevel == 0) 
				{
				Sleep, %Half%
				ImageSearch, nameX, nameY, GameLeft, checkY - Px(20), checkX, checkY + Px(20), % PicOpt("resources\name.png")
				if (ErrorLevel == 0) 
					{		
					ClickAt(nameX + Px(30), nameY)
					
					s(2000)		
					ImageSearch, portX, portY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\port.png")
					if (Errorlevel == 0) 
						{
						ClickAt(portX, portY)
						Sleep, %Half%
						
						ImageSearch, yesX, yesY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\yes.png")
						if (Errorlevel == 0) 
							{
							ClickAt(yesX, yesY)
							Sleep, %Half%
							
							Respond("Initiating Teleportation Sequence.")
								
							ImageSearch, okX, okY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\ok.png")
							if (Errorlevel == 0) 
								{
								ClickAt(okX, okY)
								
								Respond("Error Teleporting, Check If Ports Are On, Or If You're In A Dungeon.")
									
								}
							} else if ((Errorlevel == 1) && (devmode == 1))
								{
								Respond("Error Teleporting, Invalid Gui.")
								}
						} else if ((Errorlevel == 1) && (devmode == 1))
							{
							Respond("Error Teleporting, Invalid Gui.")
							}
					} else if ((Errorlevel == 1) && (devmode == 1))
						{
						Respond("Error Teleporting, Invalid Gui.")
						}
				} else if ((Errorlevel == 1) && (devmode == 1))
					{
					Respond("Error Teleporting, Invalid Gui.")
					}
			return true
			Sleep, %Ten%
			} else if (Errorlevel == 1)
				{
				return false
				} else if (Errorlevel == 2)
					{
					ErrorBox("CommandPort", dir, title)
					return false
					}
		}
	}

#If BotOn
!0::
if (on = 1)
	{
	if (devmode = 1)
		{	
		if (inbattle = 0)
			{
			#InstallMouseHook
			#InstallKeybdHook
			CoordMode, Mouse, Window
			leftoffset := (A_ScreenWidth - 800) / 2
			topoffset := (A_ScreenHeight - 600) / 2
			up = 1
			left = 2
			right = 3
			down = 4
			Mousespeedfast = 5 ;Default is 5
			Mousespeedslow = 10 ;Default is 10
			Loading = 5100 ;Default is 5000
			Wait = 325 ;Default is 300
			Delay = 175 ;Default is 150
			Buffer = 10 ;Default is 10
			
			loop 
				{
				BlockInput, SendAndMouse
				BlockInput, Mousemove
				sleep, %Wait%
				send, x
				sleep, %Wait%
				send, x
				sleep, %Wait%
				Mousemove, 625 + leftoffset, 470 + topoffset, %Mousespeedfast%
				Click
				sleep, %Wait%
				Mousemove, 615 + leftoffset, 575 + topoffset, %Mousespeedfast%
				Click
				sleep, %Buffer%
				Mousemove, A_ScreenWidth/2, A_ScreenHeight/2,%Mousespeedfast%
				BlockInput, SendAndMouse
				BlockInput, Mousemove 
				sleep, %Loading%
				loop, 600
					{
					Random, direction, 1, 4
					if (direction == up) 
					{
					send, w
					}
					if (direction == left) 
					{
					send, a
					} 
					if (direction == right) 
					{
					send, d
					}
					if (direction == down) 
					{
					 send, s
					 }
					sleep, %Buffer%
					}
				sleep, %Loading% - 1500a
				Mousemove, 610 + leftoffset, 575 + topoffset, %Mousespeedfast%
				sleep, %Delay%
				Click
				sleep, %Delay%
				Mousemove, 170 + leftoffset, 470 + topoffset, %Mousespeedfast%
				Click
				sleep, %Delay%
				Mousemove, 615 + leftoffset, 575 + topoffset, %Mousespeedfast%
				Click
				sleep, %Wait%
				Mousemove, 635 + leftoffset, 540 + topoffset, %Mousespeedfast%
				Click
				sleep, %Delay%
				Mousemove, 180 + leftoffset, 570 + topoffset, %Mousespeedfast%
				Click
				Mousemove, A_ScreenWidth/2, A_ScreenHeight/2, %Mousespeedslow%
				sleep, %Loading%
				BlockInput, Off
				}
			}
		}
	}

#`::
if (on = 1)
	{
	if (devmode = 1)
		{
		loop, 
			{
			click
			}
		}
	}
return

#If

#Esc::
ExitApp
return

!Esc::
BotRestart()
return


;Which school's badge (a name plate's school icon) matches best in the rectangle: each school with a
;badge picture at this UI size is looked for, and where it's found, how little colour tolerance it
;still matches with there decides - a badge made at another size roughly matches the other schools'
;too (they share the gold ring), the right one matches closest. Returns the school ("" if none) and
;its position in bx, by
BestBadge(x1, y1, x2, y2, ByRef bx, ByRef by, nearX := 0, nearY := 0)
	{
	;(the vision helper, if it's running; with several plates, the one nearest nearX, nearY)
	sch := VisionBadge(x1, y1, x2, y2, bx, by, nearX, nearY)
	if (sch != -1)
		return sch
	best := "", bestTol := 99, bx := 0, by := 0
	for each, sch in ["storm", "fire", "myth", "balance", "ice", "life", "death"]
		{
		rel := sch "\" sch ".png", p := PicPath(rel)
		;(the main set's 2018 badge, which doesn't match at another size)
		if (UiScale != 1 && p = A_WorkingDir "\" rel)
			continue
		ImageSearch, fx, fy, x1, y1, x2, y2, % "*" GenTol " *TransFF00FF " p
		if (ErrorLevel)
			continue
		for each2, tol in [0, 3, 6, 10, 14, GenTol]
			{
			if (tol >= bestTol)
				break
			ImageSearch, gx, gy, fx - 3, fy - 3, fx + Px(40), fy + Px(40), % "*" tol " *TransFF00FF " p
			if (ErrorLevel = 0)
				{
				best := sch, bestTol := tol, bx := gx, by := gy
				break
				}
			}
		}
	return best
	}

;The bot's number for a hitter school (0 = none)
BadgeNumber(sch)
	{
	for i, name in ["storm", "fire", "myth", "balance", "ice", "life", "death"]
		if (name = sch)
			return i
	return 0
	}

;Looks for an enchant card in hand (Epic best). Run again after one is used, since the hand shifts
FindEnchant()
	{
	global
	enchant = 0
	;(the vision helper, if it's running: the best enchant in hand)
	if (VisionOn)
		{
		visionHit := 0
		for each, ench in [[4, "resources", "epic"], [3, "resources", "colossal"], [2, "resources", "gargantuan"], [1, "life", "enchant"]]
			{
			visionHit := VisionFind(ench[2], ench[3], enchantX, enchantY)
			if (visionHit != 0)
				break
			}
		if (visionHit = 1)
			{
			if (ench[1] != 4 || hitter != 0)
				enchant := ench[1]
			return
			}
		if (visionHit = 0)
			return
		}
	ImageSearch, enchantX, enchantY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), % PicOpt("resources\epic.png", CardTol)
	If (ErrorLevel = 0) && (hitter != 0)
		{
		enchant = 4
		} else if (Errorlevel = 1)
			{
			ImageSearch, enchantX, enchantY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), % PicOpt("resources\colossal.png", CardTol)
			if ErrorLevel = 0
				{
				enchant = 3
				} else if (ErrorLevel = 1)
					{
					ImageSearch, enchantX, enchantY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), % PicOpt("resources\gargantuan.png", CardTol)
					if (ErrorLevel = 0)
						{
						enchant = 2
						} else if (Errorlevel = 1) 
							{
							ImageSearch, enchantX, enchantY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), % PicOpt("life\enchant.png", CardTol)
							if (ErrorLevel = 0)
								{
								enchant = 1
								} 
							}
					} 
			}
	}

;Checks a hit really got cast: once a spell is chosen the Pass button goes away. If it's still
;there the card couldn't be cast (not enough pips), so the round tries the next option instead
CastResult(title, ByRef hit, dir, enchanted)
	{
	global
	local passX, passY, stillThere, t0, goneFrom
	;The Pass button has to stay gone for 1 s (it can blink out for a moment while the hand updates) - looked
	;at every 100 ms; still there 0.7 s after the click = the card didn't cast
	stillThere := false, goneFrom := 0, t0 := A_TickCount
	while (A_TickCount - t0 < 2500)
		{
		Sleep, 100
		UpdateGameRect()
		ImageSearch, passX, passY, GameLeft, GameTop, GameRight, GameBottom, % PicOpt("resources\roundstart.png")
		if (ErrorLevel = 0)
			{
			goneFrom := 0
			if (A_TickCount - t0 >= 700)
				{
				stillThere := true
				break
				}
			}
		else if (!goneFrom)
			goneFrom := A_TickCount
		else if (A_TickCount - goneFrom >= 1000)
			break
		}
	if (!stillThere)
		{
		EnchantedHits.Delete(title)
		ConsumeBoosts()
		DashCast(title)
		return true
		}
	DebugLog("  " title " didn't cast (not enough pips?)")
	hit := 0
	;An unaffordable card is discarded, unless it carries an enchant (now or from an earlier round)
	if (!enchanted && !EnchantedHits[title] && Stat("discardunaffordable") == 1)
		DiscardCard(title, dir)
	CenterMouse()
	return false
	}

;Right-clicks (discards) cards that can't help this battle. Returns how many were discarded
DiscardSpare()
	{
	global
	local did := 0
	;A blade whose sharpened and plain casts have both been used this battle won't stack again
	if (blade == 1) && (used11 == 1) && (used12 == 1)
		did += DiscardCard("blade", hitschool)
	if (blade2 == 1) && (used13 == 1) && (used14 == 1)
		did += DiscardCard(bladetype, "resources")
	if (blade3 == 1) && (used15 == 1) && (used16 == 1)
		did += DiscardCard("blade3", "resources")
	if (blade4 == 1) && (used17 == 1) && (used18 == 1)
		did += DiscardCard("blade4", "resources")
	;Sharpen is spare once a sharpened blade has been used and no blade in hand still needs sharpening
	if (sharpen == 1) && (used11 == 1 || used13 == 1 || used15 == 1 || used17 == 1)
		&& !((blade == 1 && used11 != 1) || (blade2 == 1 && used13 != 1) || (blade3 == 1 && used15 != 1) || (blade4 == 1 && used17 != 1))
		did += DiscardCard("sharpen", "resources")
	return did
	}

;Right-clicks one card in hand to discard it. Returns 1 if it was found
DiscardCard(title, dir)
	{
	global
	local card := 0, cardX := 0, cardY := 0
	Find(title, card, cardX, cardY, dir)
	if (card != 1)
		return 0
	Mousemove, cardX + Px(5), cardY + Px(5), MouseSpeedNow()
	s(Stats.HasKey("clickwait") ? Stats["clickwait"] : 40)
	Click, right
	;(the hand has changed: a fresh look next time, not the vision helper's picture of it from before)
	VisionForget()
	s(Stat("discardafter"))
	DebugLog("  Discarded " title " (right-click at " cardX - GameLeft "," cardY - GameTop ")")
	return 1
	}

;A boost card was just put on the card at fx,fy: the hand re-centres. Looks for the card where it slides
;to every 100 ms (from 250 ms on) and goes once it's in the same spot twice running - the slide is over -
;instead of a fixed 1.5 s; not seen by then: RefindAfterBoost's guess
BoostSettle(n, ByRef fx, ByRef fy, boostX)
	{
	global
	local expX, nx, ny, lastX := "", lastY := "", t0 := A_TickCount
	expX := fx + (fx < boostX ? HalfPitch : -HalfPitch)
	Sleep, 250
	while (A_TickCount - t0 < 1500)
		{
		ImageSearch, nx, ny, expX - Px(30), fy - Px(25), expX + Px(50), fy + Px(40), % PicOptFile(n, CardTol)
		if (ErrorLevel = 0)
			{
			if (nx = lastX && ny = lastY)
				{
				DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " nx - GameLeft "," ny - GameTop " (settled in " A_TickCount - t0 " ms)")
				fx := nx, fy := ny
				return
				}
			lastX := nx, lastY := ny
			}
		Sleep, 100
		}
	RefindAfterBoost(n, fx, fy, boostX)
	}

;A boost card (enchant, Sharpen or Potent) was just put on the card at fx,fy and left the hand.
;The hand re-centres: cards left of the boost card slide right by half a card, cards right of it
;slide left. Looks for the card where it should be now; if it can't be seen there, uses that spot
RefindAfterBoost(n, ByRef fx, ByRef fy, boostX)
	{
	global
	local expX, nx, ny
	expX := fx + (fx < boostX ? HalfPitch : -HalfPitch)
	ImageSearch, nx, ny, expX - Px(30), fy - Px(25), expX + Px(50), fy + Px(40), % PicOptFile(n, CardTol)
	if (ErrorLevel = 0)
		{
		DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " nx - GameLeft "," ny - GameTop)
		fx := nx, fy := ny
		}
	else
		{
		DebugLog("    card not seen after the hand moved, using where it should be: " expX - GameLeft "," fy - GameTop)
		fx := expX
		}
	}

;Reads the wizard's stats off the Spellbook (StatsRead.ahk) into PlayerStats.txt and reloads them,
;out of battle: by itself when the wizard logged in now (whose school it knows from a battle) has no
;<school>.damage yet, or the ones there are from another character of that school - at most every 30
;minutes per character - or when asked (StatsWanted). Only with the game in front and nobody having
;touched the mouse or keyboard for 5 s, since it clicks through the book
StatsAuto()
	{
	static triedAt := {}
	;(cheap checks first: this runs on every pass out of battle)
	if (!StatsWanted && SrBattleSchool = "")
		return
	if (A_TimeIdlePhysical < 5000 || afk || loopmode || loremode || !WinActive("ahk_class " GameClass " ahk_exe " GameExe))
		return
	;The school of the wizard logged in now: the last battle's if that was this character (it may have
	;switched since), else the one noted for it before
	charNow := StatsCharID()
	statsFor := (charNow != "" && charNow = SrBattleChar) ? SrBattleSchool : StatsSchoolOf(charNow)
	if (statsFor = "" && !StatsWanted)
		return
	need := StatsWanted || !Stats.HasKey(statsFor ".damage") || (charNow != "" && Stats[statsFor ".charid"] != charNow)
	tryKey := charNow "|" statsFor
	if (!need || (!StatsWanted && triedAt.HasKey(tryKey) && A_TickCount - triedAt[tryKey] < 1800000))
		return
	if (KeysDown || HeldW)
		ReleaseKeys()
	triedAt[tryKey] := A_TickCount, StatsWanted := 0
	;(it stops if you touch the mouse or keyboard while it reads)
	SrHandsOff := 1
	DebugLog("Stats: reading the " (statsFor = "" ? "wizard's" : statsFor " wizard's") " stats off the Spellbook (character " (charNow = "" ? "?" : charNow) ", UI scale " Round(UiScale, 3) ")")
	err := StatsRead(statsFor, statsGot)
	if (err != "")
		{
		DebugLog("Stats: " err)
		TrayTip, Wizard101 bot, % "Couldn't read your stats: " err, 10, 2
		return
		}
	msg := StatsWrite(statsGot, statsFor, charNow)
	LoadStats(true)
	DebugLog("Stats: " StrReplace(msg, "`n", " "))
	TrayTip, Wizard101 bot, %msg%, 10, 1
	}

;On exit: stop the vision helper too (it would stop by itself within 5 s anyway)
VisionOnExit(reason, code)
	{
	VisionStop()
	}

;StatsReader.ahk was started while this runs: it asks this script to read them (no two scripts
;clicking at once)
StatsAsked(wParam, lParam)
	{
	StatsWanted := 1
	TrayTip, Wizard101 bot, Reading your stats at the next quiet moment out of battle (hands off the mouse and keys for 5 s)., 5, 1
	return 1
	}

;Saves the game as a picture (BMP) for cutting new pictures from, in the Windows temp folder
;("Wizard101 bot rounds"), keeping the newest 25. Returns the file name, or "" if it couldn't
SaveRoundPicture()
	{
	dir := A_Temp "\Wizard101 bot rounds"
	FileCreateDir, %dir%
	files := ""
	Loop, Files, %dir%\round_*.bmp
		files .= A_LoopFileName "`n"
	Sort, files
	list := StrSplit(Trim(files, "`n"), "`n")
	while (list.Length() >= 25)
		FileDelete, % dir "\" list.RemoveAt(1)
	if (!ArrowCapture(GameLeft, GameTop, GameW, GameH, pix))
		return ""
	FormatTime, stamp,, yyyyMMdd_HHmmss
	path := dir "\round_" stamp ".bmp"
	bmp := FileOpen(path, "w")
	if (!IsObject(bmp))
		return ""
	bmp.WriteUShort(0x4D42), bmp.WriteUInt(54 + GameW * GameH * 4), bmp.WriteUInt(0), bmp.WriteUInt(54)
	bmp.WriteUInt(40), bmp.WriteInt(GameW), bmp.WriteInt(-GameH), bmp.WriteUShort(1), bmp.WriteUShort(32)
	bmp.WriteUInt(0), bmp.WriteUInt(GameW * GameH * 4), bmp.WriteInt(2835), bmp.WriteInt(2835), bmp.WriteUInt(0), bmp.WriteUInt(0)
	bmp.RawWrite(pix, GameW * GameH * 4)
	bmp.Close()
	return path
	}

;Appends a timestamped line to debug.log next to this script
DebugLog(msg)
	{
	FormatTime, now,, HH:mm:ss
	FileAppend, % now " " msg "`r`n", %A_ScriptDir%\debug.log
	;(and onto the dashboard's log)
	if (DashHwnd)
		DashLog(now " " msg)
	}

#Include %A_ScriptDir%\Ocr.ahk
#Include %A_ScriptDir%\KillCalc.ahk
#Include %A_ScriptDir%\Reconnect.ahk
#Include %A_ScriptDir%\PicScale.ahk
#Include %A_ScriptDir%\StatsRead.ahk
#Include %A_ScriptDir%\Vision.ahk
#Include %A_ScriptDir%\CardLearn.ahk
#Include %A_ScriptDir%\Potions.ahk
#Include %A_ScriptDir%\Flee.ahk
#Include %A_ScriptDir%\Settings.ahk
#Include %A_ScriptDir%\Alerts.ahk
#Include %A_ScriptDir%\Dashboard.ahk
#Include %A_ScriptDir%\..\AutoQuester\Walker.ahk
#Include %A_ScriptDir%\..\AutoQuester\ArrowReader.ahk
#Include %A_ScriptDir%\..\Watch.ahk
