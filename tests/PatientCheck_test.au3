; -----------------------------------------------------------------------------
; PatientCheck tests
; -----------------------------------------------------------------------------
;
; Run with AutoIt3.exe (console output); exit code 0 = all passed.
; -----------------------------------------------------------------------------

#include "..\include\PatientCheck.au3"

Opt('MustDeclareVars', 1)

Global $iFail = 0
Global Const $sHdr = "  FileID MeasID ProtName" & @CRLF

Func Assert($b, $sName)
	If $b Then
		ConsoleWrite("PASS: " & $sName & @CRLF)
	Else
		ConsoleWrite("FAIL: " & $sName & @CRLF)
		$iFail += 1
	EndIf
EndFunc ;==>Assert

; one closed listing line in the fixture layout ($sPat is right-aligned in 32 chars)
Func RaidLine($iFid, $iMid, $sProt, $sPat)
	Return StringFormat("%8d %6d %-24s%32s cld 1048576 1048576 15.10.2026 10:00:00 15.10.2026 10:00:30 0x0", $iFid, $iMid, $sProt, $sPat) & @CRLF
EndFunc ;==>RaidLine


; --- sample listing ---
Global $aRows = PC_ParseRaidList(FileRead(@ScriptDir & "\fixtures\raid_sample.txt"))
Global $iErr = @error, $iExt = @extended
Global $i, $bOk

Assert($iErr = 0, "sample: @error = 0")
Assert($iExt = 0, "sample: @extended = 0")
Assert(UBound($aRows) = 5, "sample: 5 rows")
If UBound($aRows) <> 5 Then
	ConsoleWrite("FAIL: sample row count wrong, skipping row checks" & @CRLF)
	Exit(1)
EndIf

$bOk = True
For $i = 0 To 4
	If $aRows[$i][$PC_FID] <> 100 + $i Then $bOk = False
Next
Assert($bOk, "sample: FIDs 100-104 in order")

Assert($aRows[4][$PC_STATUS] == "?", "row 104: STATUS is ?")
Assert($aRows[4][$PC_PAT] == "", "row 104: PAT is empty")

Assert($aRows[0][$PC_PAT] == "DOE^JOHN,19800101", "row 100: PAT (right-aligned)")

; Row 101 has the same patient LEFT-aligned. The window slides left into the
; protocol, so the key changes. A left-aligned layout causes safe mismatch
; noise, never a false match.
Assert($aRows[1][$PC_STATUS] == "cld", "row 101: STATUS cld (left-aligned)")
Assert($aRows[1][$PC_PATKEY] <> $aRows[0][$PC_PATKEY], "row 101: PATKEY differs from row 100 (safe mismatch)")

Assert($aRows[2][$PC_PROT] == "t1 mpr sag iso", "row 102: PROT with spaces")
Assert($aRows[2][$PC_PAT] == "DOE^JOHN,19800101", "row 102: PAT")
Assert($aRows[2][$PC_PATKEY] == $aRows[0][$PC_PATKEY], "row 102: PATKEY equals row 100")

Assert($aRows[3][$PC_PATKEY] <> $aRows[0][$PC_PATKEY], "row 103: PATKEY differs from row 100")

Assert($aRows[0][$PC_CREATE] == "2026/10/15 10:00:00", "row 100: CREATE")
Assert($aRows[0][$PC_CLOSE] == "2026/10/15 10:00:30", "row 100: CLOSE")

; invariant: every cld row has a 16-hex key, every ? row has none
$bOk = True
For $i = 0 To UBound($aRows) - 1
	If $aRows[$i][$PC_STATUS] == "cld" And Not StringRegExp($aRows[$i][$PC_PATKEY], '^[0-9a-f]{16}$') Then $bOk = False
	If $aRows[$i][$PC_STATUS] == "?" And $aRows[$i][$PC_PATKEY] <> "" Then $bOk = False
Next
Assert($bOk, "sample: cld rows have 16-hex PATKEY, ? rows have none")

; --- PC_PatKey (known answers pin the on-disk contract) ---
Assert(PC_PatKey("  ") == "", "PC_PatKey: blank gives empty")
Assert(PC_PatKey(" X ") == PC_PatKey("X"), "PC_PatKey: trims whitespace")
Assert(PC_PatKey("DOE^JOHN,19800101") == "4af9e7f2cece32cc", "PC_PatKey: known answer")
Assert(PC_PatKey("M" & ChrW(0xDC) & "LLER^J" & ChrW(0xD6) & "RG,19800101") == "eb419fcf5c7b2c67", "PC_PatKey: known answer (UTF-8)")

; --- no header line ---
$aRows = PC_ParseRaidList(FileRead(@ScriptDir & "\fixtures\raid_noheader.txt"))
$iErr = @error
Assert($iErr = 1, "noheader: @error = 1")
Assert(UBound($aRows) = 0, "noheader: 0 rows")

; --- header only ---
$aRows = PC_ParseRaidList("RaidTool remote client" & @CRLF & $sHdr)
$iErr = @error
$iExt = @extended
Assert($iErr = 0, "header only: @error = 0")
Assert($iExt = 0, "header only: @extended = 0")
Assert(UBound($aRows) = 0, "header only: 0 rows")

; --- FID/MID only, no trailing space ---
$aRows = PC_ParseRaidList($sHdr & "     105     55")
$iExt = @extended
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 105 And $aRows[0][$PC_STATUS] == "?", "FID/MID only: ? row with FID 105")
Assert($iExt = 0, "FID/MID only: @extended = 0")

; --- garbage line after header ---
$aRows = PC_ParseRaidList($sHdr & "ERROR: timeout" & @CRLF)
$iExt = @extended
Assert($iExt = 1, "garbage line: @extended = 1")
Assert(UBound($aRows) = 0, "garbage line: 0 rows")

; --- repeated header ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", "DOE^JOHN,19800101") & $sHdr & RaidLine(101, 51, "localizer", "DOE^JOHN,19800101"))
$iExt = @extended
Assert($iExt = 0, "repeated header: @extended = 0")
Assert(UBound($aRows) = 2, "repeated header: 2 rows")

; --- non-header line mentioning FileID still counts as unknown ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", "DOE^JOHN,19800101") & "Error: timeout reading FileID 101" & @CRLF)
$iExt = @extended
Assert(UBound($aRows) = 1 And $aRows[0][$PC_STATUS] == "cld", "FileID in error line: 1 cld row")
Assert($iExt = 1, "FileID in error line: @extended = 1")

; --- blank patient field: window would slide onto the protocol name ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(106, 56, "localizer", ""))
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 106 And $aRows[0][$PC_MID] = 56 And $aRows[0][$PC_STATUS] == "?" And $aRows[0][$PC_PATKEY] == "", "blank patient field: ? row with FID 106, MID 56")

; --- patient field without a comma ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(107, 57, "localizer", "DOE^JOHN 19800101"))
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 107 And $aRows[0][$PC_STATUS] == "?", "no comma: ? row with FID 107")

ConsoleWrite(@CRLF & ($iFail = 0 ? "ALL PASSED" : $iFail & " FAILED") & @CRLF)
Exit($iFail > 0 ? 1 : 0)
