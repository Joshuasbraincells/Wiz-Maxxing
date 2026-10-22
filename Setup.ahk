; Setup.ahk - gets a PC ready to run the Wizard101 bot. Compiled to Setup.exe by build.ps1; it sits next to
; AutoFarmer\ and AutoQuester\. AutoHotkey v1.1.
;
; Each part shows whether it's there already; the ones that are missing are ticked. Install does the ticked
; ones, in order, writing what happens in the log below:
;   Install to your Programs folder   %LOCALAPPDATA%\Programs\Wiz-Maxxing (yours, no admin - the updater keeps
;                     working): the bot (and the watcher) closed, this folder copied there - over an install that's
;                     there already as an update does, its settings, learned cards and routes kept - then Setup
;                     starts from there and goes; that one does the rest of what was ticked (the shortcuts, Start
;                     menu, PATH and watcher now point there) and offers the download - the unpacked folder and the
;                     Wiz-Maxxing zip(s) beside it - to the Recycle Bin. Not for a git checkout
;   Python 3          the vision helper (card and badge matching) runs on it. winget installs it for you
;                     only (no admin); without winget, the installer from python.org
;   numpy and Pillow  the Python packages the vision helper uses (pip), then checked by importing them;
;                     katsuba too, as a spare reader of the game's zone files for the zone map (optional:
;                     the helper reads them itself)
;   Unblock files     Windows marks files that came from the internet and warns about every exe; this
;                     takes the mark off the bot's files
;   Start menu        a Wiz-Maxxing folder: Wiz-Maxxing (the bot), Wiz-Maxxing Setup, Stats reader, Quest walker only
;   Desktop shortcut  "Wiz-Maxxing" -> Wiz-Maxxing.exe (it starts AutoFarmer\Autofarmer.exe)
;   Run box and PATH  this folder on your PATH (type Wiz-Maxxing in a terminal) and Wiz-Maxxing.exe in "App
;                     Paths" (type Wiz-Maxxing in Win+R) - yours only, no admin
;   AutoHotkey v1.1   only to change the scripts and rebuild the exes (build.cmd); asks for admin
;   Git               only to get updates with git pull; asks for admin
;   GitHub updates    a read-only GitHub token, so Wiz-Maxxing can check for and download new versions when you
;                     open it (the repo is private): the token page opens, you paste the token, it's tested and
;                     kept in Windows Credential Manager (Updater.ahk)
#NoEnv
#SingleInstance force
SetWorkingDir, %A_ScriptDir%
SetBatchLines, -1

global SuLog, SuPyS, SuPkS, SuUnS, SuShS, SuAhS, SuGiS, SuPy, SuPk, SuUn, SuSh, SuAh, SuGi, SuGo, SuStart, SuSm, SuSmS, SuUp, SuUpS, SuPa, SuPaS
global SuWa, SuWaS, SuIn, SuInS
global SuLogHwnd := 0, SuBusy := 0
;(started again from the Programs folder after the copy: the folder it was in, the parts still to do, the old
;Setup's pid - /moved <folder> /do <py,pk,...> /oldpid <pid>)
global SuMovedFrom := "", SuMovedDo := "", SuMovedPid := 0, SuMovedSaved := ""
for suI, suA in A_Args
	{
	if (suA = "/moved")
		SuMovedFrom := RTrim(A_Args[suI + 1], "\")
	else if (suA = "/saved")
		SuMovedSaved := A_Args[suI + 1]
	else if (suA = "/do")
		SuMovedDo := A_Args[suI + 1]
	else if (suA = "/oldpid")
		SuMovedPid := A_Args[suI + 1] + 0
	}

if (!FileExist(A_ScriptDir "\AutoFarmer\Autofarmer.ahk"))
	{
	MsgBox, 48, Wizard101 bot setup, % "Setup.exe has to be in the bot's folder - next to AutoFarmer\ and AutoQuester\ (it's in " A_ScriptDir ")."
	ExitApp
	}

FileRead, suVersion, %A_ScriptDir%\version.txt
Gui, Su:New, , % "Wizard101 bot setup " Trim(suVersion, " `t`r`n")
Gui, Su:Margin, 14, 12
Gui, Su:Font, s11 w600, Segoe UI
Gui, Su:Add, Text, w620, Get this PC ready to run the Wizard101 bot
Gui, Su:Font, s9 w400, Segoe UI
Gui, Su:Add, Text, w620 y+4, The ticked parts get installed. Python and its packages are needed for the card matching and the zone map; the last two are only for changing the bot.
Gui, Su:Add, Checkbox, xm y+14 w260 vSuIn, Install to your Programs folder
Gui, Su:Add, Text, x+8 w350 vSuInS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuPy, Python 3
Gui, Su:Add, Text, x+8 w350 vSuPyS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuPk, numpy and Pillow (Python packages)
Gui, Su:Add, Text, x+8 w350 vSuPkS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuUn, Unblock the bot's files
Gui, Su:Add, Text, x+8 w350 vSuUnS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuUp, GitHub updates (a token, once)
Gui, Su:Add, Text, x+8 w350 vSuUpS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuSm, Start menu (Wiz-Maxxing)
Gui, Su:Add, Text, x+8 w350 vSuSmS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuSh, Desktop shortcut "Wiz-Maxxing"
Gui, Su:Add, Text, x+8 w350 vSuShS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuPa, Run box and PATH (Win+R: Wiz-Maxxing)
Gui, Su:Add, Text, x+8 w350 vSuPaS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuWa, Open with Wizard101 (F6 starts it)
Gui, Su:Add, Text, x+8 w350 vSuWaS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuAh, AutoHotkey v1.1 (to rebuild the exes)
Gui, Su:Add, Text, x+8 w350 vSuAhS, ...
Gui, Su:Add, Checkbox, xm y+8 w260 vSuGi, Git (to get updates with git pull)
Gui, Su:Add, Text, x+8 w350 vSuGiS, ...
Gui, Su:Add, Button, xm y+16 w120 h28 gSuInstall vSuGo Default, Install
Gui, Su:Add, Button, x+10 w140 h28 gSuStartBot vSuStart, Start the bot
Gui, Su:Add, Button, x+10 w90 h28 gSuGuiClose, Close
Gui, Su:Font, s9, Consolas
Gui, Su:Add, Edit, xm y+12 w620 h240 ReadOnly -Wrap +HScroll vSuLog HwndSuLogHwnd
Gui, Su:Show
SuCheck(true)
;(started from the Programs folder after the copy: the parts that were ticked, and the shortcuts / Start menu / PATH /
;watcher that point to the old folder - SuCheck ticks those - done; then the download offered to the Recycle Bin)
if (SuMovedFrom != "")
	{
	SuMovedPrep()
	gosub, SuInstall
	SuOfferDelete(SuMovedFrom)
	}
return

;Before the moved-on install: the parts that were ticked ticked again, the old Setup gone, the old folder off the PATH
SuMovedPrep()
	{
	SuLogLine("Installed in " A_ScriptDir " - doing the rest here")
	;(never copied on again from here; the parts exactly as they were ticked - plus what still points into the old
	;folder, which may go to the Recycle Bin: the shortcuts, the watcher, the PATH)
	GuiControl, Su:, SuIn, 0
	for each, code in ["py", "pk", "un", "up", "sm", "sh", "pa", "wa", "ah", "gi"]
		GuiControl, Su:, % "Su" code, % InStr("," SuMovedDo ",", "," code ",") ? 1 : 0
	if (SuLinkHere(A_Programs "\Wiz-Maxxing\Wiz-Maxxing.lnk", SuMovedFrom))
		GuiControl, Su:, SuSm, 1
	if (SuLinkHere(A_Desktop "\Wiz-Maxxing.lnk", SuMovedFrom))
		GuiControl, Su:, SuSh, 1
	if (SuLinkHere(WatchLink(), SuMovedFrom))
		GuiControl, Su:, SuWa, 1
	RegRead, oldPath, HKCU\Environment, Path
	if (SuInPath(oldPath, SuMovedFrom))
		GuiControl, Su:, SuPa, 1
	;(the old Setup gone, so its folder can go)
	if (SuMovedPid)
		Process, WaitClose, %SuMovedPid%, 15
	;(the old folder off your PATH - this one goes on it)
	GuiControlGet, pa, Su:, SuPa
	if (pa)
		SuRemovePath(SuMovedFrom)
	}

;What's there already. tick: tick the missing parts (the first look)
SuCheck(tick := false)
	{
	home := SuHome()
	notOwn := SuOwnFolder(A_ScriptDir)
	newer := SuNewerThere(home)
	if (SuSamePath(A_ScriptDir, home))
		SuShow("SuIn", "SuInS", true, "installed: " SuShort(home), tick)
	else if (FileExist(A_ScriptDir "\.git") != "")
		SuShow("SuIn", "SuInS", true, "a git checkout - it stays where it is (git pull updates it)", tick)
	else if (notOwn != "")
		SuShow("SuIn", "SuInS", false, "can't from here: " notOwn " - put the bot's files in a folder of their own", tick, false)
	else if (newer != "")
		SuShow("SuIn", "SuInS", true, "a newer version (" newer ") is installed - start that one", tick)
	else
		SuShow("SuIn", "SuInS", false, "runs from " SuShort(A_ScriptDir) " - copies itself to " SuShort(home), tick)
	py := SuPython()
	SuShow("SuPy", "SuPyS", py != "", py != "" ? "found: " SuShort(py) : "not installed", tick)
	pk := py != "" && SuRun("""" py """ -c ""import numpy, PIL""", false) = 0
	SuShow("SuPk", "SuPkS", pk, pk ? "installed" : (py = "" ? "needs Python first" : "not installed"), tick)
	marked := SuMarkedCount()
	SuShow("SuUn", "SuUnS", marked = 0, marked = 0 ? "nothing blocked" : marked " file(s) marked as downloaded", tick)
	up := UpToken() != ""
	SuShow("SuUp", "SuUpS", up, up ? "token saved - Wiz-Maxxing checks for updates when you open it" : "no token yet", tick)
	sm := SuLinkHere(A_Programs "\Wiz-Maxxing\Wiz-Maxxing.lnk")
	SuShow("SuSm", "SuSmS", sm, sm ? "in the Start menu" : FileExist(A_Programs "\Wiz-Maxxing\Wiz-Maxxing.lnk") ? "there, but for another folder" : "not there", tick)
	sc := SuLinkHere(A_Desktop "\Wiz-Maxxing.lnk")
	SuShow("SuSh", "SuShS", sc, sc ? "on the desktop" : FileExist(A_Desktop "\Wiz-Maxxing.lnk") ? "there, but for another folder" : "not there", tick)
	pa := SuPathOk()
	SuShow("SuPa", "SuPaS", pa, pa ? "Win+R or a terminal: Wiz-Maxxing" : "not set up", tick)
	wa := WatchIsOn() && SuLinkHere(WatchLink())
	SuShow("SuWa", "SuWaS", wa, wa ? "on - the bot opens in standby when the game starts" : WatchIsOn() ? "on, but for another folder" : "off (the bot's tray menu switches it too)", tick, WatchIsOn())
	ahk := SuAhk()
	SuShow("SuAh", "SuAhS", ahk != "", ahk != "" ? "found: " SuShort(ahk) : "not installed (only needed to rebuild)", tick, false)
	git := SuWhere("git.exe")
	SuShow("SuGi", "SuGiS", git != "", git != "" ? "found" : "not installed (only for updates)", tick, false)
	}

;A part's status; tick it when it's missing (and wanted by default)
SuShow(box, label, ok, text, tick, wanted := true)
	{
	GuiControl, Su:, %label%, % (ok ? "OK - " : "") text
	if (tick)
		GuiControl, Su:, %box%, % (!ok && wanted) ? 1 : 0
	}

SuInstall:
	if (SuBusy)
		return
	Gui, Su:Submit, NoHide
	SuBusy := 1
	GuiControl, Su:Disable, SuGo
	;(first: copied to the Programs folder - Setup starts again from there and does the rest; this one goes)
	if (SuIn)
		{
		suHomeRes := SuInstallHome()
		if (suHomeRes = 1)
			ExitApp
		if (suHomeRes = -1)
			{
			SuLogLine("")
			SuLogLine("Stopped: nothing else was done (see above). Untick ""Install to your Programs folder"" to set this folder up as it is.")
			GuiControl, Su:Enable, SuGo
			SuBusy := 0
			return
			}
		}
	if (SuPy)
		SuInstallPython()
	if (SuPk)
		SuInstallPackages()
	if (SuUn)
		SuUnblock()
	if (SuUp)
		SuToken()
	if (SuSm)
		SuStartMenu()
	if (SuSh)
		SuShortcut()
	if (SuPa)
		SuAddPath()
	if (SuWa)
		{
		SuLogLine("== Open with Wizard101")
		SuLogLine(WatchSet(A_ScriptDir, true) ? "on: a watcher starts with Windows (" WatchLink() ") and opens the bot in standby when Wizard101 starts - press F6 in the game to start it" : "couldn't make the Startup folder's shortcut")
		}
	if (SuAh)
		SuInstallAhk()
	if (SuGi)
		SuInstallGit()
	SuLogLine("")
	SuLogLine("Done. The statuses above are looked at again.")
	SuCheck()
	GuiControl, Su:Enable, SuGo
	SuBusy := 0
	return

SuStartBot:
	;(the launcher - its exe, or its script when Setup runs as one: Watch.ahk BotProgram)
	if (FileExist(A_ScriptDir "\Wiz-Maxxing.exe") || FileExist(A_ScriptDir "\Wiz-Maxxing.ahk"))
		{
		BotRun(A_ScriptDir "\Wiz-Maxxing", "", A_ScriptDir)
		return
		}
	if (FileExist(A_ScriptDir "\AutoFarmer\Autofarmer.exe") || SuAhk() != "")
		BotRun(A_ScriptDir "\AutoFarmer\Autofarmer", "", A_ScriptDir "\AutoFarmer")
	else
		MsgBox, 48, Wizard101 bot setup, % "There's no AutoFarmer\Autofarmer.exe here - download the zip from the GitHub Releases page (it has the exes), or install AutoHotkey v1.1 and run build.cmd."
	return

SuGuiClose:
SuGuiEscape:
	if (SuBusy)
		{
		MsgBox, 52, Wizard101 bot setup, Setup is still installing. Close anyway?
		IfMsgBox, No
			return
		}
	ExitApp

;---- the parts ----

;A line in the log, and code back (for a return)
SuSay(text, code)
	{
	SuLogLine(text)
	return code
	}

;Your own Programs folder's Wiz-Maxxing (%LOCALAPPDATA%\Programs\Wiz-Maxxing: no admin needed, as Discord and VS Code)
SuHome()
	{
	EnvGet, la, LOCALAPPDATA
	return (la = "" ? A_AppData "\..\Local" : la) "\Programs\Wiz-Maxxing"
	}

;Whether two folders are the same (any case, with or without a trailing \)
SuSamePath(a, b)
	{
	return RTrim(a, "\") = RTrim(b, "\")
	}

;Whether shortcut lnk is there and starts something in this folder (in: another) - its own folder, or the script it
;runs
SuLinkHere(lnk, in := "")
	{
	if (!FileExist(lnk))
		return false
	FileGetShortcut, %lnk%, target, dir, args
	here := RTrim(in = "" ? A_ScriptDir : in, "\") "\"
	return InStr(target, here) = 1 || InStr(dir "\", here) = 1 || InStr(args, here)
	}

;Why folder dir isn't the bot's own ("" if it is): a whole drive, a folder of yours (the Desktop, Documents,
;Downloads, your profile, OneDrive...), or one with other things in it besides the bot's - those are never copied
;into the Programs folder or offered to the Recycle Bin. contentsToo false: only whether it's a drive or such a folder
SuOwnFolder(dir, contentsToo := true)
	{
	dir := RTrim(dir, "\")
	if (RegExMatch(dir, "^[A-Za-z]:$") || RegExMatch(dir, "^\\\\[^\\]+\\[^\\]+$"))
		return "it's a whole drive"
	EnvGet, prof, USERPROFILE
	EnvGet, od1, OneDrive
	EnvGet, od2, OneDriveConsumer
	EnvGet, od3, OneDriveCommercial
	for i, k in [A_Desktop, A_DesktopCommon, A_MyDocuments, prof, prof "\Downloads", SuKnownFolder("{374DE290-123F-4565-9164-39C4925E467B}")
		, od1, od2, od3, A_ProgramFiles, A_WinDir, A_Temp, A_AppData, RegExReplace(SuHome(), "\\[^\\]+$")]
		if (k != "" && SuSamePath(dir, k))
			return "it's " k " itself"
	if (!contentsToo)
		return ""
	Loop, Files, %dir%\*, FD
		if (!RegExMatch(A_LoopFileName, "i)^(\.git.*|\.github|AutoFarmer|AutoPetTrainer|AutoQuester|assets|backups|README\.md|Setup\.(ahk|exe)|Updater\.ahk|Watch\.ahk|Wiz-Maxxing\.(ahk|exe)|build\.(cmd|ps1)|version\.txt|updater\.(ini|log)|.+\.old|desktop\.ini|Thumbs\.db)$"))
			return "it has other things in it too (" A_LoopFileName ")"
	return ""
	}

;A known folder's path (guid: its FOLDERID), "" if Windows doesn't say
SuKnownFolder(guid)
	{
	VarSetCapacity(id, 16, 0)
	if (DllCall("ole32\CLSIDFromString", "WStr", guid, "Ptr", &id) != 0)
		return ""
	if (DllCall("shell32\SHGetKnownFolderPath", "Ptr", &id, "UInt", 0, "Ptr", 0, "Ptr*", p) != 0 || !p)
		return ""
	path := StrGet(p, "UTF-16")
	DllCall("ole32\CoTaskMemFree", "Ptr", p)
	return path
	}

;The version installed in home when it's newer than this folder's ("" if not, or none there)
SuNewerThere(home)
	{
	if (!FileExist(home "\AutoFarmer\Autofarmer.ahk"))
		return ""
	FileRead, theirs, %home%\version.txt
	FileRead, mine, %A_ScriptDir%\version.txt
	theirs := Trim(theirs, " `t`r`n"), mine := Trim(mine, " `t`r`n")
	return (theirs != "" && UpCompare(theirs, mine) > 0) ? theirs : ""
	}

;When the bot last ran from folder dir (its debug.log's time, else the last run's; 0 never)
SuLastRun(dir)
	{
	for i, f in [dir "\AutoFarmer\debug.log", dir "\AutoFarmer\debug.previous.log"]
		if (FileExist(f))
			{
			FileGetTime, at, %f%, M
			return at + 0
			}
	return 0
	}

;Your files in folder from (settings, learned cards, routes, the walker's memory: the updater's UpIsMine - not the
;logs, backups or made pictures) copied into folder to, as they lie. How many
SuCopyMine(from, to)
	{
	slots := UpLearnedSlots(from "\AutoFarmer\learned\cards.txt")
	n := 0
	Loop, Files, %from%\*, FR
		{
		rel := SubStr(A_LoopFileFullPath, StrLen(from) + 2)
		if (RegExMatch(rel, "i)(^|\\)(backups|generated)\\|\.log$") || !UpIsMine(rel, slots))
			continue
		target := to "\" rel
		SplitPath, target, , targetDir
		FileCreateDir, %targetDir%
		FileCopy, %A_LoopFileFullPath%, %target%, 1
		if (!ErrorLevel)
			n++
		}
	return n
	}

;The install stopped: the watcher started again if it was closed for it (closedWatch), and -1 back
SuInstallStop(text, closedWatch)
	{
	SuLogLine(text)
	if (closedWatch && WatchIsOn())
		Run, % WatchLink(), , UseErrorLevel
	return -1
	}

;Copies the bot to SuHome and starts Setup from there (the rest of what's ticked, /do) - 1 if it did (this Setup
;then goes), 0 if there was nothing to do (here already), -1 if it couldn't (nothing else is done)
SuInstallHome()
	{
	SuLogLine("== Install to your Programs folder")
	home := SuHome()
	if (SuSamePath(A_ScriptDir, home))
		return SuSay("installed here already", 0)
	if (FileExist(A_ScriptDir "\.git") != "")
		return SuSay("this is a git checkout - it stays where it is", 0)
	if (InStr(home "\", A_ScriptDir "\") = 1 || InStr(A_ScriptDir "\", home "\") = 1)
		return SuSay("this folder and " home " are inside each other - move this folder somewhere else first", -1)
	notOwn := SuOwnFolder(A_ScriptDir)
	if (notOwn != "")
		return SuSay("not from " A_ScriptDir ": " notOwn " - put the bot's files in a folder of their own (unzip the download as it is) and run Setup there", -1)
	newer := SuNewerThere(home)
	if (newer != "")
		return SuSay("a newer version (" newer ") is installed there - start that one (Start menu: Wiz-Maxxing); this older one isn't put over it", -1)
	if (WatchBotRunning())
		{
		MsgBox, 262180, Wiz-Maxxing setup, The bot is running. Close it to install it in your Programs folder?
		IfMsgBox, No
			return SuSay("the bot is running - not installed", -1)
		}
	;(the bot from here and from there, and the watcher - they keep their files open)
	UpCloseBots(A_ScriptDir)
	UpCloseBots(home)
	DetectHiddenWindows, On
	closedWatch := WatchPids().Length() > 0
	for i, pid in WatchPids()
		{
		WinClose, ahk_pid %pid% ahk_class AutoHotkey
		Process, WaitClose, %pid%, 5
		if (ErrorLevel)
			Process, Close, %pid%
		}
	FileRead, ver, %A_ScriptDir%\version.txt
	ver := Trim(ver, " `t`r`n")
	if (FileExist(home "\AutoFarmer\Autofarmer.ahk"))
		{
		;(an install there already: this version's files over it - all or nothing, as an update does. Your settings,
		;learned cards and routes: the folder the bot ran from last keeps them in use, the other's are saved in the
		;install's backups\ - nothing lost)
		oldWins := SuLastRun(A_ScriptDir) > SuLastRun(home)
		FormatTime, stamp, , yyyy-MM-dd HHmm
		SplitPath, A_ScriptDir, , oldParent
		SplitPath, oldParent, oldParentName
		saved := home "\backups\install " stamp (oldWins ? " - the install's own before" : " - from " oldParentName)
		SuLogLine("an install is there already - copying this version over it")
		rollback := A_Temp "\wiz-maxxing-install-rollback"
		FileRemoveDir, %rollback%, 1
		res := UpCopy(A_ScriptDir, home, rollback)
		if (res.failed.Length())
			{
			UpRollback(res, home, rollback)
			FileRemoveDir, %rollback%, 1
			return SuInstallStop("couldn't write " res.failed.Length() " file(s) there (in use?) - put back as it was: " res.failed[1], closedWatch)
			}
		FileRemoveDir, %rollback%, 1
		if (oldWins)
			{
			n := SuCopyMine(home, saved)
			SuLogLine("the bot ran from here last: your settings, learned cards and routes from here are used there (the install's own " n " file(s) saved in " saved ")")
			SuCopyMine(A_ScriptDir, home)
			}
		else
			{
			n := SuCopyMine(A_ScriptDir, saved)
			SuLogLine("the install's own settings, learned cards and routes stay in use (this folder's " n " file(s) saved in " saved ")")
			}
		UpMergeStats(A_ScriptDir "\AutoFarmer\PlayerStats.txt", home "\AutoFarmer\PlayerStats.txt", ver)
		FileCopy, %A_ScriptDir%\version.txt, %home%\version.txt, 1
		SuLogLine(res.copied " file(s) copied")
		}
	else
		{
		existed := InStr(FileExist(home), "D")
		FileCreateDir, %home%
		FileCopyDir, %A_ScriptDir%, %home%, 1
		if (ErrorLevel || !FileExist(home "\AutoFarmer\Autofarmer.ahk"))
			{
			;(half a copy must never count as an install)
			if (!existed)
				FileRemoveDir, %home%, 1
			return SuInstallStop("couldn't copy everything to " home " (in use? the disk full?) - nothing installed", closedWatch)
			}
		saved := ""
		SuLogLine("copied to " home " - with your settings, learned cards and routes")
		}
	do := ""
	for each, code in ["py", "pk", "un", "up", "sm", "sh", "pa", "wa", "ah", "gi"]
		if (Su%code%)
			do .= (do = "" ? "" : ",") code
	if (!BotRun(home "\Setup", "/moved """ A_ScriptDir """ /do " (do = "" ? "-" : do) " /oldpid " DllCall("GetCurrentProcessId") (saved = "" ? "" : " /saved """ saved """"), home))
		return SuInstallStop("installed in " home ", but its Setup didn't start - start it there yourself (Start menu or " home "\Setup)", closedWatch)
	return 1
	}

;Your PATH without folder dir (and its App Paths entry, if it's that folder's)
SuRemovePath(dir, envKey := "HKCU\Environment")
	{
	RegRead, path, %envKey%, Path
	if (!SuInPath(path, dir))
		return
	keep := ""
	Loop, Parse, path, `;
		if (Trim(A_LoopField) != "" && RTrim(Trim(A_LoopField), "\") != RTrim(dir, "\"))
			keep .= (keep = "" ? "" : ";") A_LoopField
	RegWrite, REG_EXPAND_SZ, %envKey%, Path, %keep%
	SuLogLine(ErrorLevel ? "couldn't take the old folder off your PATH" : "the old folder taken off your PATH: " dir)
	}

;The download offered to the Recycle Bin once it's installed: the folder it was unpacked to (the outer
;Wiz-Maxxing-v... one too, when it holds nothing else) and the Wiz-Maxxing zip(s) beside it. Never the install, a
;git checkout, or a folder that isn't the bot's
SuOfferDelete(old)
	{
	home := SuHome()
	old := RTrim(old, "\")
	if (old = "" || !FileExist(old "\AutoFarmer\Autofarmer.ahk") || SuSamePath(old, home)
		|| InStr(home "\", old "\") = 1 || InStr(old "\", home "\") = 1 || FileExist(old "\.git") != "" || SuOwnFolder(old) != "")
		return
	top := old
	SplitPath, old, , parent
	SplitPath, parent, parentName, grand
	zipDir := parent
	if (RegExMatch(parentName, "i)^Wiz-Maxxing") && grand != "" && SuOnlyChild(parent, old) && SuOwnFolder(parent, false) = "")
		top := parent, zipDir := grand
	zips := []
	Loop, Files, %zipDir%\Wiz-Maxxing*.zip
		zips.Push(A_LoopFileFullPath)
	list := "`n   " top
	for i, z in zips
		list .= "`n   " z
	note := SuMovedSaved = "" ? "(Everything was copied over - your settings, learned cards and routes too.)"
		: "(The settings, learned cards and routes in use are in the install; the other copy was saved in`n   " SuMovedSaved ")"
	MsgBox, 262436, Wiz-Maxxing setup, % "Wiz-Maxxing is installed in`n   " home "`n`nMove the download to the Recycle Bin?" list "`n`n" note
	IfMsgBox, No
		return SuLogLine("the download was left where it is")
	SuLogLine("== The download to the Recycle Bin")
	for i, f in [top]
		{
		;(the old bot's vision helper can take a few seconds to go after the bot)
		Loop, 5
			{
			FileRecycle, %f%
			if (!FileExist(f))
				break
			Sleep, 1500
			}
		SuLogLine(FileExist(f) ? "couldn't move " f " (still in use? an Explorer window open in it?) - delete it yourself" : "to the Recycle Bin: " f)
		}
	for i, z in zips
		{
		FileRecycle, %z%
		SuLogLine(FileExist(z) ? "couldn't move " z : "to the Recycle Bin: " z)
		}
	}

;Whether folder parent holds child and nothing else
SuOnlyChild(parent, child)
	{
	n := 0, other := false
	Loop, Files, %parent%\*, FD
		{
		n++
		if (!SuSamePath(A_LoopFileFullPath, child))
			other := true
		}
	return n = 1 && !other
	}

SuInstallPython()
	{
	SuLogLine("== Python 3")
	if (SuPython() != "")
		return SuLogLine("already installed: " SuPython())
	if (SuWhere("winget.exe") != "")
		{
		SuLogLine("installing with winget (for you only - no admin)...")
		SuRun("winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements")
		}
	if (SuPython() = "")
		{
		url := "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe"
		file := A_Temp "\python-3.12.7-amd64.exe"
		SuLogLine("downloading the installer from python.org: " url)
		UrlDownloadToFile, %url%, %file%
		if (ErrorLevel || !FileExist(file))
			return SuLogLine("couldn't download it - check the internet connection, or install Python 3 from https://www.python.org/downloads/ (tick 'Add python.exe to PATH')")
		SuLogLine("installing (for you only)...")
		RunWait, "%file%" /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1, , UseErrorLevel
		SuLogLine("installer finished (exit " ErrorLevel ")")
		FileDelete, %file%
		}
	py := SuPython()
	SuLogLine(py != "" ? "Python is ready: " py : "Python still isn't found - install it from https://www.python.org/downloads/ and run Setup again")
	}

SuInstallPackages()
	{
	SuLogLine("== numpy and Pillow (and katsuba, optional)")
	SuLogLine("numpy and Pillow: the card matching and the zone map. katsuba: a spare reader of the game's zone files")
	py := SuPython()
	if (py = "")
		return SuLogLine("needs Python first")
	SuRun("""" py """ -m pip install --user --upgrade numpy pillow")
	ok := SuRun("""" py """ -c ""import numpy, PIL; print('numpy', numpy.__version__, '- Pillow', PIL.__version__)""") = 0
	SuLogLine(ok ? "the vision helper's packages load" : "they don't load - see the messages above")
	;(on its own and optional: the helper reads the zone files itself; katsuba is only its spare)
	SuRun("""" py """ -m pip install --user --upgrade katsuba")
	kt := SuRun("""" py """ -c ""import katsuba""") = 0
	SuLogLine(kt ? "katsuba loads" : "katsuba didn't install - that's fine, it's only a spare (nothing needs it)")
	}

SuUnblock()
	{
	SuLogLine("== Unblock the bot's files")
	before := SuMarkedCount()
	SuRun("powershell -NoProfile -ExecutionPolicy Bypass -Command ""Get-ChildItem -LiteralPath '" A_ScriptDir "' -Recurse -File | Unblock-File""")
	SuLogLine(before " file(s) were marked; " SuMarkedCount() " still are")
	}

SuShortcut()
	{
	SuLogLine("== Desktop shortcut")
	p := SuBotProgram()
	FileCreateShortcut, % p.target, %A_Desktop%\Wiz-Maxxing.lnk, %A_ScriptDir%, % p.args, Wiz-Maxxing - the Wizard101 bot (battles and quest walking)
	SuLogLine(ErrorLevel ? "couldn't make it" : "made: " A_Desktop "\Wiz-Maxxing.lnk -> " p.target (p.args = "" ? "" : " " p.args))
	;(the one an earlier Setup made, by its old name)
	if (FileExist(A_Desktop "\Wizard101 bot.lnk"))
		{
		FileGetShortcut, %A_Desktop%\Wizard101 bot.lnk, old
		if (InStr(old, A_ScriptDir) = 1)
			FileDelete, %A_Desktop%\Wizard101 bot.lnk
		}
	}

;Start menu: a Wiz-Maxxing folder with the bot, Setup, the stats reader and the quest walker on its own (only
;the ones that are here). Start-menu search finds them ("Wiz-Maxxing")
SuStartMenu(menuDir := "")
	{
	SuLogLine("== Start menu")
	if (menuDir = "")
		menuDir := A_Programs "\Wiz-Maxxing"
	FileCreateDir, %menuDir%
	made := 0
	;(each its exe - or its script when Setup runs as one: Watch.ahk BotProgram)
	for each, e in [["Wiz-Maxxing", "", A_ScriptDir, "The Wizard101 bot: battles and quest walking"]
		, ["Wiz-Maxxing Setup", A_ScriptDir "\Setup", A_ScriptDir, "Installs what the bot needs"]
		, ["Stats reader", A_ScriptDir "\AutoFarmer\StatsReader", A_ScriptDir "\AutoFarmer", "Reads your wizard's stats for the kill check"]
		, ["Quest walker only", A_ScriptDir "\AutoQuester\AutoQuester", A_ScriptDir "\AutoQuester", "Walks to the quest goal, no battles"]]
		{
		p := e[2] = "" ? SuBotProgram() : BotProgram(e[2])
		if (!FileExist(p.target) || (e[2] != "" && !FileExist(e[2] ".exe") && !FileExist(e[2] ".ahk")))
			continue
		FileCreateShortcut, % p.target, % menuDir "\" e[1] ".lnk", % e[3], % p.args, % e[4]
		if (!ErrorLevel)
			made++, SuLogLine("made: " e[1] " -> " p.target (p.args = "" ? "" : " " p.args))
		}
	SuLogLine(made ? made " shortcut(s) in " menuDir " - search the Start menu for Wiz-Maxxing" : "couldn't make any")
	}

;The GitHub token for updates: the page to make one opens, you paste it (hidden), it's tried, then kept in
;Windows Credential Manager. It's never shown or logged
SuToken()
	{
	SuLogLine("== GitHub updates")
	if (UpToken() != "" && UpTokenTest(UpToken()) = "")
		return SuLogLine("the saved token works")
	Run, https://github.com/settings/personal-access-tokens/new
	MsgBox, 64, GitHub updates, % "A GitHub page opened (sign in if it asks). Make a token there:`n`n1. Token name: Wiz-Maxxing updates`n2. Expiration: the longest it offers (or No expiration)`n3. Repository access: Only select repositories -> Wiz-Maxxing`n4. Permissions -> Repository permissions -> Contents: Read-only, and Issues: Read and write (for the dashboard's Report a bug)`n5. Generate token, then copy it`n`nClick OK, then paste it into the next box."
	InputBox, token, GitHub updates, Paste the token (it's kept in Windows Credential Manager on this PC only):, HIDE, 560, 150
	if (ErrorLevel || Trim(token) = "")
		return SuLogLine("no token entered")
	token := Trim(token)
	why := UpTokenTest(token)
	if (why != "")
		{
		token := ""
		return SuLogLine("not saved: " why)
		}
	saved := UpTokenSave(token)
	token := ""
	SuLogLine(saved ? "saved - Wiz-Maxxing now checks for updates whenever you open it" : "couldn't save it in Credential Manager")
	}

;---- PATH and App Paths (envKey / appKey: other keys for tests) ----

;Whether this folder is on your PATH and Wiz-Maxxing.exe is in App Paths
SuPathOk(envKey := "HKCU\Environment", appKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\Wiz-Maxxing.exe")
	{
	RegRead, path, %envKey%, Path
	RegRead, app, %appKey%
	return SuInPath(path, A_ScriptDir) && app = A_ScriptDir "\Wiz-Maxxing.exe"
	}

;Whether dir is one of path's folders (any case, with or without a trailing \)
SuInPath(path, dir)
	{
	dir := RTrim(dir, "\")
	Loop, Parse, path, `;
		if (RTrim(Trim(A_LoopField), "\") = dir)
			return true
	return false
	}

;Adds this folder to your PATH (your own, kept as it is otherwise) and Wiz-Maxxing.exe to App Paths, then
;tells Windows (new terminals and the Run box see it; already open ones don't)
SuAddPath(envKey := "HKCU\Environment", appKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\Wiz-Maxxing.exe")
	{
	SuLogLine("== Run box and PATH")
	RegRead, path, %envKey%, Path
	if (SuInPath(path, A_ScriptDir))
		SuLogLine("this folder is on your PATH already")
	else
		{
		newPath := (Trim(path) = "" ? "" : RTrim(path, "; ") ";") A_ScriptDir
		RegWrite, REG_EXPAND_SZ, %envKey%, Path, %newPath%
		SuLogLine(ErrorLevel ? "couldn't add it to your PATH" : "added to your PATH: " A_ScriptDir)
		}
	exe := A_ScriptDir "\Wiz-Maxxing.exe"
	if (!FileExist(exe))
		return SuLogLine("no Wiz-Maxxing.exe here - the Run box entry is skipped")
	;(Setup run as a script - Smart App Control: the exe would be blocked; the shortcuts start the scripts)
	if (!A_IsCompiled)
		return SuLogLine("Setup runs as a script (Smart App Control?) - the Run box entry is skipped: use the Start menu or desktop shortcut")
	RegWrite, REG_SZ, %appKey%, , %exe%
	RegWrite, REG_SZ, %appKey%, Path, %A_ScriptDir%
	SuLogLine(ErrorLevel ? "couldn't add it to App Paths" : "Win+R: type Wiz-Maxxing")
	;(WM_SETTINGCHANGE "Environment" to every window)
	DllCall("SendMessageTimeout", "Ptr", 0xFFFF, "UInt", 0x1A, "Ptr", 0, "Str", "Environment", "UInt", 2, "UInt", 3000, "Ptr*", result)
	}

;What starts the bot ({target, args}): the launcher (Wiz-Maxxing - its exe, or its script when Setup runs as one),
;else AutoFarmer\Autofarmer
SuBotProgram()
	{
	if (FileExist(A_ScriptDir "\Wiz-Maxxing.exe") || FileExist(A_ScriptDir "\Wiz-Maxxing.ahk"))
		return BotProgram(A_ScriptDir "\Wiz-Maxxing")
	return BotProgram(A_ScriptDir "\AutoFarmer\Autofarmer")
	}

SuInstallAhk()
	{
	SuLogLine("== AutoHotkey v1.1")
	if (SuAhk() != "")
		return SuLogLine("already installed: " SuAhk())
	url := "https://www.autohotkey.com/download/ahk-install.exe"
	file := A_Temp "\ahk-v1-install.exe"
	SuLogLine("downloading the v1.1 installer from autohotkey.com...")
	UrlDownloadToFile, %url%, %file%
	if (ErrorLevel || !FileExist(file))
		return SuLogLine("couldn't download it - get it from https://www.autohotkey.com/download/1.1/")
	SuLogLine("installing (Windows asks for admin)...")
	RunWait, "%file%" /S, , UseErrorLevel
	FileDelete, %file%
	SuLogLine(SuAhk() != "" ? "AutoHotkey v1.1 is ready - build.cmd can rebuild the exes" : "it isn't found after the installer (exit " ErrorLevel ") - get it from https://www.autohotkey.com/download/1.1/")
	}

SuInstallGit()
	{
	SuLogLine("== Git")
	if (SuWhere("git.exe") != "")
		return SuLogLine("already installed")
	if (SuWhere("winget.exe") = "")
		return SuLogLine("no winget here - install Git from https://git-scm.com/download/win")
	SuLogLine("installing with winget (Windows asks for admin)...")
	SuRun("winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements")
	SuLogLine(SuWhere("git.exe") != "" ? "Git is ready (open a new PowerShell window to use it)" : "Git isn't found yet - open a new window, or install it from https://git-scm.com/download/win")
	}

;---- finding things ----

;python.exe whose pythonw.exe the bot's vision helper will find (Vision.ahk: on the PATH or in
;%LOCALAPPDATA%\Programs\Python\Python3*) - never the Microsoft Store stub (WindowsApps)
SuPython()
	{
	EnvGet, pathVar, PATH
	Loop, Parse, pathVar, `;
		{
		dir := Trim(A_LoopField)
		if (dir != "" && !InStr(dir, "WindowsApps") && FileExist(dir "\pythonw.exe") && FileExist(dir "\python.exe"))
			return dir "\python.exe"
		}
	best := ""
	Loop, Files, %A_AppData%\..\Local\Programs\Python\Python3*, D
		if (FileExist(A_LoopFileFullPath "\pythonw.exe") && FileExist(A_LoopFileFullPath "\python.exe"))
			best := A_LoopFileFullPath "\python.exe"
	return best
	}

;Ahk2Exe with a v1.1 base, i.e. what build.cmd needs ("" if not): the v1 installer's .bin, or v1.1's
;AutoHotkeyU64.exe (the v2 installer puts v1.1 in a v1.1.x folder)
SuAhk()
	{
	for each, root in [A_ProgramFiles "\AutoHotkey", A_AppData "\..\Local\Programs\AutoHotkey"]
		{
		if (!FileExist(root "\Compiler\Ahk2Exe.exe"))
			continue
		if (FileExist(root "\Compiler\Unicode 64-bit.bin") || FileExist(root "\AutoHotkeyU64.exe"))
			return root
		Loop, Files, %root%\v1.1*, D
			if (FileExist(A_LoopFileFullPath "\AutoHotkeyU64.exe"))
				return root
		}
	return ""
	}

;A program on the PATH (as the system sees it now: after an install the PATH of this process is old)
SuWhere(exe)
	{
	RegRead, sysPath, HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment, Path
	RegRead, userPath, HKCU\Environment, Path
	EnvGet, procPath, PATH
	all := procPath ";" sysPath ";" userPath
	Loop, Parse, all, `;
		{
		dir := Trim(A_LoopField)
		if (dir = "")
			continue
		;(%USERPROFILE% and the like, as the registry keeps them)
		if (InStr(dir, "%"))
			{
			VarSetCapacity(buf, 4096 * 2, 0)
			DllCall("ExpandEnvironmentStrings", "Str", dir, "Str", buf, "UInt", 4096)
			dir := buf
			}
		if (FileExist(dir "\" exe))
			return dir "\" exe
		}
	if (exe = "winget.exe" && FileExist(A_AppData "\..\Local\Microsoft\WindowsApps\winget.exe"))
		return A_AppData "\..\Local\Microsoft\WindowsApps\winget.exe"
	return ""
	}

;How many of the bot's files carry the "downloaded from the internet" mark (Zone.Identifier)
SuMarkedCount()
	{
	tmp := A_Temp "\su_marked.txt"
	RunWait, % ComSpec " /c powershell -NoProfile -ExecutionPolicy Bypass -Command ""(Get-ChildItem -LiteralPath '" A_ScriptDir "' -Recurse -File | Get-Item -Stream Zone.Identifier -ErrorAction SilentlyContinue | Measure-Object).Count"" > """ tmp """ 2>nul", , Hide UseErrorLevel
	FileRead, n, %tmp%
	FileDelete, %tmp%
	n := Trim(n, " `t`r`n")
	return (n ~= "^\d+$") ? n + 0 : 0
	}

;---- running and the log ----

;Runs a command hidden and puts what it printed in the log (log false: quietly). Its exit code
SuRun(cmd, log := true)
	{
	tmp := A_Temp "\su_out_" A_TickCount ".txt"
	if (log)
		SuLogLine("> " cmd)
	RunWait, % ComSpec " /c """ cmd " > """ tmp """ 2>&1""", %A_ScriptDir%, Hide UseErrorLevel
	code := ErrorLevel
	if (log)
		{
		FileRead, out, %tmp%
		;(progress bars: only what's left after the last carriage return of each line)
		text := ""
		Loop, Parse, out, `n
			{
			;(a line can also end in two: pip's do)
			line := RegExReplace(RTrim(A_LoopField, "`r"), "s).*\r", "")
			line := RTrim(RegExReplace(line, "[^\x20-\x7E]", ""), " ")
			if (line != "" && !RegExMatch(line, "^[\s\-\\|/]+$"))
				text .= "   " line "`r`n"
			}
		if (text != "")
			SuAppend(text)
		SuLogLine("  (exit code " code ")")
		}
	FileDelete, %tmp%
	return code
	}

SuLogLine(text)
	{
	SuAppend(text "`r`n")
	}

SuAppend(text)
	{
	len := DllCall("GetWindowTextLength", "Ptr", SuLogHwnd)
	DllCall("SendMessage", "Ptr", SuLogHwnd, "UInt", 0xB1, "Ptr", len, "Ptr", len)
	DllCall("SendMessage", "Ptr", SuLogHwnd, "UInt", 0xC2, "Ptr", 0, "Str", text)
	DllCall("SendMessage", "Ptr", SuLogHwnd, "UInt", 0xB7, "Ptr", 0, "Ptr", 0)
	}

;A long path shortened for the status column
SuShort(path)
	{
	return StrLen(path) > 48 ? "..." SubStr(path, -44) : path
	}

#Include %A_ScriptDir%\Updater.ahk
#Include %A_ScriptDir%\Watch.ahk
