#Warn Unreachable, Off
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
	Dash := Gui("+Resize +MinSize740x640", "Wizard101 bot " BotVersion()), DashHwnd := Dash.Hwnd
	Dash.OnEvent("Close", DashGuiClose)
	Dash.OnEvent("Size", DashGuiSize)
	Dash.BackColor := "1B1D22"
	Dash.MarginX := 12, Dash.MarginY := 10
	Dash.SetFont("s11 w600 cF2F2F2", "Segoe UI")
	ogcTextDashHead := Dash.Add("Text", "x12 y10 w526 h22 vDashHead", BotVersion())
	;(the Updates button: the heading row's right end - DashGuiSize keeps it there)
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonDashBugBtn := Dash.Add("Button", "x544 y7 w88 h24 vDashBugBtn", "Report a bug")
	ogcButtonDashBugBtn.OnEvent("Click", DashBugButton.Bind("Normal"))
	ogcButtonDashUpdBtn := Dash.Add("Button", "x640 y7 w136 h24 vDashUpdBtn", "Check for updates")
	ogcButtonDashUpdBtn.OnEvent("Click", DashUpdButton.Bind("Normal"))
	;(the button says "Checking..." a while after a click: DashUpdBusy)
	;Four tabs: Bot (statistics, what it sees, the log), Dungeons (Dungeons.ahk), Spells (the cards the bot learned by
	;itself: Spells.ahk) and Cards (your hand, the enemies' spells)
	Dash.SetFont("s9 w600 cF2F2F2", "Segoe UI")
	Tab := ogcTab3DashTabs := Dash.Add("Tab3", "x6 y36 w772 h764 +Buttons -Theme vDashTabs", ["Bot", "Dungeons", "Spells", "Cards", "Network", "Keys"])
	Tab.UseTab(1)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w86 h16", "STATISTICS")
	Dash.SetFont("s8 w400 c9AA0A6", "Segoe UI")
	ogcDashUsageText := Dash.Add("Text", "x100 y69 w270 h16 vDashUsageText", "CPU / RAM ...")
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x372 y68 w150 h16", "WHAT IT SEES")
	;(the Map button at the right end of that row; DashGuiSize keeps it there)
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonDashCfgBtn := Dash.Add("Button", "x618 y64 w76 h22 vDashCfgBtn", "Settings")
	ogcButtonDashCfgBtn.OnEvent("Click", DashSettingsButton.Bind("Normal"))
	ogcButtonDashMapBtn := Dash.Add("Button", "x700 y64 w76 h22 vDashMapBtn", "Map")
	ogcButtonDashMapBtn.OnEvent("Click", DashMapButton.Bind("Normal"))
	Dash.SetFont("s9 w400 cDADADA", "Consolas")
	ogcDashStatText := Dash.Add("Text", "x12 y88 w350 h190 vDashStatText")
	ogcDashSeeText := Dash.Add("Text", "x372 y88 w400 h196 vDashSeeText")
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	ogcTextDashLogHead := Dash.Add("Text", "x12 y286 w200 h16 vDashLogHead", "LOG")
	;(each kind of line in its colour - movement, battle, waits... - set with the small Colours button: a rich edit, as
	;an Edit can't colour its lines; read-only, no wrap)
	Dash.SetFont("s8 w400 c000000", "Segoe UI")
	ogcButtonDashColBtn := Dash.Add("Button", "x694 y283 w78 h20 vDashColBtn", "Colours")
	ogcButtonDashColBtn.OnEvent("Click", DashLogColorsBtn.Bind("Normal"))
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	DllCall("LoadLibrary", "Str", "Msftedit.dll", "Ptr")
	ogcCustomDashConsole := Dash.Add("Custom", "ClassRICHEDIT50W x12 y306 w760 h452 +0x200000 +0x100000 +0x4 +0x800 +0x100 +0x40 +0x80 vDashConsole"), DashCon := ogcCustomDashConsole.hwnd
	DashLogInit()
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonDashPauseBtn := Dash.Add("Button", "x12 y768 w110 h26 vDashPauseBtn", "Pause log")
	ogcButtonDashPauseBtn.OnEvent("Click", DashPauseLog.Bind("Normal"))
	ogcButtonDashClearBtn := Dash.Add("Button", "x130 y768 w80 h26 vDashClearBtn", "Clear")
	ogcButtonDashClearBtn.OnEvent("Click", DashClearLog.Bind("Normal"))
	ogcButtonDashLogBtn := Dash.Add("Button", "x218 y768 w120 h26 vDashLogBtn", "Open debug.log")
	ogcButtonDashLogBtn.OnEvent("Click", DashOpenLog.Bind("Normal"))
	ogcButtonDashBotBtn := Dash.Add("Button", "x346 y768 w120 h26 vDashBotBtn", "Bot: on (" HkText("bot") ")")
	ogcButtonDashBotBtn.OnEvent("Click", DashBotToggle.Bind("Normal"))
	ogcButtonDashWalkBtn := Dash.Add("Button", "x346 y768 w150 h26 vDashWalkBtn", "Walking on/off (" HkText("walk") ")")
	ogcButtonDashWalkBtn.OnEvent("Click", DashWalkToggle.Bind("Normal"))
	ogcButtonDashFolderBtn := Dash.Add("Button", "x504 y768 w140 h26 vDashFolderBtn", "Open bot folder")
	ogcButtonDashFolderBtn.OnEvent("Click", DashFolder.Bind("Normal"))
	ogcButtonDashHandsBtn := Dash.Add("Button", "x652 y768 w124 h26 vDashHandsBtn", "Wait for me: on")
	ogcButtonDashHandsBtn.OnEvent("Click", DashHandsToggle.Bind("Normal"))
	ogcButtonDashFrontBtn := Dash.Add("Button", "x652 y768 w124 h26 vDashFrontBtn", "Game to front: off")
	ogcButtonDashFrontBtn.OnEvent("Click", DashFrontToggle.Bind("Normal"))
	ogcButtonDashViewBtn := Dash.Add("Button", "x652 y768 w110 h26 vDashViewBtn", "Advanced view")
	ogcButtonDashViewBtn.OnEvent("Click", DashViewToggle.Bind("Normal"))
	;The Dungeons tab: a run recorded once, walked again and again (Dungeons.ahk)
	Tab.UseTab(2)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w400 h16", "DUNGEON FARMING")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	ogcTextDgHelp := Dash.Add("Text", "x12 y88 w760 h48 vDgHelp", DashDgHelpText())
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonDgRecBtn := Dash.Add("Button", "x12 y142 w120 h26 vDgRecBtn", "Record a run")
	ogcButtonDgRecStopBtn := Dash.Add("Button", "x138 y142 w150 h26 vDgRecStopBtn Disabled", "Stop recording (" HkText("record") ")")
	ogcButtonDgRunBtn := Dash.Add("Button", "x300 y142 w90 h26 vDgRunBtn", "Run")
	ogcButtonDgStopBtn := Dash.Add("Button", "x396 y142 w90 h26 vDgStopBtn Disabled", "Stop run")
	ogcButtonDgDelBtn := Dash.Add("Button", "x498 y142 w90 h26 vDgDelBtn", "Delete")
	ogcButtonDgFolderBtn := Dash.Add("Button", "x594 y142 w110 h26 vDgFolderBtn", "Open folder")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcTextDgTimesLabel := Dash.Add("Text", "x12 y182 w44 h18 vDgTimesLabel", "Run it")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	ogcEditDgTimes := Dash.Add("Edit", "x58 y179 w60 h22 Number Right vDgTimes", "0")
	ogcUpDownDgTimesUD := Dash.Add("UpDown", "vDgTimesUD Range0-9999 0x80", "0")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcTextDgTimesNote := Dash.Add("Text", "x126 y182 w220 h18 vDgTimesNote", "times (0 = until you stop it)")
	ogcCheckboxDgAvoid := Dash.Add("Checkbox", "x352 y182 w186 h18 vDgAvoid", "Keep away from mobs on the way")
	;(the deck a run's fought with - kept in its file: Decks.ahk)
	ogcTextDgDeckT := Dash.Add("Text", "x542 y182 w36 h18 vDgDeckT", "Deck")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcDropDownListDgDeck := Dash.Add("DropDownList", "x580 y179 w190 AltSubmit vDgDeck", ["(none)"])
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	ogcTextDgStatus := Dash.Add("Text", "x12 y208 w760 h52 vDgStatus", "Not running.")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcDgList := Dash.Add("ListView", "x12 y262 w760 h526 vDgList AltSubmit -Multi Background111317 cDADADA", ["Run", "Steps", "Zones", "X", "Battles", "Recorded", "File"])
	ogcDgList.ModifyCol(1, 300), ogcDgList.ModifyCol(2, "60 Integer"), ogcDgList.ModifyCol(3, "60 Integer"), ogcDgList.ModifyCol(4, "50 Integer"), ogcDgList.ModifyCol(5, "70 Integer")
	ogcDgList.ModifyCol(6, 140), ogcDgList.ModifyCol(7, 0)
	;The Spells tab: the cards the bot learned by itself, and your corrections (Spells.ahk)
	Tab.UseTab(3)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w400 h16", "LEARNED SPELLS")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	ogcTextSpHelp := Dash.Add("Text", "x12 y88 w760 h32 vSpHelp", "Every card the bot learned by itself, and what it took it for. Pick one to see it. Change kind or Edit puts one right (applied out of battle; the learner never changes what you set). Forget: out of the list.")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonSpKindBtn := Dash.Add("Button", "x12 y124 w100 h26 vSpKindBtn", "Change kind...")
	ogcButtonSpEditBtn := Dash.Add("Button", "x118 y124 w64 h26 vSpEditBtn", "Edit...")
	ogcButtonSpForgetBtn := Dash.Add("Button", "x188 y124 w64 h26 vSpForgetBtn", "Forget")
	ogcButtonSpHoldBtn := Dash.Add("Button", "x258 y124 w96 h26 vSpHoldBtn", "Never discard")
	ogcButtonSpPicBtn := Dash.Add("Button", "x360 y124 w92 h26 vSpPicBtn", "Show picture")
	ogcButtonSpFolderBtn := Dash.Add("Button", "x458 y124 w86 h26 vSpFolderBtn", "Open folder")
	ogcButtonSpMovedBtn := Dash.Add("Button", "x550 y124 w100 h26 vSpMovedBtn", "Moved away...")
	ogcButtonSpRefreshBtn := Dash.Add("Button", "x656 y124 w66 h26 vSpRefreshBtn", "Refresh")
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	ogcTextSpStatus := Dash.Add("Text", "x12 y156 w760 h30 vSpStatus")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcSpList := Dash.Add("ListView", "x12 y190 w612 h598 vSpList AltSubmit Background111317 cDADADA", ["Name", "Kind", "School", "Pips", "Value", "Sure", "In use", "Text read", "TC", "Learned", "Set", "Id"])
	ogcSpList.ModifyCol(1, 96), ogcSpList.ModifyCol(2, 84), ogcSpList.ModifyCol(3, 50), ogcSpList.ModifyCol(4, 34), ogcSpList.ModifyCol(5, 66), ogcSpList.ModifyCol(6, "44 Integer")
	ogcSpList.ModifyCol(7, 112), ogcSpList.ModifyCol(8, 100), ogcSpList.ModifyCol(9, 26), ogcSpList.ModifyCol(10, 96), ogcSpList.ModifyCol(11, 50), ogcSpList.ModifyCol(12, 0)
	;(the spell picked: its picture, and what the bot took it for under it)
	ogcPictureSpPreview := Dash.Add("Picture", "x632 y190 w140 h233 Hidden vSpPreview")
	Dash.SetFont("s8 w400 cDADADA", "Segoe UI")
	ogcTextSpPreviewTxt := Dash.Add("Text", "x632 y428 w140 h360 vSpPreviewTxt", "Pick a spell to see it.")
	;The Cards tab: your hand - each card as the bot saw it this round, and what it took it for (DashHandSeen) - and the
	;enemies' spells: what each is likely to cast this round (EnemySpells.ahk EnemyDanger: DashFoesSeen)
	Tab.UseTab(4)
	;(its row of views: your hand and the enemies, or one of your decks - Decks.ahk; push-like radio buttons: tabs inside a
	;tab can't be)
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcRadioDeckView0 := Dash.Add("Radio", "x12 y62 w110 h24 +0x1000 Group Checked vDeckView0", "Hand && enemies")
	Loop 6
		{
		dx := 126 + (A_Index - 1) * 96
		ogcRadioDeckViewA_Index := Dash.Add("Radio", "x" . dx . " y62 w92 h24 +0x1000 Hidden vDeckView" . A_Index, "Deck " . A_Index)
		}
	ogcButtonDeckAddBtn := Dash.Add("Button", "x704 y62 w72 h24 vDeckAddBtn", "+ Deck")
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	ogcTextDashHandHead := Dash.Add("Text", "x12 y100 w630 h16 vDashHandHead", "YOUR HAND - nothing read yet (once a round in battle)")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonDashLearnBtn := Dash.Add("Button", "x646 y94 w130 h24 vDashLearnBtn", "Learn every card")
	ogcButtonDashLearnBtn.OnEvent("Click", DashLearnAll.Bind("Normal"))
	Dash.SetFont("s8 w400 cDADADA", "Segoe UI")
	Loop 7
		{
		cx := 12 + (A_Index - 1) * 72
		ogcPictureDashCardPicA_Index := Dash.Add("Picture", "x" . cx . " y122 w58 h97 Hidden vDashCardPic" . A_Index)
		ogcTextDashCardTxtA_Index := Dash.Add("Text", "x" . cx . " y221 w66 h28 Hidden vDashCardTxt" . A_Index)
		}
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	ogcTextDashFoeHead := Dash.Add("Text", "x12 y258 w760 h16 vDashFoeHead", "ENEMIES - nothing yet (each battle round, with Settings > Predict the enemies' spells on)")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcDashFoeList := Dash.Add("ListView", "x12 y278 w760 h514 vDashFoeList NoSort -Multi Background111317 cDADADA", ["Enemy", "Spell", "This round", "Pips, what it does", "This battle", "Seen (all battles)"])
	ogcDashFoeList.ModifyCol(1, 130), ogcDashFoeList.ModifyCol(2, 170), ogcDashFoeList.ModifyCol(3, 76), ogcDashFoeList.ModifyCol(4, 186), ogcDashFoeList.ModifyCol(5, 84), ogcDashFoeList.ModifyCol(6, 96)
	;(a deck's view: what it is, what it's for, its damage, and the settings it has of its own - hidden till one's picked)
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcTextDeckFNameT := Dash.Add("Text", "x12 y101 w44 h18 Hidden vDeckFNameT", "Name")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	ogcEditDeckFName := Dash.Add("Edit", "x58 y98 w180 h22 Limit30 Hidden vDeckFName")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcTextDeckFSchoolT := Dash.Add("Text", "x250 y101 w48 h18 Hidden vDeckFSchoolT", "School")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcDropDownListDeckFSchool := Dash.Add("DropDownList", "x300 y98 w90 Hidden vDeckFSchool", ["any", "storm", "fire", "myth", "balance", "ice", "life", "death"])
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcTextDeckFSetT := Dash.Add("Text", "x402 y101 w96 h18 Hidden vDeckFSetT", "Equipment Set")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	ogcEditDeckFSet := Dash.Add("Edit", "x498 y98 w30 h22 Number Limit1 Hidden vDeckFSet")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	ogcTextDeckFSetN := Dash.Add("Text", "x534 y101 w240 h18 Hidden vDeckFSetN", "(its Ctrl+1-9 puts its in-game deck on; 0: none)")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcTextDeckFWhenT := Dash.Add("Text", "x12 y131 w64 h18 Hidden vDeckFWhenT", "Used for")
	ogcCheckboxDeckFWDefault := Dash.Add("Checkbox", "x78 y130 w104 h20 Hidden vDeckFWDefault", "anything else")
	ogcCheckboxDeckFWCollect := Dash.Add("Checkbox", "x186 y130 w104 h20 Hidden vDeckFWCollect", "collect goals")
	ogcCheckboxDeckFWBoss := Dash.Add("Checkbox", "x294 y130 w112 h20 Hidden vDeckFWBoss", "bosses (" HkText("boss") ")")
	ogcCheckboxDeckFWDungeon := Dash.Add("Checkbox", "x410 y130 w104 h20 Hidden vDeckFWDungeon", "dungeon runs")
	ogcCheckboxDeckFWFarm := Dash.Add("Checkbox", "x518 y130 w104 h20 Hidden vDeckFWFarm", "farming (loop)")
	ogcTextDeckFPriT := Dash.Add("Text", "x630 y131 w48 h18 Hidden vDeckFPriT", "Priority")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	ogcEditDeckFPri := Dash.Add("Edit", "x680 y128 w40 h22 Number Limit3 Hidden vDeckFPri")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcCheckboxDeckFPin := Dash.Add("Checkbox", "x12 y160 w380 h20 Hidden vDeckFPin", "Use this deck now, whatever's ahead (pinned)")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonDeckFSave := Dash.Add("Button", "x480 y157 w90 h24 Hidden vDeckFSave", "Save")
	ogcButtonDeckFCopy := Dash.Add("Button", "x576 y157 w90 h24 Hidden vDeckFCopy", "Copy")
	ogcButtonDeckFDel := Dash.Add("Button", "x672 y157 w90 h24 Hidden vDeckFDel", "Delete")
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	ogcTextDeckFDmg := Dash.Add("Text", "x12 y188 w760 h44 Hidden vDeckFDmg")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcDeckFList := Dash.Add("ListView", "x12 y236 w760 h470 Hidden vDeckFList AltSubmit -Multi NoSort Background111317 cDADADA", ["Setting", "This deck", "Everywhere else", "Key"])
	ogcDeckFList.ModifyCol(1, 360), ogcDeckFList.ModifyCol(2, 170), ogcDeckFList.ModifyCol(3, 200), ogcDeckFList.ModifyCol(4, 0)
	ogcTextDeckFValT := Dash.Add("Text", "x12 y715 w128 h18 Hidden vDeckFValT", "Value for this deck:")
	Dash.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	ogcEditDeckFVal := Dash.Add("Edit", "x142 y712 w70 h22 Hidden vDeckFVal")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonDeckFValSet := Dash.Add("Button", "x218 y711 w60 h24 Hidden vDeckFValSet", "Set")
	ogcButtonDeckFValClear := Dash.Add("Button", "x284 y711 w150 h24 Hidden vDeckFValClear", "Not set by this deck")
	Dash.SetFont("s9 w400 cB9E2B9", "Segoe UI")
	ogcTextDeckFNote := Dash.Add("Text", "x442 y715 w330 h36 Hidden vDeckFNote")
	;The Network tab: every bot on your home network (Network.ahk) - pick one: its log and its game; the buttons send it
	;a command (with the network PIN)
	Tab.UseTab(5)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w400 h16", "BOTS ON YOUR NETWORK")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	ogcTextNetHelp := Dash.Add("Text", "x12 y88 w760 h32 vNetHelp", "Every PC on your home network running the bot with Settings > NETWORK > neton. Pick one to see its log and its game. The buttons need the network PIN, the same on both PCs (Settings: netpin); Play for me can only be switched off from here.")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonNetOnBtn := Dash.Add("Button", "x12 y124 w80 h26 vNetOnBtn", "Bot on")
	ogcButtonNetOnBtn.OnEvent("Click", DashNetOn.Bind("Normal"))
	ogcButtonNetOffBtn := Dash.Add("Button", "x98 y124 w80 h26 vNetOffBtn", "Bot off")
	ogcButtonNetOffBtn.OnEvent("Click", DashNetOff.Bind("Normal"))
	ogcButtonNetPfmBtn := Dash.Add("Button", "x184 y124 w120 h26 vNetPfmBtn", "Play for me off")
	ogcButtonNetPfmBtn.OnEvent("Click", DashNetPfm.Bind("Normal"))
	ogcButtonNetRestartBtn := Dash.Add("Button", "x310 y124 w80 h26 vNetRestartBtn", "Restart")
	ogcButtonNetRestartBtn.OnEvent("Click", DashNetRestart.Bind("Normal"))
	ogcButtonNetRefreshBtn := Dash.Add("Button", "x396 y124 w80 h26 vNetRefreshBtn", "Refresh")
	ogcButtonNetRefreshBtn.OnEvent("Click", DashNetRefresh.Bind("Normal"))
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	ogcTextNetStatus := Dash.Add("Text", "x12 y156 w760 h30 vNetStatus", "Network: off (Settings > NETWORK > neton)")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcNetList := Dash.Add("ListView", "x12 y190 w760 h150 vNetList AltSubmit -Multi Background111317 cDADADA", ["PC", "Version", "Wizard", "Zone", "Bot", "Play for me", "Doing", "Health", "Mana", "Deaths", "Seen", "Id"])
	ogcNetList.OnEvent("DoubleClick", DashNetListEvent.Bind("DoubleClick"))
	ogcNetList.ModifyCol(1, 110), ogcNetList.ModifyCol(2, 58), ogcNetList.ModifyCol(3, 110), ogcNetList.ModifyCol(4, 130), ogcNetList.ModifyCol(5, 52), ogcNetList.ModifyCol(6, 72)
	ogcNetList.ModifyCol(7, 96), ogcNetList.ModifyCol(8, 74), ogcNetList.ModifyCol(9, 60), ogcNetList.ModifyCol(10, 54), ogcNetList.ModifyCol(11, 60), ogcNetList.ModifyCol(12, 0)
	Dash.SetFont("s8 w400 cDADADA", "Consolas")
	ogcEditNetLog := Dash.Add("Edit", "x12 y348 w380 h440 ReadOnly -Wrap +HScroll +VScroll vNetLog")
	ogcPictureNetPic := Dash.Add("Picture", "x400 y348 w372 h210 vNetPic")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	ogcTextNetPicNote := Dash.Add("Text", "x400 y564 w372 h60 vNetPicNote", "Pick a bot to see its log and its game.")
	;The Keys tab: every action's key - yours to change (Hotkeys.ahk)
	Tab.UseTab(6)
	Dash.SetFont("s9 w600 c8AB4F8", "Segoe UI")
	Dash.Add("Text", "x12 y68 w400 h16", "KEYS")
	Dash.SetFont("s9 w400 c9AA0A6", "Segoe UI")
	ogcTextKeyHelp := Dash.Add("Text", "x12 y88 w760 h32 vKeyHelp", "Pick an action and click Change (or double-click it), then press the new key - with Ctrl, Alt, Shift or Windows if you like. Keys the bot presses in the game (W A S D, X, Space, Ctrl+O, Ctrl+1-9, F13-F24) and plain letters can't be taken.")
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonKeyChangeBtn := Dash.Add("Button", "x12 y124 w90 h26 vKeyChangeBtn", "Change...")
	ogcButtonKeyDefaultBtn := Dash.Add("Button", "x108 y124 w90 h26 vKeyDefaultBtn", "Its default")
	ogcButtonKeyNoneBtn := Dash.Add("Button", "x204 y124 w90 h26 vKeyNoneBtn", "No key")
	ogcButtonKeyAllBtn := Dash.Add("Button", "x300 y124 w110 h26 vKeyAllBtn", "All to defaults")
	Dash.SetFont("s9 w400 cB9E2B9", "Consolas")
	ogcTextKeyStatus := Dash.Add("Text", "x12 y156 w760 h30 vKeyStatus")
	Dash.SetFont("s9 w400 cDADADA", "Segoe UI")
	ogcKeyList := Dash.Add("ListView", "x12 y190 w760 h598 vKeyList AltSubmit -Multi Background111317 cDADADA", ["Action", "Key", "Default", "Works", "Id"])
	ogcKeyList.ModifyCol(1, 330), ogcKeyList.ModifyCol(2, 130), ogcKeyList.ModifyCol(3, 150), ogcKeyList.ModifyCol(4, 140), ogcKeyList.ModifyCol(5, 0)
	Tab.UseTab()
	;The Play for me button, on every tab - the tab row's right end (DashGuiSize keeps it there), not the heading's
	;room: every check for you off till you click it again; off at every start. A red bar (green while on: DashPlayShow) -
	;a Progress control takes a colour - with the clickable words over it
	ogcProgressDashPlayBg := Dash.Add("Progress", "x668 y37 w108 h24 BackgroundB71C1C Disabled vDashPlayBg")
	Dash.SetFont("s9 w700 cFFFFFF", "Segoe UI")
	ogcTextDashPlayBtn := Dash.Add("Text", "x668 y37 w108 h24 +Center +0x200 BackgroundTrans vDashPlayBtn", "Play for me")
	ogcTextDashPlayBtn.OnEvent("Click", DashPlayToggle.Bind("Normal"))
	Dash.SetFont("s9 w400 c000000", "Segoe UI")
	;(the log so far: the lines written before the window was made)
	earlier := FileRead(A_ScriptDir "\debug.log")
	if (earlier != "")
		DashAppend(earlier)
	shown := IniRead(A_ScriptDir "\dashboard.ini", "window", "shown", 1)
	DashApplyView()
	;(the Dungeons tab's list and status; the Spells tab's)
	DgListFill()
	DgShow()
	SpInit()
	;(the Keys tab's list)
	if (IsFunc("KeyListFill"))
		KeyListFill.Call()
	if (shown)
		DashShow()
	SetTimer(DashRefresh,1000)
	OnExit("DashOnExit")
	;(the map: back if it was open when the bot stopped)
	mapShown := IniRead(A_ScriptDir "\dashboard.ini", "map", "shown", 0)
	if (mapShown = 1)
		DashMapShow()
	}

;The "Learn every card" button's label
DashLearnShow(learnOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashLearnBtn, % learnOn ? "Learning... (stop)" : "Learn every card" ; V1toV2: Ternary not yet supported (coming soon)
	}

;The bot on/off button's label
DashBotShow(isOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashBotBtn, % "Bot: " (isOn ? "on" : "off") " (" HkText("bot") ")" ; V1toV2: Ternary not yet supported (coming soon)
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
	GuiControl, Dash:, DashBotBtn, % "Bot: " (BotOn ? "on" : "off") " (" HkText("bot") ")" ; V1toV2: Ternary not yet supported (coming soon)
	ogcButtonDashWalkBtn.Text := "Walking on/off (" HkText("walk") ")"
	ogcTextDgHelp.Value := DashDgHelpText()
	;(while a run's being recorded: the key it was begun with - the one that stops it)
	GuiControl, Dash:, DgRecStopBtn, % "Stop recording (" (DgRecording ? HkName(DgRecKey) : HkText("record")) ")" ; V1toV2: Ternary not yet supported (coming soon)
	ogcCheckboxDeckFWBoss.Text := "bosses (" HkText("boss") ")"
	}

;The "Game to front" button's label
DashFrontShow(frontOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashFrontBtn, % "Game to front: " (frontOn ? "on" : "off") ; V1toV2: Ternary not yet supported (coming soon)
	}

;The "Play for me" button: red "Play for me" off, green "PLAYING FOR ME" on (you asked, 2026-10-26)
DashPlayShow(on)
	{
	if (!DashHwnd)
		return
	playCol := on ? "2E7D32" : "B71C1C"
	ogcProgressDashPlayBg.Opt("+Background" playCol)
	GuiControl, Dash:, DashPlayBtn, % on ? "PLAYING FOR ME" : "Play for me" ; V1toV2: Ternary not yet supported (coming soon)
	;(the words drawn again over the bar's new colour)
	ogcTextDashPlayBtn.Move()
	}

;The "Wait while I play" button's label
DashHandsShow(waitOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashHandsBtn, % "Wait for me: " (waitOn ? "on" : "off") ; V1toV2: Ternary not yet supported (coming soon)
	}

;Simple (true) or advanced: which view of a window (what: "dashboard", "settings") - dashboard.ini [view]. Not set yet:
;advanced where the bot ran before (it had a dashboard.ini - nothing that was there goes missing), simple on a new one
ViewSimple(what)
	{
	ini := A_ScriptDir "\dashboard.ini"
	v := IniRead(ini, "view", what, A_Space)
	if (v = "")
		{
		;(both views decided at once - the first one asked mustn't make the file the other takes for "ran before")
		v := FileExist(ini) ? 0 : 1
		for each, w in ["dashboard", "settings"]
			{
			had := IniRead(ini, "view", w, A_Space)
			if (had = "")
				IniWrite(v, ini, "view", w)
			}
		v := IniRead(ini, "view", what, v)
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
		ogc%c%.%act%() ; V1toV2: SubCommand passed as variable, check variable contents and docs
	GuiControl, Dash:, DashViewBtn, % DashSimple ? "Advanced view" : "Simple view" ; V1toV2: Ternary not yet supported (coming soon)
	Gui, % "Dash:+MinSize740x" (DashSimple ? 330 : 640) ; V1toV2: Ternary not yet supported (coming soon)
	}

;Shows the window where it was (else on a monitor the game isn't on), without taking the focus - each view its own
;place and size ([window]: advanced, [simple])
DashShow()
	{
	section := DashSimple ? "simple" : "window"
	x := IniRead(A_ScriptDir "\dashboard.ini", section, "x", A_Space)
	y := IniRead(A_ScriptDir "\dashboard.ini", section, "y", A_Space)
	w := IniRead(A_ScriptDir "\dashboard.ini", section, "w", 784)
	h := IniRead(A_ScriptDir "\dashboard.ini", section, "h", A_Space)
	layout := IniRead(A_ScriptDir "\dashboard.ini", "window", "layout", 1)
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
		spare := DashSpareMonitor(&mLeft, &mTop, &mRight, &mBottom)
		;(no bigger than that monitor)
		w := Min(w, Floor((mRight - mLeft - 40) / dpi) - 16), h := Min(h, Floor((mBottom - mTop - 40) / dpi) - 40)
		x := spare ? mLeft + 20 : mRight - Round((w + 16) * dpi) - 20
		y := spare ? mTop + 20 : mBottom - Round((h + 40) * dpi) - 20
		}
	DashFitHeight(x, y, &h)
	Dash.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")
	DashShown := 1
	DashRefresh()
	}

;The work area of the first monitor that doesn't hold the middle of the game window: true; else the main
;monitor's and false
DashSpareMonitor(&mLeft, &mTop, &mRight, &mBottom)
	{
	gx := GameLeft + GameW // 2, gy := GameTop + GameH // 2
	count := MonitorGetCount()
	Loop count
		{
		MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
		if (!(gx >= mLeft && gx < mRight && gy >= mTop && gy < mBottom))
			return true
		}
	MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
	return false
	}

;The work area of the monitor that holds x, y (else the main monitor's)
DashMonitorAt(x, y, &mLeft, &mTop, &mRight, &mBottom)
	{
	count := MonitorGetCount()
	Loop count
		{
		MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
		if (x >= mLeft && x < mRight && y >= mTop && y < mBottom)
			return
		}
	MonitorGetWorkArea(, &mLeft, &mTop, &mRight, &mBottom)
	}

;h (a window's inside, at 100% display scaling) cut so a window at x, y fits on the monitor it's on
DashFitHeight(x, y, &h)
	{
	dpi := A_ScreenDPI / 96
	count := MonitorGetCount()
	Loop count
		{
		MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
		if (x + 40 >= mLeft && x + 40 < mRight && y + 20 >= mTop && y + 20 < mBottom)
			h := Min(h, Floor((mBottom - y - 20) / dpi) - 40)
		}
	}

DashOnScreen(x, y)
	{
	count := MonitorGetCount()
	Loop count
		{
		MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
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
		Dash.Hide()
		DashShown := 0
		}
	else
		DashShow()
	IniWrite(DashShown, A_ScriptDir "\dashboard.ini", "window", "shown")
	}

DashSavePlace()
	{
	if (!DashShown || !DashHwnd)
		return
	if (DashSimple)
		DashSaveWin(DashHwnd, "simple")
	else if (DashSaveWin(DashHwnd, "window"))
		IniWrite(3, A_ScriptDir "\dashboard.ini", "window", "layout")
	}

;Saves where a window is in dashboard.ini [section]: x, y on the screen, and its inside's width and height at
;100% display scaling (as Gui Show takes them). Not while it's minimized or maximized (false)
DashSaveWin(hwnd, section)
	{
	mm := WinGetMinMax("ahk_id " hwnd)
	if (mm != 0)
		return false
	rc := Buffer(16, 0) ; V1toV2: if 'rc' is a UTF-16 string, use 'VarSetStrCapacity(&rc, 16)' and replace all instances of 'rc.Ptr' with 'StrPtr(rc)'
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc.Ptr)
	WinGetPos(&x, &y, , , "ahk_id " hwnd)
	if (x = "")
		return false
	IniWrite(x, A_ScriptDir "\dashboard.ini", section, "x")
	IniWrite(y, A_ScriptDir "\dashboard.ini", section, "y")
	IniWrite(Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), A_ScriptDir "\dashboard.ini", section, "w")
	IniWrite(Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI), A_ScriptDir "\dashboard.ini", section, "h")
	return true
	}

;---- The Network tab (Network.ahk) ----

;The Network tab is the one showing (and the window's up)
DashNetShown()
	{
	if (!DashHwnd || !DashShown)
		return false
	netTab := ogcTab3DashTabs.Value
	return netTab = "Network"
	}

;The Network tab's list and status line afresh (NetTick, every 2 s): this PC first, then every bot heard - the one
;picked kept picked
DashNetFill()
	{
	if (!DashHwnd)
		return
	n := IsObject(NetPeers) ? NetPeers.Length : 0
	DashSet("NetStatus", "Network: " NetState (NetWhy != "" ? " - " NetWhy : "") (NetState = "on" ? "`n" n " other bot" (n = 1 ? "" : "s") " heard on your home network" (n ? "" : " - is neton switched on there, and Python allowed through its firewall?") : ""))
	if (!DashNetShown())
		return
	wasCrit := A_IsCritical
	Critical()
	;Gui, Dash:Default ; V1toV2: removed, but applied
	V1toV2_LineFill := true ; remove me after inspection
	prevLV := A_DefaultListView
	;Gui, Dash:ListView, NetList ; V1toV2: removed, but applied
	V1toV2_LineFill := true ; remove me after inspection
	ogcNetList.Opt("-Redraw")
	ogcNetList.Delete()
	ogcNetList.Add("", A_ComputerName " (this PC)", BotVersion(), OwnName(), WalkZone(), (BotStandby && !BotEverOn) ? "standby" : BotOn ? "on" : "off"
		, PlayForMe ? "ON" : "off", "-", RegExReplace(IsObject(DashSees) ? DashSees.hp : "", "\s*\(.*"), IsObject(DashSees) ? DashSees.mana : ""
		, IsObject(DashN) && DashN.deaths ? DashN.deaths : 0, "now", "")
	for i, p in NetPeers
		{
		row := ogcNetList.Add("", p.pc, p.ver, p.wiz (p.school != "" ? " (" p.school ")" : ""), p.zone, p.bot, p.pfm = 1 ? "ON" : "off", p.doing
, p.hp, p.mana, p.deaths (p.dall != "" ? " / " p.dall : ""), p.age > 15 ? NetAge(p.age) " ago (quiet)" : "now", p.id)
		if (p.id = NetSel)
			ogcNetList.Modify(row, "Select Focus")
		}
	ogcNetList.Opt("+Redraw")
	if (prevLV != "" && prevLV != "NetList")
		Gui, Dash:ListView, %prevLV% ; V1toV2: [%prevLV%] not found. Manual edit required.
	CfgUncritical(wasCrit, 0)
	}

;The picked bot's log and picture onto the tab (NetFetchPicked); pic "" - none, why says why
DashNetShow(log, pic, why)
	{
	if (!DashHwnd)
		return
	if (log != "")
		{
		ogcEditNetLog.Value := log
		;(the log's end in view)
		netLogHwnd := ogcEditNetLog.Hwnd
		ErrorLevel := SendMessage(0x115, 7, 0, , "ahk_id " netLogHwnd)
		}
	if (pic != "")
		{
		ogcPictureNetPic.Value := "*w372 *h-1 " pic
		ogcPictureNetPic.Visible := true
		GuiControl, Dash:, NetPicNote, % "Its game, " A_Hour ":" A_Min ":" A_Sec (why != "" ? " - " why : "") ; V1toV2: Ternary not yet supported (coming soon)
		}
	else
		{
		;(no picture this time: the last one isn't left up under it)
		ogcPictureNetPic.Visible := false
		GuiControl, Dash:, NetPicNote, % why != "" ? why : "No picture" ; V1toV2: Ternary not yet supported (coming soon)
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
		c := IniRead(A_ScriptDir "\dashboard.ini", "logcolors", k[1], k[3])
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
	cf := Buffer(116, 0) ; V1toV2: if 'cf' is a UTF-16 string, use 'VarSetStrCapacity(&cf, 116)' and replace all instances of 'cf.Ptr' with 'StrPtr(cf)'
	NumPut("UInt", 116, cf, 0), NumPut("UInt", 0x40000000, cf, 4), NumPut("UInt", DashBGR(rgb), cf, 20)    ; CFM_COLOR, crTextColor
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x444, "Ptr", 1, "Ptr", cf.Ptr)    ; EM_SETCHARFORMAT, SCF_SELECTION
	}

;The log box's length in its own characters (a line break counts 1 - as EM_SETSEL counts)
DashLogLen()
	{
	gtl := Buffer(8, 0), NumPut("UInt", 10, gtl, 0), NumPut("UInt", 1200, gtl, 4)       ; GTL_PRECISE|GTL_NUMCHARS, UTF-16 ; V1toV2: if 'gtl' is a UTF-16 string, use 'VarSetStrCapacity(&gtl, 8)' and replace all instances of 'gtl.Ptr' with 'StrPtr(gtl)'
	return DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x45F, "Ptr", gtl.Ptr, "Ptr", 0, "Ptr")  ; EM_GETTEXTLENGTHEX
	}

;The log box (a rich edit - an Edit can't colour its lines) set up: the dark background, Consolas 9, no word wrap
DashLogInit()
	{
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x443, "Ptr", 0, "Ptr", DashBGR("111317"))   ; EM_SETBKGNDCOLOR
	cf := Buffer(116, 0) ; V1toV2: if 'cf' is a UTF-16 string, use 'VarSetStrCapacity(&cf, 116)' and replace all instances of 'cf.Ptr' with 'StrPtr(cf)'
	NumPut("UInt", 116, cf, 0), NumPut("UInt", 0xE0000000, cf, 4)      ; CFM_SIZE | CFM_COLOR | CFM_FACE
	NumPut("Int", 180, cf, 12), NumPut("UInt", DashBGR("DADADA"), cf, 20)
	StrPut("Consolas", cf.Ptr + 26, 32, "UTF-16")
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0x444, "Ptr", 4, "Ptr", cf.Ptr)    ; EM_SETCHARFORMAT, SCF_ALL
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
	Loop Parse, text, "`n"
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
	LogCol := Gui("+OwnerDash +ToolWindow", "Log colours"), LogColHwnd := LogCol.Hwnd
	LogCol.OnEvent("Close", LogColGuiClose)
	LogCol.OnEvent("Escape", LogColGuiEscape)
	LogCol.BackColor := "1B1D22"
	LogCol.SetFont("s9 w400 cF2F2F2", "Segoe UI")
	kinds := DashLogKinds(), colours := DashLogColors()
	for i, k in kinds
		{
		y := 10 + (i - 1) * 28, col := colours[k[1]]
		ogcProgressLogColSwi := LogCol.Add("Progress", "x10 y" . y . " w22 h18 Background" . col . " Disabled vLogColSw" . i)
		LogCol.Add("Text", "x40 y" . y . " w270 h18 +0x200", k[2])
		LogCol.SetFont("s9 w400 c000000", "Segoe UI")
		ogcButtonLogColBtni := LogCol.Add("Button", "x316 y" . y . " w76 h20 vLogColBtn" . i, "Change...")
		ogcButtonLogColBtni.OnEvent("Click", DashLogColorPick.Bind("Normal"))
		LogCol.SetFont("s9 w400 cF2F2F2", "Segoe UI")
		}
	y := 16 + kinds.Length * 28
	LogCol.SetFont("s9 w400 c000000", "Segoe UI")
	ogcButtonResetall := LogCol.Add("Button", "x10 y" . y . " w110 h24", "Reset all")
	ogcButtonResetall.OnEvent("Click", DashLogColorReset.Bind("Normal"))
	ogcButtonClose := LogCol.Add("Button", "x292 y" . y . " w100 h24", "Close")
	ogcButtonClose.OnEvent("Click", DashLogColorClose.Bind("Normal"))
	LogCol.Show("AutoSize")
	}

;Windows' colour picker, starting at rgb (RRGGBB): the colour chosen, "" cancelled
DashPickColour(rgb, owner)
	{
	;(its 16 custom colours kept between opens - made once: the buffer read as text is "" whenever slot 1 is black)
	static cust, custMade := 0
	if (!custMade)
		cust := Buffer(64, 0), custMade := 1 ; V1toV2: if 'cust' is a UTF-16 string, use 'VarSetStrCapacity(&cust, 64)' and replace all instances of 'cust.Ptr' with 'StrPtr(cust)'
	size := A_PtrSize = 8 ? 72 : 36
	cc := Buffer(size, 0) ; V1toV2: if 'cc' is a UTF-16 string, use 'VarSetStrCapacity(&cc, size)' and replace all instances of 'cc.Ptr' with 'StrPtr(cc)'
	NumPut("UInt", size, cc, 0)
	NumPut("Ptr", owner, cc, A_PtrSize)                         ; hwndOwner
	NumPut("UInt", DashBGR(rgb), cc, 3 * A_PtrSize)             ; rgbResult
	NumPut("Ptr", cust.Ptr, cc, 4 * A_PtrSize)                     ; lpCustColors
	NumPut("UInt", 0x3, cc, 5 * A_PtrSize)                      ; CC_RGBINIT | CC_FULLOPEN
	if (!DllCall("comdlg32\ChooseColorW", "Ptr", cc.Ptr))
		return ""
	c := NumGet(cc, 3 * A_PtrSize, "UInt")
	return Format("{:02X}{:02X}{:02X}", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)
	}

;The log box coloured afresh - its lines put back in, each in its kind's colour now
DashLogRecolour()
	{
	lrAll := ogcCustomDashConsole.Value
	ogcCustomDashConsole.Value := ""
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
	else if (RegExMatch(msg, "^  saving pips for (\w+) \((\d+) pips, you have (\d+)\).*up to (\d+) round", &m))
		DashAdd("pipsaves"), DashSees.plan := "saving pips for " DashShortName(m[1]) " (" m[3] "/" m[2] " pips)"
	else if (RegExMatch(msg, "^  (not saving pips|saved pips) .*", &m))
		DashSees.plan := Trim((m&&m[0]))
	else if (RegExMatch(msg, "^  Click pass: found=1"))
		DashAdd("passes")
	else if (InStr(msg, "  Discarded ") = 1)
		DashAdd("discards")
	else if (InStr(msg, "  fleeing: ") = 1)
		DashAdd("flees")
	else if (InStr(msg, "Defeated:") = 1)
		DashAdd("deaths"), DashDeathsAll(1)
	else if (RegExMatch(msg, "^  kill check: (.*) -> (.*)$", &m))
		{
		DashSees.enemies := m[1]
		if (m[2] != "no lethal hit")
			DashAdd("lethal")
		}
	else if (RegExMatch(msg, "^  pips=(-?\d+)", &m))
		DashSees.pips := (m[1] < 0 ? "?" : m[1])
	else if (RegExMatch(msg, "^  own health: (\d+)/(\d+)", &m))
		DashSees.hp := m[1] "/" m[2] " (" Round(100 * m[1] / m[2]) "%, name plate)"
	else if (RegExMatch(msg, "school=(\w*) \| hitter=(\w*)", &m))
		DashSees.school := m[1], DashSees.hitter := m[2]
	else if (RegExMatch(msg, "^  learned a new card: (.*?)( \(picture:|$)", &m))
		DashAdd("learned"), DashSees.lastLearned := m[1]
	else if (InStr(msg, "Potions: drank one") = 1)
		DashAdd("potions")
	else if (InStr(msg, "Potions: no potion left - going to buy some") = 1)
		DashAdd("potionRuns")
	;(the backpack quick sold - QuickSell.ahk: "Backpack: quick sold 37 items for 12,345 gold (...) - 2,000 gold lost over the pouch")
	else if (RegExMatch(msg, "^Backpack: quick sold (\d+) items for ([\d,]+) gold(?:.* - ([\d,]+) gold lost over the pouch)?", &m))
		DashAdd("quicksells"), DashAdd("itemsSold", m[1] + 0), DashAdd("goldSold", StrReplace(m[2], ",") + 0), DashAdd("goldLost", m[3] = "" ? 0 : StrReplace(m[3], ",") + 0)
	else if (InStr(msg, "Reconnect: ") = 1)
		DashSees.reconnect := SubStr(msg, 12), DashSees.reconnectAt := A_TickCount
	else if (InStr(msg, "Pictures: ") = 1)
		DashSees.pictures := SubStr(msg, 11)
	else if (InStr(msg, "Stats: ") = 1)
		DashSees.stats := SubStr(msg, 8)
	else if (RegExMatch(msg, "^  (UseHeal|UseHit|UseBlade|UseTrap|UseOnSelf|UseOnHammer|UseConvert|Click) (\w+): found=1", &m) && m[2] != "pass")
		DashSees.lastTry := m[2]
	}

DashAdd(key, n := 1)
	{
	if (IsObject(DashN))
		DashN[key] := (DashN.Has(key) ? DashN[key] : 0) + n ;  V1toV2: Invalid Index errors?, try 'DashN.Push(<val>)'
	}

;A card went down (CastResult saw it cast)
DashCast(title)
	{
	if (!IsObject(DashCasts))
		return
	DashCasts[title] := (DashCasts.Has(title) ? DashCasts[title] : 0) + 1 ;  V1toV2: Invalid Index errors?, try 'DashCasts.Push(<val>)'
	DashAdd("casts")
	DashSees.lastCast := DashCardName(title) " at " A_Hour ":" A_Min ":" A_Sec
	}

;What the bot sees (key: hand, you...)
DashSee(key, text)
	{
	if (IsObject(DashSees))
		DashSees[key] := text ;  V1toV2: Invalid Index errors?, try 'DashSees.Push(<val>)'
	}

;The hand as the vision helper read it (/hand's answer, CardLearn.ahk): each card's name, ?<type> for one
;the bot doesn't know, * for a greyed-out one (not enough pips). A box the helper says isn't a card (field 15 = 0:
;the deck's back, the round's timer, the floor) is left out
DashHandSeen(answer)
	{
	text := "", n := 0, box := 0, notCards := 0
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length < 12 || f[1] != "card")
			continue
		;(the helper saves every box's picture, generated\hand\hand<box>.png)
		box += 1
		if (f.Length >= 15 && f[15] = "0")
			{
			notCards += 1
			continue
			}
		known := f[6]
		name := known = "" ? "?" (f[9] = "" ? "card" : f[9]) : InStr(known, "learned/") = 1 ? DashLearnedName(SubStr(known, 9)) : DashShortName(SubStr(known, (InStr(known, "/") + 1)<1 ? (InStr(known, "/") + 1)-1 : (InStr(known, "/") + 1)), SubStr(known, 1, InStr(known, "/") - 1))
		text .= (text = "" ? "" : ", ") name (f[8] = 1 ? "*" : "")
		n += 1
		if (n <= 7)
			DashHandCard(n, name, known, f[8] = 1, f[11] != "" ? f[11] : DashKnownPips(known), box)
		}
	;(the slots past the hand: empty)
	Loop 7 - Min(n, 7)
		{
		slot := n + A_Index
		DashCardShow(slot, 0, 0)
		}
	now := FormatTime(, "HH:mm:ss")
	GuiControl, Dash:, DashHandHead, % "YOUR HAND " now " (" n " card" (n = 1 ? "" : "s") (notCards ? ", " notCards " not a card" : "") ")   white known   yellow new to it   grey can't cast" ; V1toV2: Ternary not yet supported (coming soon)
	DashSee("hand", text)
	}

;A known card's pip cost when its digit wasn't read ("" not known): an enchant (Sharpened Blade, Potent Trap, Epic,
;Colossal...) and the like are free - 0 - and a slot's cost is in PlayerStats.txt (<school>.<slot>pips); a "?" for a
;free card was shown otherwise (2026-10-23)
DashKnownPips(known)
	{
	if (known = "")
		return ""
	dir := SubStr(known, 1, InStr(known, "/") - 1), title := SubStr(known, (InStr(known, "/") + 1)<1 ? (InStr(known, "/") + 1)-1 : (InStr(known, "/") + 1))
	if (dir = "resources" && RegExMatch(title, "i)^(sharpen|potent|epic|colossal|gargantuan|monstrous|giant|strong)$"))
		return 0
	if (dir = "life" && title = "enchant")
		return 0
	;(0 there is an X-pip spell's - all your pips - not a free one: left as not known)
	if (IsObject(Stats) && Stats.Has(dir "." title "pips") && Stats[dir "." title "pips"] > 0)
		return Stats[dir "." title "pips"]
	return ""
	}

;A learned card's name in the hand: the one you gave it on the Spells tab, else "learned"
DashLearnedName(id)
	{
	c := IsFunc("LearnCardOf") ? LearnCardOf.Call(id) : ""
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
		ogcDashCardPic%n%.Value := "*w" Round(58 * A_ScreenDPI / 96) " *h" Round(97 * A_ScreenDPI / 96) " " pic
		DashCardShow(n, 1, "")
		}
	else
		DashCardShow(n, 0, "")
	colour := grey ? "8A8A8A" : known = "" ? "F2C14E" : "E8E8E8"
	ogcDashCardTxt%n%.Opt("+c" colour)
	GuiControl, Dash:, DashCardTxt%n%, % SubStr(name, 1, 12) "`n" (pips = "" ? "? pips" : pips " pip" (pips = 1 ? "" : "s")) (grey ? " - grey" : "") ; V1toV2: Ternary not yet supported (coming soon)
	DashCardShow(n, "", 1)
	}

;A hand card's picture (pic) and words (txt) shown (1) or not (0) - "" left as they are: kept for the hand's view, shown
;only while it's the one up (a deck's view over it: Decks.ahk DeckViewShow puts them back)
DashCardShow(n, pic, txt)
	{
	if (!IsObject(DashCardWant))
		DashCardWant := {}
	if (pic != "")
		DashCardWant["p" n] := pic ;  V1toV2: Invalid Index errors?, try 'DashCardWant.Push(<val>)'
	if (txt != "")
		DashCardWant["t" n] := txt ;  V1toV2: Invalid Index errors?, try 'DashCardWant.Push(<val>)'
	if (DeckView)
		return
	if (pic != "")
		GuiControl, % "Dash:" (pic ? "Show" : "Hide"), DashCardPic%n% ; V1toV2: Ternary not yet supported (coming soon)
	if (txt != "")
		GuiControl, % "Dash:" (txt ? "Show" : "Hide"), DashCardTxt%n% ; V1toV2: Ternary not yet supported (coming soon)
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
	Critical()
	;(the window has three ListViews: this one for the LV_ functions, the one before put back after)
	;Gui, Dash:Default ; V1toV2: removed, but applied
	V1toV2_LineFill := true ; remove me after inspection
	prevLV := A_DefaultListView
	;Gui, Dash:ListView, DashFoeList ; V1toV2: removed, but applied
	V1toV2_LineFill := true ; remove me after inspection
	ogcDashFoeList.Opt("-Redraw")
	ogcDashFoeList.Delete()
	foes := 0
	Loop Parse, answer, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] != "enemy")
			continue
		foes += 1
		if (foes > 1)
			ogcDashFoeList.Add("", "")
		if (f[4] != "ok")
			ogcDashFoeList.Add("", f[3], f[4] = "pending" ? "looking it up on the wiki" : "not on the wiki - its spells not known")
		else
			{
			about := (f[9] != "" ? f[9] : "") (f[10] != "" ? ", rank " f[10] : "") (f[11] != "" ? ", " f[11] " health" : "")
			ogcDashFoeList.Add("", f[3], about = "" ? "" : "(" LTrim(about, ", ") ")", "hits you " Round(f[6] * 100) "%"
				, "~" Round(f[5], 1) " pips now" (f[7] > 0 ? ", biggest hit " f[7] : ""))
			}
		;(spell:chance:pips and damage:seen before:rounds cast this battle)
		for each, card in StrSplit(f[12], ";")
			{
			p := StrSplit(card, ":")
			if (p[1] = "")
				continue
			ogcDashFoeList.Add("", "", "   " p[1], Round(p[2] * 100) "%", p[3], p[5] = "" ? "" : "round " StrReplace(p[5], "/", ", ")
, p[4] > 0 ? RegExReplace(Round(p[4], 1), "\.0$") : "")
			}
		}
	ogcDashFoeList.Opt("+Redraw")
	if (prevLV != "" && prevLV != "DashFoeList")
		Gui, Dash:ListView, %prevLV% ; V1toV2: [%prevLV%] not found. Manual edit required.
	now := FormatTime(, "HH:mm:ss")
	ogcTextDashFoeHead.Value := "ENEMIES " now ", round " rnd " - " (foes = 0 ? "none named in the game's log"
		: lethal = "" ? "your health not read: the chance they kill you not known" : Round(lethal * 100) "% chance their hits kill you this round (your health " health ")")
	if (!wasCrit)
		Critical("Off")
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
		Loop Read, A_ScriptDir "\PlayerStats.txt"
			{
			line := A_LoopReadLine
			if (RegExMatch(line, "^\s*([\w.]+)\s*:[^;]*;\s*(.*)$", &m))
				key := m[1], comment := m[2]
			else if (prevKey != "" && RegExMatch(line, "^\s*;\s*\^\s*(.*)$", &m))
				key := prevKey, comment := m[1]
			else
				{
				prevKey := RegExMatch(line, "^\s*([\w.]+)\s*:", &m) ? m[1] : ""
				continue
				}
			prevKey := RegExMatch(line, "^\s*([\w.]+)\s*:", &k) ? k[1] : ""
			comment := RegExReplace(comment, "i)^learned \d+:\s*")
			if (RegExMatch(comment, "^([A-Z][A-Za-z']*(?: [A-Z][A-Za-z']*)*)", &n) && !DashNames.Has(key))
				DashNames[key] := n[1] ;  V1toV2: Invalid Index errors?, try 'DashNames.Push(<val>)'
			}
		}
	key := Format("{:L}", (dir != "" && dir != "resources" ? dir : hitschool) "." title)
	if (DashNames.Has(key))
		return DashNames[key] " (" title ")"
	key := Format("{:L}", title)
	return DashNames.Has(key) ? DashNames[key] " (" title ")" : title
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
		doing := "Learning every card (" (IsObject(LearnedCards) ? LearnedCards.Length - LearnAllFrom : 0) " new so far)"
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
		ogcButtonDashUpdBtn.Enabled := true
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
		. (n.quicksells ? "Quick sells      " DashNum(n.quicksells) "   (" n.itemsSold " items, " QsThousands(n.goldSold) " gold" (n.goldLost ? ", " QsThousands(n.goldLost) " lost over the pouch" : "") ")`n" : "")
		. "Cards learned    " DashNum(n.learned) "`n"
		. "Cards cast       " DashNum(n.casts) casts
	DashSet("DashStatText", s)
	DashSet("DashUsageText", DashUsage())
	;What it sees
	see := DashSees
	zone := IsFunc("WalkZone") ? WalkZone.Call() : ""
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
	ogcDashSeeText.GetPos(&posX, &posY, &posW, &posH)
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
		total := IniRead(A_ScriptDir "\dashboard.ini", "stats", "deaths", 0)
		total := RegExMatch(total, "^\d+$") ? total + 0 : 0
		}
	if (add)
		{
		total += add
		IniWrite(total, A_ScriptDir "\dashboard.ini", "stats", "deaths")
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
	last[control] := text ;  V1toV2: Invalid Index errors?, try 'last.Push(<val>)'
	ogc%control%.Value := text
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
	IniWrite(DashMapShown ? 1 : 0, A_ScriptDir "\dashboard.ini", "map", "shown")
	}

;Makes the window (hidden), the first time it's shown
DashMapMake()
	{
	DashMapShown := 0, DashMapReq := "", DashMapKind := "", DashMapAt := 0, DashMapW := 0, DashMapH := 0
	DashMapNote := "", DashMapNav := "", DashMapPicAt := ""
	;(in the temp folder: it's rewritten every second, which OneDrive would keep uploading)
	DashMapFile := A_Temp "\Wizard101 bot map\navmap.png"
	DirCreate(A_Temp "\Wizard101 bot map")
	DirCreate(A_ScriptDir "\generated")
	Map := Gui()
	Map.OnEvent("Close", MapGuiClose)
	Map.OnEvent("Size", MapGuiSize)
	Map.Opt("+Resize +MinSize320x240"), DashMapHwnd := Map.Hwnd
	Map.BackColor := "1B1D22"
	Map.MarginX := 8, Map.MarginY := 8
	ogcPictureDashMapPic := Map.Add("Picture", "x8 y8 w624 h460 vDashMapPic"), DashMapPicH := ogcPictureDashMapPic.hwnd
	Map.SetFont("s9 w400 cDADADA", "Consolas")
	;(one line: cut with "..." when it's longer than the window is wide, not wrapped)
	ogcDashMapText := Map.Add("Text", "x8 y474 w624 h18 +0x400C vDashMapText", "Asking the vision helper for the map...")
	}

;Shows it where it was (else beside the dashboard), without taking the focus, and starts asking
DashMapShow()
	{
	if (!DashMapHwnd)
		DashMapMake()
	x := IniRead(A_ScriptDir "\dashboard.ini", "map", "x", A_Space)
	y := IniRead(A_ScriptDir "\dashboard.ini", "map", "y", A_Space)
	w := IniRead(A_ScriptDir "\dashboard.ini", "map", "w", 640)
	h := IniRead(A_ScriptDir "\dashboard.ini", "map", "h", 500)
	if (x = "" || y = "" || !DashOnScreen(x + 40, y + 20))
		DashMapPlace(&x, &y, w, h)
	DashFitHeight(x, y, &h)
	Map.Title := "Wizard101 bot " BotVersion() " - map"
	Map.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")
	DashMapShown := 1, DashMapAt := 0
	SetTimer(DashMapTick,250)
	}

;Hides it (keeping its place) and stops asking
DashMapHide()
	{
	if (!DashMapHwnd)
		return
	if (DashMapShown)
		DashSaveWin(DashMapHwnd, "map")
	Map.Hide()
	DashMapShown := 0
	SetTimer(DashMapTick,0)
	if (IsObject(DashMapReq))
				{
try DashMapReq.Abort()
		}
	DashMapReq := ""
	}

;Where it goes the first time (w, h: its inside at 100% display scaling): beside the dashboard - right of it,
;below, left or above, whichever fits on the dashboard's monitor - else that monitor's bottom right (the
;spare monitor's, when the dashboard is hidden)
DashMapPlace(&x, &y, w, h)
	{
	dpi := A_ScreenDPI / 96
	ow := Round(w * dpi) + 16, oh := Round(h * dpi) + 40
	if (DashShown && DashHwnd)
		{
		WinGetPos(&dx, &dy, &dw, &dh, "ahk_id " DashHwnd)
		DashMonitorAt(dx + dw // 2, dy + dh // 2, &mLeft, &mTop, &mRight, &mBottom)
		for each, p in [[dx + dw + 8, dy], [dx, dy + dh + 8], [dx - ow - 8, dy], [dx, dy - oh - 8]]
			if (p[1] >= mLeft && p[2] >= mTop && p[1] + ow <= mRight && p[2] + oh <= mBottom)
				{
				x := p[1], y := p[2]
				return
				}
		}
	else
		DashSpareMonitor(&mLeft, &mTop, &mRight, &mBottom)
	x := Max(mLeft, mRight - ow - 20), y := Max(mTop, mBottom - oh - 20)
	}

;Every 250 ms while it's shown: picks up the answer it's waiting for; else asks for a new picture once a
;second (at once when the window's size changed)
DashMapTick()
	{
	if (!DashMapShown)
		{
		SetTimer(DashMapTick,0)
		return
		}
	if (IsObject(DashMapReq))
		return DashMapCheck()
	;(minimized: nothing to draw)
	if (DllCall("IsIconic", "Ptr", DashMapHwnd))
		return
	;(the picture is asked for at the size it's shown at, in screen pixels: shown as it is, not stretched)
	rc := Buffer(16, 0) ; V1toV2: if 'rc' is a UTF-16 string, use 'VarSetStrCapacity(&rc, 16)' and replace all instances of 'rc.Ptr' with 'StrPtr(rc)'
	DllCall("GetClientRect", "Ptr", DashMapPicH, "Ptr", rc.Ptr)
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
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", "http://127.0.0.1:" (VisionPort ? VisionPort : 47128) path, true)
		req.Send()
		DashMapReq := req
		}
	Catch
		DashMapGot(kind, "", false)
	}

;The answer to the request sent, once it's there (after 4 s it's given up)
DashMapCheck()
	{
	req := DashMapReq, done := 0
	try
		done := req.WaitForResponse(0)
	Catch
		{
		;(nothing answering on the port: the helper isn't running)
		DashMapReq := ""
		return DashMapGot(DashMapKind, "", false)
		}
	if (!done)
		{
		if (A_TickCount - DashMapReqAt > 4000)
			{
						{
try req.Abort()
			}
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
			ogcPictureDashMapPic.Value := f
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
	ogcDashMapText.Value := line
	}

;/nav's answer as "zone | at x, y, z | goal in this zone | arrow 1520" (? for what it couldn't read; arrow = how
;far the on-screen arrow's point is, along the game's path)
DashMapNavLine(answer)
	{
	if (answer = "")
		return ""
	f := {}
	Loop Parse, answer, "`n", "`r"
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
		rc := Buffer(16, 0) ; V1toV2: if 'rc' is a UTF-16 string, use 'VarSetStrCapacity(&rc, 16)' and replace all instances of 'rc.Ptr' with 'StrPtr(rc)'
		DllCall("GetClientRect", "Ptr", DashMapHwnd, "Ptr", rc.Ptr)
		gw := Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), gh := Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI)
		}
	ogcPictureDashMapPic.Move(, , Max(16, gw - 16), Max(16, gh - 40))
	ogcDashMapText.Move(, gh - 26, Max(16, gw - 16))
	}

;Text for a URL: UTF-8, everything but letters, digits and - . _ ~ %-escaped
DashMapUri(s)
	{
	buf := Buffer(StrPut(s, "UTF-8"), 0) ; V1toV2: if 'buf' is a UTF-16 string, use 'VarSetStrCapacity(&buf, StrPut(s, "UTF-8"))' and replace all instances of 'buf.Ptr' with 'StrPtr(buf)'
	n := StrPut(s, buf.Ptr, "UTF-8") - 1
	out := ""
	Loop n
		{
		c := NumGet(buf, A_Index - 1, "UChar")
		out .= (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c = 45 || c = 46 || c = 95 || c = 126) ? Chr(c) : "%" Format("{:02X}", c)
		}
	return out
	}

DashMapButton:
DashMapButton()
	return

DashMapTick:
DashMapTick()
	return

MapGuiClose:
MapGuiClose()
	return

MapGuiSize:
MapGuiSize()
	return

;---- The dashboard's buttons ----

DashRefresh:
DashRefresh()
	return

DashPauseLog:
DashPauseLog()
	return

DashClearLog:
DashClearLog()
	return

;The Network tab: a bot picked (its log and picture fetched now), and the buttons for it
DashNetListEvent:
DashNetListEvent()
	return

DashNetOn:
DashNetOn()
return
DashNetOff:
DashNetOff()
return
DashNetPfm:
DashNetPfm()
return
DashNetRestart:
DashNetRestart()
	return

DashNetRefresh:
DashNetRefresh()
	return

;The log's Colours button, and its window's buttons: a kind's colour changed (kept in dashboard.ini [logcolors]), all
;back to the defaults, the window closed - the log coloured afresh each time
DashLogColorsBtn:
DashLogColorsBtn()
	return

DashLogColorPick:
DashLogColorPick()
	return

DashLogColorReset:
DashLogColorReset()
	return

DashLogColorClose:
DashLogColorClose()
return
LogColGuiClose:
LogColGuiClose()
return
LogColGuiEscape:
LogColGuiEscape()
	return

DashOpenLog:
DashOpenLog()
	return

DashWalkToggle:
DashWalkToggle()
	return

DashFolder:
DashFolder()
	return

;CPU and RAM in use, for the STATISTICS row: the bot (this script and its vision helper), the game, the whole PC.
;CPU from the time each has used since the last look (all cores = 100%), RAM its working set (what Task Manager
;shows, about). Read-only process queries - nothing is changed
DashUsage()
	{
	static last := {}, procs := {}
	cores := EnvGet("NUMBER_OF_PROCESSORS")
	cores := cores > 0 ? cores : 1
	now := A_TickCount
	gamePid := 0
	gamePid := WinGetPID("ahk_class " GameClass " ahk_exe " GameExe)
	who := map("bot", [DllCall("GetCurrentProcessId"), VisionPid], game: [gamePid]}
	out := {}
	for name, pids in who
		{
		cpu := 0, ram := 0, seen := 0
		for each, pid in pids
			{
			if (!pid)
				continue
			if (!procs.Has(pid))
				procs[pid] := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr") ;  V1toV2: Invalid Index errors?, try 'procs.Push(<val>)'
			h := procs[pid]
			if (!h)
				continue
			ft := Buffer(32, 0) ; V1toV2: if 'ft' is a UTF-16 string, use 'VarSetStrCapacity(&ft, 32)' and replace all instances of 'ft.Ptr' with 'StrPtr(ft)'
			if (!DllCall("GetProcessTimes", "Ptr", h, "Ptr", ft.Ptr, "Ptr", ft.Ptr + 8, "Ptr", ft.Ptr + 16, "Ptr", ft.Ptr + 24))
				{
				DllCall("CloseHandle", "Ptr", h), procs.Delete(pid)
				continue
				}
			used := NumGet(ft, 16, "Int64") + NumGet(ft, 24, "Int64")
			if (last.Has(pid) && now > last[pid].at)
				cpu += (used - last[pid].used) / 10000 / (now - last[pid].at) / cores * 100
			last[pid] := {used: used, at: now} ;  V1toV2: Invalid Index errors?, try 'last.Push(<val>)'
			cb := 8 + 8 * A_PtrSize
			pmc := Buffer(cb, 0), NumPut("UInt", cb, pmc, 0) ; V1toV2: if 'pmc' is a UTF-16 string, use 'VarSetStrCapacity(&pmc, cb)' and replace all instances of 'pmc.Ptr' with 'StrPtr(pmc)'
			if (DllCall("K32GetProcessMemoryInfo", "Ptr", h, "Ptr", pmc.Ptr, "UInt", cb))
				ram += NumGet(pmc, 8 + A_PtrSize, "UPtr")
			seen += 1
			}
		out[name] := seen ? DashUsageNum(cpu) "%" Chr(183) DashBytes(ram) : "-" ;  V1toV2: Invalid Index errors?, try 'out.Push(<val>)'
		}
	;the whole PC: busy share of all cores since the last look, and RAM in use
	st := Buffer(24, 0) ; V1toV2: if 'st' is a UTF-16 string, use 'VarSetStrCapacity(&st, 24)' and replace all instances of 'st.Ptr' with 'StrPtr(st)'
	pcCpu := "?"
	if (DllCall("GetSystemTimes", "Ptr", st.Ptr, "Ptr", st.Ptr + 8, "Ptr", st.Ptr + 16))
		{
		idle := NumGet(st, 0, "Int64"), total := NumGet(st, 8, "Int64") + NumGet(st, 16, "Int64")
		if (last.Has("pc") && total > last.pc.total)
			pcCpu := DashUsageNum(100 * (1 - (idle - last.pc.idle) / (total - last.pc.total)))
		last.pc := {idle: idle, total: total}
		}
	ms := Buffer(64, 0), NumPut("UInt", 64, ms, 0) ; V1toV2: if 'ms' is a UTF-16 string, use 'VarSetStrCapacity(&ms, 64)' and replace all instances of 'ms.Ptr' with 'StrPtr(ms)'
	pcRam := DllCall("GlobalMemoryStatusEx", "Ptr", ms.Ptr) ? NumGet(ms, 4, "UInt") "%" : "?"
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
DashUpdButton()
	return

;Report a bug (BugReport.ahk): what went wrong, posted as an issue on GitHub
DashBugButton:
DashBugButton()
	return

;The Settings window (Settings.ahk): the mouse, the waits, how it plays its cards
DashSettingsButton:
DashSettingsButton()
	return

;"Learn every card" on/off (CardLearn.ahk)
DashLearnAll:
DashLearnAll()
	return

;The bot on/off (BotToggle in Autofarmer.ahk)
DashBotToggle:
DashBotToggle()
	return

;Simple / advanced view (dashboard.ini [view] dashboard): each view keeps its own place and size
DashViewToggle:
DashViewToggle()
	return

;"Bring Wizard101 to the front" on/off (GameFrontToggle in Autofarmer.ahk)
DashFrontToggle:
DashFrontToggle()
	return

;"Play for me" on/off (PlayForMeToggle in Autofarmer.ahk)
DashPlayToggle:
DashPlayToggle()
	return

;"Wait while I play" on/off (HandsOffToggle in Autofarmer.ahk)
DashHandsToggle:
DashHandsToggle()
	return

;(the window's X stops the bot - minimise it, or Windows+2, to just put it away)
DashGuiClose:
DashGuiClose()
	ExitApp()
	return

DashGuiSize:
DashGuiSize()
	return

;###############  V1toV2 FUNCS  ###############
DashMapButton(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	DashMapToggle()
	return
}
;##############################################
DashMapTick() { ; V1toV2: Lbl->Func
	global
	DashMapTick()
	return
}
;##############################################
MapGuiClose(*) { ; V1toV2: Lbl->Func
	global
	DashMapToggle()
	return
}
;##############################################
MapGuiSize(thisGui:="", MinMax:="", A_GuiWidth:="", A_GuiHeight:="") { ; V1toV2: Lbl->Func
	global
	if (A_EventInfo != 1)
		DashMapFit(A_GuiWidth, A_GuiHeight)
	return
}
;##############################################
DashRefresh() { ; V1toV2: Lbl->Func
	global
	DashRefresh()
	return
}
;##############################################
DashPauseLog(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	DashPaused := !DashPaused
	GuiControl, Dash:, DashPauseBtn, % DashPaused ? "Resume log" : "Pause log" ; V1toV2: Ternary not yet supported (coming soon)
	if (!DashPaused && DashHeld != "")
		DashAppend(DashHeld), DashHeld := ""
	return
}
;##############################################
DashClearLog(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	ogcCustomDashConsole.Value := ""
	return
}
;##############################################
DashNetListEvent(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (A_GuiEvent = "I" && InStr(ErrorLevel, "S"))
		{
		;Gui, Dash:ListView, NetList ; V1toV2: removed, but applied
		V1toV2_LineFill := true ; remove me after inspection
		DashNetId := ogcNetList.GetText(Info)
		if (DashNetId != NetSel)
			{
			;(kept by its PC: a bot started again has a new id)
			NetSelPc := ""
			if (DashNetId != "")
				NetSelPc := ogcNetList.GetText(Info)
			NetSel := DashNetId, NetLogAt := 0, NetSnapAt := "", NetRefresh := 1
			ogcEditNetLog.Value := ""
			ogcPictureNetPic.Visible := false
			GuiControl, Dash:, NetPicNote, % NetSel = "" ? "This PC - its log is the Bot tab's." : "Fetching its log and game..." ; V1toV2: Ternary not yet supported (coming soon)
			}
		}
	return
}
;##############################################
DashNetOn(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
global
A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
DashNetRestart()
}
;##############################################
DashNetOff(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
global
A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
DashNetRestart()
}
;##############################################
DashNetPfm(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
global
A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
DashNetRestart()
}
;##############################################
DashNetRestart(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	DashNetCmd := {DashNetOn: "on", DashNetOff: "off", DashNetPfm: "pfmoff", DashNetRestart: "restart"}[A_ThisLabel]
	DashSet("NetStatus", "Network: " NetSend(DashNetCmd))
	NetLogAt := A_TickCount - 4000
	return
}
;##############################################
DashNetRefresh(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	NetRefresh := 1
	return
}
;##############################################
DashLogColorsBtn(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	DashLogColorsWindow()
	return
}
;##############################################
DashLogColorPick(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	lcI := RegExReplace(A_GuiControl, "\D")
	lcKinds := DashLogKinds(), lcK := lcKinds[lcI], lcCols := DashLogColors()
	lcNew := DashPickColour(lcCols[lcK[1]], LogColHwnd)
	if (lcNew != "")
		{
		IniWrite(lcNew, A_ScriptDir "\dashboard.ini", "logcolors", lcK[1])
		DashLogColors(true)
		ogcLogColSw%lcI%.Opt("+Background" lcNew)
		DashLogRecolour()
		}
	return
}
;##############################################
DashLogColorReset(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	IniDelete(A_ScriptDir "\dashboard.ini", "logcolors")
	lcCols := DashLogColors(true), lcKinds := DashLogKinds()
	for lcI, lcK in lcKinds
		{
		lcCol := lcCols[lcK[1]]
		ogcLogColSw%lcI%.Opt("+Background" lcCol)
		}
	DashLogRecolour()
	return
}
;##############################################
DashLogColorClose(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
global
A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
LogColGuiEscape()
}
;##############################################
LogColGuiClose(*) { ; V1toV2: Lbl->Func
global
LogColGuiEscape()
}
;##############################################
LogColGuiEscape(*) { ; V1toV2: Lbl->Func
	global
	Try LogCol.Destroy()
	return
}
;##############################################
DashOpenLog(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	Run("notepad.exe `"" A_ScriptDir "\debug.log`"")
	return
}
;##############################################
DashWalkToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (IsFunc("WalkToggle"))
		WalkToggle.Call()
	return
}
;##############################################
DashFolder(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	Run(A_ScriptDir)
	return
}
;##############################################
DashUpdButton(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	;The Updates button: the usual check - a newer version offered (its notes), installed if you say so, the bot then
	;started again as it is now - or "you're up to date" (UpdCheckNow, as the tray menu's Check for updates).
	;"Checking..." and not clickable for 10 s
	if (UpdCheckNow())
		{
		DashUpdBusy := A_TickCount
		ogcButtonDashUpdBtn.Enabled := false
		DashRefresh()
		}
	return
}
;##############################################
DashBugButton(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (IsFunc("BugShow"))
		BugShow.Call()
	return
}
;##############################################
DashSettingsButton(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (IsFunc("CfgShow"))
		CfgShow.Call()
	return
}
;##############################################
DashLearnAll(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (IsFunc("LearnAllToggle"))
		LearnAllToggle.Call()
	return
}
;##############################################
DashBotToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (IsFunc("BotToggle"))
		BotToggle.Call()
	return
}
;##############################################
DashViewToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	DashSavePlace()
	DashSimple := !DashSimple
	IniWrite(DashSimple ? 1 : 0, A_ScriptDir "\dashboard.ini", "view", "dashboard")
	DashApplyView()
	DashShow()
	return
}
;##############################################
DashFrontToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (IsFunc("GameFrontToggle"))
		GameFrontToggle.Call()
	return
}
;##############################################
DashPlayToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (IsFunc("PlayForMeToggle"))
		PlayForMeToggle.Call()
	return
}
;##############################################
DashHandsToggle(A_GuiEvent:="", A_GuiControl:="", Info:="", *) { ; V1toV2: Lbl->Func
	global
	A_GuiControl := (A_GuiControl.Name) ? A_GuiControl.Name : (HasProp(A_GuiControl, "Text") ? A_GuiControl.Text : A_GuiControl)
	if (IsFunc("HandsOffToggle"))
		HandsOffToggle.Call()
	return
}
;##############################################
DashGuiClose(*) { ; V1toV2: Lbl->Func
	global
	DebugLog("Dashboard closed - the bot stops")
	ExitApp()
}
;##############################################
DashGuiSize(thisGui:="", MinMax:="", A_GuiWidth:="", A_GuiHeight:="") { ; V1toV2: Lbl->Func
	global
	if (A_EventInfo = 1)
		return
	;(GuiControl Move places a tab's controls from the tabs' inside, not the window's: where that starts, measured
	;once the window's up - a control moved to 0,0 there and where it lands read)
	if (DashTabOX = "")
		{
		ogcButtonDashPauseBtn.Move(0, 0)
		ogcButtonDashPauseBtn.GetPos(&DashTabOX, &DashTabOY, &DashTabOW, &DashTabOH)
		}
	ogcTextDashHead.Move(, , A_GuiWidth - 258)
	ogcProgressDashPlayBg.Move(A_GuiWidth - 116)
	ogcTextDashPlayBtn.Move(A_GuiWidth - 116)
	ogcButtonDashBugBtn.Move(A_GuiWidth - 240)
	ogcButtonDashUpdBtn.Move(A_GuiWidth - 144)
	ogcButtonDashMapBtn.Move(A_GuiWidth - 84 - DashTabOX)
	ogcButtonDashCfgBtn.Move(A_GuiWidth - 166 - DashTabOX)
	ogcDashSeeText.Move(, , A_GuiWidth - 384)
	ogcCustomDashConsole.Move(, , A_GuiWidth - 24, Max(40, A_GuiHeight - 352))
	ogcButtonDashColBtn.Move(A_GuiWidth - 90 - DashTabOX)
	;(the Cards tab: the Learn button at the right end of the hand's row, its heading up to it; the enemies' list takes
	;what's left)
	ogcButtonDashLearnBtn.Move(A_GuiWidth - 138 - DashTabOX)
	ogcTextDashHandHead.Move(, , A_GuiWidth - 154)
	ogcTextDashFoeHead.Move(, , A_GuiWidth - 24)
	ogcDashFoeList.Move(, , A_GuiWidth - 24, Max(40, A_GuiHeight - 290))
	;(a deck's view: its settings list takes what's left, the value's row under it; the right end's buttons at the right
	;end - the window can be narrower than they were placed for)
	ogcTextDeckFDmg.Move(, , A_GuiWidth - 24)
	ogcDeckFList.Move(, , A_GuiWidth - 24, Max(60, A_GuiHeight - 330))
	DashDeckRowY := Max(236 + 60 + 6, A_GuiHeight - 88) - DashTabOY
	ogcTextDeckFValT.Move(, DashDeckRowY + 4)
	ogcEditDeckFVal.Move(, DashDeckRowY + 1)
	ogcButtonDeckFValSet.Move(, DashDeckRowY)
	ogcButtonDeckFValClear.Move(, DashDeckRowY)
	ogcTextDeckFNote.Move(, DashDeckRowY + 4, Max(120, A_GuiWidth - 454))
	ogcButtonDeckAddBtn.Move(A_GuiWidth - 80 - DashTabOX)
	ogcButtonDeckFSave.Move(A_GuiWidth - 304 - DashTabOX)
	ogcButtonDeckFCopy.Move(A_GuiWidth - 208 - DashTabOX)
	ogcButtonDeckFDel.Move(A_GuiWidth - 112 - DashTabOX)
	ogcTextDeckFPriT.Move(A_GuiWidth - 154 - DashTabOX)
	ogcEditDeckFPri.Move(A_GuiWidth - 104 - DashTabOX)
	ogcTextDeckFSetN.Move(, , Max(80, A_GuiWidth - 544))
	ogcDropDownListDgDeck.Move(, , Min(260, Max(100, A_GuiWidth - 594)))
	;(the Network tab: the list across, the log under it on the left, the game's picture on the right)
	ogcTextNetHelp.Move(, , A_GuiWidth - 24)
	ogcTextNetStatus.Move(, , A_GuiWidth - 24)
	ogcNetList.Move(, , A_GuiWidth - 24)
	ogcEditNetLog.Move(, , Max(200, A_GuiWidth - 404), Max(40, A_GuiHeight - 360))
	ogcPictureNetPic.Move(A_GuiWidth - 384 - DashTabOX)
	ogcTextNetPicNote.Move(A_GuiWidth - 384 - DashTabOX)
	;(the tabs fill the window under the heading; the Dungeons tab's list takes what's left)
	ogcTab3DashTabs.Move(, , A_GuiWidth - 12, A_GuiHeight - 42)
	ogcTextDgHelp.Move(, , A_GuiWidth - 24)
	ogcTextDgStatus.Move(, , A_GuiWidth - 24)
	ogcDgList.Move(, , A_GuiWidth - 24, A_GuiHeight - 274)
	;(the Keys tab: its list takes what's left)
	ogcTextKeyHelp.Move(, , A_GuiWidth - 24)
	ogcTextKeyStatus.Move(, , A_GuiWidth - 24)
	ogcKeyList.Move(, , A_GuiWidth - 24, Max(60, A_GuiHeight - 202))
	;(the Spells tab: its list takes what's left of the picture on its right)
	ogcTextSpHelp.Move(, , A_GuiWidth - 24)
	ogcTextSpStatus.Move(, , A_GuiWidth - 24)
	ogcSpList.Move(, , A_GuiWidth - 172, A_GuiHeight - 202)
	ogcPictureSpPreview.Move(A_GuiWidth - 152 - DashTabOX)
	ogcTextSpPreviewTxt.Move(A_GuiWidth - 152 - DashTabOX, , , Max(40, A_GuiHeight - 440))
	;(the bottom row shares the width, each button in proportion to the width it was made with, so all fit at any
	;size - 620 at the least; the simple view: without the log's three)
	;(a label runs in the global scope: Dash-named variables only)
	DashRowList := [["DashBotBtn", 100], ["DashWalkBtn", 140], ["DashFolderBtn", 120], ["DashHandsBtn", 120], ["DashFrontBtn", 130], ["DashViewBtn", 110]]
	if (!DashSimple)
		DashRowList.InsertAt(1, ["DashPauseBtn", 100], ["DashClearBtn", 70], ["DashLogBtn", 110])
	DashRowSum := 0
	for DashRowI, DashRowB in DashRowList
		DashRowSum += DashRowB[2]
	DashRowX := 12, DashRowRoom := A_GuiWidth - 24 - 6 * (DashRowList.Length - 1)
	for DashRowI, DashRowB in DashRowList
		{
		DashRowW := Floor(DashRowRoom * DashRowB[2] / DashRowSum)
		ogc% DashRowB[1].Move(DashRowX - DashTabOX, A_GuiHeight - 36 - DashTabOY, DashRowW)
		DashRowX += DashRowW + 6
		}
	return
}

;(Windows+2 is in Autofarmer.ahk: it shows the dev-mode info box in dev mode)
