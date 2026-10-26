; Dashboard.ahk - a window with the bot's statistics, what it sees right now, and a live log (every line
; of debug.log as it's written). AHK v1.1, functions and labels only; #Included by Autofarmer.ahk.
;
; Windows+2 or the tray menu shows / hides it; closing it only hides it. It opens on a monitor the game
; isn't on (if there is one) and remembers where you put it (dashboard.ini). It never takes the focus by
; itself - clicking into it does, and the walker waits while Wizard101 isn't the active window.
;
; The numbers come from the log lines (DashLog sees every DebugLog line) plus a few calls from the battle
; code: DashCast (a card was cast), DashSee (what the bot sees: the hand, enemies, your health...).
;
; Its Map button (or the tray menu) opens a second window: a top-down picture of the zone the wizard is in,
; drawn by the vision helper (/navmap) - see "The map" below.

global DashHwnd := 0, DashCon := 0, DashShown := 0, DashPaused := 0, DashHeld := "", DashStart := 0
;Counts (rounds, passes, ...) and casts per card; what it sees ({key: text}); card names off PlayerStats.txt
global DashN := "", DashCasts := "", DashSees := "", DashNames := ""
global DashHead, DashStatText, DashSeeText, DashConsole, DashPauseBtn, DashHandsBtn
;CPU and RAM in use, on the STATISTICS row (DashUsage)
global DashUsageText
;The Settings button (Settings.ahk), left of the Map button
global DashCfgBtn
;The view: simple (1 - what it's doing and seeing, the main buttons: no hand pictures, no log) or advanced (0 -
;everything); its button (the bottom row's right end) and the LOG heading
global DashSimple, DashViewBtn, DashLogHead
;The log's Colours button (DashLogColorsWindow), and the Colours window's swatches and buttons
global DashColBtn, LogColHwnd
;"Game to front" on/off (gamefront - Autofarmer.ahk GameFrontToggle)
global DashFrontBtn
;The Updates button, at the right end of the heading row (says whether a newer version is out: UpdState); Report a
;bug left of it (BugReport.ahk)
global DashUpdBtn, DashUpdBusy, DashBugBtn
;The "Play for me" button (a coloured bar - red off, green on - and clickable words: a button can't be coloured) -
;Autofarmer.ahk PlayForMeToggle
global DashPlayBtn, DashPlayBg
;Where the tabs' inside starts in the window (GuiControl Move places a tab's controls from there: DashGuiSize)
global DashTabOX, DashTabOY, DashTabOW, DashTabOH
;The bottom row's other buttons (they share the window's width)
global DashClearBtn, DashLogBtn, DashWalkBtn, DashFolderBtn, DashBotBtn
;The Cards tab: your hand - its heading, and a picture and a label for each of up to 7 cards - and the enemies' spells
;(their heading and list: DashFoesSeen)
global DashFoeHead, DashFoeList
global DashLearnBtn, DashHandHead, DashCardPic1, DashCardPic2, DashCardPic3, DashCardPic4, DashCardPic5, DashCardPic6, DashCardPic7
global DashCardTxt1, DashCardTxt2, DashCardTxt3, DashCardTxt4, DashCardTxt5, DashCardTxt6, DashCardTxt7
;The map window: the button, the window, its picture and line; the request it's waiting for (kind: map / nav,
;sent at); when it last asked for a picture and at what size (screen pixels); the picture's file; what went
;wrong with the picture; /nav's last answer; when the picture shown was made
global DashMapBtn, DashMapHwnd, DashMapPic, DashMapPicH, DashMapText, DashMapShown, DashMapReq, DashMapKind, DashMapReqAt
global DashMapAt, DashMapW, DashMapH, DashMapFile, DashMapNote, DashMapNav, DashMapPicAt

;Makes the window (shown unless dashboard.ini says it was hidden). Called once at start
DashInit()
	{
	DashN := {}, DashCasts := {}, DashSees := {}, DashStart := A_TickCount
	DashSimple := ViewSimple("dashboard")
	Gui, Dash:New, +Resize +MinSize740x640 +HwndDashHwnd, % "Wizard101 bot " BotVersion()
	Gui, Dash:Color, 1B1D22, 111317
	Gui, Dash:Margin, 12, 10
	Gui, Dash:Font, s11 w600 cF2F2F2, Segoe UI
	Gui, Dash:Add, Text, x12 y10 w526 h22 vDashHead, % BotVersion()
	;(the Updates button: the heading row's right end - DashGuiSize keeps it there)
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x544 y7 w88 h24 gDashBugButton vDashBugBtn, Report a bug
	Gui, Dash:Add, Button, x640 y7 w136 h24 gDashUpdButton vDashUpdBtn, Check for updates
	;(the button says "Checking..." a while after a click: DashUpdBusy)
	;Four tabs: Bot (statistics, what it sees, the log), Dungeons (Dungeons.ahk), Spells (the cards the bot learned by
	;itself: Spells.ahk) and Cards (your hand, the enemies' spells)
	Gui, Dash:Font, s9 w600 cF2F2F2, Segoe UI
	Gui, Dash:Add, Tab3, x6 y36 w772 h764 +Buttons -Theme vDashTabs, Bot|Dungeons|Spells|Cards|Network|Keys
	Gui, Dash:Tab, 1
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y68 w86 h16, STATISTICS
	Gui, Dash:Font, s8 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x100 y69 w270 h16 vDashUsageText, CPU / RAM ...
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x372 y68 w150 h16, WHAT IT SEES
	;(the Map button at the right end of that row; DashGuiSize keeps it there)
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x618 y64 w76 h22 gDashSettingsButton vDashCfgBtn, Settings
	Gui, Dash:Add, Button, x700 y64 w76 h22 gDashMapButton vDashMapBtn, Map
	Gui, Dash:Font, s9 w400 cDADADA, Consolas
	Gui, Dash:Add, Text, x12 y88 w350 h190 vDashStatText
	Gui, Dash:Add, Text, x372 y88 w400 h196 vDashSeeText
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y286 w200 h16 vDashLogHead, LOG
	;(each kind of line in its colour - movement, battle, waits... - set with the small Colours button: a rich edit, as
	;an Edit can't colour its lines; read-only, no wrap)
	Gui, Dash:Font, s8 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x694 y283 w78 h20 gDashLogColorsBtn vDashColBtn, Colours
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	DllCall("LoadLibrary", "Str", "Msftedit.dll", "Ptr")
	Gui, Dash:Add, Custom, ClassRICHEDIT50W x12 y306 w760 h452 +0x200000 +0x100000 +0x4 +0x800 +0x100 +0x40 +0x80 vDashConsole HwndDashCon
	DashLogInit()
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y768 w110 h26 gDashPauseLog vDashPauseBtn, Pause log
	Gui, Dash:Add, Button, x130 y768 w80 h26 gDashClearLog vDashClearBtn, Clear
	Gui, Dash:Add, Button, x218 y768 w120 h26 gDashOpenLog vDashLogBtn, Open debug.log
	Gui, Dash:Add, Button, x346 y768 w120 h26 gDashBotToggle vDashBotBtn, % "Bot: on (" HkText("bot") ")"
	Gui, Dash:Add, Button, x346 y768 w150 h26 gDashWalkToggle vDashWalkBtn, % "Walking on/off (" HkText("walk") ")"
	Gui, Dash:Add, Button, x504 y768 w140 h26 gDashFolder vDashFolderBtn, Open bot folder
	Gui, Dash:Add, Button, x652 y768 w124 h26 gDashHandsToggle vDashHandsBtn, Wait for me: on
	Gui, Dash:Add, Button, x652 y768 w124 h26 gDashFrontToggle vDashFrontBtn, Game to front: off
	Gui, Dash:Add, Button, x652 y768 w110 h26 gDashViewToggle vDashViewBtn, Advanced view
	;The Dungeons tab: a run recorded once, walked again and again (Dungeons.ahk)
	Gui, Dash:Tab, 2
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y68 w400 h16, DUNGEON FARMING
	Gui, Dash:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x12 y88 w760 h48 vDgHelp, % DashDgHelpText()
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y142 w120 h26 gDgRecordClick vDgRecBtn, Record a run
	Gui, Dash:Add, Button, x138 y142 w150 h26 gDgRecStopClick vDgRecStopBtn Disabled, % "Stop recording (" HkText("record") ")"
	Gui, Dash:Add, Button, x300 y142 w90 h26 gDgRunClick vDgRunBtn, Run
	Gui, Dash:Add, Button, x396 y142 w90 h26 gDgStopClick vDgStopBtn Disabled, Stop run
	Gui, Dash:Add, Button, x498 y142 w90 h26 gDgDeleteClick vDgDelBtn, Delete
	Gui, Dash:Add, Button, x594 y142 w110 h26 gDgFolderClick vDgFolderBtn, Open folder
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x12 y182 w44 h18 vDgTimesLabel, Run it
	Gui, Dash:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, Dash:Add, Edit, x58 y179 w60 h22 Number Right vDgTimes, 0
	Gui, Dash:Add, UpDown, vDgTimesUD Range0-9999 0x80, 0
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x126 y182 w220 h18 vDgTimesNote, times (0 = until you stop it)
	Gui, Dash:Add, Checkbox, x352 y182 w186 h18 vDgAvoid, Keep away from mobs on the way
	;(the deck a run's fought with - kept in its file: Decks.ahk)
	Gui, Dash:Add, Text, x542 y182 w36 h18 vDgDeckT, Deck
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, DropDownList, x580 y179 w190 AltSubmit vDgDeck gDgDeckPick, (none)
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Text, x12 y208 w760 h52 vDgStatus, Not running.
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, ListView, x12 y262 w760 h526 vDgList gDgListEvent AltSubmit -Multi Background111317 cDADADA, Run|Steps|Zones|X|Battles|Recorded|File
	LV_ModifyCol(1, 300), LV_ModifyCol(2, "60 Integer"), LV_ModifyCol(3, "60 Integer"), LV_ModifyCol(4, "50 Integer"), LV_ModifyCol(5, "70 Integer")
	LV_ModifyCol(6, 140), LV_ModifyCol(7, 0)
	;The Spells tab: the cards the bot learned by itself, and your corrections (Spells.ahk)
	Gui, Dash:Tab, 3
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y68 w400 h16, LEARNED SPELLS
	Gui, Dash:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x12 y88 w760 h32 vSpHelp, Every card the bot learned by itself, and what it took it for. Pick one to see it. Change kind or Edit puts one right (applied out of battle; the learner never changes what you set). Forget: out of the list.
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y124 w100 h26 gSpKindClick vSpKindBtn, Change kind...
	Gui, Dash:Add, Button, x118 y124 w64 h26 gSpEditClick vSpEditBtn, Edit...
	Gui, Dash:Add, Button, x188 y124 w64 h26 gSpForgetClick vSpForgetBtn, Forget
	Gui, Dash:Add, Button, x258 y124 w96 h26 gSpHoldClick vSpHoldBtn, Never discard
	Gui, Dash:Add, Button, x360 y124 w92 h26 gSpPicClick vSpPicBtn, Show picture
	Gui, Dash:Add, Button, x458 y124 w86 h26 gSpFolderClick vSpFolderBtn, Open folder
	Gui, Dash:Add, Button, x550 y124 w100 h26 gSpMovedClick vSpMovedBtn, Moved away...
	Gui, Dash:Add, Button, x656 y124 w66 h26 gSpRefreshClick vSpRefreshBtn, Refresh
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Text, x12 y156 w760 h30 vSpStatus
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, ListView, x12 y190 w612 h598 vSpList gSpListEvent AltSubmit Background111317 cDADADA, Name|Kind|School|Pips|Value|Sure|In use|Text read|TC|Learned|Set|Id
	LV_ModifyCol(1, 96), LV_ModifyCol(2, 84), LV_ModifyCol(3, 50), LV_ModifyCol(4, 34), LV_ModifyCol(5, 66), LV_ModifyCol(6, "44 Integer")
	LV_ModifyCol(7, 112), LV_ModifyCol(8, 100), LV_ModifyCol(9, 26), LV_ModifyCol(10, 96), LV_ModifyCol(11, 50), LV_ModifyCol(12, 0)
	;(the spell picked: its picture, and what the bot took it for under it)
	Gui, Dash:Add, Picture, x632 y190 w140 h233 Hidden vSpPreview
	Gui, Dash:Font, s8 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x632 y428 w140 h360 vSpPreviewTxt, Pick a spell to see it.
	;The Cards tab: your hand - each card as the bot saw it this round, and what it took it for (DashHandSeen) - and the
	;enemies' spells: what each is likely to cast this round (EnemySpells.ahk EnemyDanger: DashFoesSeen)
	Gui, Dash:Tab, 4
	;(its row of views: your hand and the enemies, or one of your decks - Decks.ahk; push-like radio buttons: tabs inside a
	;tab can't be)
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Radio, x12 y62 w110 h24 +0x1000 Group Checked gDeckViewClick vDeckView0, Hand && enemies
	Loop, 6
		{
		dx := 126 + (A_Index - 1) * 96
		Gui, Dash:Add, Radio, x%dx% y62 w92 h24 +0x1000 Hidden gDeckViewClick vDeckView%A_Index%, Deck %A_Index%
		}
	Gui, Dash:Add, Button, x704 y62 w72 h24 gDeckAddClick vDeckAddBtn, + Deck
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y100 w630 h16 vDashHandHead, YOUR HAND - nothing read yet (once a round in battle)
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x646 y94 w130 h24 gDashLearnAll vDashLearnBtn, Learn every card
	Gui, Dash:Font, s8 w400 cDADADA, Segoe UI
	Loop, 7
		{
		cx := 12 + (A_Index - 1) * 72
		Gui, Dash:Add, Picture, x%cx% y122 w58 h97 Hidden vDashCardPic%A_Index%
		Gui, Dash:Add, Text, x%cx% y221 w66 h28 Hidden vDashCardTxt%A_Index%
		}
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y258 w760 h16 vDashFoeHead, ENEMIES - nothing yet (each battle round, with Settings > Predict the enemies' spells on)
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, ListView, x12 y278 w760 h514 vDashFoeList NoSort -Multi Background111317 cDADADA, Enemy|Spell|This round|Pips, what it does|This battle|Seen (all battles)
	LV_ModifyCol(1, 130), LV_ModifyCol(2, 170), LV_ModifyCol(3, 76), LV_ModifyCol(4, 186), LV_ModifyCol(5, 84), LV_ModifyCol(6, 96)
	;(a deck's view: what it is, what it's for, its damage, and the settings it has of its own - hidden till one's picked)
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x12 y101 w44 h18 Hidden vDeckFNameT, Name
	Gui, Dash:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, Dash:Add, Edit, x58 y98 w180 h22 Limit30 Hidden vDeckFName
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x250 y101 w48 h18 Hidden vDeckFSchoolT, School
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, DropDownList, x300 y98 w90 Hidden vDeckFSchool, any|storm|fire|myth|balance|ice|life|death
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x402 y101 w96 h18 Hidden vDeckFSetT, Equipment Set
	Gui, Dash:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, Dash:Add, Edit, x498 y98 w30 h22 Number Limit1 Hidden vDeckFSet
	Gui, Dash:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x534 y101 w240 h18 Hidden vDeckFSetN, (its Ctrl+1-9 puts its in-game deck on; 0: none)
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x12 y131 w64 h18 Hidden vDeckFWhenT, Used for
	Gui, Dash:Add, Checkbox, x78 y130 w104 h20 Hidden vDeckFWDefault, anything else
	Gui, Dash:Add, Checkbox, x186 y130 w104 h20 Hidden vDeckFWCollect, collect goals
	Gui, Dash:Add, Checkbox, x294 y130 w112 h20 Hidden vDeckFWBoss, % "bosses (" HkText("boss") ")"
	Gui, Dash:Add, Checkbox, x410 y130 w104 h20 Hidden vDeckFWDungeon, dungeon runs
	Gui, Dash:Add, Checkbox, x518 y130 w104 h20 Hidden vDeckFWFarm, farming (loop)
	Gui, Dash:Add, Text, x630 y131 w48 h18 Hidden vDeckFPriT, Priority
	Gui, Dash:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, Dash:Add, Edit, x680 y128 w40 h22 Number Limit3 Hidden vDeckFPri
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Checkbox, x12 y160 w380 h20 Hidden vDeckFPin, Use this deck now, whatever's ahead (pinned)
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x480 y157 w90 h24 Hidden gDeckSaveClick vDeckFSave, Save
	Gui, Dash:Add, Button, x576 y157 w90 h24 Hidden gDeckCopyClick vDeckFCopy, Copy
	Gui, Dash:Add, Button, x672 y157 w90 h24 Hidden gDeckDelClick vDeckFDel, Delete
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Text, x12 y188 w760 h44 Hidden vDeckFDmg
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, ListView, x12 y236 w760 h470 Hidden vDeckFList gDeckListEvent AltSubmit -Multi NoSort Background111317 cDADADA, Setting|This deck|Everywhere else|Key
	LV_ModifyCol(1, 360), LV_ModifyCol(2, 170), LV_ModifyCol(3, 200), LV_ModifyCol(4, 0)
	Gui, Dash:Add, Text, x12 y715 w128 h18 Hidden vDeckFValT, Value for this deck:
	Gui, Dash:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, Dash:Add, Edit, x142 y712 w70 h22 Hidden vDeckFVal
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x218 y711 w60 h24 Hidden gDeckValSet vDeckFValSet, Set
	Gui, Dash:Add, Button, x284 y711 w150 h24 Hidden gDeckValClear vDeckFValClear, Not set by this deck
	Gui, Dash:Font, s9 w400 cB9E2B9, Segoe UI
	Gui, Dash:Add, Text, x442 y715 w330 h36 Hidden vDeckFNote
	;The Network tab: every bot on your home network (Network.ahk) - pick one: its log and its game; the buttons send it
	;a command (with the network PIN)
	Gui, Dash:Tab, 5
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y68 w400 h16, BOTS ON YOUR NETWORK
	Gui, Dash:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x12 y88 w760 h32 vNetHelp, Every PC on your home network running the bot with Settings > NETWORK > neton. Pick one to see its log and its game. The buttons need the network PIN, the same on both PCs (Settings: netpin); Play for me can only be switched off from here.
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y124 w80 h26 gDashNetOn vNetOnBtn, Bot on
	Gui, Dash:Add, Button, x98 y124 w80 h26 gDashNetOff vNetOffBtn, Bot off
	Gui, Dash:Add, Button, x184 y124 w120 h26 gDashNetPfm vNetPfmBtn, Play for me off
	Gui, Dash:Add, Button, x310 y124 w80 h26 gDashNetRestart vNetRestartBtn, Restart
	Gui, Dash:Add, Button, x396 y124 w80 h26 gDashNetRefresh vNetRefreshBtn, Refresh
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Text, x12 y156 w760 h30 vNetStatus, Network: off (Settings > NETWORK > neton)
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, ListView, x12 y190 w760 h150 vNetList gDashNetListEvent AltSubmit -Multi Background111317 cDADADA, PC|Version|Wizard|Zone|Bot|Play for me|Doing|Health|Mana|Deaths|Seen|Id
	LV_ModifyCol(1, 110), LV_ModifyCol(2, 58), LV_ModifyCol(3, 110), LV_ModifyCol(4, 130), LV_ModifyCol(5, 52), LV_ModifyCol(6, 72)
	LV_ModifyCol(7, 96), LV_ModifyCol(8, 74), LV_ModifyCol(9, 60), LV_ModifyCol(10, 54), LV_ModifyCol(11, 60), LV_ModifyCol(12, 0)
	Gui, Dash:Font, s8 w400 cDADADA, Consolas
	Gui, Dash:Add, Edit, x12 y348 w380 h440 ReadOnly -Wrap +HScroll +VScroll vNetLog
	Gui, Dash:Add, Picture, x400 y348 w372 h210 vNetPic
	Gui, Dash:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x400 y564 w372 h60 vNetPicNote, Pick a bot to see its log and its game.
	;The Keys tab: every action's key - yours to change (Hotkeys.ahk)
	Gui, Dash:Tab, 6
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y68 w400 h16, KEYS
	Gui, Dash:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x12 y88 w760 h32 vKeyHelp, Pick an action and click Change (or double-click it), then press the new key - with Ctrl, Alt, Shift or Windows if you like. Keys the bot presses in the game (W A S D, X, Space, Ctrl+O, Ctrl+1-9, F13-F24) and plain letters can't be taken.
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y124 w90 h26 gKeyChangeClick vKeyChangeBtn, Change...
	Gui, Dash:Add, Button, x108 y124 w90 h26 gKeyDefaultClick vKeyDefaultBtn, Its default
	Gui, Dash:Add, Button, x204 y124 w90 h26 gKeyNoneClick vKeyNoneBtn, No key
	Gui, Dash:Add, Button, x300 y124 w110 h26 gKeyAllClick vKeyAllBtn, All to defaults
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Text, x12 y156 w760 h30 vKeyStatus
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, ListView, x12 y190 w760 h598 vKeyList gKeyListEvent AltSubmit -Multi Background111317 cDADADA, Action|Key|Default|Works|Id
	LV_ModifyCol(1, 330), LV_ModifyCol(2, 130), LV_ModifyCol(3, 150), LV_ModifyCol(4, 140), LV_ModifyCol(5, 0)
	Gui, Dash:Tab
	;The Play for me button, on every tab - the tab row's right end (DashGuiSize keeps it there), not the heading's
	;room: every check for you off till you click it again; off at every start. A red bar (green while on: DashPlayShow) -
	;a Progress control takes a colour - with the clickable words over it
	Gui, Dash:Add, Progress, x668 y37 w108 h24 BackgroundB71C1C Disabled vDashPlayBg
	Gui, Dash:Font, s9 w700 cFFFFFF, Segoe UI
	Gui, Dash:Add, Text, x668 y37 w108 h24 +Center +0x200 BackgroundTrans gDashPlayToggle vDashPlayBtn, Play for me
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	;(the log so far: the lines written before the window was made)
	FileRead, earlier, %A_ScriptDir%\debug.log
	if (earlier != "")
		DashAppend(earlier)
	IniRead, shown, %A_ScriptDir%\dashboard.ini, window, shown, 1
	DashApplyView()
	;(the Dungeons tab's list and status; the Spells tab's)
	DgListFill()
	DgShow()
	SpInit()
	;(the Keys tab's list)
	if (IsFunc("KeyListFill"))
		Func("KeyListFill").Call()
	if (shown)
		DashShow()
	SetTimer, DashRefresh, 1000
	OnExit("DashOnExit")
	;(the map: back if it was open when the bot stopped)
	IniRead, mapShown, %A_ScriptDir%\dashboard.ini, map, shown, 0
	if (mapShown = 1)
		DashMapShow()
	}

;The "Learn every card" button's label
DashLearnShow(learnOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashLearnBtn, % learnOn ? "Learning... (stop)" : "Learn every card"
	}

;The bot on/off button's label
DashBotShow(isOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashBotBtn, % "Bot: " (isOn ? "on" : "off") " (" HkText("bot") ")"
	}

;The Dungeons tab's help line - with the keys set now (Hotkeys.ahk)
DashDgHelpText()
	{
	return "Record a run once: stand outside the dungeon by its sigil, click Record a run and play it - X at the sigil, to the boss (fighting on the way), back out to where you started - then press " HkText("record") ". Pick it and click Run: the bot walks the same way, presses X where you did, fights every battle (the bot on, " HkText("bot") ") and starts over. " HkText("walk") " pauses it."
	}

;A key changed on the Keys tab (KeySet, KeyAllClick - Hotkeys.ahk): the dashboard's texts that name a key made again
;with the keys set now (the others - the status lines - are made afresh every second)
DashKeysChanged()
	{
	if (!DashHwnd)
		return
	GuiControl, Dash:, DashBotBtn, % "Bot: " (BotOn ? "on" : "off") " (" HkText("bot") ")"
	GuiControl, Dash:, DashWalkBtn, % "Walking on/off (" HkText("walk") ")"
	GuiControl, Dash:, DgHelp, % DashDgHelpText()
	;(while a run's being recorded: the key it was begun with - the one that stops it)
	GuiControl, Dash:, DgRecStopBtn, % "Stop recording (" (DgRecording ? HkName(DgRecKey) : HkText("record")) ")"
	GuiControl, Dash:Text, DeckFWBoss, % "bosses (" HkText("boss") ")"
	}

;The "Game to front" button's label
DashFrontShow(frontOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashFrontBtn, % "Game to front: " (frontOn ? "on" : "off")
	}

;The "Play for me" button: red "Play for me" off, green "PLAYING FOR ME" on (you asked, 2026-10-26)
DashPlayShow(on)
	{
	if (!DashHwnd)
		return
	playCol := on ? "2E7D32" : "B71C1C"
	GuiControl, Dash:+Background%playCol%, DashPlayBg
	GuiControl, Dash:, DashPlayBtn, % on ? "PLAYING FOR ME" : "Play for me"
	;(the words drawn again over the bar's new colour)
	GuiControl, Dash:MoveDraw, DashPlayBtn
	}

;The "Wait while I play" button's label
DashHandsShow(waitOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashHandsBtn, % "Wait for me: " (waitOn ? "on" : "off")
	}

;Simple (true) or advanced: which view of a window (what: "dashboard", "settings") - dashboard.ini [view]. Not set yet:
;advanced where the bot ran before (it had a dashboard.ini - nothing that was there goes missing), simple on a new one
ViewSimple(what)
	{
	ini := A_ScriptDir "\dashboard.ini"
	IniRead, v, %ini%, view, %what%, %A_Space%
	if (v = "")
		{
		;(both views decided at once - the first one asked mustn't make the file the other takes for "ran before")
		v := FileExist(ini) ? 0 : 1
		for each, w in ["dashboard", "settings"]
			{
			IniRead, had, %ini%, view, %w%, %A_Space%
			if (had = "")
				IniWrite, %v%, %ini%, view, %w%
			}
		IniRead, v, %ini%, view, %what%, %v%
		}
	return v = 1
	}

;The view shown: simple hides the log with its buttons (the window that much shorter), advanced shows them; the view
;button says which the other is
DashApplyView()
	{
	if (!DashHwnd)
		return
	act := DashSimple ? "Hide" : "Show"
	for each, c in ["DashLogHead", "DashConsole", "DashPauseBtn", "DashClearBtn", "DashLogBtn", "DashColBtn"]
		GuiControl, Dash:%act%, %c%
	GuiControl, Dash:, DashViewBtn, % DashSimple ? "Advanced view" : "Simple view"
	Gui, % "Dash:+MinSize740x" (DashSimple ? 330 : 640)
	}

;Shows the window where it was (else on a monitor the game isn't on), without taking the focus - each view its own
;place and size ([window]: advanced, [simple])
DashShow()
	{
	section := DashSimple ? "simple" : "window"
	IniRead, x, %A_ScriptDir%\dashboard.ini, %section%, x, %A_Space%
	IniRead, y, %A_ScriptDir%\dashboard.ini, %section%, y, %A_Space%
	IniRead, w, %A_ScriptDir%\dashboard.ini, %section%, w, 784
	IniRead, h, %A_ScriptDir%\dashboard.ini, %section%, h, %A_Space%
	IniRead, layout, %A_ScriptDir%\dashboard.ini, window, layout, 1
	;(the Hand section came in above the log, then the tabs: a window saved before that is that much taller now)
	if (DashSimple)
		h := (h = "") ? 330 : Max(330, h)
	else
		h := (h = "") ? 804 : (layout < 2 ? h + 180 : layout < 3 ? h + 28 : h)
	;(w and h are at 100% display scaling; Windows' scaling makes the window that much bigger)
	dpi := A_ScreenDPI / 96
	if (x = "" || y = "" || !DashOnScreen(x + 40, y + 20))
		{
		;(the first monitor that doesn't hold the middle of the game window; else the bottom right)
		spare := DashSpareMonitor(mLeft, mTop, mRight, mBottom)
		;(no bigger than that monitor)
		w := Min(w, Floor((mRight - mLeft - 40) / dpi) - 16), h := Min(h, Floor((mBottom - mTop - 40) / dpi) - 40)
		x := spare ? mLeft + 20 : mRight - Round((w + 16) * dpi) - 20
		y := spare ? mTop + 20 : mBottom - Round((h + 40) * dpi) - 20
		}
	DashFitHeight(x, y, h)
	Gui, Dash:Show, x%x% y%y% w%w% h%h% NoActivate
	DashShown := 1
	DashRefresh()
	}

;The work area of the first monitor that doesn't hold the middle of the game window: true; else the main
;monitor's and false
DashSpareMonitor(ByRef mLeft, ByRef mTop, ByRef mRight, ByRef mBottom)
	{
	gx := GameLeft + GameW // 2, gy := GameTop + GameH // 2
	SysGet, count, MonitorCount
	Loop, %count%
		{
		SysGet, m, MonitorWorkArea, %A_Index%
		if (!(gx >= mLeft && gx < mRight && gy >= mTop && gy < mBottom))
			return true
		}
	SysGet, m, MonitorWorkArea
	return false
	}

;The work area of the monitor that holds x, y (else the main monitor's)
DashMonitorAt(x, y, ByRef mLeft, ByRef mTop, ByRef mRight, ByRef mBottom)
	{
	SysGet, count, MonitorCount
	Loop, %count%
		{
		SysGet, m, MonitorWorkArea, %A_Index%
		if (x >= mLeft && x < mRight && y >= mTop && y < mBottom)
			return
		}
	SysGet, m, MonitorWorkArea
	}

;h (a window's inside, at 100% display scaling) cut so a window at x, y fits on the monitor it's on
DashFitHeight(x, y, ByRef h)
	{
	dpi := A_ScreenDPI / 96
	SysGet, count, MonitorCount
	Loop, %count%
		{
		SysGet, m, MonitorWorkArea, %A_Index%
		if (x + 40 >= mLeft && x + 40 < mRight && y + 20 >= mTop && y + 20 < mBottom)
			h := Min(h, Floor((mBottom - y - 20) / dpi) - 40)
		}
	}

DashOnScreen(x, y)
	{
	SysGet, count, MonitorCount
	Loop, %count%
		{
		SysGet, m, Monitor, %A_Index%
		if (x >= mLeft && x < mRight && y >= mTop && y < mBottom)
			return true
		}
	return false
	}

;Windows+2 / tray menu
DashToggle()
	{
	if (!DashHwnd)
		return
	if (DashShown)
		{
		DashSavePlace()
		Gui, Dash:Hide
		DashShown := 0
		}
	else
		DashShow()
	IniWrite, %DashShown%, %A_ScriptDir%\dashboard.ini, window, shown
	}

DashSavePlace()
	{
	if (!DashShown || !DashHwnd)
		return
	if (DashSimple)
		DashSaveWin(DashHwnd, "simple")
	else if (DashSaveWin(DashHwnd, "window"))
		IniWrite, 3, %A_ScriptDir%\dashboard.ini, window, layout
	}

;Saves where a window is in dashboard.ini [section]: x, y on the screen, and its inside's width and height at
;100% display scaling (as Gui Show takes them). Not while it's minimized or maximized (false)
DashSaveWin(hwnd, section)
	{
	WinGet, mm, MinMax, ahk_id %hwnd%
	if (mm != 0)
		return false
	VarSetCapacity(rc, 16, 0)
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rc)
	WinGetPos, x, y,,, ahk_id %hwnd%
	if (x = "")
		return false
	IniWrite, %x%, %A_ScriptDir%\dashboard.ini, %section%, x
	IniWrite, %y%, %A_ScriptDir%\dashboard.ini, %section%, y
	IniWrite, % Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), %A_ScriptDir%\dashboard.ini, %section%, w
	IniWrite, % Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI), %A_ScriptDir%\dashboard.ini, %section%, h
	return true
	}

;---- The Network tab (Network.ahk) ----

;The Network tab is the one showing (and the window's up)
DashNetShown()
	{
	if (!DashHwnd || !DashShown)
		return false
	GuiControlGet, netTab, Dash:, DashTabs
	return netTab = "Network"
	}

;The Network tab's list and status line afresh (NetTick, every 2 s): this PC first, then every bot heard - the one
;picked kept picked
DashNetFill()
	{
	if (!DashHwnd)
		return
	n := IsObject(NetPeers) ? NetPeers.Length() : 0
	DashSet("NetStatus", "Network: " NetState (NetWhy != "" ? " - " NetWhy : "") (NetState = "on" ? "`n" n " other bot" (n = 1 ? "" : "s") " heard on your home network" (n ? "" : " - is neton switched on there, and Python allowed through its firewall?") : ""))
	if (!DashNetShown())
		return
	wasCrit := A_IsCritical
	Critical
	Gui, Dash:Default
	prevLV := A_DefaultListView
	Gui, Dash:ListView, NetList
	GuiControl, Dash:-Redraw, NetList
	LV_Delete()
	LV_Add("", A_ComputerName " (this PC)", BotVersion(), OwnName(), WalkZone(), (BotStandby && !BotEverOn) ? "standby" : BotOn ? "on" : "off"
		, PlayForMe ? "ON" : "off", "-", RegExReplace(IsObject(DashSees) ? DashSees.hp : "", "\s*\(.*"), IsObject(DashSees) ? DashSees.mana : ""
		, IsObject(DashN) && DashN.deaths ? DashN.deaths : 0, "now", "")
	for i, p in NetPeers
		{
		row := LV_Add("", p.pc, p.ver, p.wiz (p.school != "" ? " (" p.school ")" : ""), p.zone, p.bot, p.pfm = 1 ? "ON" : "off", p.doing
			, p.hp, p.mana, p.deaths (p.dall != "" ? " / " p.dall : ""), p.age > 15 ? NetAge(p.age) " ago (quiet)" : "now", p.id)
		if (p.id = NetSel)
			LV_Modify(row, "Select Focus")
		}
	GuiControl, Dash:+Redraw, NetList
	if (prevLV != "" && prevLV != "NetList")
		Gui, Dash:ListView, %prevLV%
	CfgUncritical(wasCrit, 0)
	}

;The picked bot's log and picture onto the tab (NetFetchPicked); pic "" - none, why says why
DashNetShow(log, pic, why)
	{
	if (!DashHwnd)
		return
	if (log != "")
		{
		GuiControl, Dash:, NetLog, %log%
		;(the log's end in view)
		GuiControlGet, netLogHwnd, Dash:Hwnd, NetLog
		SendMessage, 0x115, 7, 0, , ahk_id %netLogHwnd%
		}
	if (pic != "")
		{
		GuiControl, Dash:, NetPic, *w372 *h-1 %pic%
		GuiControl, Dash:Show, NetPic
		GuiControl, Dash:, NetPicNote, % "Its game, " A_Hour ":" A_Min ":" A_Sec (why != "" ? " - " why : "")
		}
	else
		{
		;(no picture this time: the last one isn't left up under it)
		GuiControl, Dash:Hide, NetPic
		GuiControl, Dash:, NetPicNote, % why != "" ? why : "No picture"
		}
	}

DashOnExit(reason, code)
	{
	DashSavePlace()
	if (DashMapShown && DashMapHwnd)
		DashSaveWin(DashMapHwnd, "map")
	}

;---- What goes in ----

;Every DebugLog line (with its time): onto the log, and into the counts
DashLog(line)
	{
	;(the last line written - the Network tab's "last" for the other bots, Network.ahk)
	NetLastLine := line
	if (!DashHwnd)
		return
	DashParse(line)
	if (DashPaused)
		DashHeld .= line "`r`n"
	else
		DashAppend(line "`r`n")
	}

;---- The log in colour: each line's kind (DashLogKind) in its colour (dashboard.ini [logcolors], the Colours button) ----

;The kinds, in the order the Colours window lists them: [key, label, default colour RRGGBB]
DashLogKinds()
	{
	static kinds := ""
	if (!IsObject(kinds))
		kinds := [["problem", "Problems (needs you, stuck, couldn't...)", "FF6B6B"], ["movement", "Movement (walking)", "7FB3FF"]
			, ["battle", "Battle (rounds, cards, enemies)", "F2A65A"], ["wait", "Waits and delays", "8A8F98"]
			, ["potion", "Potions", "C792EA"], ["reconnect", "Reconnect and the game's window", "E5C07B"]
			, ["party", "Party", "56D4C9"], ["alert", "Discord alerts", "F78FB3"]
			, ["system", "The bot itself (start, settings, pictures)", "B9E2B9"], ["other", "Everything else", "DADADA"]]
	return kinds
	}

;Which kind a log line is ("HH:mm:ss text")
DashLogKind(line)
	{
	msg := SubStr(line, 10)
	if (RegExMatch(msg, "i)^Defeated:|NEEDS YOU|\bstuck\b|couldn't|can't|\bfailed\b|didn't work|gave up|giving up|\bERR\b|error|not found|wasn't found|hung"))
		return "problem"
	if (RegExMatch(msg, "i)^Walk: (waiting|paused)|^Watching for a round|resting|^Walk: loading|loading screen|^Walk: speed: 1x"))
		return "wait"
	if (InStr(msg, "Walk:") = 1)
		return "movement"
	if (InStr(msg, "Potions:") = 1)
		return "potion"
	if (InStr(msg, "Reconnect:") = 1 || InStr(msg, "Wizard101 brought to the front") = 1)
		return "reconnect"
	if (InStr(msg, "Party:") = 1)
		return "party"
	if (InStr(msg, "Discord:") = 1)
		return "alert"
	if (RegExMatch(msg, "^(Round start|Round done|Out of battle|In a battle|Battle log|  )"))
		return "battle"
	if (RegExMatch(msg, "^(Started|Vision:|UI size|Pictures:|Settings|Play for me|Wait while I play|Bring Wizard101|Walking on|Walking off|Bot )"))
		return "system"
	return "other"
	}

;The colours in use: {kind: "RRGGBB"} - dashboard.ini [logcolors], else the defaults
DashLogColors(reload := false)
	{
	static colours := ""
	if (IsObject(colours) && !reload)
		return colours
	colours := {}
	for each, k in DashLogKinds()
		{
		IniRead, c, %A_ScriptDir%\dashboard.ini, logcolors, % k[1], % k[3]
		colours[k[1]] := RegExMatch(c, "^[0-9A-Fa-f]{6}$") ? c : k[3]
		}
	return colours
	}

;A colour RRGGBB as the COLORREF Windows wants (0x00BBGGRR)
DashBGR(rgb)
	{
	;(a standalone += - "0x" rgb + 0 inside an expression comes out blank)
	v := "0x" rgb
	v += 0
	return ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF)
	}

;The text that follows in the log box: in this colour (CHARFORMAT2W on the selection - the end, where it's added)
DashLogColour(rgb)
	{
	VarSetCapacity(cf, 116, 0)
	NumPut(116, cf, 0, "UInt"), NumPut(0x40000000, cf, 4, "UInt"), NumPut(DashBGR(rgb), cf, 20, "UInt")    ; CFM_COLOR, crTextColor
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x444, "Ptr", 1, "Ptr", &cf)    ; EM_SETCHARFORMAT, SCF_SELECTION
	}

;The log box's length in its own characters (a line break counts 1 - as EM_SETSEL counts)
DashLogLen()
	{
	VarSetCapacity(gtl, 8, 0), NumPut(10, gtl, 0, "UInt"), NumPut(1200, gtl, 4, "UInt")       ; GTL_PRECISE|GTL_NUMCHARS, UTF-16
	return DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x45F, "Ptr", &gtl, "Ptr", 0, "Ptr")  ; EM_GETTEXTLENGTHEX
	}

;The log box (a rich edit - an Edit can't colour its lines) set up: the dark background, Consolas 9, no word wrap
DashLogInit()
	{
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x443, "Ptr", 0, "Ptr", DashBGR("111317"))   ; EM_SETBKGNDCOLOR
	VarSetCapacity(cf, 116, 0)
	NumPut(116, cf, 0, "UInt"), NumPut(0xE0000000, cf, 4, "UInt")      ; CFM_SIZE | CFM_COLOR | CFM_FACE
	NumPut(180, cf, 12, "Int"), NumPut(DashBGR("DADADA"), cf, 20, "UInt")
	StrPut("Consolas", &cf + 26, 32, "UTF-16")
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x444, "Ptr", 4, "Ptr", &cf)    ; EM_SETCHARFORMAT, SCF_ALL
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x448, "Ptr", 0, "Ptr", 1)      ; EM_SETTARGETDEVICE: no wrap
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x435, "Ptr", 0, "Ptr", 0x7FFFFFFE)   ; EM_EXLIMITTEXT
	}

;Lines added to the log box, each in its kind's colour (runs of one kind added at once); the first half let go past
;200000 characters
DashAppend(text)
	{
	;(a rich edit's own text ends its lines with a bare CR: DashLogRecolour)
	text := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
	len := DashLogLen()
	if (len > 200000)
		{
		cutLine := DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x436, "Ptr", 0, "Ptr", len // 2, "Ptr")    ; EM_EXLINEFROMCHAR
		cut := DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xBB, "Ptr", cutLine + 1, "Ptr", 0, "Ptr")      ; EM_LINEINDEX
		if (cut > 0)
			{
			DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xB1, "Ptr", 0, "Ptr", cut)      ; EM_SETSEL
			DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xC2, "Ptr", 0, "Str", "")       ; EM_REPLACESEL
			}
		len := DashLogLen()
		}
	colours := DashLogColors()
	run := "", runKind := ""
	Loop, Parse, text, `n
		{
		if (A_LoopField = "" && A_Index > 1)
			continue
		k := DashLogKind(A_LoopField)
		if (k != runKind && run != "")
			DashAppendRun(run, colours[runKind]), run := ""
		runKind := k, run .= A_LoopField "`r`n"
		}
	if (run != "")
		DashAppendRun(run, colours[runKind])
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xB7, "Ptr", 0, "Ptr", 0)         ; EM_SCROLLCARET
	}

;One run of lines at the log box's end, in colour rgb
DashAppendRun(run, rgb)
	{
	len := DashLogLen()
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xB1, "Ptr", len, "Ptr", len)      ; EM_SETSEL (the end)
	DashLogColour(rgb)
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xC2, "Ptr", 0, "Str", run)       ; EM_REPLACESEL
	}

;The Colours window: each kind of log line - a swatch of its colour, Change... (Windows' colour picker) - and Reset
DashLogColorsWindow()
	{
	global
	local kinds, colours, i, k, y, col
	Gui, LogCol:New, +OwnerDash +ToolWindow +HwndLogColHwnd, Log colours
	Gui, LogCol:Color, 1B1D22
	Gui, LogCol:Font, s9 w400 cF2F2F2, Segoe UI
	kinds := DashLogKinds(), colours := DashLogColors()
	for i, k in kinds
		{
		y := 10 + (i - 1) * 28, col := colours[k[1]]
		Gui, LogCol:Add, Progress, x10 y%y% w22 h18 Background%col% Disabled vLogColSw%i%
		Gui, LogCol:Add, Text, x40 y%y% w270 h18 +0x200, % k[2]
		Gui, LogCol:Font, s9 w400 c000000, Segoe UI
		Gui, LogCol:Add, Button, x316 y%y% w76 h20 gDashLogColorPick vLogColBtn%i%, Change...
		Gui, LogCol:Font, s9 w400 cF2F2F2, Segoe UI
		}
	y := 16 + kinds.Length() * 28
	Gui, LogCol:Font, s9 w400 c000000, Segoe UI
	Gui, LogCol:Add, Button, x10 y%y% w110 h24 gDashLogColorReset, Reset all
	Gui, LogCol:Add, Button, x292 y%y% w100 h24 gDashLogColorClose, Close
	Gui, LogCol:Show, AutoSize
	}

;Windows' colour picker, starting at rgb (RRGGBB): the colour chosen, "" cancelled
DashPickColour(rgb, owner)
	{
	;(its 16 custom colours kept between opens - made once: the buffer read as text is "" whenever slot 1 is black)
	static cust, custMade := 0
	if (!custMade)
		VarSetCapacity(cust, 64, 0), custMade := 1
	size := A_PtrSize = 8 ? 72 : 36
	VarSetCapacity(cc, size, 0)
	NumPut(size, cc, 0, "UInt")
	NumPut(owner, cc, A_PtrSize, "Ptr")                         ; hwndOwner
	NumPut(DashBGR(rgb), cc, 3 * A_PtrSize, "UInt")             ; rgbResult
	NumPut(&cust, cc, 4 * A_PtrSize, "Ptr")                     ; lpCustColors
	NumPut(0x3, cc, 5 * A_PtrSize, "UInt")                      ; CC_RGBINIT | CC_FULLOPEN
	if (!DllCall("comdlg32\ChooseColorW", "Ptr", &cc))
		return ""
	c := NumGet(cc, 3 * A_PtrSize, "UInt")
	return Format("{:02X}{:02X}{:02X}", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)
	}

;The log box coloured afresh - its lines put back in, each in its kind's colour now
DashLogRecolour()
	{
	GuiControlGet, lrAll, Dash:, DashConsole
	GuiControl, Dash:, DashConsole,
	if (lrAll != "")
		DashAppend(lrAll)
	}

;The counts and what it sees, from a log line ("HH:mm:ss text")
DashParse(line)
	{
	msg := SubStr(line, 10)
	if (InStr(msg, "Round start:") = 1)
		DashAdd("rounds"), DashSees.mode := "battle", DashSees.roundAt := A_TickCount, DashSees.plan := "", DashSees.threat := ""
	else if (msg = "Round done")
		DashSees.mode := "battle"
	else if (InStr(msg, "Out of battle") = 1)
		DashSees.mode := "out", DashSees.plan := ""
	else if (RegExMatch(msg, "^  saving pips for (\w+) \((\d+) pips, you have (\d+)\).*up to (\d+) round", m))
		DashAdd("pipsaves"), DashSees.plan := "saving pips for " DashShortName(m1) " (" m3 "/" m2 " pips)"
	else if (RegExMatch(msg, "^  (not saving pips|saved pips) .*", m))
		DashSees.plan := Trim(m)
	else if (RegExMatch(msg, "^  Click pass: found=1"))
		DashAdd("passes")
	else if (InStr(msg, "  Discarded ") = 1)
		DashAdd("discards")
	else if (InStr(msg, "  fleeing: ") = 1)
		DashAdd("flees")
	else if (InStr(msg, "Defeated:") = 1)
		DashAdd("deaths"), DashDeathsAll(1)
	else if (RegExMatch(msg, "^  kill check: (.*) -> (.*)$", m))
		{
		DashSees.enemies := m1
		if (m2 != "no lethal hit")
			DashAdd("lethal")
		}
	else if (RegExMatch(msg, "^  pips=(-?\d+)", m))
		DashSees.pips := (m1 < 0 ? "?" : m1)
	else if (RegExMatch(msg, "^  own health: (\d+)/(\d+)", m))
		DashSees.hp := m1 "/" m2 " (" Round(100 * m1 / m2) "%, name plate)"
	else if (RegExMatch(msg, "school=(\w*) \| hitter=(\w*)", m))
		DashSees.school := m1, DashSees.hitter := m2
	else if (RegExMatch(msg, "^  learned a new card: (.*?)( \(picture:|$)", m))
		DashAdd("learned"), DashSees.lastLearned := m1
	else if (InStr(msg, "Potions: drank one") = 1)
		DashAdd("potions")
	else if (InStr(msg, "Potions: no potion left - going to buy some") = 1)
		DashAdd("potionRuns")
	else if (InStr(msg, "Reconnect: ") = 1)
		DashSees.reconnect := SubStr(msg, 12), DashSees.reconnectAt := A_TickCount
	else if (InStr(msg, "Pictures: ") = 1)
		DashSees.pictures := SubStr(msg, 11)
	else if (InStr(msg, "Stats: ") = 1)
		DashSees.stats := SubStr(msg, 8)
	else if (RegExMatch(msg, "^  (UseHeal|UseHit|UseBlade|UseTrap|UseOnSelf|UseOnHammer|UseConvert|Click) (\w+): found=1", m) && m2 != "pass")
		DashSees.lastTry := m2
	}

DashAdd(key, n := 1)
	{
	if (IsObject(DashN))
		DashN[key] := (DashN.HasKey(key) ? DashN[key] : 0) + n
	}

;A card went down (CastResult saw it cast)
DashCast(title)
	{
	if (!IsObject(DashCasts))
		return
	DashCasts[title] := (DashCasts.HasKey(title) ? DashCasts[title] : 0) + 1
	DashAdd("casts")
	DashSees.lastCast := DashCardName(title) " at " A_Hour ":" A_Min ":" A_Sec
	}

;What the bot sees (key: hand, you...)
DashSee(key, text)
	{
	if (IsObject(DashSees))
		DashSees[key] := text
	}

;The hand as the vision helper read it (/hand's answer, CardLearn.ahk): each card's name, ?<type> for one
;the bot doesn't know, * for a greyed-out one (not enough pips). A box the helper says isn't a card (field 15 = 0:
;the deck's back, the round's timer, the floor) is left out
DashHandSeen(answer)
	{
	text := "", n := 0, box := 0, notCards := 0
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 12 || f[1] != "card")
			continue
		;(the helper saves every box's picture, generated\hand\hand<box>.png)
		box += 1
		if (f.Length() >= 15 && f[15] = "0")
			{
			notCards += 1
			continue
			}
		known := f[6]
		name := known = "" ? "?" (f[9] = "" ? "card" : f[9]) : InStr(known, "learned/") = 1 ? DashLearnedName(SubStr(known, 9)) : DashShortName(SubStr(known, InStr(known, "/") + 1), SubStr(known, 1, InStr(known, "/") - 1))
		text .= (text = "" ? "" : ", ") name (f[8] = 1 ? "*" : "")
		n += 1
		if (n <= 7)
			DashHandCard(n, name, known, f[8] = 1, f[11] != "" ? f[11] : DashKnownPips(known), box)
		}
	;(the slots past the hand: empty)
	Loop, % 7 - Min(n, 7)
		{
		slot := n + A_Index
		DashCardShow(slot, 0, 0)
		}
	FormatTime, now, , HH:mm:ss
	GuiControl, Dash:, DashHandHead, % "YOUR HAND " now " (" n " card" (n = 1 ? "" : "s") (notCards ? ", " notCards " not a card" : "") ")   white known   yellow new to it   grey can't cast"
	DashSee("hand", text)
	}

;A known card's pip cost when its digit wasn't read ("" not known): an enchant (Sharpened Blade, Potent Trap, Epic,
;Colossal...) and the like are free - 0 - and a slot's cost is in PlayerStats.txt (<school>.<slot>pips); a "?" for a
;free card was shown otherwise (2026-10-23)
DashKnownPips(known)
	{
	if (known = "")
		return ""
	dir := SubStr(known, 1, InStr(known, "/") - 1), title := SubStr(known, InStr(known, "/") + 1)
	if (dir = "resources" && RegExMatch(title, "i)^(sharpen|potent|epic|colossal|gargantuan|monstrous|giant|strong)$"))
		return 0
	if (dir = "life" && title = "enchant")
		return 0
	;(0 there is an X-pip spell's - all your pips - not a free one: left as not known)
	if (IsObject(Stats) && Stats.HasKey(dir "." title "pips") && Stats[dir "." title "pips"] > 0)
		return Stats[dir "." title "pips"]
	return ""
	}

;A learned card's name in the hand: the one you gave it on the Spells tab, else "learned"
DashLearnedName(id)
	{
	c := IsFunc("LearnCardOf") ? Func("LearnCardOf").Call(id) : ""
	return (IsObject(c) && c.name != "") ? c.name : "learned"
	}

;One card of the Hand section (n: its place there): its picture as the bot saw it (generated\hand\hand<box>.png,
;saved by the vision helper - box: the helper's count, non-cards too) and under it what it took it for and the pips it
;read - white known, yellow unknown, grey greyed out
DashHandCard(n, name, known, grey, pips, box := "")
	{
	if (!DashHwnd)
		return
	pic := A_ScriptDir "\generated\hand\hand" (box = "" ? n : box) ".png"
	if (FileExist(pic))
		{
		;(the picture control is sized for 100% display scaling; the picture is loaded at its real size)
		GuiControl, Dash:, DashCardPic%n%, % "*w" Round(58 * A_ScreenDPI / 96) " *h" Round(97 * A_ScreenDPI / 96) " " pic
		DashCardShow(n, 1, "")
		}
	else
		DashCardShow(n, 0, "")
	colour := grey ? "8A8A8A" : known = "" ? "F2C14E" : "E8E8E8"
	GuiControl, Dash:+c%colour%, DashCardTxt%n%
	GuiControl, Dash:, DashCardTxt%n%, % SubStr(name, 1, 12) "`n" (pips = "" ? "? pips" : pips " pip" (pips = 1 ? "" : "s")) (grey ? " - grey" : "")
	DashCardShow(n, "", 1)
	}

;A hand card's picture (pic) and words (txt) shown (1) or not (0) - "" left as they are: kept for the hand's view, shown
;only while it's the one up (a deck's view over it: Decks.ahk DeckViewShow puts them back)
DashCardShow(n, pic, txt)
	{
	if (!IsObject(DashCardWant))
		DashCardWant := {}
	if (pic != "")
		DashCardWant["p" n] := pic
	if (txt != "")
		DashCardWant["t" n] := txt
	if (DeckView)
		return
	if (pic != "")
		GuiControl, % "Dash:" (pic ? "Show" : "Hide"), DashCardPic%n%
	if (txt != "")
		GuiControl, % "Dash:" (txt ? "Show" : "Hide"), DashCardTxt%n%
	}

;The Cards tab's enemies (EnemySpells.ahk EnemyDanger, each round): each one - its school, rank and health off the wiki,
;the chance it hits you, its pips - and under it every spell it has, likeliest first: the chance it casts it this
;round, its pips and damage, the rounds it cast it this battle, how often it was seen casting it (all battles, weighed).
;answer: /enemies'; lethal: the chance their hits kill you this round ("" not known); health: yours as read ("" not
;read); rnd: the round
DashFoesSeen(answer, lethal, health, rnd)
	{
	if (!DashHwnd)
		return
	wasCrit := A_IsCritical
	Critical
	;(the window has three ListViews: this one for the LV_ functions, the one before put back after)
	Gui, Dash:Default
	prevLV := A_DefaultListView
	Gui, Dash:ListView, DashFoeList
	GuiControl, Dash:-Redraw, DashFoeList
	LV_Delete()
	foes := 0
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] != "enemy")
			continue
		foes += 1
		if (foes > 1)
			LV_Add("", "")
		if (f[4] != "ok")
			LV_Add("", f[3], f[4] = "pending" ? "looking it up on the wiki" : "not on the wiki - its spells not known")
		else
			{
			about := (f[9] != "" ? f[9] : "") (f[10] != "" ? ", rank " f[10] : "") (f[11] != "" ? ", " f[11] " health" : "")
			LV_Add("", f[3], about = "" ? "" : "(" LTrim(about, ", ") ")", "hits you " Round(f[6] * 100) "%"
				, "~" Round(f[5], 1) " pips now" (f[7] > 0 ? ", biggest hit " f[7] : ""))
			}
		;(spell:chance:pips and damage:seen before:rounds cast this battle)
		for each, card in StrSplit(f[12], ";")
			{
			p := StrSplit(card, ":")
			if (p[1] = "")
				continue
			LV_Add("", "", "   " p[1], Round(p[2] * 100) "%", p[3], p[5] = "" ? "" : "round " StrReplace(p[5], "/", ", ")
				, p[4] > 0 ? RegExReplace(Round(p[4], 1), "\.0$") : "")
			}
		}
	GuiControl, Dash:+Redraw, DashFoeList
	if (prevLV != "" && prevLV != "DashFoeList")
		Gui, Dash:ListView, %prevLV%
	FormatTime, now, , HH:mm:ss
	GuiControl, Dash:, DashFoeHead, % "ENEMIES " now ", round " rnd " - " (foes = 0 ? "none named in the game's log"
		: lethal = "" ? "your health not read: the chance they kill you not known" : Round(lethal * 100) "% chance their hits kill you this round (your health " health ")")
	if (!wasCrit)
		Critical, Off
	}

;A slot's card name alone (e.g. "Scarab"), else the slot
DashShortName(title, dir := "")
	{
	full := DashCardName(title, dir)
	return InStr(full, " (") ? SubStr(full, 1, InStr(full, " (") - 1) : full
	}

;A card's name for a slot (e.g. hit1 -> "Scarab"), from its comment in PlayerStats.txt; else the slot
DashCardName(title, dir := "")
	{
	if (!IsObject(DashNames) || A_TickCount - DashNames._at > 60000)
		{
		DashNames := {_at: A_TickCount}
		prevKey := ""
		Loop, Read, %A_ScriptDir%\PlayerStats.txt
			{
			line := A_LoopReadLine
			if (RegExMatch(line, "^\s*([\w.]+)\s*:[^;]*;\s*(.*)$", m))
				key := m1, comment := m2
			else if (prevKey != "" && RegExMatch(line, "^\s*;\s*\^\s*(.*)$", m))
				key := prevKey, comment := m1
			else
				{
				prevKey := RegExMatch(line, "^\s*([\w.]+)\s*:", m) ? m1 : ""
				continue
				}
			prevKey := RegExMatch(line, "^\s*([\w.]+)\s*:", k) ? k1 : ""
			comment := RegExReplace(comment, "i)^learned \d+:\s*")
			if (RegExMatch(comment, "^([A-Z][A-Za-z']*(?: [A-Z][A-Za-z']*)*)", n) && !DashNames.HasKey(key))
				DashNames[key] := n1
			}
		}
	key := Format("{:L}", (dir != "" && dir != "resources" ? dir : hitschool) "." title)
	if (DashNames.HasKey(key))
		return DashNames[key] " (" title ")"
	key := Format("{:L}", title)
	return DashNames.HasKey(key) ? DashNames[key] " (" title ")" : title
	}

;---- Showing it ----

DashRefresh()
	{
	;(a dungeon run or recording: its line on the Dungeons tab)
	if (IsObject(DgRun) || DgRecording)
		DgShow()
	if (!DashShown || !DashHwnd)
		return
	;(the Spells tab's list: again when the catalog changed - LearnSave - or a correction was applied)
	if (SpDirty)
		SpListFill()
	up := (A_TickCount - DashStart) // 1000
	upText := Format("{:02}:{:02}:{:02}", up // 3600, Mod(up // 60, 60), Mod(up, 60))
	;What it's doing
	if (!BotOn)
		doing := BotEverOn ? "Off - " HkText("bot") " turns the bot on" : "Standby - press " HkText("bot") " to start the bot"
	else if (PotionRecording)
		doing := "Recording potion buying"
	else if (LearnAll)
		doing := "Learning every card (" (IsObject(LearnedCards) ? LearnedCards.Length() - LearnAllFrom : 0) " new so far)"
	else if (WkNoteKind != "")
		doing := "Needs you: " WkNoteTitle
	else if (PlayerActive)
		doing := "You're playing - the bot waits"
	else if (DashSees.mode = "battle" && A_TickCount - DashSees.roundAt < 120000)
		doing := "In battle (round " DashN.rounds ")"
	else if (!Walking)
		doing := "Walking off (" HkText("walk") ")"
	else if (StatusText != "")
		doing := StatusText
	else
		doing := "Watching"
	;(the window's title says "Wizard101 bot")
	DashSet("DashHead", BotVersion() "  |  up " upText "  |  vision " (VisionOn ? "on" : "off") "  |  " SubStr(doing, 1, 70))
	;The version, and whether a newer one is out (the last look-up: UpdState) - on the Updates button too
	upd := UpdState()
	verNote := upd.newer ? upd.latest " is out" : upd.err != "" ? "can't check" : upd.latest != "" ? "up to date" : "not checked yet"
	;(why it can't check: in the log, once each time it changes)
	static updErrSaid := ""
	if (upd.err != updErrSaid)
		{
		updErrSaid := upd.err
		if (upd.err != "")
			DebugLog("Updates: can't check for a newer version - " upd.err)
		}
	if (DashUpdBusy && A_TickCount - DashUpdBusy > 10000)
		{
		DashUpdBusy := 0
		GuiControl, Dash:Enable, DashUpdBtn
		}
	DashSet("DashUpdBtn", DashUpdBusy ? "Checking..." : upd.newer ? "Update to " upd.latest : (upd.err = "" && upd.latest != "") ? "Up to date" : "Check for updates")
	;Statistics
	n := DashN
	casts := ""
	for title, count in DashCasts
		casts .= "`n   " SubStr(DashCardName(title) "                              ", 1, 25) Format("{:6}", count)
	;(the cards cast one by one last: what the box's height cuts off)
	s := "Version          " (BotVersion() = "" ? "?" : BotVersion()) " - " verNote "`n"
		. "Battles          " DashNum(battles) "`n"
		. "Deaths           " DashNum(n.deaths) "   (all time: " DashDeathsAll() ")`n"
		. "Rounds played    " DashNum(n.rounds) "`n"
		. "Passed           " DashNum(n.passes) "   (fled: " (n.flees = "" ? 0 : n.flees) ")`n"
		. "Discarded        " DashNum(n.discards) "`n"
		. "Kill-check hits  " DashNum(n.lethal) "`n"
		. "Rounds saving pips" SubStr(DashNum(n.pipsaves), 2) "`n"
		. "Potions drunk    " DashNum(n.potions) "   (buying runs: " (n.potionRuns = "" ? 0 : n.potionRuns) ")`n"
		. "Cards learned    " DashNum(n.learned) "`n"
		. "Cards cast       " DashNum(n.casts) casts
	DashSet("DashStatText", s)
	DashSet("DashUsageText", DashUsage())
	;What it sees
	see := DashSees
	zone := IsFunc("WalkZone") ? Func("WalkZone").Call() : ""
	t := "You          " (see.hp != "" ? see.hp : "?") (see.mana != "" ? ", mana " see.mana : "") ", pips " (see.pips != "" ? see.pips : "?") "`n"
		. "School       " (see.school != "" ? see.school : "?") "  (hitting with " (see.hitter != "" ? see.hitter : "?") ")`n"
		. "Hand         " DashCut(see.hand != "" ? see.hand : "-") "`n"
		. "Enemies      " DashCut(see.enemies != "" ? see.enemies : "-") "`n"
		. "Threat       " DashCut(see.threat != "" ? see.threat : "-") "`n"
		. "Plan         " DashCut(see.plan != "" ? see.plan : "-") "`n"
		. "Deck         " DashCut(see.deck != "" ? see.deck : "-") "`n"
		. "Last cast    " (see.lastCast != "" ? see.lastCast : "-") "`n"
		. "Zone         " DashCut(zone != "" ? zone : "?") "`n"
		. "Walker       " DashCut(StatusText != "" ? StatusText : "-") "`n"
		. (see.party != "" ? "Party        " DashCut(see.party) "`n" : "")
		. "Pictures     " DashCut(see.pictures != "" ? RegExReplace(see.pictures, " - card area.*") : "?") "`n"
		. "Last learned " DashCut(see.lastLearned != "" ? see.lastLearned : "-")
		. (see.reconnect != "" && A_TickCount - see.reconnectAt < 600000 ? "`nReconnect    " DashCut(see.reconnect) : "")
	DashSet("DashSeeText", t)
	}

;A value cut to what fits the "What it sees" column (its width, past the 13-letter label; Consolas 9 is
;about 7 px a letter - the width is in 100%-scaling pixels too)
DashCut(text)
	{
	GuiControlGet, pos, Dash:Pos, DashSeeText
	fit := Max(20, Floor(posW / 7) - 14)
	return StrLen(text) > fit ? SubStr(text, 1, fit - 1) "~" : text
	}

;A count, right-aligned (blank = 0)
;Deaths over every run (dashboard.ini [stats] deaths - updates keep it): add one or more, and the total
DashDeathsAll(add := 0)
	{
	static total := ""
	if (total = "")
		{
		IniRead, total, %A_ScriptDir%\dashboard.ini, stats, deaths, 0
		total := RegExMatch(total, "^\d+$") ? total + 0 : 0
		}
	if (add)
		{
		total += add
		IniWrite, %total%, %A_ScriptDir%\dashboard.ini, stats, deaths
		}
	return total
	}

DashNum(v)
	{
	return Format("{:6}", v = "" ? 0 : v)
	}

;Sets a control's text only when it changed (no flicker)
DashSet(control, text)
	{
	static last := {}
	if (last[control] == text)
		return
	last[control] := text
	GuiControl, Dash:, %control%, %text%
	}

;---- The map ----
;
;A window with a top-down picture of the zone the wizard is in, drawn by the vision helper (/navmap: the
;floor, what's in the way, the game's path, the wizard as an arrow, where the arrow points, the goal), and
;under it a line off /nav: the zone, where the wizard is, how far the goal is. Read from the game's memory by
;the helper (read-only). A new picture once a second while it's shown; closing it only hides it (and stops
;asking). Its requests don't wait for the answer - the next tick (every 250 ms) picks it up - so the bot never
;waits for the map. It never takes the focus by itself. Its place is kept in dashboard.ini [map].

;The Map button / tray menu: shows or hides it
DashMapToggle()
	{
	if (DashMapShown)
		DashMapHide()
	else
		DashMapShow()
	IniWrite, % DashMapShown ? 1 : 0, %A_ScriptDir%\dashboard.ini, map, shown
	}

;Makes the window (hidden), the first time it's shown
DashMapMake()
	{
	DashMapShown := 0, DashMapReq := "", DashMapKind := "", DashMapAt := 0, DashMapW := 0, DashMapH := 0
	DashMapNote := "", DashMapNav := "", DashMapPicAt := ""
	;(in the temp folder: it's rewritten every second, which OneDrive would keep uploading)
	DashMapFile := A_Temp "\Wizard101 bot map\navmap.png"
	FileCreateDir, %A_Temp%\Wizard101 bot map
	FileCreateDir, %A_ScriptDir%\generated
	Gui, Map:+Resize +MinSize320x240 +HwndDashMapHwnd
	Gui, Map:Color, 1B1D22, 111317
	Gui, Map:Margin, 8, 8
	Gui, Map:Add, Picture, x8 y8 w624 h460 vDashMapPic HwndDashMapPicH
	Gui, Map:Font, s9 w400 cDADADA, Consolas
	;(one line: cut with "..." when it's longer than the window is wide, not wrapped)
	Gui, Map:Add, Text, x8 y474 w624 h18 +0x400C vDashMapText, Asking the vision helper for the map...
	}

;Shows it where it was (else beside the dashboard), without taking the focus, and starts asking
DashMapShow()
	{
	if (!DashMapHwnd)
		DashMapMake()
	IniRead, x, %A_ScriptDir%\dashboard.ini, map, x, %A_Space%
	IniRead, y, %A_ScriptDir%\dashboard.ini, map, y, %A_Space%
	IniRead, w, %A_ScriptDir%\dashboard.ini, map, w, 640
	IniRead, h, %A_ScriptDir%\dashboard.ini, map, h, 500
	if (x = "" || y = "" || !DashOnScreen(x + 40, y + 20))
		DashMapPlace(x, y, w, h)
	DashFitHeight(x, y, h)
	Gui, Map:Show, x%x% y%y% w%w% h%h% NoActivate, % "Wizard101 bot " BotVersion() " - map"
	DashMapShown := 1, DashMapAt := 0
	SetTimer, DashMapTick, 250
	}

;Hides it (keeping its place) and stops asking
DashMapHide()
	{
	if (!DashMapHwnd)
		return
	if (DashMapShown)
		DashSaveWin(DashMapHwnd, "map")
	Gui, Map:Hide
	DashMapShown := 0
	SetTimer, DashMapTick, Off
	if (IsObject(DashMapReq))
		try DashMapReq.Abort()
	DashMapReq := ""
	}

;Where it goes the first time (w, h: its inside at 100% display scaling): beside the dashboard - right of it,
;below, left or above, whichever fits on the dashboard's monitor - else that monitor's bottom right (the
;spare monitor's, when the dashboard is hidden)
DashMapPlace(ByRef x, ByRef y, w, h)
	{
	dpi := A_ScreenDPI / 96
	ow := Round(w * dpi) + 16, oh := Round(h * dpi) + 40
	if (DashShown && DashHwnd)
		{
		WinGetPos, dx, dy, dw, dh, ahk_id %DashHwnd%
		DashMonitorAt(dx + dw // 2, dy + dh // 2, mLeft, mTop, mRight, mBottom)
		for each, p in [[dx + dw + 8, dy], [dx, dy + dh + 8], [dx - ow - 8, dy], [dx, dy - oh - 8]]
			if (p[1] >= mLeft && p[2] >= mTop && p[1] + ow <= mRight && p[2] + oh <= mBottom)
				{
				x := p[1], y := p[2]
				return
				}
		}
	else
		DashSpareMonitor(mLeft, mTop, mRight, mBottom)
	x := Max(mLeft, mRight - ow - 20), y := Max(mTop, mBottom - oh - 20)
	}

;Every 250 ms while it's shown: picks up the answer it's waiting for; else asks for a new picture once a
;second (at once when the window's size changed)
DashMapTick()
	{
	if (!DashMapShown)
		{
		SetTimer, DashMapTick, Off
		return
		}
	if (IsObject(DashMapReq))
		return DashMapCheck()
	;(minimized: nothing to draw)
	if (DllCall("IsIconic", "Ptr", DashMapHwnd))
		return
	;(the picture is asked for at the size it's shown at, in screen pixels: shown as it is, not stretched)
	VarSetCapacity(rc, 16, 0)
	DllCall("GetClientRect", "Ptr", DashMapPicH, "Ptr", &rc)
	pw := NumGet(rc, 8, "Int"), ph := NumGet(rc, 12, "Int")
	if (pw < 16 || ph < 16)
		{
		;(a picture that didn't load shrinks the control to nothing: back to the window's size)
		DashMapFit()
		return
		}
	if (A_TickCount - DashMapAt < 1000 && pw = DashMapW && ph = DashMapH)
		return
	DashMapAt := A_TickCount, DashMapW := pw, DashMapH := ph
	DashMapAsk("map", "/navmap?w=" pw "&h=" ph "&out=" DashMapUri(DashMapFile))
	}

;Sends a request to the vision helper without waiting for the answer (DashMapCheck picks it up). Not
;VisionGet: that waits, and its failures count towards turning the card vision off - the map's mustn't
DashMapAsk(kind, path)
	{
	DashMapReq := "", DashMapKind := kind, DashMapReqAt := A_TickCount
	try
		{
		req := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", "http://127.0.0.1:" (VisionPort ? VisionPort : 47128) path, true)
		req.Send()
		DashMapReq := req
		}
	catch
		DashMapGot(kind, "", false)
	}

;The answer to the request sent, once it's there (after 4 s it's given up)
DashMapCheck()
	{
	req := DashMapReq, done := 0
	try
		done := req.WaitForResponse(0)
	catch
		{
		;(nothing answering on the port: the helper isn't running)
		DashMapReq := ""
		return DashMapGot(DashMapKind, "", false)
		}
	if (!done)
		{
		if (A_TickCount - DashMapReqAt > 4000)
			{
			try req.Abort()
			DashMapReq := ""
			DashMapGot(DashMapKind, "ERR the vision helper didn't answer in 4 s", false)
			}
		return
		}
	DashMapReq := "", text := "", status := 0
	try
		text := req.ResponseText, status := req.Status
	text := Trim(text, " `t`r`n")
	if (status != 200 && InStr(text, "ERR") != 1)
		text := "ERR the vision helper answered " status
	DashMapGot(DashMapKind, text, true)
	}

;An answer ("" = the helper couldn't be asked; answered: it did answer): the picture, then the line under it
DashMapGot(kind, text, answered)
	{
	if (kind = "map")
		{
		f := SubStr(text, 4)
		if (InStr(text, "ok|") != 1)
			DashMapNote := "Map: " DashMapWhy(text)
		else if (!FileExist(f) && !FileExist(f := DashMapFile))
			DashMapNote := "Map: the picture isn't there (" f ")"
		else
			{
			;(no *w *h: fitted to the control - the size it was asked for)
			GuiControl, Map:, DashMapPic, %f%
			DashMapPicAt := A_Hour ":" A_Min ":" A_Sec, DashMapNote := ""
			}
		if (DashMapNote != "" && DashMapPicAt != "")
			DashMapNote .= " (picture from " DashMapPicAt ")"
		;(then /nav for the line under it, if the helper is there to ask)
		if (answered)
			DashMapAsk("nav", "/nav")
		else
			DashMapNav := ""
		}
	else
		DashMapNav := text
	DashMapLine()
	}

;Why a request got no picture / no position ("ERR <why>", or "" when the helper couldn't be asked)
DashMapWhy(text)
	{
	if (text = "")
		return VisionOn ? "no answer from the vision helper (see vision\vision.log)" : "the vision helper isn't running (debug.log says why)"
	return InStr(text, "ERR") = 1 ? Trim(SubStr(text, 4)) : "an odd answer: " SubStr(text, 1, 60)
	}

;The line under the picture: what went wrong with the picture (if anything), then the zone, the place, the goal
DashMapLine()
	{
	static last := ""
	nav := DashMapNav
	if (InStr(nav, "ERR") = 1)
		{
		why := DashMapWhy(nav)
		;(the same reason as the picture's: once is enough)
		nav := InStr(DashMapNote, why) ? "" : "Can't read the game: " why
		}
	else
		nav := DashMapNavLine(nav)
	line := DashMapNote (DashMapNote != "" && nav != "" ? " | " : "") nav
	if (line == last)
		return
	last := line
	GuiControl, Map:, DashMapText, % line
	}

;/nav's answer as "zone | at x, y, z | goal in this zone | arrow 1520" (? for what it couldn't read; arrow = how
;far the on-screen arrow's point is, along the game's path)
DashMapNavLine(answer)
	{
	if (answer = "")
		return ""
	f := {}
	Loop, Parse, answer, `n, `r
		{
		p := StrSplit(A_LoopField, "|")
		f[p[1]] := p
		}
	if (!IsObject(f.ok))
		return "an odd /nav answer: " SubStr(answer, 1, 60)
	zone := IsObject(f.zone) && f.zone[2] != "" ? f.zone[2] : "zone ?"
	pos := IsObject(f.pos) ? "at " DashMapNum(f.pos[2]) ", " DashMapNum(f.pos[3]) ", " DashMapNum(f.pos[4]) : "at ?"
	hops := IsObject(f.goal) ? f.goal[5] : ""
	goal := hops = "" ? "goal ?" : hops = 0 ? "goal in this zone" : "goal " hops " zone" (hops = 1 ? "" : "s") " away"
	if (IsObject(f.quest) && f.quest[2] = "0")
		goal := "no quest goal (the quest helper is off)"
	arrow := IsObject(f.dist) && f.dist[2] != "" ? " | arrow " DashMapNum(f.dist[2]) : ""
	return zone " | " pos " | " goal arrow
	}

DashMapNum(v)
	{
	return v = "" ? "?" : Round(v)
	}

;Fits the picture and the line to the window (gw, gh: its inside at 100% display scaling, as GuiSize gives
;them; blank: the window's now)
DashMapFit(gw := "", gh := "")
	{
	if (gw = "")
		{
		VarSetCapacity(rc, 16, 0)
		DllCall("GetClientRect", "Ptr", DashMapHwnd, "Ptr", &rc)
		gw := Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), gh := Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI)
		}
	GuiControl, Map:Move, DashMapPic, % "w" Max(16, gw - 16) " h" Max(16, gh - 40)
	GuiControl, Map:Move, DashMapText, % "y" gh - 26 " w" Max(16, gw - 16)
	}

;Text for a URL: UTF-8, everything but letters, digits and - . _ ~ %-escaped
DashMapUri(s)
	{
	VarSetCapacity(buf, StrPut(s, "UTF-8"), 0)
	n := StrPut(s, &buf, "UTF-8") - 1
	out := ""
	Loop, %n%
		{
		c := NumGet(buf, A_Index - 1, "UChar")
		out .= (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c = 45 || c = 46 || c = 95 || c = 126) ? Chr(c) : "%" Format("{:02X}", c)
		}
	return out
	}

DashMapButton:
	DashMapToggle()
	return

DashMapTick:
	DashMapTick()
	return

MapGuiClose:
	DashMapToggle()
	return

MapGuiSize:
	if (A_EventInfo != 1)
		DashMapFit(A_GuiWidth, A_GuiHeight)
	return

;---- The dashboard's buttons ----

DashRefresh:
	DashRefresh()
	return

DashPauseLog:
	DashPaused := !DashPaused
	GuiControl, Dash:, DashPauseBtn, % DashPaused ? "Resume log" : "Pause log"
	if (!DashPaused && DashHeld != "")
		DashAppend(DashHeld), DashHeld := ""
	return

DashClearLog:
	GuiControl, Dash:, DashConsole,
	return

;The Network tab: a bot picked (its log and picture fetched now), and the buttons for it
DashNetListEvent:
	if (A_GuiEvent = "I" && InStr(ErrorLevel, "S"))
		{
		Gui, Dash:ListView, NetList
		LV_GetText(DashNetId, A_EventInfo, 12)
		if (DashNetId != NetSel)
			{
			;(kept by its PC: a bot started again has a new id)
			NetSelPc := ""
			if (DashNetId != "")
				LV_GetText(NetSelPc, A_EventInfo, 1)
			NetSel := DashNetId, NetLogAt := 0, NetSnapAt := "", NetRefresh := 1
			GuiControl, Dash:, NetLog,
			GuiControl, Dash:Hide, NetPic
			GuiControl, Dash:, NetPicNote, % NetSel = "" ? "This PC - its log is the Bot tab's." : "Fetching its log and game..."
			}
		}
	return

DashNetOn:
DashNetOff:
DashNetPfm:
DashNetRestart:
	DashNetCmd := {DashNetOn: "on", DashNetOff: "off", DashNetPfm: "pfmoff", DashNetRestart: "restart"}[A_ThisLabel]
	DashSet("NetStatus", "Network: " NetSend(DashNetCmd))
	NetLogAt := A_TickCount - 4000
	return

DashNetRefresh:
	NetRefresh := 1
	return

;The log's Colours button, and its window's buttons: a kind's colour changed (kept in dashboard.ini [logcolors]), all
;back to the defaults, the window closed - the log coloured afresh each time
DashLogColorsBtn:
	DashLogColorsWindow()
	return

DashLogColorPick:
	lcI := RegExReplace(A_GuiControl, "\D")
	lcKinds := DashLogKinds(), lcK := lcKinds[lcI], lcCols := DashLogColors()
	lcNew := DashPickColour(lcCols[lcK[1]], LogColHwnd)
	if (lcNew != "")
		{
		IniWrite, %lcNew%, %A_ScriptDir%\dashboard.ini, logcolors, % lcK[1]
		DashLogColors(true)
		GuiControl, LogCol:+Background%lcNew%, LogColSw%lcI%
		DashLogRecolour()
		}
	return

DashLogColorReset:
	IniDelete, %A_ScriptDir%\dashboard.ini, logcolors
	lcCols := DashLogColors(true), lcKinds := DashLogKinds()
	for lcI, lcK in lcKinds
		{
		lcCol := lcCols[lcK[1]]
		GuiControl, LogCol:+Background%lcCol%, LogColSw%lcI%
		}
	DashLogRecolour()
	return

DashLogColorClose:
LogColGuiClose:
LogColGuiEscape:
	Gui, LogCol:Destroy
	return

DashOpenLog:
	Run, notepad.exe "%A_ScriptDir%\debug.log"
	return

DashWalkToggle:
	if (IsFunc("WalkToggle"))
		Func("WalkToggle").Call()
	return

DashFolder:
	Run, %A_ScriptDir%
	return

;CPU and RAM in use, for the STATISTICS row: the bot (this script and its vision helper), the game, the whole PC.
;CPU from the time each has used since the last look (all cores = 100%), RAM its working set (what Task Manager
;shows, about). Read-only process queries - nothing is changed
DashUsage()
	{
	static last := {}, procs := {}
	EnvGet, cores, NUMBER_OF_PROCESSORS
	cores := cores > 0 ? cores : 1
	now := A_TickCount
	gamePid := 0
	WinGet, gamePid, PID, ahk_class %GameClass% ahk_exe %GameExe%
	who := {bot: [DllCall("GetCurrentProcessId"), VisionPid], game: [gamePid]}
	out := {}
	for name, pids in who
		{
		cpu := 0, ram := 0, seen := 0
		for each, pid in pids
			{
			if (!pid)
				continue
			if (!procs.HasKey(pid))
				procs[pid] := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
			h := procs[pid]
			if (!h)
				continue
			VarSetCapacity(ft, 32, 0)
			if (!DllCall("GetProcessTimes", "Ptr", h, "Ptr", &ft, "Ptr", &ft + 8, "Ptr", &ft + 16, "Ptr", &ft + 24))
				{
				DllCall("CloseHandle", "Ptr", h), procs.Delete(pid)
				continue
				}
			used := NumGet(ft, 16, "Int64") + NumGet(ft, 24, "Int64")
			if (last.HasKey(pid) && now > last[pid].at)
				cpu += (used - last[pid].used) / 10000 / (now - last[pid].at) / cores * 100
			last[pid] := {used: used, at: now}
			cb := 8 + 8 * A_PtrSize
			VarSetCapacity(pmc, cb, 0), NumPut(cb, pmc, 0, "UInt")
			if (DllCall("K32GetProcessMemoryInfo", "Ptr", h, "Ptr", &pmc, "UInt", cb))
				ram += NumGet(pmc, 8 + A_PtrSize, "UPtr")
			seen += 1
			}
		out[name] := seen ? DashUsageNum(cpu) "%" Chr(183) DashBytes(ram) : "-"
		}
	;the whole PC: busy share of all cores since the last look, and RAM in use
	VarSetCapacity(st, 24, 0)
	pcCpu := "?"
	if (DllCall("GetSystemTimes", "Ptr", &st, "Ptr", &st + 8, "Ptr", &st + 16))
		{
		idle := NumGet(st, 0, "Int64"), total := NumGet(st, 8, "Int64") + NumGet(st, 16, "Int64")
		if (last.HasKey("pc") && total > last.pc.total)
			pcCpu := DashUsageNum(100 * (1 - (idle - last.pc.idle) / (total - last.pc.total)))
		last.pc := {idle: idle, total: total}
		}
	VarSetCapacity(ms, 64, 0), NumPut(64, ms, 0, "UInt")
	pcRam := DllCall("GlobalMemoryStatusEx", "Ptr", &ms) ? NumGet(ms, 4, "UInt") "%" : "?"
	return "CPU" Chr(183) "RAM   bot " out.bot "   game " out.game "   PC " pcCpu "%" Chr(183) pcRam
	}

DashUsageNum(v)
	{
	return v < 0 ? 0 : v < 10 ? Round(v, 1) : Round(v)
	}

DashBytes(n)
	{
	return n >= 1073741824 ? Round(n / 1073741824, 1) "GB" : Round(n / 1048576) "MB"
	}

DashUpdButton:
	;The Updates button: the usual check - a newer version offered (its notes), installed if you say so, the bot then
	;started again as it is now - or "you're up to date" (UpdCheckNow, as the tray menu's Check for updates).
	;"Checking..." and not clickable for 10 s
	if (UpdCheckNow())
		{
		DashUpdBusy := A_TickCount
		GuiControl, Dash:Disable, DashUpdBtn
		DashRefresh()
		}
	return

;Report a bug (BugReport.ahk): what went wrong, posted as an issue on GitHub
DashBugButton:
	if (IsFunc("BugShow"))
		Func("BugShow").Call()
	return

;The Settings window (Settings.ahk): the mouse, the waits, how it plays its cards
DashSettingsButton:
	if (IsFunc("CfgShow"))
		Func("CfgShow").Call()
	return

;"Learn every card" on/off (CardLearn.ahk)
DashLearnAll:
	if (IsFunc("LearnAllToggle"))
		Func("LearnAllToggle").Call()
	return

;The bot on/off (BotToggle in Autofarmer.ahk)
DashBotToggle:
	if (IsFunc("BotToggle"))
		Func("BotToggle").Call()
	return

;Simple / advanced view (dashboard.ini [view] dashboard): each view keeps its own place and size
DashViewToggle:
	DashSavePlace()
	DashSimple := !DashSimple
	IniWrite, % DashSimple ? 1 : 0, %A_ScriptDir%\dashboard.ini, view, dashboard
	DashApplyView()
	DashShow()
	return

;"Bring Wizard101 to the front" on/off (GameFrontToggle in Autofarmer.ahk)
DashFrontToggle:
	if (IsFunc("GameFrontToggle"))
		Func("GameFrontToggle").Call()
	return

;"Play for me" on/off (PlayForMeToggle in Autofarmer.ahk)
DashPlayToggle:
	if (IsFunc("PlayForMeToggle"))
		Func("PlayForMeToggle").Call()
	return

;"Wait while I play" on/off (HandsOffToggle in Autofarmer.ahk)
DashHandsToggle:
	if (IsFunc("HandsOffToggle"))
		Func("HandsOffToggle").Call()
	return

;(the window's X stops the bot - minimise it, or Windows+2, to just put it away)
DashGuiClose:
	DebugLog("Dashboard closed - the bot stops")
	ExitApp
	return

DashGuiSize:
	if (A_EventInfo = 1)
		return
	;(GuiControl Move places a tab's controls from the tabs' inside, not the window's: where that starts, measured
	;once the window's up - a control moved to 0,0 there and where it lands read)
	if (DashTabOX = "")
		{
		GuiControl, Dash:Move, DashPauseBtn, x0 y0
		GuiControlGet, DashTabO, Dash:Pos, DashPauseBtn
		}
	GuiControl, Dash:Move, DashHead, % "w" A_GuiWidth - 258
	GuiControl, Dash:Move, DashPlayBg, % "x" A_GuiWidth - 116
	GuiControl, Dash:Move, DashPlayBtn, % "x" A_GuiWidth - 116
	GuiControl, Dash:Move, DashBugBtn, % "x" A_GuiWidth - 240
	GuiControl, Dash:Move, DashUpdBtn, % "x" A_GuiWidth - 144
	GuiControl, Dash:Move, DashMapBtn, % "x" A_GuiWidth - 84 - DashTabOX
	GuiControl, Dash:Move, DashCfgBtn, % "x" A_GuiWidth - 166 - DashTabOX
	GuiControl, Dash:Move, DashSeeText, % "w" A_GuiWidth - 384
	GuiControl, Dash:Move, DashConsole, % "w" A_GuiWidth - 24 " h" Max(40, A_GuiHeight - 352)
	GuiControl, Dash:Move, DashColBtn, % "x" A_GuiWidth - 90 - DashTabOX
	;(the Cards tab: the Learn button at the right end of the hand's row, its heading up to it; the enemies' list takes
	;what's left)
	GuiControl, Dash:Move, DashLearnBtn, % "x" A_GuiWidth - 138 - DashTabOX
	GuiControl, Dash:Move, DashHandHead, % "w" A_GuiWidth - 154
	GuiControl, Dash:Move, DashFoeHead, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, DashFoeList, % "w" A_GuiWidth - 24 " h" Max(40, A_GuiHeight - 290)
	;(a deck's view: its settings list takes what's left, the value's row under it; the right end's buttons at the right
	;end - the window can be narrower than they were placed for)
	GuiControl, Dash:Move, DeckFDmg, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, DeckFList, % "w" A_GuiWidth - 24 " h" Max(60, A_GuiHeight - 330)
	DashDeckRowY := Max(236 + 60 + 6, A_GuiHeight - 88) - DashTabOY
	GuiControl, Dash:Move, DeckFValT, % "y" DashDeckRowY + 4
	GuiControl, Dash:Move, DeckFVal, % "y" DashDeckRowY + 1
	GuiControl, Dash:Move, DeckFValSet, % "y" DashDeckRowY
	GuiControl, Dash:Move, DeckFValClear, % "y" DashDeckRowY
	GuiControl, Dash:Move, DeckFNote, % "y" DashDeckRowY + 4 " w" Max(120, A_GuiWidth - 454)
	GuiControl, Dash:Move, DeckAddBtn, % "x" A_GuiWidth - 80 - DashTabOX
	GuiControl, Dash:Move, DeckFSave, % "x" A_GuiWidth - 304 - DashTabOX
	GuiControl, Dash:Move, DeckFCopy, % "x" A_GuiWidth - 208 - DashTabOX
	GuiControl, Dash:Move, DeckFDel, % "x" A_GuiWidth - 112 - DashTabOX
	GuiControl, Dash:Move, DeckFPriT, % "x" A_GuiWidth - 154 - DashTabOX
	GuiControl, Dash:Move, DeckFPri, % "x" A_GuiWidth - 104 - DashTabOX
	GuiControl, Dash:Move, DeckFSetN, % "w" Max(80, A_GuiWidth - 544)
	GuiControl, Dash:Move, DgDeck, % "w" Min(260, Max(100, A_GuiWidth - 594))
	;(the Network tab: the list across, the log under it on the left, the game's picture on the right)
	GuiControl, Dash:Move, NetHelp, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, NetStatus, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, NetList, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, NetLog, % "w" Max(200, A_GuiWidth - 404) " h" Max(40, A_GuiHeight - 360)
	GuiControl, Dash:Move, NetPic, % "x" A_GuiWidth - 384 - DashTabOX
	GuiControl, Dash:Move, NetPicNote, % "x" A_GuiWidth - 384 - DashTabOX
	;(the tabs fill the window under the heading; the Dungeons tab's list takes what's left)
	GuiControl, Dash:Move, DashTabs, % "w" A_GuiWidth - 12 " h" A_GuiHeight - 42
	GuiControl, Dash:Move, DgHelp, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, DgStatus, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, DgList, % "w" A_GuiWidth - 24 " h" A_GuiHeight - 274
	;(the Keys tab: its list takes what's left)
	GuiControl, Dash:Move, KeyHelp, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, KeyStatus, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, KeyList, % "w" A_GuiWidth - 24 " h" Max(60, A_GuiHeight - 202)
	;(the Spells tab: its list takes what's left of the picture on its right)
	GuiControl, Dash:Move, SpHelp, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, SpStatus, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, SpList, % "w" A_GuiWidth - 172 " h" A_GuiHeight - 202
	GuiControl, Dash:Move, SpPreview, % "x" A_GuiWidth - 152 - DashTabOX
	GuiControl, Dash:Move, SpPreviewTxt, % "x" A_GuiWidth - 152 - DashTabOX " h" Max(40, A_GuiHeight - 440)
	;(the bottom row shares the width, each button in proportion to the width it was made with, so all fit at any
	;size - 620 at the least; the simple view: without the log's three)
	;(a label runs in the global scope: Dash-named variables only)
	DashRowList := [["DashBotBtn", 100], ["DashWalkBtn", 140], ["DashFolderBtn", 120], ["DashHandsBtn", 120], ["DashFrontBtn", 130], ["DashViewBtn", 110]]
	if (!DashSimple)
		DashRowList.InsertAt(1, ["DashPauseBtn", 100], ["DashClearBtn", 70], ["DashLogBtn", 110])
	DashRowSum := 0
	for DashRowI, DashRowB in DashRowList
		DashRowSum += DashRowB[2]
	DashRowX := 12, DashRowRoom := A_GuiWidth - 24 - 6 * (DashRowList.Length() - 1)
	for DashRowI, DashRowB in DashRowList
		{
		DashRowW := Floor(DashRowRoom * DashRowB[2] / DashRowSum)
		GuiControl, Dash:Move, % DashRowB[1], % "x" DashRowX - DashTabOX " y" A_GuiHeight - 36 - DashTabOY " w" DashRowW
		DashRowX += DashRowW + 6
		}
	return

;(Windows+2 is in Autofarmer.ahk: it shows the dev-mode info box in dev mode)
