; -----------------------------------------------------------------------------
; ShimCache GUI test
; -----------------------------------------------------------------------------
;
; Launches a patched copy of shimcache.au3 against tests\fake_raidtool.cmd and
; tests\fake_adjvalidate.cmd, then drives Get, Set and the patient check
; dialogs through the real window. Nothing in the repository is modified; the
; copy lives in a scratch directory under @TempDir that is removed at the end.
; The real AdjValidate and RaidTool are never called.
;
; Run with AutoIt3.exe /ErrorStdOut from a desktop session and leave the mouse
; and keyboard alone; exit code 0 = all passed. Refuses to run while ShimCache
; is open, because the singleton would raise that window and the test would
; click its Set.
; -----------------------------------------------------------------------------

#include <File.au3>
#include <Date.au3>
#include "..\include\config.au3"	; $CFG_IDLE_MINUTES decides the idle scenario's outcome

Opt('MustDeclareVars', 1)
Opt('WinTitleMatchMode', 3)

Global Const $sFakeRaid = @ScriptDir & "\fake_raidtool.cmd"
Global Const $sFakeAdj = @ScriptDir & "\fake_adjvalidate.cmd"
Global Const $sStateShim = @TempDir & "\shimcache_fake_adj_shim.txt"
Global Const $sStateTx = @TempDir & "\shimcache_fake_adj_txscale.txt"
Global Const $sScratch = @TempDir & "\ShimCacheGuiTest_" & @AutoItPID
Global Const $sWinB0 = "[TITLE:ShimCache B0; CLASS:AutoIt v3 GUI]"
Global Const $sWinB1 = "[TITLE:ShimCache B1; CLASS:AutoIt v3 GUI]"
Global Const $sLV = "[CLASS:SysListView32; INSTANCE:1]"

Global $iPass = 0, $iFail = 0
; the instance being driven
Global $hWin = 0, $iPid = 0, $sPgm = "", $sState = "", $sRaid = "", $iLogSeen = 0, $iFailAtStart = 0

Func Check($b, $sName)
	If $b Then
		ConsoleWrite("PASS: " & $sName & @CRLF)
		$iPass += 1
	Else
		ConsoleWrite("FAIL: " & $sName & @CRLF)
		$iFail += 1
	EndIf
EndFunc ;==>Check

; delete the scratch dir and the fake AdjValidate state, print the result, exit
Func Finish()
	; a stalled fake RaidTool (the hang scenario) can still hold its working
	; directory for up to 30 s, so retry
	Local $i
	For $i = 1 To 40
		DirRemove($sScratch, 1)
		If Not FileExists($sScratch) Then ExitLoop
		Sleep(1000)
	Next
	If FileExists($sScratch) Then ConsoleWrite("WARNING: could not remove " & $sScratch & @CRLF)
	FileDelete($sStateShim)
	FileDelete($sStateTx)
	ConsoleWrite("RESULT " & $iPass & " passed, " & $iFail & " failed" & @CRLF)
	Exit(($iFail = 0 And $iPass > 0) ? 0 : 1)
EndFunc ;==>Finish

; --- listings ---------------------------------------------------------------

; "dd.mm.yyyy hh:mm:ss", $iMin minutes before now
Func Stamp($iMin)
	Local $s = _DateAdd('n', -$iMin, _NowCalc())	; yyyy/mm/dd hh:mm:ss
	Return StringMid($s, 9, 2) & "." & StringMid($s, 6, 2) & "." & StringMid($s, 1, 4) & StringMid($s, 11)
EndFunc ;==>Stamp

; one listing row in the fixtures' layout, closed $iAgoClose minutes ago
; (a running "wip" row has the epoch-0 close time RaidTool prints)
Func Row($iFid, $sProt, $sPat, $sSts, $iAgoClose)
	Local $sClose = ($sSts = "wip") ? "31.12.1969 19:00:00" : Stamp($iAgoClose)
	Return StringFormat("%8d%7d %-22s%32s %s 1048576 1048576 %s %s 0x0", $iFid, $iFid - 50, $sProt, $sPat, $sSts, Stamp($iAgoClose + 2), $sClose) & @CRLF
EndFunc ;==>Row

Func Listing($sRows)
	Local $sHdr = "RaidTool remote client" & @CRLF & "Connected to 192.168.2.2:8010" & @CRLF & _
			"  FileID MeasID ProtName                                         PatName Sts Size    OnDisk  CreateTime          CloseTime           Attr" & @CRLF
	Return $sHdr & $sRows
EndFunc ;==>Listing

; write $sText to $sPath, replacing the file
Func WriteFile($sPath, $sText)
	Local $h = FileOpen($sPath, 2)
	FileWrite($h, $sText)
	FileClose($h)
EndFunc ;==>WriteFile

; point the running instance at $sText (or at nothing: RaidTool fails)
Func SetRaid($sText)
	If $sText = "" Then
		FileDelete($sRaid)
	Else
		WriteFile($sRaid, $sText)
	EndIf
EndFunc ;==>SetRaid

; --- scratch copy -----------------------------------------------------------

; copy shimcache.au3 and include\*.au3 into $sScratch and point the two config
; lines at the fakes; each replacement must happen exactly once
Func MakeScratchCopy()
	Local $sRepo = @ScriptDir & "\.."
	DirCreate($sScratch & "\include")
	FileCopy($sRepo & "\shimcache.au3", $sScratch & "\shimcache.au3", 1)
	FileCopy($sRepo & "\include\*.au3", $sScratch & "\include\", 1)
	Local $sCfgFile = $sScratch & "\include\config.au3"
	Local $sCfg = FileRead($sCfgFile)
	Local $aKeys[2] = ['Global Const $CFG_RAIDTOOL = ""', 'Global Const $CFG_ADJVALIDATE = ""']
	Local $aFakes[2] = [$sFakeRaid, $sFakeAdj]
	Local $i, $iHits
	For $i = 0 To 1
		StringReplace($sCfg, $aKeys[$i], "", 0, 1)
		$iHits = @extended
		If $iHits <> 1 Then
			ConsoleWrite("FAIL: config.au3 line '" & $aKeys[$i] & "' found " & $iHits & " times, expected once" & @CRLF)
			$iFail += 1
			Finish()
		EndIf
		$sCfg = StringReplace($sCfg, $aKeys[$i], StringTrimRight($aKeys[$i], 1) & $aFakes[$i] & '"', 0, 1)
	Next
	WriteFile($sCfgFile, $sCfg)
EndFunc ;==>MakeScratchCopy

; --- driving the window -----------------------------------------------------

Func LogText()
	Return ControlGetText($hWin, "", "[CLASS:Edit; INSTANCE:1]")
EndFunc ;==>LogText

; log text added since the last call
Func NewLog()
	Local $s = LogText()
	Local $sNew = StringMid($s, $iLogSeen + 1)
	$iLogSeen = StringLen($s)
	Return $sNew
EndFunc ;==>NewLog

; the window of process $iPid with this title spec, or 0
Func FindWin($sSpec)
	Local $a = WinList($sSpec)
	For $i = 1 To $a[0][0]
		If WinGetProcess($a[$i][1]) = $iPid Then Return $a[$i][1]
	Next
	Return 0
EndFunc ;==>FindWin

Func CloseInstance()
	If $hWin <> 0 Then WinClose($hWin)
	If ProcessWaitClose($iPid, 10) = 0 Then ProcessClose($iPid)
	$hWin = 0
EndFunc ;==>CloseInstance

; Launch the scratch copy in $iMode (0 = B0, 1 = B1) with $sWork as its
; working directory and $sListing as the RaidTool output. Returns False (after
; closing it) if the window is wrong or does not use the fakes.
Func StartInstance($iMode, $sWork, $sListing, $bHang = False)
	$sPgm = ($iMode = 1) ? "ShimCache B1" : "ShimCache B0"
	$sState = ($iMode = 1) ? $sStateTx : $sStateShim
	$sRaid = $sWork & "\raid.txt"
	$iLogSeen = 0
	$iFailAtStart = $iFail
	SetRaid($sListing)
	; clear fake switches a user's shell may have left over
	EnvSet("SHIMCACHE_FAKE_RAID_HANG")
	EnvSet("FAKE_ADJ_NOPROT")
	EnvSet("FAKE_ADJ_SECOND_ORDER")
	EnvSet("FAKE_ADJ_RESET")
	EnvSet("SHIMCACHE_FAKE_RAID", $sRaid)
	If $bHang Then EnvSet("SHIMCACHE_FAKE_RAID_HANG", "1")
	$iPid = Run('"' & @AutoItExe & '" /AutoIt3ExecuteScript "' & $sScratch & '\shimcache.au3" ' & $iMode & ' "' & $sWork & '"', $sWork)
	EnvSet("SHIMCACHE_FAKE_RAID")	; the child has inherited them
	EnvSet("SHIMCACHE_FAKE_RAID_HANG")
	Local $t = TimerInit()
	While $hWin = 0 And TimerDiff($t) < 20000
		Sleep(200)
		$hWin = FindWin("[TITLE:" & $sPgm & "; CLASS:AutoIt v3 GUI]")
	WEnd
	Check($hWin <> 0, "window '" & $sPgm & "' opened")
	If $hWin = 0 Then
		CloseInstance()
		Return False
	EndIf
	Sleep(1500)
	Local $sLog = NewLog()
	ConsoleWrite("startup log: " & StringStripWS($sLog, 3) & @CRLF)
	Local $bFakes = StringInStr($sLog, "Found " & $sFakeAdj) > 0 And StringInStr($sLog, "Patient check using " & $sFakeRaid) > 0
	Check($bFakes, $sPgm & ": startup log shows both fakes in use")
	If Not $bFakes Then
		CloseInstance()
		Return False
	EndIf
	Return True
EndFunc ;==>StartInstance

; final checks on the instance, dump its log if anything failed, close it
Func EndInstance()
	Local $sAll = LogText()
	Check(Not StringRegExp($sAll, "ROE|DOE|JANE|JOHN|PHANTOM"), $sPgm & ": no patient name in the log")
	If $iFail > $iFailAtStart Then ConsoleWrite("==== full log" & @CRLF & $sAll & @CRLF)
	CloseInstance()
EndFunc ;==>EndInstance

Func SelectRow($iIdx)
	ControlListView($hWin, "", $sLV, "SelectClear")
	ControlListView($hWin, "", $sLV, "Select", $iIdx)
EndFunc ;==>SelectRow

Func RowStamp($iIdx)
	Return ControlListView($hWin, "", $sLV, "GetText", $iIdx, 1)
EndFunc ;==>RowStamp

; click Get; wait for the patient check to report; return the log produced
Func Get($sLabel)
	Local $n = ControlListView($hWin, "", $sLV, "GetItemCount")
	Sleep(1100)	; shimset file names have one-second resolution
	NewLog()
	ControlClick($hWin, "", "[CLASS:Button; TEXT:Get]")
	Local $t = TimerInit(), $sLog = ""
	While TimerDiff($t) < 30000
		Sleep(200)
		$sLog &= NewLog()
		If StringInStr($sLog, "patient information") Or StringInStr($sLog, "patient check unavailable") Then ExitLoop
	WEnd
	Sleep(500)
	$sLog &= NewLog()
	Check(ControlListView($hWin, "", $sLV, "GetItemCount") = $n + 1, $sLabel & ": Get added a row")
	Return $sLog
EndFunc ;==>Get

; AdjValidate failed: ShimCache shows a modal error box. Fail the check and
; dismiss it so the scenarios that follow can still run.
Func DismissError($sLabel)
	Local $hErr = FindWin("[TITLE:" & $sPgm & ": Error; CLASS:#32770]")
	If $hErr <> 0 Then
		Check(False, $sLabel & ": Set raised the error box '" & StringStripWS(WinGetText($hErr), 7) & "'")
		ControlClick($hErr, "", "[CLASS:Button; ID:2]")	; OK
		Sleep(300)
	EndIf
EndFunc ;==>DismissError

; Click Set on row $iIdx and answer any patient check dialog with $sAnswer
; ("Yes" or "No"). Prints the dialog, the log and whether the fake applied the
; shims. Returns [dialog title, dialog text, log, applied].
Func SetRow($sLabel, $iIdx, $sAnswer)
	FileDelete($sState)	; the fake AdjValidate creates it on Set
	SelectRow($iIdx)
	Sleep(300)
	NewLog()
	ControlClick($hWin, "", "[CLASS:Button; TEXT:Set]")
	Local $t = TimerInit(), $sTitle = "", $sText = "", $sLog = "", $hDlg = 0
	Local $aTitles[2] = [$sPgm & ": DIFFERENT PATIENT", $sPgm & ": Patient not verified"]
	While TimerDiff($t) < 40000 And $sTitle = ""
		Sleep(200)
		$sLog &= NewLog()
		For $sT In $aTitles
			Local $h = FindWin("[TITLE:" & $sT & "; CLASS:#32770]")
			If $h <> 0 Then
				$hDlg = $h
				$sTitle = $sT
				$sText = WinGetText($h)
			EndIf
		Next
		If StringInStr($sLog, "Succeeded!") Or StringInStr($sLog, "ERROR") Then ExitLoop
	WEnd
	DismissError($sLabel)
	If $sTitle <> "" Then
		Sleep(400)
		ControlClick($hDlg, "", "[CLASS:Button; ID:" & ($sAnswer = "Yes" ? 6 : 7) & "]")	; IDYES / IDNO
		Sleep(300)
		Check(Not WinExists($hDlg), $sLabel & ": dialog closed by " & $sAnswer)
		Local $t2 = TimerInit()
		While TimerDiff($t2) < 10000
			Sleep(200)
			$sLog &= NewLog()
			If StringInStr($sLog, "Succeeded!") Or StringInStr($sLog, "cancelled") Or StringInStr($sLog, "ERROR") Then ExitLoop
		WEnd
	EndIf
	Sleep(300)
	$sLog &= NewLog()
	DismissError($sLabel)
	Local $aR[4] = [$sTitle, $sText, $sLog, FileExists($sState)]
	ConsoleWrite("---- " & $sLabel & @CRLF & "dialog: " & $sTitle & @CRLF & StringStripWS($sText, 3) & @CRLF & "log: " & StringStripWS($sLog, 3) & @CRLF & "applied: " & $aR[3] & @CRLF)
	Return $aR
EndFunc ;==>SetRow

; Set goes through with no dialog
Func ExpectOK($sLabel, $iIdx)
	Local $aR = SetRow($sLabel, $iIdx, "No")
	Check($aR[0] = "", $sLabel & ": no dialog")
	Check(StringInStr($aR[2], "Patient check OK") > 0, $sLabel & ": logged Patient check OK")
	Check($aR[3], $sLabel & ": shims applied")
EndFunc ;==>ExpectOK

; Set raises dialog "<program>: $sKind" containing $sTextHas; $sAnswer decides the outcome. Returns the dialog text.
Func ExpectDialog($sLabel, $iIdx, $sKind, $sAnswer, $sTextHas)
	Local $aR = SetRow($sLabel, $iIdx, $sAnswer)
	Check($aR[0] = $sPgm & ": " & $sKind, $sLabel & ": dialog '" & $sKind & "'")
	Check(StringInStr($aR[1], $sTextHas) > 0, $sLabel & ": dialog says '" & $sTextHas & "'")
	If $sAnswer = "No" Then
		Check(Not $aR[3], $sLabel & ": shims NOT applied after No")
		Check(StringInStr($aR[2], "cancelled by patient check") > 0, $sLabel & ": logged cancel")
	Else
		Check($aR[3], $sLabel & ": shims applied after Yes")
		Check(StringInStr($aR[2], "overridden by user") > 0, $sLabel & ": logged override")
	EndIf
	Return $aR[1]
EndFunc ;==>ExpectDialog

; --- scenarios --------------------------------------------------------------

Func ScenarioB0($sWork, $sBase, $sSame, $sOther, $sIdle)
	; shimset from before the patient check existed (no trailer) is the only row
	WriteFile($sWork & "\shimset_20200101080000.txt", "0 0 0 1 2 3 4 5 6 7 8 9" & @CRLF)
	If Not StartInstance(0, $sWork, $sBase) Then Return
	ExpectDialog("pre-feature file", 0, "Patient not verified", "No", "without readable patient information")

	; Get with patient ROE newest; then the same listing -> verified
	Local $sGet = Get("Get base")
	Check(StringInStr($sGet, "Recorded patient information") > 0, "Get recorded patient information")
	Local $aFiles = _FileListToArray($sWork, "shimset_*.txt", 1)
	Local $sNewest = ""
	For $i = 1 To $aFiles[0]
		If $aFiles[$i] > $sNewest Then $sNewest = $aFiles[$i]
	Next
	Local $sContent = FileRead($sWork & "\" & $sNewest)
	Check(StringRegExp($sContent, "(?m)^#ShimCachePatientCheck v1 pat=[0-9a-f]{16} fid=103 at=\d{14}\r?$"), "trailer in " & $sNewest)
	Check(RowStamp(0) <> RowStamp(1), "new row listed first: " & RowStamp(0))
	ExpectOK("same listing", 0)

	SetRaid($sSame)
	ExpectOK("same patient scanned again", 0)

	SetRaid($sOther)
	ExpectDialog("other patient, answer No", 0, "DIFFERENT PATIENT", "No", "DOE^JOHN,19800101")
	Local $sText = ExpectDialog("other patient, answer Yes", 0, "DIFFERENT PATIENT", "Yes", "Apply them anyway?")
	Check(StringRegExp(StringStripWS($sText, 3), "Apply them anyway\?\s*(&\w+\s*)*$"), "mismatch dialog ends with the question")
	Check(StringInStr($sText, "Another patient has been scanned") = 0, "mismatch dialog does not repeat the reason")

	SetRaid(FileRead(@ScriptDir & "\fixtures\raid_noheader.txt"))
	ExpectDialog("unrecognized listing", 0, "Patient not verified", "No", "unrecognized RaidTool output")
	SetRaid("")
	ExpectDialog("RaidTool failing", 0, "Patient not verified", "No", "unrecognized RaidTool output")

	; idle: Get and Set with the newest measurement closed 45 min ago
	SetRaid($sIdle)
	Get("Get idle")
	If ($CFG_IDLE_MINUTES > 0 And $CFG_IDLE_MINUTES < 45) Then
		ExpectDialog("idle scanner", 0, "Patient not verified", "No", "No measurement has finished in the last")
	Else
		ExpectOK("idle scanner, idle check off or longer", 0)
	EndIf

	; README recipe: sample fixture, newest row is wip
	SetRaid(FileRead(@ScriptDir & "\fixtures\raid_sample.txt"))
	Get("Get README recipe")
	ExpectOK("README recipe (wip newest)", 0)

	; Get while RaidTool fails: shims saved without trailer, then Set prompts
	SetRaid("")
	Local $sGet2 = Get("Get with RaidTool failing")
	Check(StringInStr($sGet2, "patient check unavailable") > 0, "Get warned patient check unavailable")
	SetRaid($sBase)
	ExpectDialog("shims saved without trailer", 0, "Patient not verified", "No", "saved without readable patient information")
	EndInstance()
EndFunc ;==>ScenarioB0

Func ScenarioB1($sWork, $sBase, $sOther)
	If Not StartInstance(1, $sWork, $sBase) Then Return
	Local $sGet = Get("B1 Get")
	Check(StringInStr($sGet, "Recorded patient information") > 0, "B1 Get recorded patient information")
	ExpectOK("B1 same listing", 0)
	SetRaid($sOther)
	ExpectDialog("B1 other patient", 0, "DIFFERENT PATIENT", "No", "DOE^JOHN")
	EndInstance()
EndFunc ;==>ScenarioB1

; RaidTool stalls past its timeout: the Set must give up and ask
Func ScenarioHang($sWork, $sBase)
	If Not StartInstance(0, $sWork, $sBase, True) Then Return
	Local $t = TimerInit()
	ExpectDialog("RaidTool hangs", 0, "Patient not verified", "No", "timed out after")
	Local $fSec = TimerDiff($t) / 1000
	ConsoleWrite("hang Set took " & Round($fSec, 1) & " s" & @CRLF)
	Check($fSec >= 10 And $fSec < 30, "hang Set waited for the RaidTool timeout (10 to 30 s)")
	EndInstance()
EndFunc ;==>ScenarioHang

; --- main -------------------------------------------------------------------

; A running ShimCache would be raised by the singleton check and the test would
; click its Set: never go on while one is open.
If WinExists($sWinB0) Or WinExists($sWinB1) Then
	ConsoleWrite("FAIL: ShimCache B0 or B1 is open. Close it before running this test; it would be driven instead of the test copy." & @CRLF)
	Exit(1)
EndIf

FileDelete($sStateShim)
FileDelete($sStateTx)

; listings, with times relative to now
Global $sROE = "ROE^JANE,19750505", $sDOE = "DOE^JOHN,19800101"
Global $sRowsBase = Row(103, "localizer", $sROE, "cld", 5) & Row(102, "t1 mpr", $sDOE, "cld", 50) & Row(101, "localizer", $sDOE, "cld", 60)
Global $sBase = Listing($sRowsBase)
Global $sSame = Listing(Row(105, "t2_tse_tra", $sROE, "cld", 1) & $sRowsBase)
Global $sOther = Listing(Row(106, "localizer", $sDOE, "cld", 1) & Row(105, "t2_tse_tra", $sROE, "cld", 2) & $sRowsBase)
Global $sIdle = Listing(Row(103, "localizer", $sROE, "cld", 45) & Row(102, "t1 mpr", $sDOE, "cld", 90))

Global $sWorkB0 = $sScratch & "\work"
Global $sWorkB1 = $sScratch & "\workb1"

; a reused PID must not leave stale shimset files from an earlier run
DirRemove($sScratch, 1)
If FileExists($sScratch) Then
	ConsoleWrite("FAIL: cannot remove stale scratch dir " & $sScratch & @CRLF)
	Exit(1)
EndIf
MakeScratchCopy()
DirCreate($sWorkB0)
DirCreate($sWorkB1)

ScenarioB0($sWorkB0, $sBase, $sSame, $sOther, $sIdle)
ScenarioB1($sWorkB1, $sBase, $sOther)
ScenarioHang($sWorkB0, $sBase)

Finish()
