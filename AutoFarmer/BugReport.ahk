; BugReport.ahk - "Report a bug" (the dashboard's button, the tray menu): a window where you say what went wrong.
; Send posts it as an issue on the Wiz-Maxxing repo on GitHub, with the bot's version and setup, what the dashboard's
; STATISTICS and WHAT IT SEES show, and the end of debug.log. AHK v1.1, functions and labels only; #Included by
; Autofarmer.ahk.
;
; Wiz-Maxxing.exe /report posts it (Updater.ahk UpReport), with the GitHub token in Windows Credential Manager - this
; never reads the token. The token needs Issues: Read and write on the repo, besides Contents for updates. The report
; waits in reports\ until Wiz-Maxxing answers: reports\report_<time>.txt (its first line the title), the answer in
; reports\report_<time>.txt.result. What looks secret (a Discord webhook, a GitHub token, a password=...) is blanked
; out of all of it. Closing the window keeps what you typed until it's sent.

;The window and its controls (vBugTitle...); the report waiting for Wiz-Maxxing's answer ("" none) and when it went
global BugHwnd, BugTitle, BugText, BugAddLog, BugSendBtn, BugStatus, BugFile, BugSentAt

;Opens the window (made once: what you typed stays when it's closed)
BugShow()
	{
	if (!BugHwnd)
		{
		BugBuild()
		;(the first time: next to the dashboard when it's up)
		bugPos := ""
		if (DashHwnd && DashShown)
			{
			WinGet, bugMm, MinMax, ahk_id %DashHwnd%
			WinGetPos, bugDx, bugDy, , , ahk_id %DashHwnd%
			if (bugDx != "" && bugMm != -1)
				bugPos := "x" bugDx + 60 " y" bugDy + 80 " "
			}
		Gui, Bug:Show, % bugPos "AutoSize", % "Wizard101 bot " BotVersion() " - report a bug"
		}
	else
		Gui, Bug:Show
	GuiControl, Bug:Focus, BugText
	}

;Makes the window (not shown)
BugBuild()
	{
	Gui, Bug:New, +HwndBugHwnd -MaximizeBox, % "Wizard101 bot " BotVersion() " - report a bug"
	Gui, Bug:Color, 1B1D22, 111317
	Gui, Bug:Margin, 12, 10
	Gui, Bug:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Bug:Add, Text, x12 y12 w560 h18, REPORT A BUG
	Gui, Bug:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Bug:Add, Text, x12 y34 w560 h32, What went wrong, and what was the bot doing? Send posts it as an issue on the Wiz-Maxxing repo on GitHub, with the bot's version and what the dashboard shows.
	Gui, Bug:Font, s9 w400 cDADADA, Segoe UI
	Gui, Bug:Add, Text, x12 y74 w560 h18, Title (a few words)
	Gui, Bug:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, Bug:Add, Edit, x12 y94 w560 h24 Limit120 vBugTitle
	Gui, Bug:Font, s9 w400 cDADADA, Segoe UI
	Gui, Bug:Add, Text, x12 y128 w560 h18, What happened
	Gui, Bug:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, Bug:Add, Edit, x12 y148 w560 h220 Multi +VScroll Limit20000 vBugText
	Gui, Bug:Font, s9 w400 cDADADA, Segoe UI
	Gui, Bug:Add, Checkbox, x12 y378 w560 h18 Checked vBugAddLog, Add the end of debug.log (the last few hundred lines)
	Gui, Bug:Font, s9 w400 c000000, Segoe UI
	Gui, Bug:Add, Button, x12 y406 w90 h26 gBugSend vBugSendBtn, Send
	Gui, Bug:Add, Button, x+8 yp w90 h26 gBugGuiClose, Close
	;(the status under the buttons, room for three lines - the way to fix the token takes two)
	Gui, Bug:Font, s9 w400 cB9E2B9, Segoe UI
	Gui, Bug:Add, Text, x12 y440 w560 h48 vBugStatus
	}

;Send: the report written to reports\ and Wiz-Maxxing started to post it; BugPoll waits for its answer
BugSendNow()
	{
	Gui, Bug:Submit, NoHide
	if (BugFile != "")
		return
	bugWhat := Trim(BugText, " `t`r`n")
	if (StrLen(bugWhat) < 5)
		return BugSay("Say what went wrong first.")
	bugHead := Trim(BugTitle, " `t`r`n")
	if (bugHead = "")
		bugHead := SubStr(Trim(StrSplit(bugWhat, "`n")[1], " `t`r"), 1, 80)
	;(Wiz-Maxxing posts it: the exe - or, run as a script, Wiz-Maxxing.ahk by this AutoHotkey)
	if (A_IsCompiled && !FileExist(A_ScriptDir "\..\Wiz-Maxxing.exe"))
		return BugSay("Not sent: Wiz-Maxxing.exe isn't in the bot's folder (it sends the report).")
	FileCreateDir, %A_ScriptDir%\reports
	FormatTime, bugStamp, , yyyyMMdd_HHmmss
	bugF := A_ScriptDir "\reports\report_" bugStamp ".txt"
	FileDelete, %bugF%.result
	bugOut := FileOpen(bugF, "w", "UTF-8")
	if (!IsObject(bugOut))
		return BugSay("Not sent: couldn't write " bugF)
	bugOut.Write(BugRedact(StrReplace(bugHead, "`n", " ")) "`n" BugBody(bugWhat, BugAddLog))
	bugOut.Close()
	if (!BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/report """ bugF """", A_ScriptDir "\.."))
		{
		bugErr := A_LastError
		FileDelete, %bugF%
		return BugSay("Not sent: Wiz-Maxxing couldn't be started (error " bugErr ").")
		}
	BugFile := bugF, BugSentAt := A_TickCount
	GuiControl, Bug:Disable, BugSendBtn
	BugSay("Sending...")
	SetTimer, BugPoll, 500
	}

;Wiz-Maxxing's answer (BugSendNow's report): "ok|<issue number>|<address>" or "err|<why>" - none in 45 s: given up
BugPollNow()
	{
	if (BugFile = "")
		{
		SetTimer, BugPoll, Off
		return
		}
	bugAns := ""
	if (FileExist(BugFile ".result"))
		{
		bugIn := FileOpen(BugFile ".result", "r", "UTF-8")
		if (IsObject(bugIn))
			bugAns := Trim(bugIn.Read(), " `t`r`n"), bugIn.Close()
		}
	;(not there yet - or not written all the way: looked at again)
	if (bugAns = "")
		{
		if (A_TickCount - BugSentAt < 45000)
			return
		bugAns := "err|no answer from Wiz-Maxxing in 45 s"
		}
	SetTimer, BugPoll, Off
	FileDelete, %BugFile%.result
	FileDelete, %BugFile%
	BugFile := ""
	GuiControl, Bug:Enable, BugSendBtn
	bugP := StrSplit(bugAns, "|", , 3)
	if (bugP[1] = "ok")
		{
		GuiControl, Bug:, BugTitle
		GuiControl, Bug:, BugText
		BugSay("Sent: issue #" bugP[2] " on GitHub. Thanks!")
		DebugLog("Bug report sent: issue #" bugP[2] " on GitHub")
		return
		}
	bugWhy := (bugP[1] = "err" && bugP[2] != "") ? bugP[2] : bugAns
	BugSay("Not sent: " bugWhy ". What you typed is still here.")
	DebugLog("Bug report not sent: " bugWhy)
	}

;The window's status line
BugSay(msg)
	{
	GuiControl, Bug:, BugStatus, %msg%
	return ""
	}

;The issue's text (GitHub markdown): what you wrote; the bot's version and setup; what the dashboard's STATISTICS and
;WHAT IT SEES show now; and (addLog) as much of the end of debug.log as GitHub's 65536 characters leave room for. What
;looks secret is blanked out (BugRedact)
BugBody(what, addLog)
	{
	;(the dashboard hidden: its texts aren't kept up - made now, the window staying hidden)
	if (DashHwnd && !DashShown && IsFunc("DashRefresh"))
		{
		Critical
		DashShown := 1
		Func("DashRefresh").Call()
		DashShown := 0
		Critical, Off
		}
	FormatTime, bugNow, , yyyy-MM-dd HH:mm:ss
	bugB := what "`n`n---`n**" BotVersion() "** - " bugNow " - PC " A_ComputerName " - screen " A_ScreenWidth "x" A_ScreenHeight
		. " - UI " UiScale " - " (BotOn ? "bot on" : "bot off") (Walking ? ", walking" : "") (school != "" ? " - " school : "") "`n"
	GuiControlGet, bugStats, Dash:, DashStatText
	GuiControlGet, bugSees, Dash:, DashSeeText
	if (Trim(bugStats) != "")
		bugB .= BugFold("Statistics", bugStats)
	if (Trim(bugSees) != "")
		bugB .= BugFold("What it sees", bugSees)
	;(the log gets what's left: its fold's own lines, and what blanking out may add, kept free - debug.log is ANSI, a
	;byte a character)
	bugRoom := 64000 - StrLen(bugB) - 300
	if (addLog && bugRoom > 1000)
		{
		bugLog := BugLogTail(Min(bugRoom, 45000), bugLines)
		if (bugLog != "")
			bugB .= BugFold("debug.log, its last " bugLines " lines", bugLog)
		}
	return BugRedact(bugB)
	}

;A folded block of text in the issue (title: what's on its fold)
BugFold(title, text)
	{
	bugFence := Chr(96) Chr(96) Chr(96)
	;(a fence in the text would end the block early)
	return "`n<details><summary>" title "</summary>`n`n" bugFence "text`n" StrReplace(Trim(StrReplace(text, "`r", ""), "`n"), bugFence, "'''") "`n" bugFence "`n</details>`n"
	}

;The end of debug.log: up to maxBytes, from the start of a line; lines: how many
BugLogTail(maxBytes, ByRef lines)
	{
	lines := 0
	bugIn := FileOpen(A_ScriptDir "\debug.log", "r")
	if (!IsObject(bugIn))
		return ""
	bugSize := bugIn.Length
	if (bugSize > maxBytes)
		bugIn.Seek(bugSize - maxBytes)
	bugT := bugIn.Read()
	bugIn.Close()
	;(from somewhere in a line: from the next one)
	if (bugSize > maxBytes)
		bugT := SubStr(bugT, InStr(bugT, "`n") + 1)
	bugT := StrReplace(bugT, "`r", "")
	StrReplace(Trim(bugT, "`n"), "`n", "`n", lines)
	lines += (Trim(bugT, "`n") != "")
	return bugT
	}

;s with what looks secret blanked out: Discord webhook addresses, GitHub tokens, "Bearer ..." and password= / token= /
;secret= values
BugRedact(s)
	{
	s := RegExReplace(s, "i)https?://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\S+", "[a Discord webhook - left out]")
	s := RegExReplace(s, "\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,})", "[a GitHub token - left out]")
	s := RegExReplace(s, "i)\bBearer\s+\S+", "Bearer [left out]")
	return RegExReplace(s, "i)\b(password|passwd|pwd|token|secret)(\s*[=:]\s*)\S+", "$1$2[left out]")
	}

BugSend:
	BugSendNow()
	return

BugPoll:
	BugPollNow()
	return

;(closing it keeps what you typed - and a report on its way is still answered)
BugGuiClose:
BugGuiEscape:
	Gui, Bug:Hide
	return
