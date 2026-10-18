; Setup.ahk - gets a PC ready to run the Wizard101 bot. Compiled to Setup.exe by build.ps1; it sits next to
; AutoFarmer\ and AutoQuester\. AutoHotkey v1.1.
;
; Each part shows whether it's there already; the ones that are missing are ticked. Install does the ticked
; ones, in order, writing what happens in the log below:
;   Python 3          the vision helper (card and badge matching) runs on it. winget installs it for you
;                     only (no admin); without winget, the installer from python.org
;   numpy and Pillow  the Python packages the vision helper uses (pip), then checked by importing them
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
global SuLogHwnd := 0, SuBusy := 0

if (!FileExist(A_ScriptDir "\AutoFarmer\Autofarmer.ahk"))
	{
	MsgBox, 48, Wizard101 bot setup, % "Setup.exe has to be in the bot's folder - next to AutoFarmer\ and AutoQuester\ (it's in " A_ScriptDir ")."
	ExitApp
	}

Gui, Su:New, , Wizard101 bot setup
Gui, Su:Margin, 14, 12
Gui, Su:Font, s11 w600, Segoe UI
Gui, Su:Add, Text, w620, Get this PC ready to run the Wizard101 bot
Gui, Su:Font, s9 w400, Segoe UI
Gui, Su:Add, Text, w620 y+4, The ticked parts get installed. Python and its packages are needed for the card matching; the last two are only for changing the bot.
Gui, Su:Add, Checkbox, xm y+14 w260 vSuPy, Python 3
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
return

;What's there already. tick: tick the missing parts (the first look)
SuCheck(tick := false)
	{
	py := SuPython()
	SuShow("SuPy", "SuPyS", py != "", py != "" ? "found: " SuShort(py) : "not installed", tick)
	pk := py != "" && SuRun("""" py """ -c ""import numpy, PIL""", false) = 0
	SuShow("SuPk", "SuPkS", pk, pk ? "installed" : (py = "" ? "needs Python first" : "not installed"), tick)
	marked := SuMarkedCount()
	SuShow("SuUn", "SuUnS", marked = 0, marked = 0 ? "nothing blocked" : marked " file(s) marked as downloaded", tick)
	up := UpToken() != ""
	SuShow("SuUp", "SuUpS", up, up ? "token saved - Wiz-Maxxing checks for updates when you open it" : "no token yet", tick)
	sm := FileExist(A_Programs "\Wiz-Maxxing\Wiz-Maxxing.lnk") != ""
	SuShow("SuSm", "SuSmS", sm, sm ? "in the Start menu" : "not there", tick)
	sc := FileExist(A_Desktop "\Wiz-Maxxing.lnk") != ""
	SuShow("SuSh", "SuShS", sc, sc ? "on the desktop" : "not there", tick)
	pa := SuPathOk()
	SuShow("SuPa", "SuPaS", pa, pa ? "Win+R or a terminal: Wiz-Maxxing" : "not set up", tick)
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
	exe := A_ScriptDir "\Wiz-Maxxing.exe"
	if (FileExist(exe))
		{
		Run, "%exe%", %A_ScriptDir%
		return
		}
	exe := A_ScriptDir "\AutoFarmer\Autofarmer.exe"
	if (FileExist(exe))
		Run, "%exe%", %A_ScriptDir%\AutoFarmer
	else if (SuAhk() != "")
		Run, "%A_ScriptDir%\AutoFarmer\Autofarmer.ahk", %A_ScriptDir%\AutoFarmer
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
	SuLogLine("== numpy and Pillow")
	py := SuPython()
	if (py = "")
		return SuLogLine("needs Python first")
	SuRun("""" py """ -m pip install --user --upgrade numpy pillow")
	ok := SuRun("""" py """ -c ""import numpy, PIL; print('numpy', numpy.__version__, '- Pillow', PIL.__version__)""") = 0
	SuLogLine(ok ? "the vision helper's packages load" : "they don't load - see the messages above")
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
	target := SuBotExe()
	FileCreateShortcut, %target%, %A_Desktop%\Wiz-Maxxing.lnk, %A_ScriptDir%, , Wiz-Maxxing - the Wizard101 bot (battles and quest walking)
	SuLogLine(ErrorLevel ? "couldn't make it" : "made: " A_Desktop "\Wiz-Maxxing.lnk -> " target)
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
	for each, e in [["Wiz-Maxxing", SuBotExe(), A_ScriptDir, "The Wizard101 bot: battles and quest walking"]
		, ["Wiz-Maxxing Setup", A_ScriptDir "\Setup.exe", A_ScriptDir, "Installs what the bot needs"]
		, ["Stats reader", A_ScriptDir "\AutoFarmer\StatsReader.exe", A_ScriptDir "\AutoFarmer", "Reads your wizard's stats for the kill check"]
		, ["Quest walker only", A_ScriptDir "\AutoQuester\AutoQuester.exe", A_ScriptDir "\AutoQuester", "Walks to the quest goal, no battles"]]
		{
		if (!FileExist(e[2]))
			continue
		FileCreateShortcut, % e[2], % menuDir "\" e[1] ".lnk", % e[3], , % e[4]
		if (!ErrorLevel)
			made++, SuLogLine("made: " e[1] " -> " e[2])
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
	MsgBox, 64, GitHub updates, % "A GitHub page opened (sign in if it asks). Make a token there:`n`n1. Token name: Wiz-Maxxing updates`n2. Expiration: the longest it offers (or No expiration)`n3. Repository access: Only select repositories -> Wiz-Maxxing`n4. Permissions -> Repository permissions -> Contents: Read-only`n5. Generate token, then copy it`n`nClick OK, then paste it into the next box."
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
	RegWrite, REG_SZ, %appKey%, , %exe%
	RegWrite, REG_SZ, %appKey%, Path, %A_ScriptDir%
	SuLogLine(ErrorLevel ? "couldn't add it to App Paths" : "Win+R: type Wiz-Maxxing")
	;(WM_SETTINGCHANGE "Environment" to every window)
	DllCall("SendMessageTimeout", "Ptr", 0xFFFF, "UInt", 0x1A, "Ptr", 0, "Str", "Environment", "UInt", 2, "UInt", 3000, "Ptr*", result)
	}

;What starts the bot: Wiz-Maxxing.exe, else AutoFarmer\Autofarmer.exe, else the script
SuBotExe()
	{
	for each, f in [A_ScriptDir "\Wiz-Maxxing.exe", A_ScriptDir "\AutoFarmer\Autofarmer.exe"]
		if (FileExist(f))
			return f
	return A_ScriptDir "\AutoFarmer\Autofarmer.ahk"
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
