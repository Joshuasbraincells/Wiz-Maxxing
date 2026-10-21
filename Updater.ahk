; Updater.ahk - checks GitHub for a newer Wiz-Maxxing release and, if you say so, installs it. AHK v1.1,
; functions only; #Included by Wiz-Maxxing.ahk (it checks every time you open the bot) and Setup.ahk (which
; stores the token). The tray menu's "Check for updates" runs Wiz-Maxxing.exe /check.
;
; The repo is private, so it reads it with a GitHub token (fine-grained, read-only Contents on the repo),
; kept in Windows Credential Manager as "Wiz-Maxxing GitHub" - never in a file, never in the log.
; This folder's version is version.txt (e.g. v0.10; none = older than any release). Releases are numbered
; v0.01, v0.02, ... v0.99, v1.00, v1.01.
;
; Updating: the release zip is downloaded, the bot is closed if it's running, and the zip's files are
; copied over this folder - except your own: PlayerStats.txt (only settings it doesn't have yet are added),
; learned cards (learned\ folders, and the slot pictures learned\cards.txt says they went into), dungeon runs, potion
; routes, the walker's memory, window positions, logs. A program that's in use (Wiz-Maxxing.exe, Setup.exe)
; is renamed out of the way and the new one put in its place. It's all or nothing: every file it replaces
; is copied aside first, and if any file can't be written the folder is put back as it was, version.txt
; and all. Only then is version.txt set to the release's tag. Log: updater.log.

;(tests only: another address for GitHub's API, a token, and yes to the question)
global UpTestApi, UpTestToken, UpTestYes

;(the repo, and the token's name in Credential Manager - functions, since a global's starting value in an
;#Included file never runs)
UpRepo()
	{
	return "Joshuasbraincells/Wiz-Maxxing"
	}

UpApi()
	{
	return UpTestApi != "" ? UpTestApi : "https://api.github.com"
	}

UpCredTarget()
	{
	return "Wiz-Maxxing GitHub"
	}

;---- the check ----

;Looks for a newer release and asks to install it. quiet: no message when there's nothing to do or it can't
;check (opening the bot). True if it updated (the bot's files were replaced)
UpCheck(quiet := true)
	{
	UpCleanup()
	token := UpToken()
	if (token = "")
		{
		if (!quiet)
			MsgBox, 262192, Wiz-Maxxing updates, % "There's no GitHub token on this PC, so updates can't be checked.`n`nRun Setup.exe and tick ""GitHub updates"" to add one."
		return false
		}
	rel := UpLatest(token, err, status)
	token := ""
	if (!IsObject(rel))
		{
		UpPeekSave("", err)
		UpLog("check failed: " err)
		;(an expired or revoked token: said once even when opening the bot, else updates stop unnoticed)
		IniRead, warned, %A_ScriptDir%\updater.ini, token, warned, 0
		if (!UpTestYes && (!quiet || ((status = 401 || status = 403) && !warned)))
			MsgBox, 262192, Wiz-Maxxing updates, % "Couldn't check for updates:`n" err
		if ((status = 401 || status = 403) && quiet)
			IniWrite, 1, %A_ScriptDir%\updater.ini, token, warned
		return false
		}
	IniWrite, 0, %A_ScriptDir%\updater.ini, token, warned
	UpPeekSave(rel.tag, "")
	have := UpVersion()
	UpLog("installed " (have = "" ? "(no version.txt)" : have) ", latest " rel.tag)
	if (UpCompare(rel.tag, have) <= 0)
		{
		if (!quiet)
			MsgBox, 262208, Wiz-Maxxing updates, % "You're up to date (" (have = "" ? rel.tag : have) ")."
		return false
		}
	notes := rel.body
	notes := RegExReplace(notes, "\*\*|__|``", "")
	if (StrLen(notes) > 700)
		notes := SubStr(notes, 1, 700) "..."
	if (!UpTestYes)
		MsgBox, 262180, Wiz-Maxxing update, % "A new version is out: " rel.name "`n(you have " (have = "" ? "an older one" : have) ")`n`n" notes "`n`nUpdate now? Your settings, learned cards and potion routes are kept."
	IfMsgBox, No
		{
		UpLog("you chose not to update to " rel.tag " now")
		return false
		}
	;(installed meanwhile - by another check: nothing to do)
	if (UpCompare(rel.tag, UpVersion()) <= 0)
		return false
	return UpInstall(rel)
	}

;Only looks (Wiz-Maxxing /latest - the bot's dashboard runs it now and then): the latest release's tag, or why it
;couldn't be looked up, into updater.ini [latest] - no question, no install, no message
UpPeek()
	{
	token := UpToken()
	if (token = "")
		{
		UpPeekSave("", "no GitHub token on this PC (Setup.exe: GitHub updates)")
		return
		}
	rel := UpLatest(token, err, status)
	token := ""
	UpPeekSave(IsObject(rel) ? rel.tag : "", IsObject(rel) ? "" : err)
	}

;The latest release's tag (or why it couldn't be looked up) for the dashboard: updater.ini [latest]. A failed
;look-up keeps the tag it last found (a newer version is still out) and says why it can't check
UpPeekSave(tag, err)
	{
	if (tag != "")
		IniWrite, %tag%, %A_ScriptDir%\updater.ini, latest, tag
	IniWrite, % RegExReplace(err, "[\r\n]+", " "), %A_ScriptDir%\updater.ini, latest, err
	IniWrite, %A_Now%, %A_ScriptDir%\updater.ini, latest, at
	}

;One update check / install at a time, across all the bot's processes (the dashboard's button clicked twice, the
;watcher's check, the tray's): true when this one may go on - else the other one's question is brought forward
UpOnlyOne()
	{
	static mutex := 0
	if (mutex)
		return true
	mutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Wiz-Maxxing update", "Ptr")
	if (A_LastError != 183)
		return true
	DllCall("CloseHandle", "Ptr", mutex)
	mutex := 0
	WinActivate, Wiz-Maxxing update ahk_class #32770
	WinActivate, Wiz-Maxxing updates ahk_class #32770
	return false
	}

;"v0.10" vs "v0.09": 1 newer, 0 same, -1 older ("" counts as older than any)
UpCompare(a, b)
	{
	if (b = "")
		return a = "" ? 0 : 1
	;(vMAJOR.MAIN.BUG - v0.14 is v0.14.0)
	if (!RegExMatch(a, "(\d+)\.(\d+)(?:\.(\d+))?", x) || !RegExMatch(b, "(\d+)\.(\d+)(?:\.(\d+))?", y))
		return a = b ? 0 : 1
	pa := [x1 + 0, x2 + 0, x3 = "" ? 0 : x3 + 0], pb := [y1 + 0, y2 + 0, y3 = "" ? 0 : y3 + 0]
	Loop, 3
		if (pa[A_Index] != pb[A_Index])
			return pa[A_Index] > pb[A_Index] ? 1 : -1
	return 0
	}

;This folder's version (version.txt), "" if none
UpVersion()
	{
	FileRead, v, %A_ScriptDir%\version.txt
	return Trim(v, " `t`r`n")
	}

;The latest release: {tag, name, body, zipUrl, zipName}; "" and err on a problem
UpLatest(token, ByRef err, ByRef status := 0)
	{
	err := ""
	resp := UpHttp(UpApi() "/repos/" UpRepo() "/releases/latest", token, "application/vnd.github+json", status, 8000)
	if (status = 401 || status = 403)
		{
		err := "GitHub refused the token (" status ") - it may have expired. Make a new one and add it with Setup.exe."
		return ""
		}
	if (status = 404)
		{
		err := "GitHub says there's no release - or the token can't see the repo (404)."
		return ""
		}
	if (status != 200)
		{
		err := (status = 0 ? "no answer from GitHub (offline?)" : "GitHub answered " status)
		return ""
		}
	rel := {}
	RegExMatch(resp, """tag_name"":\s*""([^""]+)""", m), rel.tag := m1
	RegExMatch(resp, """tag_name"":.*?""name"":\s*""((?:[^""\\]++|\\.)*+)""", m), rel.name := UpUnescape(m1)
	RegExMatch(resp, """body"":\s*""((?:[^""\\]++|\\.)*+)""", m), rel.body := UpUnescape(m1)
	;(the zip among the assets: its API url downloads it)
	if (RegExMatch(resp, """url"":\s*""([^""]+/releases/assets/\d+)"",\s*""id"":\s*\d+,\s*""node_id"":\s*""[^""]*"",\s*""name"":\s*""([^""]+\.zip)""", m))
		rel.zipUrl := m1, rel.zipName := m2
	if (rel.tag = "")
		{
		err := "couldn't read GitHub's answer"
		return ""
		}
	if (rel.name = "")
		rel.name := rel.tag
	return rel
	}

;---- installing ----

UpInstall(rel)
	{
	if (rel.zipUrl = "")
		{
		MsgBox, 48, Wiz-Maxxing update, % rel.tag " has no zip to download - get it from the GitHub Releases page."
		return false
		}
	Progress, b w360 zh0 fs10, % "Downloading " rel.zipName "...", Wiz-Maxxing update
	tmp := A_Temp "\wiz-maxxing-update"
	FileRemoveDir, %tmp%, 1
	FileCreateDir, %tmp%
	zip := tmp "\" rel.zipName
	token := UpToken()
	ok := UpDownload(rel.zipUrl, token, zip, err)
	token := ""
	if (!ok)
		{
		Progress, Off
		UpLog("download failed: " err)
		MsgBox, 48, Wiz-Maxxing update, % "The download failed: " err "`n`nNothing was changed."
		return false
		}
	Progress, , Unpacking...
	RunWait, % "powershell -NoProfile -ExecutionPolicy Bypass -Command ""try { Expand-Archive -LiteralPath '" zip "' -DestinationPath '" tmp "\unzipped' -Force -ErrorAction Stop } catch { exit 1 }""", , Hide UseErrorLevel
	unzipped := (ErrorLevel = 0)
	src := ""
	Loop, Files, %tmp%\unzipped\*, D
		src := A_LoopFileFullPath
	if (!unzipped || src = "" || !FileExist(src "\AutoFarmer\Autofarmer.ahk"))
		{
		Progress, Off
		UpLog("the zip didn't unpack (" zip ")")
		MsgBox, 48, Wiz-Maxxing update, The downloaded zip didn't unpack - nothing was changed.
		FileRemoveDir, %tmp%, 1
		return false
		}
	Progress, , Closing the bot...
	UpCloseBots()
	Progress, , Copying the new files...
	res := UpCopy(src, A_ScriptDir, tmp "\rollback")
	if (res.failed.Length())
		{
		UpRollback(res)
		Progress, Off
		list := ""
		for i, f in res.failed
			list .= "`n   " f
		UpLog("update to " rel.tag " failed - put back as it was; couldn't write: " SubStr(StrReplace(list, "`n   ", " | "), 4))
		if (!UpTestYes)
			MsgBox, 48, Wiz-Maxxing update, % "The update couldn't replace these files, so everything was put back as it was:" list "`n`nClose anything that has them open (Setup, an editor, the bot, the 'Open with Wizard101' watcher: its tray icon > Stop watching) and try again - the update is offered again next time."
		FileRemoveDir, %tmp%, 1
		return false
		}
	UpMergeStats(src "\AutoFarmer\PlayerStats.txt", A_ScriptDir "\AutoFarmer\PlayerStats.txt", rel.tag)
	;(the version is the release's tag - only now, with every file in place)
	FileDelete, %A_ScriptDir%\version.txt
	FileAppend, % rel.tag "`r`n", %A_ScriptDir%\version.txt
	FileRemoveDir, %tmp%, 1
	Progress, Off
	UpLog("updated to " rel.tag ": " res.copied " file(s) replaced or added, " res.kept " of yours kept")
	TrayTip, Wiz-Maxxing, % "Updated to " rel.tag ".", 5, 1
	return true
	}

;Closes the bot's programs running from this folder (dir: another): its exes, or its scripts run by AutoHotkey -
;nothing else (an editor that has a script open is left alone). Politely first; forced only if it's an AutoHotkey
;program
UpCloseBots(dir := "")
	{
	if (dir = "")
		dir := A_ScriptDir
	DetectHiddenWindows, On
	pids := []
	bots := "i)^(AutoFarmer\\Autofarmer|AutoFarmer\\StatsReader|AutoQuester\\AutoQuester)\."
	for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, ExecutablePath, CommandLine FROM Win32_Process")
		{
		path := p.ExecutablePath, cmd := p.CommandLine
		if (p.ProcessId = DllCall("GetCurrentProcessId") || path = "")
			continue
		mine := false
		;(an exe of the bot, in this folder)
		if (InStr(path, dir "\") = 1 && RegExMatch(SubStr(path, StrLen(dir) + 2), bots "exe$"))
			mine := true
		;(AutoHotkey running one of the bot's scripts from this folder: the script is its first argument)
		else if (RegExMatch(path, "i)\\AutoHotkey[^\\]*\.exe$") && RegExMatch(cmd, "i)""?([A-Z]:\\[^""]+?\.ahk)""?", m)
			&& InStr(m1, dir "\") = 1 && RegExMatch(SubStr(m1, StrLen(dir) + 2), bots "ahk$"))
			mine := true
		if (mine && WinExist("ahk_pid " p.ProcessId " ahk_class AutoHotkey"))
			pids.Push(p.ProcessId)
		}
	for i, pid in pids
		WinClose, ahk_pid %pid% ahk_class AutoHotkey
	for i, pid in pids
		{
		Process, WaitClose, %pid%, 10
		if (ErrorLevel)
			Process, Close, %pid%
		UpLog("closed the running bot (pid " pid ")")
		}
	Sleep, % pids.Length() ? 1500 : 0
	}

;Copies the new release's files over the folder, keeping yours (UpIsMine) - every file it replaces copied to
;rollback first, a file in use renamed out of the way. Returns {copied, kept, failed: [], backups: [],
;created: [], renamed: []} for UpRollback
UpCopy(src, dest, rollback)
	{
	res := {copied: 0, kept: 0, failed: [], backups: [], created: [], renamed: []}
	slots := UpLearnedSlots(dest "\AutoFarmer\learned\cards.txt", src "\AutoFarmer\learned\cards.txt")
	Loop, Files, %src%\*, FR
		{
		rel := SubStr(A_LoopFileFullPath, StrLen(src) + 2)
		;(set from the release's tag once everything is in place)
		if (rel = "version.txt")
			continue
		target := dest "\" rel
		exists := FileExist(target) != ""
		;(nor one the bot took away itself, making room for a stronger learned hit: learned\slots_written.txt)
		if ((exists && UpIsMine(rel, slots)) || (!exists && InStr(rel, "AutoFarmer\") = 1 && slots.HasKey("file:" Format("{:L}", SubStr(rel, 12)))))
			{
			res.kept++
			continue
			}
		SplitPath, target,, targetDir
		FileCreateDir, %targetDir%
		if (exists)
			{
			FileCreateDir, % RegExReplace(rollback "\" rel, "\\[^\\]*$")
			FileCopy, %target%, %rollback%\%rel%, 1
			if (ErrorLevel)
				{
				res.failed.Push(rel)
				continue
				}
			res.backups.Push(rel)
			}
		FileCopy, %A_LoopFileFullPath%, %target%, 1
		;(in use - a running program: moved aside, deleted next time. A .old still in use - the watcher's own image
		;from an earlier update - can't be replaced: another name)
		if (ErrorLevel && exists)
			{
			old := target ".old"
			if (FileExist(old))
				FileDelete, %old%
			if (FileExist(old))
				old := target "." A_TickCount ".old"
			FileMove, %target%, %old%, 1
			if (!ErrorLevel)
				{
				res.renamed.Push({rel: rel, old: old})
				FileCopy, %A_LoopFileFullPath%, %target%, 1
				}
			}
		if (ErrorLevel)
			{
			res.failed.Push(rel)
			continue
			}
		if (!exists)
			res.created.Push(rel)
		res.copied++
		}
	return res
	}

;Puts the folder (dest: another) back as it was before UpCopy (rollback: the folder UpCopy was given)
UpRollback(res, dest := "", rollback := "")
	{
	if (dest = "")
		dest := A_ScriptDir
	if (rollback = "")
		rollback := A_Temp "\wiz-maxxing-update\rollback"
	for i, rel in res.created
		FileDelete, %dest%\%rel%
	for i, r in res.renamed
		{
		FileDelete, % dest "\" r.rel
		FileMove, % r.old, % dest "\" r.rel, 1
		}
	for i, rel in res.backups
		FileCopy, %rollback%\%rel%, %dest%\%rel%, 1
	UpLog("put back: " res.backups.Length() " file(s) restored, " res.created.Length() " new one(s) removed")
	}

;The slots learned cards went into ("balance\hit2", ...), from this folder's and the release's catalog - and the slot
;pictures the bot moved itself (making room for a stronger learned hit: learned\slots_written.txt next to the
;catalog, paths in the AutoFarmer folder) as "file:<path>"
UpLearnedSlots(files*)
	{
	slots := {}
	for i, f in files
		{
		Loop, Read, %f%
			{
			if (SubStr(A_LoopReadLine, 1, 1) = ";")
				continue
			fld := StrSplit(A_LoopReadLine, "|")
			if (fld.Length() >= 8 && fld[8] != "")
				slots[Format("{:L}", fld[8])] := 1
			}
		SplitPath, f,, fdir
		Loop, Read, %fdir%\slots_written.txt
			if (Trim(A_LoopReadLine) != "")
				slots["file:" Format("{:L}", Trim(A_LoopReadLine))] := 1
		}
	return slots
	}

;Files that are yours: kept when they're here already
UpIsMine(rel, slots)
	{
	if (RegExMatch(rel, "i)^AutoFarmer\\(PlayerStats\.txt|dashboard\.ini|resources\\characters\.txt)$"))
		return true
	if (RegExMatch(rel, "i)(^|\\)(learned|routes|backups|generated|dungeons)\\"))
		return true
	if (RegExMatch(rel, "i)^AutoQuester\\resources\\(walk_memory|known_zones)\.txt$"))
		return true
	if (RegExMatch(rel, "i)\.(log|ini)$"))
		return true
	;(a slot picture a card was learned into - in any picture set - and its solid copy)
	if (RegExMatch(rel, "i)^AutoFarmer\\(?:ui[\d.]+\\)?(\w+\\\w+?)(?:\.raw)?\.png$", m) && slots.HasKey(Format("{:L}", m1)))
		return true
	;(a slot picture the bot moved there itself: learned\slots_written.txt)
	if (InStr(rel, "AutoFarmer\") = 1 && slots.HasKey("file:" Format("{:L}", SubStr(rel, 12))))
		return true
	return false
	}

;The new release's PlayerStats.txt settings this one doesn't have yet are added at the end (with their
;comment); yours are left as they are
UpMergeStats(newFile, myFile, tag)
	{
	if (!FileExist(myFile) || !FileExist(newFile))
		return
	FileRead, mine, %myFile%
	have := {}
	Loop, Parse, mine, `n, `r
		if (RegExMatch(A_LoopField, "^\s*([\w.]+)\s*:", m))
			have[Format("{:L}", m1)] := 1
	add := "", comment := ""
	Loop, Read, %newFile%
		{
		line := A_LoopReadLine
		if (RegExMatch(line, "^\s*;"))
			{
			comment .= line "`r`n"
			continue
			}
		if (RegExMatch(line, "^\s*([\w.]+)\s*:", m) && !have.HasKey(Format("{:L}", m1)))
			add .= comment line "`r`n"
		comment := ""
		}
	if (add = "")
		return
	FileAppend, % "`r`n; ---- Added by the update to " tag " (new settings; yours above are kept) ----`r`n" add, %myFile%
	UpLog("added new settings to PlayerStats.txt")
	}

;What a past update moved aside (programs that were in use)
UpCleanup()
	{
	Loop, Files, %A_ScriptDir%\*.old, FR
		FileDelete, %A_LoopFileFullPath%
	}

;---- GitHub and the token ----

;GET url with the token; the answer's text, status in status (0 = no answer). Sent without waiting and
;polled, so the time limit holds
UpHttp(url, token, accept, ByRef status, timeoutMs := 8000)
	{
	status := 0
	try
		{
		req := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", url, true)
		req.SetRequestHeader("User-Agent", "Wiz-Maxxing-updater")
		req.SetRequestHeader("Accept", accept)
		req.SetRequestHeader("X-GitHub-Api-Version", "2022-11-28")
		if (token != "")
			req.SetRequestHeader("Authorization", "Bearer " token)
		req.Send()
		t0 := A_TickCount
		while (!req.WaitForResponse(0))
			{
			if (A_TickCount - t0 > timeoutMs)
				{
				req.Abort()
				return ""
				}
			Sleep, 20
			}
		status := req.Status
		return req.ResponseText
		}
	catch e
		return ""
	}

;Downloads a release asset (the API sends it on to a storage address, which mustn't get the token)
UpDownload(assetUrl, token, file, ByRef err)
	{
	err := ""
	try
		{
		req := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		req.Option(6) := false
		req.Open("GET", assetUrl, true)
		req.SetRequestHeader("User-Agent", "Wiz-Maxxing-updater")
		req.SetRequestHeader("Accept", "application/octet-stream")
		if (token != "")
			req.SetRequestHeader("Authorization", "Bearer " token)
		req.Send()
		if (!UpWait(req, 20000))
			{
			err := "no answer from GitHub"
			return false
			}
		url := assetUrl
		if (req.Status = 302 || req.Status = 301 || req.Status = 307)
			{
			url := req.GetResponseHeader("Location")
			req := ComObjCreate("WinHttp.WinHttpRequest.5.1")
			req.Open("GET", url, true)
			req.SetRequestHeader("User-Agent", "Wiz-Maxxing-updater")
			req.Send()
			if (!UpWait(req, 180000))
				{
				err := "the download took too long"
				return false
				}
			}
		if (req.Status != 200)
			{
			err := "GitHub answered " req.Status
			return false
			}
		stream := ComObjCreate("ADODB.Stream")
		stream.Type := 1
		stream.Open()
		stream.Write(req.ResponseBody)
		stream.SaveToFile(file, 2)
		stream.Close()
		}
	catch e
		{
		err := IsObject(e) ? e.Message : e
		return false
		}
	FileGetSize, size, %file%
	err := (size > 100000 ? "" : "the file came down empty")
	return size > 100000
	}

UpWait(req, timeoutMs)
	{
	t0 := A_TickCount
	while (!req.WaitForResponse(0))
		{
		if (A_TickCount - t0 > timeoutMs)
			{
			req.Abort()
			return false
			}
		Sleep, 30
		}
	return true
	}

;The token from Windows Credential Manager ("" none)
UpToken()
	{
	if (UpTestToken != "")
		return UpTestToken
	credPtr := 0, token := ""
	is64 := (A_PtrSize = 8)
	VarSetCapacity(targetW, (StrLen(UpCredTarget()) + 1) * 2, 0), StrPut(UpCredTarget(), &targetW, "UTF-16")
	if (!DllCall("Advapi32\CredReadW", "Ptr", &targetW, "UInt", 1, "UInt", 0, "Ptr*", credPtr) || !credPtr)
		return ""
	blobSize := NumGet(credPtr + 0, is64 ? 32 : 24, "UInt")
	blobPtr := NumGet(credPtr + 0, is64 ? 40 : 28, "Ptr")
	if (blobPtr && blobSize)
		token := StrGet(blobPtr, blobSize // 2, "UTF-16")
	DllCall("Advapi32\CredFree", "Ptr", credPtr)
	return Trim(token)
	}

;Stores the token in Windows Credential Manager. True if it did
UpTokenSave(token)
	{
	is64 := (A_PtrSize = 8)
	user := "github-token"
	VarSetCapacity(targetW, (StrLen(UpCredTarget()) + 1) * 2, 0), StrPut(UpCredTarget(), &targetW, "UTF-16")
	VarSetCapacity(userW, (StrLen(user) + 1) * 2, 0), StrPut(user, &userW, "UTF-16")
	blobSize := StrLen(token) * 2
	VarSetCapacity(blob, blobSize + 2, 0), StrPut(token, &blob, "UTF-16")
	VarSetCapacity(cred, is64 ? 80 : 52, 0)
	NumPut(1, cred, 4, "UInt")                          ;Type: CRED_TYPE_GENERIC
	NumPut(&targetW, cred, 8, "Ptr")                    ;TargetName
	NumPut(blobSize, cred, is64 ? 32 : 24, "UInt")      ;CredentialBlobSize
	NumPut(&blob, cred, is64 ? 40 : 28, "Ptr")          ;CredentialBlob
	NumPut(2, cred, is64 ? 48 : 32, "UInt")             ;Persist: CRED_PERSIST_LOCAL_MACHINE
	NumPut(&userW, cred, is64 ? 72 : 48, "Ptr")         ;UserName
	saved := DllCall("Advapi32\CredWriteW", "Ptr", &cred, "UInt", 0)
	DllCall("RtlZeroMemory", "Ptr", &blob, "Ptr", blobSize + 2)
	return saved
	}

;Whether a token works: it can see the repo's releases ("" yes, else why not)
UpTokenTest(token)
	{
	UpHttp(UpApi() "/repos/" UpRepo() "/releases/latest", token, "application/vnd.github+json", status, 8000)
	return status = 200 ? "" : status = 401 ? "GitHub doesn't accept that token (401)" : status = 404 ? "the token can't see the Wiz-Maxxing repo (404) - give it access to that repository" : status = 403 ? "GitHub refused it (403)" : status = 0 ? "no answer from GitHub (offline?)" : "GitHub answered " status
	}

UpUnescape(s)
	{
	s := StrReplace(s, "\r\n", "`n"), s := StrReplace(s, "\n", "`n"), s := StrReplace(s, "\r", "")
	s := StrReplace(s, "\""", """"), s := StrReplace(s, "\/", "/"), s := StrReplace(s, "\t", "`t")
	return StrReplace(s, "\\", "\")
	}

UpLog(text)
	{
	FormatTime, now,, yyyy-MM-dd HH:mm:ss
	FileAppend, % now " " text "`r`n", %A_ScriptDir%\updater.log
	}
