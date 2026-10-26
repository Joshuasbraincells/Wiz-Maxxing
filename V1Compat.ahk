; V1Compat.ahk - the AutoHotkey v1.1 behaviours the v2 port of the bot keeps, in one place (see the port's
; CONVENTIONS.md: every file uses these the same way). AutoHotkey v2; functions and classes only - #Included at the
; bottom of every entry script (Autofarmer, AutoQuester, StatsReader, Wiz-Maxxing, Setup, PetTrainer).
; Each helper says what v1 did; none adds a behaviour v1 didn't have.

;v1's start: ErrorLevel 0 - and every variable blank (each file's <File>Blank(), called with this first thing by the
;entry script: v2 leaves a variable unset until it's assigned, and reading it throws)
V1Start()
	{
	global ErrorLevel := 0
	;v1's defaults where v2's differ (checked with both interpreters) - called first thing in the auto-execute section,
	;so they become every thread's defaults, as v1's were; each entry script's own settings come after and override
	;them. Send / Click / MouseMove: v1 Event (key and mouse delays, MouseMove's speed), v2 Input
	SendMode("Event")
	;a window's title starts with the text: v1 1, v2 2 (anywhere in it)
	SetTitleMatchMode(1)
	;coordinates relative to the active window: v1 Window, v2 Client
	CoordMode("ToolTip", "Window"), CoordMode("Pixel", "Window"), CoordMode("Mouse", "Window")
	CoordMode("Caret", "Window"), CoordMode("Menu", "Window")
	}

;v1: each thread had its own ErrorLevel - a new thread (a timer, a hotkey, a menu item, a button) started with the
;interrupted thread's, and that came back when the new one ended. The port's ErrorLevel is one global variable
;(as a callee's was its caller's in v1); a callback that touches it starts with
;	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
;which puts the interrupted thread's ErrorLevel back when the callback returns
class V1Thread
	{
	__New()
		{
		global ErrorLevel
		this.el := IsSet(ErrorLevel) ? ErrorLevel : 0
		}
	__Delete()
		{
		global ErrorLevel
		ErrorLevel := this.el
		}
	}

;v1's IsFunc("Name"): the function's mandatory parameters + 1 when the program has it, else 0 (v2 has no IsFunc).
;The bot asks it before calling a function of a file another program doesn't #Include (StatsReader, AutoQuester)
V1IsFunc(name)
	{
	try
		f := %name%
	catch
		return 0
	return (f is Func) ? f.MinParams + 1 : 0
	}

;---------------------------------------------------------------- numbers
;a number as v1 did math with it: a number, or text that is one (" 12 ", "0x1F", "-3.5")
V1IsNum(x) => !IsObject(x) && x != "" && IsNumber(x)

;v1's standalone X += n / X -= n / X *= n / X /= n / X++ / X-- (a line of its own - v1's old EnvAdd): a blank or
;text X counted as 0.	X++  ->  X := V1N(X) + 1
V1N(x) => V1IsNum(x) ? x : 0

;v1's math in an expression (+ - * / //, and X += n chained with commas): blank when either side isn't a number,
;and when dividing by zero.	A_TickCount - t  ->  V1Sub(A_TickCount, t)
V1Add(a, b) => (V1IsNum(a) && V1IsNum(b)) ? a + b : ""
V1Sub(a, b) => (V1IsNum(a) && V1IsNum(b)) ? a - b : ""
V1Mul(a, b) => (V1IsNum(a) && V1IsNum(b)) ? a * b : ""
V1Div(a, b) => (V1IsNum(a) && V1IsNum(b) && b != 0) ? a / b : ""
V1FloorDiv(a, b) => (V1IsNum(a) && V1IsNum(b) && b != 0) ? a // b : ""
V1Neg(a) => V1IsNum(a) ? -a : ""

;v1's A_TickCount - t: blank while t is (a time never set). Compare it with V1Lt / V1Gt - v1 compared a blank as text:
;"" < 5000 was TRUE (as if it had just happened), "" > 5000 false
V1Ago(t) => V1Sub(A_TickCount, t)

;v1's < > <= >=: two numbers compared as numbers, anything else (a blank, text) alphabetically and case-insensitive.
;v2 throws on a blank or text there.	A_TickCount - t < 5000  ->  V1Lt(V1Ago(t), 5000)
V1Cmp(a, b) => (V1IsNum(a) && V1IsNum(b)) ? (a < b ? -1 : a > b ? 1 : 0) : StrCompare(a "", b "", false)
V1Lt(a, b) => V1Cmp(a, b) < 0
V1Gt(a, b) => V1Cmp(a, b) > 0
V1Le(a, b) => V1Cmp(a, b) <= 0
V1Ge(a, b) => V1Cmp(a, b) >= 0

;v1's Round/Floor/Ceil of a blank or text: 0 (Abs, Max, Min, Mod, Sqrt...: blank) - v2 throws
V1Round(x, n := 0) => V1IsNum(x) ? Round(x, n) : 0
V1Floor(x) => V1IsNum(x) ? Floor(x) : 0
V1Ceil(x) => V1IsNum(x) ? Ceil(x) : 0
V1Abs(x) => V1IsNum(x) ? Abs(x) : ""
V1Mod(a, b) => (V1IsNum(a) && V1IsNum(b) && b != 0) ? Mod(a, b) : ""
V1Max(p*) {
	for v in p
		if !V1IsNum(v)
			return ""
	return Max(p*)
}
V1Min(p*) {
	for v in p
		if !V1IsNum(v)
			return ""
	return Min(p*)
}

;---------------------------------------------------------------- objects
;v1's arr[i] / obj[key] / obj.key for an item that isn't there: blank (v2 throws). Also a blank where v1 had no object
V1At(o, k)
	{
	if !IsObject(o)
		return ""
	if (o is Array)
		return (V1IsNum(k) && Integer(k) = k && k >= 1 && k <= o.Length && o.Has(k)) ? o[k] : ""
	if (o is Map)
		return o.Has(k) ? o[k] : ""
	;(a RegExMatch's match: m[1] / m["name"] - a subpattern it hasn't: blank, as v1's m1. HasProp doesn't see them)
	if (o is RegExMatchInfo)
		{
		try
			return o[k]
		catch
			return ""
		}
	return (!IsObject(k) && o.HasProp(k)) ? o.%k% : ""
	}

;v1's objects - {} and Object(): one key -> value store, keys case-insensitive ("Boss" and "boss" the same item),
;obj.key and obj["key"] the same item, a key that isn't there blank, for k, v in obj in key order (numbers, then
;text). The port's v1 objects:
;	{}  ->  V1Obj()		{a: 1, b: x}  ->  V1Obj({a: 1, b: x})  (or V1Obj("a", 1, "b", x))
;	obj.HasKey(k) / obj.Has(k), obj.Count, obj.Delete(k) (a key that isn't there: blank, as v1), obj.Clone()
;A data key named like one of Map's own members - Count, Capacity, CaseSense, Default, Clear, Clone, Delete, Get,
;Has, Set, HasKey, Base - is read and set with brackets: o["count"] (o.count is the Map's)
class V1Obj extends Map
	{
	__New(pairs*)
		{
		this.CaseSense := "Off", this.DefineProp("Default", {value: ""})
		if (pairs.Length = 1 && IsObject(pairs[1]) && !(pairs[1] is Map))
			{
			for k, v in pairs[1].OwnProps()
				this[k] := v
			}
		else if (pairs.Length)
			super.Set(pairs*)
		}
	__Get(name, params)
		{
		v := this[name]
		return params.Length ? (IsObject(v) ? v[params*] : "") : v
		}
	__Set(name, params, value)
		{
		if !params.Length
			return this[name] := value
		v := this[name]
		if IsObject(v)
			v[params*] := value
		return value
		}
	HasKey(k) => this.Has(k)
	Delete(k) => this.Has(k) ? super.Delete(k) : ""
	}

;---------------------------------------------------------------- what set ErrorLevel in v1
;v1's ImageSearch: ErrorLevel 0 found (x, y its top left), 1 not found, 2 couldn't search (the picture missing or
;unreadable); x, y blank when not found. v2 returns 1 / 0 and throws for 2. Sets the global ErrorLevel and returns it:
;	ImageSearch, x, y, x1, y1, x2, y2, % pic  ->  V1ImageSearch(&x, &y, x1, y1, x2, y2, pic)
V1ImageSearch(&x, &y, x1, y1, x2, y2, image)
	{
	global ErrorLevel
	try
		ErrorLevel := ImageSearch(&x, &y, x1, y1, x2, y2, image) ? 0 : 1
	catch
		ErrorLevel := 2, x := "", y := ""
	return ErrorLevel
	}

;v1's PixelSearch: the colour BGR unless the options say RGB (the bot's all say Fast RGB); ErrorLevel 0 / 1 / 2
V1PixelSearch(&x, &y, x1, y1, x2, y2, color, variation := 0, options := "")
	{
	global ErrorLevel
	if !InStr(options, "RGB")
		color := ((color & 0xFF) << 16) | (color & 0xFF00) | ((color >> 16) & 0xFF)
	try
		ErrorLevel := PixelSearch(&x, &y, x1, y1, x2, y2, color, variation) ? 0 : 1
	catch
		ErrorLevel := 2, x := "", y := ""
	return ErrorLevel
	}

;v1's FileRead: the text, or blank and ErrorLevel 1 when the file couldn't be read (v2 throws)
V1FileRead(path, options := "")
	{
	global ErrorLevel
	try
		{
		t := FileRead(path, options)
		ErrorLevel := 0
		return t
		}
	catch
		{
		ErrorLevel := 1
		return ""
		}
	}

;v1's FileAppend / FileDelete / FileCopy / FileMove / FileCreateDir / IniWrite / IniDelete...: ErrorLevel 0, or 1 (a
;count for the File* ones with wildcards - V1Do gives 1) when it failed; v2 throws.
;	FileDelete, %f%  ->  V1Do(FileDelete, f)		IniWrite, %v%, %ini%, s, k  ->  V1Do(IniWrite, v, ini, "s", "k")
V1Do(fn, args*)
	{
	global ErrorLevel
	try
		{
		fn(args*)
		ErrorLevel := 0
		}
	catch as e
		{
		;(v1's FileCopy / FileMove of one file that isn't there: no file failed - ErrorLevel 0, checked with v1.1; v2
		;throws. FileDelete's: 1, as below)
		if ((fn = FileCopy || fn = FileMove) && args.Length && !IsObject(args[1]) && !InStr(args[1], "*")
			&& !InStr(args[1], "?") && !FileExist(args[1]))
			ErrorLevel := 0
		else
			ErrorLevel := (e.HasProp("Extra") && IsInteger(e.Extra) && e.Extra > 0) ? e.Extra : 1
		}
	return ErrorLevel
	}

;v1's Run with UseErrorLevel: ErrorLevel "ERROR" when it couldn't start it (A_LastError says why - v2 sets it too),
;else 0; the process id in &pid
V1Run(target, dir := "", options := "", &pid := "")
	{
	global ErrorLevel
	try
		{
		Run(target, dir, options, &pid)
		ErrorLevel := 0
		}
	catch
		ErrorLevel := "ERROR", pid := ""
	return ErrorLevel
	}

;v1's RunWait with UseErrorLevel: ErrorLevel the program's exit code, or "ERROR"
V1RunWait(target, dir := "", options := "", &pid := "")
	{
	global ErrorLevel
	try
		ErrorLevel := RunWait(target, dir, options, &pid)
	catch
		ErrorLevel := "ERROR", pid := ""
	return ErrorLevel
	}

;v1 gave a blank (often ErrorLevel 1) where v2 throws - a window or control that isn't there (WinGetTitle,
;WinGetPos's outputs, ControlGetText...):	WinGetTitle, t, ahk_id %h%  ->  t := V1Try(WinGetTitle, "ahk_id " h)
V1Try(fn, args*)
	{
	try
		return fn(args*)
	catch
		return ""
	}

;---------------------------------------------------------------- Gui
;v1's A_GuiControl in a g-label: the control's variable (v-name), else its text. The converter's label functions get
;the control object as their A_GuiControl parameter:	A_GuiControl := V1GuiName(A_GuiControl)
V1GuiName(ctl) => !IsObject(ctl) ? ctl : (ctl.Name != "" ? ctl.Name : ctl.Text)

;v1's Gui, Submit: every control with a v-variable put its contents in that global (v2's Submit returns them):
;	Gui, Cfg:Submit, NoHide  ->  V1GuiSubmit(Cfg, false)
V1GuiSubmit(g, hide := true)
	{
	global
	local v1Vals, v1Name, v1Val
	v1Vals := g.Submit(hide)
	for v1Name, v1Val in v1Vals.OwnProps()
		%v1Name% := v1Val
	return v1Vals
	}
