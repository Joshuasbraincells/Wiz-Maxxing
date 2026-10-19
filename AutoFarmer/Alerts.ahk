; Alerts.ahk - Discord alerts when the wizard needs you, through a webhook of your Discord channel. AHK v1.1, functions
; and labels only; #Included by Autofarmer.ahk.
;
; Sent for: the walker's "needs you" notices (stuck, a teleport that doesn't work, no quest arrow, waiting at the
; quest goal, a collect quest), out of potions with none to be had, "Crowns" seen in a potion run, out of mana, a
; wizard whose school the bot doesn't know, the backpack full, and not getting back into the game (a login turned
; down, patching, the launcher, a ban or another login). The message says what's wrong, the zone and the time -
; nothing else: never a login, never a screenshot.
;
; The webhook's address is kept in Windows Credential Manager as "Wiz-Maxxing Discord webhook" - never in a file,
; never in debug.log (tray menu "Discord alerts...": set it - a test message is sent - or type OFF to remove it).
; alertson:0 in PlayerStats.txt (the Settings window) switches the alerts off. The same alert at most once in 10
; minutes; alerts less than 20 s apart wait their turn (held, then sent - never dropped); sent in the background
; (the bot doesn't wait for Discord) and the answer logged ("Discord: ...").

;When each kind was last sent (kind -> tick; "" -> any); the sends still under way ({req, kind, at}); alerts held
;for the 20 s gap ({kind, title, text}); tests only: another address for every send
global AlertLast, AlertReqs, AlertTestUrl, AlertWait

AlertTarget()
	{
	return "Wiz-Maxxing Discord webhook"
	}

;The webhook's address from Windows Credential Manager ("" none)
AlertUrl()
	{
	if (AlertTestUrl != "")
		return AlertTestUrl
	credPtr := 0, url := ""
	is64 := (A_PtrSize = 8)
	VarSetCapacity(targetW, (StrLen(AlertTarget()) + 1) * 2, 0), StrPut(AlertTarget(), &targetW, "UTF-16")
	if (!DllCall("Advapi32\CredReadW", "Ptr", &targetW, "UInt", 1, "UInt", 0, "Ptr*", credPtr) || !credPtr)
		return ""
	blobSize := NumGet(credPtr + 0, is64 ? 32 : 24, "UInt")
	blobPtr := NumGet(credPtr + 0, is64 ? 40 : 28, "Ptr")
	if (blobPtr && blobSize)
		url := StrGet(blobPtr, blobSize // 2, "UTF-16")
	DllCall("Advapi32\CredFree", "Ptr", credPtr)
	return Trim(url)
	}

;Keeps the webhook's address in Windows Credential Manager ("" removes it). True if done
AlertUrlSave(url)
	{
	VarSetCapacity(targetW, (StrLen(AlertTarget()) + 1) * 2, 0), StrPut(AlertTarget(), &targetW, "UTF-16")
	if (url = "")
		{
		DllCall("Advapi32\CredDeleteW", "Ptr", &targetW, "UInt", 1, "UInt", 0)
		return AlertUrl() = ""
		}
	is64 := (A_PtrSize = 8)
	user := "discord-webhook"
	VarSetCapacity(userW, (StrLen(user) + 1) * 2, 0), StrPut(user, &userW, "UTF-16")
	blobSize := StrLen(url) * 2
	VarSetCapacity(blob, blobSize + 2, 0), StrPut(url, &blob, "UTF-16")
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

;A Discord webhook's address: https://discord.com/api/webhooks/<id>/<token> (also discordapp.com, ptb., canary.)
AlertUrlOk(url)
	{
	return RegExMatch(url, "^https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\d+/[\w-]+$")
	}

;An alert, if they're on and a webhook's set: kind - one of each kind at most once in 10 minutes; title, text - what's
;wrong and what to do. Sent in the background
AlertSend(kind, title, text)
	{
	if (Stats.HasKey("alertson") && !Stats["alertson"])
		return
	url := AlertUrl()
	if (url = "")
		return
	if (!IsObject(AlertLast))
		AlertLast := {}
	now := A_TickCount
	if (AlertLast.HasKey(kind) && now - AlertLast[kind] < 600000)
		return
	;(another went less than 20 s ago: this one waits its turn - an alert that the bot has stopped often comes
	;right after the one that led to it)
	if (AlertLast.HasKey("") && now - AlertLast[""] < 20000)
		{
		if (!IsObject(AlertWait))
			AlertWait := []
		for i, w in AlertWait
			if (w.kind = kind)
				return
		AlertWait.Push({kind: kind, title: title, text: text})
		DebugLog("Discord: alert '" title "' held - another went less than 20 s ago")
		SetTimer, AlertFlush, % -(20000 - (now - AlertLast[""]) + 200)
		return
		}
	AlertLast[kind] := now, AlertLast[""] := now
	zone := IsFunc("WalkZone") ? Func("WalkZone").Call() : ""
	FormatTime, at, , HH:mm
	AlertPost(url, "**Wizard101 bot needs you: " title "**`n" text "`n_" (zone != "" ? zone " - " : "") at "_", kind)
	}

;Posts content to the webhook in the background (wait: until Discord answers, up to 10 s - the HTTP status, or ""
;when it couldn't be sent). Never logs the address
AlertPost(url, content, kind, wait := false)
	{
	body := "{""content"": """ AlertJson(SubStr(content, 1, 1900)) """, ""username"": ""Wiz-Maxxing"", ""allowed_mentions"": {""parse"": []}}"
	try
		{
		req := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		req.Open("POST", url, !wait)
		req.SetTimeouts(5000, 5000, 10000, 10000)
		req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
		req.Send(body)
		}
	catch e
		{
		DebugLog("Discord: alert '" kind "' couldn't be sent (" e.Message ")")
		return ""
		}
	if (wait)
		return req.Status
	if (!IsObject(AlertReqs))
		AlertReqs := []
	AlertReqs.Push({req: req, kind: kind, at: A_TickCount})
	SetTimer, AlertPoll, 1000
	return ""
	}

;The sends under way: their answers logged (204 = Discord took it)
AlertPoll()
	{
	if (!IsObject(AlertReqs) || !AlertReqs.Length())
		{
		SetTimer, AlertPoll, Off
		return
		}
	i := 1
	while (i <= AlertReqs.Length())
		{
		r := AlertReqs[i]
		done := false
		try done := r.req.WaitForResponse(0)
		if (done)
			{
			status := ""
			try status := r.req.Status
			DebugLog("Discord: alert '" r.kind "' " ((status = 204 || status = 200) ? "sent" : "not taken (HTTP " status (status = 404 ? " - the webhook was deleted? Tray menu: Discord alerts..." : status = 429 ? " - too many messages for now" : "") ")"))
			AlertReqs.RemoveAt(i)
			continue
			}
		if (A_TickCount - r.at > 30000)
			{
			DebugLog("Discord: alert '" r.kind "' - no answer from Discord in 30 s")
			AlertReqs.RemoveAt(i)
			continue
			}
		i += 1
		}
	}

;s for a JSON string: backslash, quote and control characters escaped
AlertJson(s)
	{
	s := StrReplace(s, "\", "\\")
	s := StrReplace(s, """", "\""")
	s := StrReplace(s, "`r", "")
	s := StrReplace(s, "`n", "\n")
	s := StrReplace(s, "`t", "\t")
	return RegExReplace(s, "[\x00-\x1F]", " ")
	}

;Tray menu "Discord alerts...": set the webhook (a test message is sent), test the one there (empty), or OFF to
;remove it. The address is typed hidden and kept only in Windows Credential Manager
AlertSetup()
	{
	;(a walking key the bot holds let go: this box can stay up a while)
	if (IsFunc("ReleaseKeys"))
		Func("ReleaseKeys").Call()
	have := AlertUrl() != ""
	prompt := have ? "Alerts go to a Discord webhook already.`n`nPaste a new webhook address to change it, leave it empty to send a test message, or type OFF to remove it." : "In Discord: the channel's settings > Integrations > Webhooks > New Webhook > Copy Webhook URL.`nPaste it here - it's kept in Windows Credential Manager on this PC only.`n`nThe bot then messages that channel when the wizard needs you."
	InputBox, url, Discord alerts, %prompt%, HIDE, 560, 210
	if (ErrorLevel)
		return
	url := Trim(url)
	if (url = "OFF" || url = "off")
		{
		AlertUrlSave("")
		DebugLog("Discord: alerts' webhook removed")
		TrayTip, Wizard101 bot, Discord alerts are off (the webhook was removed)., 5, 1
		return
		}
	isNew := (url != "")
	if (!isNew)
		{
		if (!have)
			return
		url := AlertUrl()
		}
	else if (!AlertUrlOk(url))
		{
		MsgBox, 48, Discord alerts, That isn't a Discord webhook address (it starts https://discord.com/api/webhooks/). Nothing was changed.
		return
		}
	;(the test first: a new address is kept only once Discord takes it - the one there before stays otherwise)
	status := AlertPost(url, "**Wiz-Maxxing alerts are on.** This channel gets a message when the wizard needs you.", "test", true)
	took := (status = 204 || status = 200)
	saved := !isNew || (took && AlertUrlSave(url))
	url := ""
	DebugLog("Discord: test message - " (took ? "sent" : "not taken (HTTP " status ")"))
	off := (Stats.HasKey("alertson") && !Stats["alertson"])
	if (took && !saved)
		MsgBox, 48, Discord alerts, The test message went through`, but the address couldn't be kept in Windows Credential Manager - nothing was changed.
	else if (took)
		MsgBox, 64, Discord alerts, % "A test message went to your Discord channel. " (off ? "Alerts are switched off in the Settings window, though (""Discord alerts when the wizard needs you"") - tick it to get them." : "Alerts are on.")
	else
		MsgBox, 48, Discord alerts, % "Discord didn't take the test message (" (status = "" ? "no answer" : "HTTP " status) "). " (isNew ? "The new address wasn't kept" (have ? " - alerts still go to the one before" : "") "." : "Check the webhook still exists, then try again.")
	}

AlertPoll:
	AlertPoll()
	return

;An alert held for the 20 s gap: sent now (the rules checked again), the next one 20 s later
AlertFlush:
	if (IsObject(AlertWait) && AlertWait.Length())
		{
		AlertFlushOne := AlertWait.RemoveAt(1)
		AlertSend(AlertFlushOne.kind, AlertFlushOne.title, AlertFlushOne.text)
		if (AlertWait.Length())
			SetTimer, AlertFlush, -20200
		}
	return
