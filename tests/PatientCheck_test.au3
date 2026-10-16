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
	If $aRows[$i][$PC_FID] <> 104 - $i Then $bOk = False
Next
Assert($bOk, "sample: FIDs 104-100 in order (newest first)")

Assert($aRows[0][$PC_STATUS] == "?", "row 104: STATUS is ?")
Assert($aRows[0][$PC_PAT] == "", "row 104: PAT is empty")

Assert($aRows[4][$PC_PAT] == "DOE^JOHN,19800101", "row 100: PAT (right-aligned)")

; Row 101 has the same patient LEFT-aligned. The window slides left into the
; protocol, so the key changes. A left-aligned layout causes safe mismatch
; noise, never a false match.
Assert($aRows[3][$PC_STATUS] == "cld", "row 101: STATUS cld (left-aligned)")
Assert($aRows[3][$PC_PATKEY] <> $aRows[4][$PC_PATKEY], "row 101: PATKEY differs from row 100 (safe mismatch)")

Assert($aRows[2][$PC_PROT] == "t1 mpr sag iso", "row 102: PROT with spaces")
Assert($aRows[2][$PC_PAT] == "DOE^JOHN,19800101", "row 102: PAT")
Assert($aRows[2][$PC_PATKEY] == $aRows[4][$PC_PATKEY], "row 102: PATKEY equals row 100")

Assert($aRows[1][$PC_PATKEY] <> $aRows[4][$PC_PATKEY], "row 103: PATKEY differs from row 100")

Assert($aRows[4][$PC_CREATE] == "2026/10/15 10:00:00", "row 100: CREATE")
Assert($aRows[4][$PC_CLOSE] == "2026/10/15 10:00:30", "row 100: CLOSE")

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

; =============================================================================
; Baseline and verdict
; =============================================================================

; True if $aV is [verdict, reason, ...] with this verdict and a reason starting with $sPrefix
Func VerdictIs($aV, $iVerdict, $sPrefix)
	If Not IsArray($aV) Or UBound($aV) <> 3 Then Return False
	Return $aV[0] = $iVerdict And StringLeft($aV[1], StringLen($sPrefix)) == $sPrefix
EndFunc ;==>VerdictIs

; one closed listing line like RaidLine but with another close time ("dd.mm.yyyy hh:mm:ss")
Func RaidLineClosed($iFid, $iMid, $sProt, $sPat, $sClose)
	Return StringReplace(RaidLine($iFid, $iMid, $sProt, $sPat), "15.10.2026 10:00:30", $sClose)
EndFunc ;==>RaidLineClosed

Global Const $sPatA = "DOE^JOHN,19800101", $sPatB = "ROE^JANE,19750505"
Global Const $sGet = "2026/10/15 10:10:00"		; baseline capture time
Global Const $sSet = "2026/10/15 10:30:00"		; RaidLine rows close at 10:00:30, so 29 min idle
Global Const $sOk = "No other patient has been scanned"
Global Const $sBadDate = "Could not compare the scanner's dates"
Global $aBase, $aBase2, $aV, $sLine
Global $aShort[2] = ["4af9e7f2cece32cc", 101]		; wrongly shaped baseline

; --- MakeBaseline: in-progress row at Get, fid is the keyed row ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & "     102     52" & @CRLF)
$aBase = PC_MakeBaseline($aRows, $sGet)
Assert($aBase[0] == PC_PatKey($sPatA) And $aBase[1] = 101 And $aBase[2] == $sGet, "MakeBaseline: key A, fid 101 (keyed row, not the ? row 102)")

; --- MakeBaseline: rows out of FID order ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(105, 55, "localizer", $sPatA) & RaidLine(107, 57, "localizer", $sPatB) & RaidLine(106, 56, "localizer", $sPatA) & "     108     58" & @CRLF)
$aBase2 = PC_MakeBaseline($aRows, $sGet)
Assert($aBase2[0] == PC_PatKey($sPatB) And $aBase2[1] = 107, "MakeBaseline: out of order, picks largest-FID cld row 107")

; --- MakeBaseline: no cld rows ---
$aRows = PC_ParseRaidList($sHdr)
$aBase2 = PC_MakeBaseline($aRows, $sGet)
Assert($aBase2[0] == "" And $aBase2[1] = 0 And $aBase2[2] == $sGet, "MakeBaseline: no cld rows gives empty key, fid 0")

; --- Format / Parse round trip ---
$sLine = PC_FormatBaseline($aBase)
Assert($sLine == "#ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=101 at=20261015101000", "FormatBaseline: exact v1 line")
$aBase2 = PC_ParseBaseline($sLine)
Assert(@error = 0 And IsArray($aBase2) And $aBase2[0] == $aBase[0] And $aBase2[1] = 101 And IsNumber($aBase2[1]) And $aBase2[2] == $sGet, "ParseBaseline: round trip")

$aRows = PC_ParseRaidList($sHdr)
$sLine = PC_FormatBaseline(PC_MakeBaseline($aRows, $sGet))
Assert($sLine == "#ShimCachePatientCheck v1 pat=- fid=0 at=20261015101000", "FormatBaseline: empty key as pat=-")
$aBase2 = PC_ParseBaseline($sLine)
Assert(@error = 0 And IsArray($aBase2) And $aBase2[0] == "" And $aBase2[1] = 0 And $aBase2[2] == $sGet, "ParseBaseline: round trip pat=-")

$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=101 at=20261015101000  " & @CRLF)
Assert(@error = 0 And IsArray($aBase2) And $aBase2[1] = 101, "ParseBaseline: trailing whitespace/CRLF accepted")

; --- Format rejects a malformed time ---
$aBase2 = PC_MakeBaseline($aRows, "2026-10-15 10:10:00")
$sLine = PC_FormatBaseline($aBase2)
Assert(@error = 1 And $sLine == "", "FormatBaseline: malformed time sets @error, returns empty")

; --- Format rejects a fid the parser could not read back ---
$aBase2 = $aBase
$aBase2[1] = 1000000000000000
$sLine = PC_FormatBaseline($aBase2)
Assert(@error = 1 And $sLine == "", "FormatBaseline: 16-digit fid sets @error, returns empty")
$aBase2[1] = -1
$sLine = PC_FormatBaseline($aBase2)
Assert(@error = 1 And $sLine == "", "FormatBaseline: negative fid sets @error, returns empty")
$aBase2[1] = 999999999999999
$sLine = PC_FormatBaseline($aBase2)
Assert(@error = 0 And $sLine == "#ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=999999999999999 at=20261015101000", "FormatBaseline: 15-digit fid accepted")

; --- Parse rejections ---
$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v2 pat=4af9e7f2cece32cc fid=101 at=20261015101000")
Assert(@error = 1 And Not IsArray($aBase2), "ParseBaseline: rejects v2")
$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v1 pat=4af9e7f2cece32c fid=101 at=20261015101000")
Assert(@error = 1 And Not IsArray($aBase2), "ParseBaseline: rejects 15-char key")
$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v1 pat=4AF9E7F2CECE32CC fid=101 at=20261015101000")
Assert(@error = 1 And Not IsArray($aBase2), "ParseBaseline: rejects uppercase hex")
$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=101")
Assert(@error = 1 And Not IsArray($aBase2), "ParseBaseline: rejects missing at=")
$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=101 at=20261015101000 x")
Assert(@error = 1 And Not IsArray($aBase2), "ParseBaseline: rejects trailing text")
$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=99999999999999999999 at=20261015101000")
Assert(@error = 1 And Not IsArray($aBase2), "ParseBaseline: rejects 20-digit fid")

; $aBase from here on: patient A, fid 101, captured at $sGet

; --- (a) no baseline / wrongly shaped baseline ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict(0, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "These shims were saved without readable patient information"), "Verdict (a): no baseline -> UNVERIFIED")
$aV = PC_Verdict($aShort, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "These shims were saved without readable patient information"), "Verdict (a): 2-element baseline -> UNVERIFIED")

; --- (b) baseline with empty key ---
$aRows = PC_ParseRaidList($sHdr)
$aBase2 = PC_MakeBaseline($aRows, $sGet)
$aRows = PC_ParseRaidList($sHdr & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase2, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "No patient data was on the RAID"), "Verdict (b): empty baseline key -> UNVERIFIED")

; --- (c) listing older than baseline / empty listing / reset with another patient ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(50, 5, "localizer", $sPatA) & RaidLine(51, 6, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "The RAID listing is older"), "Verdict (c): max FID below baseline -> UNVERIFIED")
$aRows = PC_ParseRaidList($sHdr)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "The RAID listing is older"), "Verdict (c): no rows -> UNVERIFIED")
$aRows = PC_ParseRaidList($sHdr & RaidLine(1, 1, "localizer", $sPatB) & RaidLine(2, 2, "t1", $sPatB))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (c): RAID reset, patient B on RAID -> MISMATCH")
$aRows = PC_ParseRaidList($sHdr & RaidLine(5, 1, "localizer", $sPatA) & RaidLine(5, 2, "localizer", $sPatB))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (c): RAID reset, duplicate FID 5, A then B -> MISMATCH")
$aRows = PC_ParseRaidList($sHdr & RaidLine(5, 2, "localizer", $sPatB) & RaidLine(5, 1, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (c): RAID reset, duplicate FID 5, B then A -> MISMATCH")

; --- (d) no cld rows ---
$aRows = PC_ParseRaidList($sHdr & "     102     52" & @CRLF)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "No completed measurement with readable patient information"), "Verdict (d): only ? rows -> UNVERIFIED")
Assert($aV[2] == "", "Verdict (d): currentPat empty")

; --- (e) newer different-patient cld row (newest row is A again) ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(102, 52, "localizer", $sPatB) & RaidLine(103, 53, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Verdict (e): newer different-patient row -> MISMATCH")

; --- (e) newer ? row ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & "     102     52" & @CRLF)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "A newer measurement is in progress"), "Verdict (e): newer ? row -> UNVERIFIED")

; --- (e) an old ? row below the checked range is ignored ---
$aRows = PC_ParseRaidList($sHdr & "     100     50" & @CRLF & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict (e): old ? row below the checked range -> VERIFIED")

; --- (f) newest cld row at the baseline FID belongs to someone else (IDs reused) ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatB))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (f): newest row different patient -> MISMATCH")
Assert($aV[2] == $sPatB, "Verdict (f): currentPat is patient B")

; --- (f) duplicate FID 101 for A and B, either listing order ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(101, 52, "localizer", $sPatB))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (f): duplicate FID 101, A then B -> MISMATCH")
$aRows = PC_ParseRaidList($sHdr & RaidLine(101, 52, "localizer", $sPatB) & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (f): duplicate FID 101, B then A -> MISMATCH")

; --- (f) IDs reused: ? row at the baseline FID is newer than the newest cld row ---
$sLine = ""
For $i = 95 To 100
	$sLine &= RaidLine($i, $i - 50, "localizer", $sPatA)
Next
$aRows = PC_ParseRaidList($sHdr & $sLine & "     101     99" & @CRLF)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "A newer measurement is in progress"), "Verdict (f): cld A 95-100 and ? 101 -> UNVERIFIED")

; --- unparsed lines ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & "Error: timeout" & @CRLF)
$iExt = @extended
$aV = PC_Verdict($aBase, $aRows, $iExt, $sSet, 60, 12)
Assert($iExt = 1 And VerdictIs($aV, $PC_UNVERIFIED, "Part of the RAID listing could not be read."), "Verdict: unparsed line, same patient -> UNVERIFIED")
$aRows = PC_ParseRaidList($sHdr & RaidLine(101, 51, "localizer", $sPatA) & "Error: timeout" & @CRLF & RaidLine(102, 52, "localizer", $sPatB))
$iExt = @extended
$aV = PC_Verdict($aBase, $aRows, $iExt, $sSet, 60, 12)
Assert($iExt = 1 And VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Verdict: unparsed line, different patient -> MISMATCH")

; --- (g) shims too old ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/16 10:10:00", 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "These shims were saved 24 hours ago."), "Verdict (g): 24 h old -> UNVERIFIED (before idle)")
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/15 22:10:00", 0, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "These shims were saved 12 hours ago."), "Verdict (g): exactly 12 h -> UNVERIFIED")
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/15 22:09:59", 0, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict (g): 11 h 59 m 59 s -> VERIFIED (whole hours)")

; --- (g) baseline dated in the future ---
$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=101 at=20261020101000")
$aV = PC_Verdict($aBase2, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "These shims are dated in the future"), "Verdict (g): baseline 5 days in the future -> UNVERIFIED")

; --- (h) scanner idle ---
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/15 11:30:00", 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "No measurement has finished in the last 60 minutes"), "Verdict (h): 89 min idle -> UNVERIFIED")
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/15 11:00:30", 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict (h): exactly 60 min idle -> VERIFIED")
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/15 11:01:30", 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "No measurement has finished"), "Verdict (h): 61 min idle -> UNVERIFIED")

; --- (h) scanner clock ahead ---
$aRows = PC_ParseRaidList($sHdr & RaidLineClosed(101, 51, "localizer", $sPatA, "15.10.2026 13:30:00"))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "The scanner clock is ahead"), "Verdict (h): CLOSE 3 h ahead -> UNVERIFIED")
$aRows = PC_ParseRaidList($sHdr & RaidLineClosed(101, 51, "localizer", $sPatA, "15.10.2026 10:30:30"))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict (h): CLOSE 30 s ahead -> VERIFIED")

; --- (g) and (h) off ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/18 10:10:00", 0, 0)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict: idle 0 and max age 0 turn (g) and (h) off")

; --- malformed dates never give VERIFIED ---
$aBase2 = PC_ParseBaseline("#ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=101 at=20261399000000")
$aV = PC_Verdict($aBase2, $aRows, 0, $sSet, 0, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, $sBadDate), "Verdict (g): bad baseline time -> UNVERIFIED")
$aRows = PC_ParseRaidList($sHdr & RaidLineClosed(101, 51, "localizer", $sPatA, "15.13.2026 10:00:30"))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 0)
Assert(VerdictIs($aV, $PC_UNVERIFIED, $sBadDate), "Verdict (h): bad close time -> UNVERIFIED")

; --- precedence: new ? row plus new different-patient row ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & "     102     52" & @CRLF & RaidLine(103, 53, "localizer", $sPatB))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Verdict: ? row + different patient -> MISMATCH")
Assert($aV[2] == $sPatB, "Verdict: currentPat is newest cld patient")

; --- in progress at Get (baseline fid 101), row 102 at Set ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(102, 52, "localizer", $sPatB))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "In progress: 102 closed for patient B -> MISMATCH")
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & "     102     52" & @CRLF)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "A newer measurement is in progress"), "In progress: 102 still ? -> UNVERIFIED")
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(102, 52, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, "No other patient has been scanned since these shims were saved."), "In progress: 102 closed for patient A -> VERIFIED")
Assert($aV[2] == $sPatA, "In progress: currentPat is patient A")

; --- same patient, recent ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(102, 52, "t1", $sPatA) & RaidLine(103, 53, "t2", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict: same patient, new rows, recent -> VERIFIED")
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict: same patient, no new rows, recent -> VERIFIED")

; --- enum: UNVERIFIED is the zero value ---
Assert($PC_UNVERIFIED = 0 And $PC_VERIFIED <> 0, "Enum: UNVERIFIED is 0, VERIFIED is not")

ConsoleWrite(@CRLF & ($iFail = 0 ? "ALL PASSED" : $iFail & " FAILED") & @CRLF)
Exit($iFail > 0 ? 1 : 0)
