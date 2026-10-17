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

; one running ("wip") listing line in the fixture layout, created at $sCreate
; ("dd.mm.yyyy hh:mm:ss"); RaidTool prints epoch 0 in local time as its close time
Func RaidLineWip($iFid, $iMid, $sProt, $sPat, $sCreate)
	Return StringFormat("%8d %6d %-24s%32s wip 2097152 2097152 %s 31.12.1969 19:00:00 0x0", $iFid, $iMid, $sProt, $sPat, $sCreate) & @CRLF
EndFunc ;==>RaidLineWip

; one closed listing line approximating the REAL fixed-width layout (see
; fixtures\raid_real_phantom.txt): every field right-aligned, no separators. The
; real PatName is a separator space plus %31s (fixtures\raid_real_longname.txt),
; which prints the same for names of up to 31 characters
Func RaidLineReal($iFid, $iMid, $sProt, $sPat)
	Return StringFormat("%7d%11d%32s%32s%9s%13s%13s%22s%22s", $iFid, $iMid, $sProt, $sPat, "cld", 1048576, 4194304, "15.10.2026 21:22:14", "15.10.2026 21:22:19") & @CRLF
EndFunc ;==>RaidLineReal


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

; row 104 is still running: status wip, placeholder close time
Assert($aRows[0][$PC_STATUS] == "wip", "row 104: STATUS is wip")
Assert($aRows[0][$PC_PAT] == "ROE^JANE,19750505", "row 104: PAT")
Assert($aRows[0][$PC_PATKEY] == $aRows[1][$PC_PATKEY], "row 104: PATKEY equals row 103")
Assert($aRows[0][$PC_CREATE] == "2026/10/15 11:01:00", "row 104: CREATE")
Assert($aRows[0][$PC_CLOSE] == "", "row 104: CLOSE is empty (placeholder never used)")

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

; invariant: cld and wip rows have a 16-hex key; cld rows have CREATE and CLOSE;
; wip rows have CREATE and an empty CLOSE; ? rows have only FID and MID
Func InvariantOk(ByRef $aR)
	Local $j
	For $j = 0 To UBound($aR) - 1
		Switch $aR[$j][$PC_STATUS]
			Case "cld", "wip"
				If Not StringRegExp($aR[$j][$PC_PATKEY], '^[0-9a-f]{16}$') Or $aR[$j][$PC_CREATE] == "" Then Return False
				If $aR[$j][$PC_STATUS] == "cld" And $aR[$j][$PC_CLOSE] == "" Then Return False
				If $aR[$j][$PC_STATUS] == "wip" And $aR[$j][$PC_CLOSE] <> "" Then Return False
			Case "?"
				If $aR[$j][$PC_PROT] <> "" Or $aR[$j][$PC_PAT] <> "" Or $aR[$j][$PC_PATKEY] <> "" Or $aR[$j][$PC_CREATE] <> "" Or $aR[$j][$PC_CLOSE] <> "" Then Return False
			Case Else
				Return False
		EndSwitch
	Next
	Return True
EndFunc ;==>InvariantOk
Assert(InvariantOk($aRows), "sample: cld/wip rows keyed, cld has CLOSE, wip has none, ? rows only FID/MID")

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

; --- real capture from a phantom: right-aligned %32s ProtName and PatName,
; newest-first, a running "wip" row on top with a "dependent files" column ---
$aRows = PC_ParseRaidList(FileRead(@ScriptDir & "\fixtures\raid_real_phantom.txt"))
$iErr = @error
$iExt = @extended
Assert($iErr = 0, "real phantom: @error = 0")
Assert($iExt = 0, "real phantom: @extended = 0")
Assert(UBound($aRows) = 5, "real phantom: 5 rows")
If UBound($aRows) <> 5 Then
	ConsoleWrite("FAIL: real phantom row count wrong, skipping row checks" & @CRLF)
	Exit(1)
EndIf
$bOk = True
For $i = 0 To 4
	If $aRows[$i][$PC_FID] <> 17068 - $i Then $bOk = False
Next
Assert($bOk, "real phantom: FIDs 17068-17064 in order (newest first)")
Assert($aRows[0][$PC_STATUS] == "wip", "real phantom: row 0 STATUS wip")
Assert($aRows[0][$PC_PROT] == "localizer_64ch @QA FMRI", "real phantom: row 0 PROT")
Assert($aRows[0][$PC_PAT] == "PHANTOM^ezFMRI,20060701", "real phantom: row 0 PAT")
Assert($aRows[0][$PC_CREATE] == "2026/10/15 21:22:24", "real phantom: row 0 CREATE")
Assert($aRows[0][$PC_CLOSE] == "", "real phantom: row 0 CLOSE is empty")
Assert($aRows[1][$PC_STATUS] == "cld" And $aRows[2][$PC_STATUS] == "cld" And $aRows[3][$PC_STATUS] == "cld" And $aRows[4][$PC_STATUS] == "cld", "real phantom: rows 1-4 STATUS cld")
Assert($aRows[1][$PC_PROT] == "AdjCoilSens" And $aRows[2][$PC_PROT] == "AdjDico" And $aRows[3][$PC_PROT] == "AdjTra" And $aRows[4][$PC_PROT] == "AdjFre", "real phantom: rows 1-4 PROT")
$bOk = StringRegExp($aRows[0][$PC_PATKEY], '^[0-9a-f]{16}$')
For $i = 1 To 4
	If Not ($aRows[$i][$PC_PATKEY] == $aRows[0][$PC_PATKEY]) Then $bOk = False
Next
Assert($bOk, "real phantom: all PATKEYs equal row 0")
Assert($aRows[1][$PC_CLOSE] == "2026/10/15 21:22:19", "real phantom: row 1 CLOSE")

; --- real layout: a protocol name of 32+ characters abuts MeasID ---
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(17069, 195, "ep2d_diff_mddw_30dir_p2_AP_b1000", "PHANTOM^ezFMRI,20060701"))
$iExt = @extended
Assert(UBound($aRows) = 1 And $aRows[0][$PC_STATUS] == "cld" And $aRows[0][$PC_FID] = 17069 And $aRows[0][$PC_MID] = 195 And $aRows[0][$PC_PROT] == "ep2d_diff_mddw_30dir_p2_AP_b1000", "32-char protocol: cld row, FID, MID and PROT")
Assert(UBound($aRows) = 1 And $aRows[0][$PC_PAT] == "PHANTOM^ezFMRI,20060701" And $aRows[0][$PC_PATKEY] == PC_PatKey("PHANTOM^ezFMRI,20060701"), "32-char protocol: PAT and PATKEY")
Assert($iExt = 0, "32-char protocol: @extended = 0")
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(17070, 196, "ep2d_diff_mddw_30dir_p2_AP_b1000_PA", "PHANTOM^ezFMRI,20060701"))
$iExt = @extended
Assert(UBound($aRows) = 1 And $aRows[0][$PC_STATUS] == "cld" And $aRows[0][$PC_FID] = 17070 And $aRows[0][$PC_PROT] == "ep2d_diff_mddw_30dir_p2_AP_b1000_PA", "35-char protocol: cld row, FID and PROT")
Assert(UBound($aRows) = 1 And $aRows[0][$PC_PAT] == "PHANTOM^ezFMRI,20060701" And $aRows[0][$PC_PATKEY] == PC_PatKey("PHANTOM^ezFMRI,20060701"), "35-char protocol: PAT and PATKEY")
Assert($iExt = 0, "35-char protocol: @extended = 0")

; --- real capture (VE11C): a 62-character name overflows the patient field
; (RaidTool truncates it, dropping comma and birthdate) and a patient
; registered without a birthdate prints as "TestPatient," ---
Global $sLong = "TEST^" & StringReplace(StringFormat("%57s", ""), " ", "t")
Global $sLongKey = PC_PatKey(StringRight($sLong, 32))
$aRows = PC_ParseRaidList(FileRead(@ScriptDir & "\fixtures\raid_real_longname.txt"))
$iErr = @error
$iExt = @extended
Assert($iErr = 0 And $iExt = 0, "real long name: @error = 0, @extended = 0")
Assert(UBound($aRows) = 30, "real long name: 30 rows")
If UBound($aRows) <> 30 Then
	ConsoleWrite("FAIL: real long name row count wrong, skipping row checks" & @CRLF)
	Exit(1)
EndIf
$bOk = True
For $i = 0 To 29
	If $aRows[$i][$PC_FID] <> 17091 - $i Or $aRows[$i][$PC_STATUS] == "?" Then $bOk = False
Next
Assert($bOk, "real long name: FIDs 17091-17062 in order, no ? rows")
$bOk = True
For $i = 0 To 7
	If Not ($aRows[$i][$PC_PAT] == StringRight($sLong, 32) And $aRows[$i][$PC_PATKEY] == $sLongKey) Then $bOk = False
Next
Assert($bOk, "real long name: 17091-17084 keyed on the last 32 characters")
Assert($aRows[0][$PC_PROT] == "localizer_64ch @QA FMRI " & StringTrimRight($sLong, 32) And $aRows[0][$PC_CREATE] == "2026/10/16 15:38:56" And $aRows[0][$PC_CLOSE] == "2026/10/16 15:39:09", "real long name: row 0 PROT (takes the name's overflow), CREATE and CLOSE")
Assert($aRows[8][$PC_FID] = 17083 And $aRows[8][$PC_PATKEY] == PC_PatKey("TEST,19580327"), "real long name: 17083 keyed as TEST,19580327")
Assert($aRows[14][$PC_FID] = 17077 And $aRows[14][$PC_PAT] == "TestPatient," And $aRows[14][$PC_PATKEY] == PC_PatKey("TestPatient,"), "real long name: 17077 keyed as TestPatient, (no birthdate)")
Assert($aRows[15][$PC_FID] = 17076 And $aRows[15][$PC_PATKEY] == PC_PatKey("PHANTOM^ezFMRI,20060701"), "real long name: phantom key unchanged")

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

; --- unknown status token: full line, but not cld or wip ---
$aRows = PC_ParseRaidList($sHdr & StringReplace(RaidLine(108, 58, "localizer", "DOE^JOHN,19800101"), " cld ", " opn "))
$iExt = @extended
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 108 And $aRows[0][$PC_MID] = 58 And $aRows[0][$PC_STATUS] == "?" And $aRows[0][$PC_PATKEY] == "", "unknown status opn: ? row with FID 108, MID 58")
Assert($iExt = 0, "unknown status opn: @extended = 0")

; --- wip row with a blank patient field ---
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(109, 59, "localizer", "", "15.10.2026 10:20:00"))
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 109 And $aRows[0][$PC_STATUS] == "?" And $aRows[0][$PC_PATKEY] == "", "wip, blank patient field: ? row with FID 109")

; --- real layout, blank patient field, 40-character protocol: the window lands
; on the protocol's last 32 characters (no whitespace); the gap rule rejects it ---
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(110, 60, StringReplace(StringFormat("%40s", ""), " ", "p"), ""))
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 110 And $aRows[0][$PC_STATUS] == "?" And $aRows[0][$PC_PATKEY] == "", "blank field, 40-char protocol: gap rule gives ? row with FID 110")

; --- real layout, blank patient field, short protocol with a comma: the window
; takes the protocol's tail plus padding; the run counts that padding ---
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(112, 62, "t1,sag", ""))
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 112 And $aRows[0][$PC_STATUS] == "?" And $aRows[0][$PC_PATKEY] == "", "blank field, protocol t1,sag: gap rule gives ? row with FID 112")

; --- fixture layout, blank patient field, 40-char protocol: the run is exactly
; 33 characters, one more than the field (pins the threshold) ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(113, 63, StringReplace(StringFormat("%40s", ""), " ", "p"), ""))
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 113 And $aRows[0][$PC_STATUS] == "?" And $aRows[0][$PC_PATKEY] == "", "blank field, run of 33: gap rule gives ? row with FID 113")

; --- patient field that is only a comma ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(111, 61, "localizer", ","))
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 111 And $aRows[0][$PC_STATUS] == "?" And $aRows[0][$PC_PATKEY] == "", "comma-only patient field: ? row with FID 111")

; --- patient field with a birthdate but no name ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(114, 64, "localizer", ",19800101"))
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 114 And $aRows[0][$PC_STATUS] == "?" And $aRows[0][$PC_PATKEY] == "", "empty name part ,19800101: ? row with FID 114")

; --- invariant over a mixed listing ---
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(103, 53, "t1", "DOE^JOHN,19800101", "15.10.2026 10:20:00") & "     102     52" & @CRLF & RaidLine(101, 51, "localizer", "DOE^JOHN,19800101"))
Assert(UBound($aRows) = 3 And InvariantOk($aRows), "mixed wip/?/cld listing: invariant holds")

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

; --- MakeBaseline: unreadable row at Get, fid is the keyed row ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & "     102     52" & @CRLF)
$aBase = PC_MakeBaseline($aRows, $sGet)
Assert($aBase[0] == PC_PatKey($sPatA) And $aBase[1] = 101 And $aBase[2] == $sGet, "MakeBaseline: key A, fid 101 (keyed row, not the ? row 102)")

; --- MakeBaseline: rows out of FID order ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(105, 55, "localizer", $sPatA) & RaidLine(107, 57, "localizer", $sPatB) & RaidLine(106, 56, "localizer", $sPatA) & "     108     58" & @CRLF)
$aBase2 = PC_MakeBaseline($aRows, $sGet)
Assert($aBase2[0] == PC_PatKey($sPatB) And $aBase2[1] = 107, "MakeBaseline: out of order, picks largest-FID cld row 107")

; --- MakeBaseline: no keyed rows ---
$aRows = PC_ParseRaidList($sHdr)
$aBase2 = PC_MakeBaseline($aRows, $sGet)
Assert($aBase2[0] == "" And $aBase2[1] = 0 And $aBase2[2] == $sGet, "MakeBaseline: no keyed rows gives empty key, fid 0")

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
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(5, 2, "t1", $sPatB, "15.10.2026 10:20:00") & RaidLine(4, 1, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (c): RAID reset, lone wip B at newest FID 5 -> MISMATCH")
$aRows = PC_ParseRaidList($sHdr & RaidLine(5, 1, "localizer", $sPatA) & RaidLineWip(5, 2, "t1", $sPatB, "15.10.2026 10:20:00"))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (c): RAID reset, duplicate FID 5, cld A then wip B -> MISMATCH")
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(5, 2, "t1", $sPatB, "15.10.2026 10:20:00") & RaidLine(5, 1, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "The most recent measurement belongs"), "Verdict (c): RAID reset, duplicate FID 5, wip B then cld A -> MISMATCH")

; --- (d) no keyed rows ---
$aRows = PC_ParseRaidList($sHdr & "     102     52" & @CRLF)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "No measurement with readable patient information"), "Verdict (d): only ? rows -> UNVERIFIED")
Assert($aV[2] == "", "Verdict (d): currentPat empty")

; --- (e) newer different-patient cld row (newest row is A again) ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(102, 52, "localizer", $sPatB) & RaidLine(103, 53, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Verdict (e): newer different-patient row -> MISMATCH")

; --- (e) newer ? row ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & "     102     52" & @CRLF)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "A newer measurement could not be read."), "Verdict (e): newer ? row -> UNVERIFIED")

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

; --- (f) IDs reused: ? row at the baseline FID is newer than the newest keyed row ---
$sLine = ""
For $i = 95 To 100
	$sLine &= RaidLine($i, $i - 50, "localizer", $sPatA)
Next
$aRows = PC_ParseRaidList($sHdr & $sLine & "     101     99" & @CRLF)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "A newer measurement could not be read."), "Verdict (f): cld A 95-100 and ? 101 -> UNVERIFIED")

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

; --- row 102 unreadable at Get (baseline fid 101), re-checked at Set ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(102, 52, "localizer", $sPatB))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Unread at Get: 102 closed for patient B -> MISMATCH")
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & "     102     52" & @CRLF)
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "A newer measurement could not be read."), "Unread at Get: 102 still ? -> UNVERIFIED")
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(102, 52, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, "No other patient has been scanned since these shims were saved."), "Unread at Get: 102 closed for patient A -> VERIFIED")
Assert($aV[2] == $sPatA, "Unread at Get: currentPat is patient A")

; --- same patient, recent ---
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(102, 52, "t1", $sPatA) & RaidLine(103, 53, "t2", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict: same patient, new rows, recent -> VERIFIED")
$aRows = PC_ParseRaidList($sHdr & RaidLine(100, 50, "localizer", $sPatA) & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Verdict: same patient, no new rows, recent -> VERIFIED")

; --- running measurements ("wip") ---
; A wip row means that patient is in the scanner now (an aborted scan ends as
; cld, and the patient cannot change mid-acquisition), so the idle check is
; skipped while the newest keyed row is wip.
; a newer running measurement of another patient (idle check on)
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(102, 52, "t1", $sPatB, "15.10.2026 10:20:00") & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(100, 50, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Wip: newer wip row for patient B -> MISMATCH")
Assert($aV[2] == $sPatB, "Wip: currentPat is the running patient B")

; a newer running measurement of the same patient; the last close (29.5 min
; ago) is over the 20 min limit, but the idle check is skipped
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(102, 52, "t1", $sPatA, "15.10.2026 10:20:00") & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 20, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Wip: newer wip row for patient A, idle check skipped -> VERIFIED")
Assert($aV[2] == $sPatA, "Wip: currentPat is the running patient A")

; last closed row 2 h ago, but a measurement started 10 min ago: not idle
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(102, 52, "t1", $sPatA, "15.10.2026 12:00:00") & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/15 12:10:00", 30, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Wip: cld closed 2 h ago, wip A created 10 min ago -> VERIFIED (not idle)")

; a measurement running longer than the idle limit: still that patient
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(102, 52, "t1", $sPatA, "15.10.2026 11:20:00") & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, "2026/10/15 12:00:00", 30, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Wip: wip A created 40 min ago, idle 30 -> VERIFIED")

; Get during the patient's first measurement, Set after it closed
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(101, 51, "localizer", $sPatA, "15.10.2026 10:05:00"))
$aBase2 = PC_MakeBaseline($aRows, $sGet)
Assert($aBase2[0] == PC_PatKey($sPatA) And $aBase2[1] = 101, "Wip: Get with only a wip row for A -> baseline key A, fid 101")
$aRows = PC_ParseRaidList($sHdr & RaidLineClosed(101, 51, "localizer", $sPatA, "15.10.2026 10:20:00"))
$aV = PC_Verdict($aBase2, $aRows, 0, $sSet, 30, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Wip: same FID now cld for A, closed recently -> VERIFIED")

; a running measurement dated in the future: CREATE is never compared with
; this computer's clock, so scanner clock skew is not detected from a wip row
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(102, 52, "t1", $sPatA, "15.10.2026 10:40:00") & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Wip: CREATE 10 min ahead -> VERIFIED (skew not read for wip)")

; a running measurement of the baseline patient over newer rows of another patient
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(103, 53, "t2", $sPatA, "15.10.2026 10:25:00") & RaidLine(102, 52, "t1", $sPatB) & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Wip: wip A newest over cld B above the baseline -> MISMATCH")

; a newer running measurement with an unreadable patient field
$aRows = PC_ParseRaidList($sHdr & RaidLineWip(102, 52, "localizer", "", "15.10.2026 10:20:00") & RaidLine(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, 0, $sSet, 60, 12)
Assert($aRows[0][$PC_STATUS] == "?" And VerdictIs($aV, $PC_UNVERIFIED, "A newer measurement could not be read."), "Wip: newer wip row with blank patient field -> ? -> UNVERIFIED")

; --- real capture: baseline at 17067, Set while 17068 is running for the same patient ---
$aRows = PC_ParseRaidList(FileRead(@ScriptDir & "\fixtures\raid_real_phantom.txt"))
$aBase2 = $aBase
$aBase2[0] = PC_PatKey("PHANTOM^ezFMRI,20060701")
$aBase2[1] = 17067
$aBase2[2] = "2026/10/15 21:22:30"
$aV = PC_Verdict($aBase2, $aRows, 0, "2026/10/15 21:25:00", 30, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Real phantom: baseline 17067, wip 17068 same patient -> VERIFIED")
$aV = PC_Verdict($aBase2, $aRows, 0, "2026/10/15 22:00:00", 30, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Real phantom: Set at 22:00 during a long scan -> VERIFIED")

; --- real capture (VE11C) with an overflowed long name on top ---
Global $sFixLong = FileRead(@ScriptDir & "\fixtures\raid_real_longname.txt")
$aRows = PC_ParseRaidList($sFixLong)
$aBase2 = PC_MakeBaseline($aRows, "2026/10/16 15:40:00")
Assert($aBase2[0] == $sLongKey And $aBase2[1] = 17091, "Real long name: Get records the long-name key at 17091")
$aV = PC_Verdict($aBase2, $aRows, 0, "2026/10/16 15:41:00", 0, 12)
Assert(VerdictIs($aV, $PC_VERIFIED, $sOk), "Real long name: Get then Set on the same listing -> VERIFIED")
$aBase2[0] = PC_PatKey("TEST,19580327")
$aBase2[1] = 17083
$aBase2[2] = "2026/10/16 06:10:00"
$aV = PC_Verdict($aBase2, $aRows, 0, "2026/10/16 15:41:00", 0, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Real long name: baseline TEST,19580327 at 17083, long name since -> MISMATCH")

; a newer row of another long-name patient, in the real overflow layout (one
; separator space after the protocol field, the rest pushed right)
Global $sLong2 = "OTHER^" & StringReplace(StringFormat("%56s", ""), " ", "u")
$sLine = StringFormat("%7d%11d%32s %31s%9s%13s%13s%22s%22s", 17092, 22, "AdjDico", $sLong2, "cld", 1598016, 4194304, "16.10.2026 15:45:00", "16.10.2026 15:45:02") & @CRLF
$aRows = PC_ParseRaidList(StringReplace($sFixLong, "  17091 ", $sLine & "  17091 ", 1))
$iExt = @extended
Assert($iExt = 0 And UBound($aRows) = 31 And $aRows[0][$PC_FID] = 17092 And $aRows[0][$PC_PATKEY] == PC_PatKey(StringRight($sLong2, 32)), "Real long name: newer long-name row parses and is keyed")
$aBase2[0] = $sLongKey
$aBase2[1] = 17091
$aBase2[2] = "2026/10/16 15:40:00"
$aV = PC_Verdict($aBase2, $aRows, 0, "2026/10/16 15:46:00", 0, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Real long name: baseline long name, newer other long name -> MISMATCH")

; --- real layout row with a BLANK FileID and a digit-leading protocol ---
; Without the 7-space anchor it would parse as FID 194, MID 3 and fall below
; the checked range (a false VERIFIED). It must be an unparsed line instead.
$sLine = StringFormat("%7s%11d%32s%32s%9s%13s%13s%22s%22s", "", 194, "3D_localizer", $sPatB, "cld", 1048576, 4194304, "15.10.2026 10:20:00", "15.10.2026 10:25:00") & @CRLF
$aRows = PC_ParseRaidList($sHdr & $sLine & RaidLine(101, 51, "localizer", $sPatA) & RaidLine(100, 50, "localizer", $sPatA))
$iExt = @extended
Assert($iExt = 1 And UBound($aRows) = 2, "Blank FileID: row is unparsed, @extended = 1")
$aV = PC_Verdict($aBase, $aRows, $iExt, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_UNVERIFIED, "Part of the RAID listing could not be read."), "Blank FileID: digit-leading protocol for patient B -> UNVERIFIED")

; Set time after the RaidLineReal rows close (21:22), so the clock check stays quiet
Global Const $sSetReal = "2026/10/15 21:40:00"
; --- retro-recon rows (MeasID >= 3000000, read from its column) are omitted ---
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(103, 3000001, "localizer", $sPatA) & RaidLineReal(102, 2999999, "localizer", $sPatA) & RaidLineReal(101, 51, "localizer", $sPatA))
$iExt = @extended
Assert(UBound($aRows) = 2 And $aRows[0][$PC_FID] = 102 And $aRows[1][$PC_FID] = 101 And $iExt = 0, "Retro-recon: MeasID 3000001 omitted, 2999999 kept, @extended = 0")
Assert(UBound($aRows) = 2 And $aRows[0][$PC_MID] = 2999999, "Retro-recon: kept row has MID 2999999")

; a newest retro-recon row of another patient must not trigger a mismatch
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(103, 3000005, "localizer", $sPatB) & RaidLineReal(102, 52, "localizer", $sPatA) & RaidLineReal(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, @extended, $sSetReal, 60, 12)
Assert(UBound($aRows) = 2 And VerdictIs($aV, $PC_VERIFIED, $sOk), "Retro-recon: newest row of patient B omitted -> VERIFIED")
; the same row below the retro threshold is a real new measurement
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(103, 2999999, "localizer", $sPatB) & RaidLineReal(102, 52, "localizer", $sPatA) & RaidLineReal(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, @extended, $sSet, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Retro-recon: same row with MeasID 2999999 -> MISMATCH")

; an unreadable ("?") row with a retro MeasID is omitted too, a low one is kept
$aRows = PC_ParseRaidList($sHdr & StringFormat("%7d%11d", 104, 3000000) & " junk" & @CRLF & StringFormat("%7d%11d", 103, 3500000) & @CRLF & StringFormat("%7d%11d", 102, 53) & " junk" & @CRLF)
$iExt = @extended
Assert(UBound($aRows) = 1 And $aRows[0][$PC_FID] = 102 And $aRows[0][$PC_STATUS] == "?" And $iExt = 0, "Retro-recon: ? row with retro MeasID omitted, low MeasID kept")

; guard: MeasID 300000 followed by a digit-leading 32-char protocol: the parsed MID
; is 3000001, but the MeasID column holds 300000, so the row is a real measurement
Global $sGlue = "1D_" & StringReplace(StringFormat("%29s", ""), " ", "x")
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(102, 300000, $sGlue, $sPatB) & RaidLineReal(101, 51, "localizer", $sPatA))
$iExt = @extended
Assert(UBound($aRows) = 2 And $aRows[0][$PC_FID] = 102 And $aRows[0][$PC_MID] = 3000001, "Retro-recon guard: glued protocol digits, row kept (MID parses as 3000001)")
$aV = PC_Verdict($aBase, $aRows, $iExt, $sSetReal, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Retro-recon guard: new patient B in the glued row -> MISMATCH")
; same, but the row falls to "?" (blank patient field): still kept, never VERIFIED
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(102, 300000, $sGlue, "") & RaidLineReal(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, @extended, $sSetReal, 60, 12)
Assert(UBound($aRows) = 2 And $aRows[0][$PC_STATUS] == "?" And VerdictIs($aV, $PC_UNVERIFIED, "A newer measurement could not be read."), "Retro-recon guard: glued protocol, blank patient -> ? row, UNVERIFIED")

; the column checks reject anything that is not a row with both numbers in their
; own columns: such a line is never silently dropped
$aRows = PC_ParseRaidList($sHdr & "Error: 3000000 abc def" & @CRLF & RaidLineReal(102, 52, "localizer", $sPatA) & RaidLineReal(101, 51, "localizer", $sPatA))
$iExt = @extended
$aV = PC_Verdict($aBase, $aRows, $iExt, $sSetReal, 60, 12)
Assert($iExt = 1 And UBound($aRows) = 2 And VerdictIs($aV, $PC_UNVERIFIED, "Part of the RAID listing could not be read."), "Retro-recon guard: non-row line is unparsed -> @extended 1, UNVERIFIED")
; text in the FileID column, MeasID column intact
$aRows = PC_ParseRaidList($sHdr & StringFormat("%-7s%11d", "Error:", 3000000) & " abc" & @CRLF & RaidLineReal(102, 52, "localizer", $sPatA) & RaidLineReal(101, 51, "localizer", $sPatA))
$iExt = @extended
Assert($iExt = 1 And UBound($aRows) = 2, "Retro-recon guard: text in the FileID column is not a row -> @extended 1")
; blank FileID, retro-looking MeasID, patient B
$sLine = StringFormat("%7s%11d%32s%32s%9s%13s%13s%22s%22s", "", 3000005, "localizer", $sPatB, "cld", 1048576, 4194304, "15.10.2026 21:30:00", "15.10.2026 21:30:05") & @CRLF
$aRows = PC_ParseRaidList($sHdr & $sLine & RaidLineReal(102, 52, "localizer", $sPatA) & RaidLineReal(101, 51, "localizer", $sPatA))
$iExt = @extended
$aV = PC_Verdict($aBase, $aRows, $iExt, $sSetReal, 60, 12)
Assert($iExt = 1 And UBound($aRows) = 2 And VerdictIs($aV, $PC_UNVERIFIED, "Part of the RAID listing could not be read."), "Retro-recon guard: blank FileID is not dropped -> @extended 1, UNVERIFIED")
; 8-digit FileID overflows into the MeasID column: kept, and patient B is seen
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(12345678, 3000005, "localizer", $sPatB) & RaidLineReal(101, 51, "localizer", $sPatA))
$aV = PC_Verdict($aBase, $aRows, @extended, $sSetReal, 60, 12)
Assert(UBound($aRows) = 2 And $aRows[0][$PC_FID] = 12345678 And VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Retro-recon guard: 8-digit FileID row kept -> MISMATCH")
; FileID overflowing into column 8 with no gap before the MeasID: not a row
$sLine = StringFormat("%8d%11s%32s%32s%9s%13s%13s%22s%22s", 12345678, "30000000005", "localizer", $sPatB, "cld", 1048576, 4194304, "15.10.2026 21:30:00", "15.10.2026 21:30:05") & @CRLF
$aRows = PC_ParseRaidList($sHdr & $sLine & RaidLineReal(102, 52, "localizer", $sPatA) & RaidLineReal(101, 51, "localizer", $sPatA))
$iExt = @extended
$aV = PC_Verdict($aBase, $aRows, $iExt, $sSetReal, 60, 12)
Assert($iExt = 1 And UBound($aRows) = 2 And VerdictIs($aV, $PC_UNVERIFIED, "Part of the RAID listing could not be read."), "Retro-recon guard: FileID overflowing into the MeasID column is not dropped -> UNVERIFIED")
; layout shifted left (%6d FileID): the "1" of the protocol lands in column 18
$sLine = StringFormat("%6d%11d%32s%32s%9s%13s%13s%22s%22s", 102, 1243569, "1 " & StringReplace(StringFormat("%30s", ""), " ", "x"), $sPatB, "cld", 1048576, 4194304, "15.10.2026 21:30:00", "15.10.2026 21:30:05") & @CRLF
$aRows = PC_ParseRaidList($sHdr & $sLine & RaidLineReal(101, 51, "localizer", $sPatA))
Assert(UBound($aRows) = 2 And $aRows[0][$PC_FID] = 102, "Retro-recon guard: row shifted left is kept")
; a retro row whose 32-character protocol starts right at column 19 (no separator)
; is still dropped
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(103, 3000005, "ep2d_diff_mddw_30dir_p2_AP_b1000", $sPatB) & RaidLineReal(102, 52, "localizer", $sPatA) & RaidLineReal(101, 51, "localizer", $sPatA))
$iExt = @extended
$aV = PC_Verdict($aBase, $aRows, $iExt, $sSetReal, 60, 12)
Assert($iExt = 0 And UBound($aRows) = 2 And $aRows[0][$PC_FID] = 102 And VerdictIs($aV, $PC_VERIFIED, $sOk), "Retro-recon: 32-char protocol with no separator: retro row dropped")

; Get side: a newest retro row of A must not become the baseline
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(121, 3000005, "localizer", $sPatA) & RaidLineReal(120, 60, "localizer", $sPatB) & RaidLineReal(119, 59, "localizer", $sPatB) & RaidLineReal(110, 50, "localizer", $sPatA))
$aBase2 = PC_MakeBaseline($aRows, $sGet)
Assert($aBase2[0] == PC_PatKey($sPatB) And $aBase2[1] = 120, "Retro-recon Get: baseline is patient B, fid 120 (not the retro row 121)")
$aRows = PC_ParseRaidList($sHdr & RaidLineReal(122, 62, "localizer", $sPatA) & RaidLineReal(121, 3000005, "localizer", $sPatA) & RaidLineReal(120, 60, "localizer", $sPatB) & RaidLineReal(119, 59, "localizer", $sPatB) & RaidLineReal(110, 50, "localizer", $sPatA))
$aV = PC_Verdict($aBase2, $aRows, @extended, $sSetReal, 60, 12)
Assert(VerdictIs($aV, $PC_MISMATCH, "A different patient has been scanned"), "Retro-recon Get: patient A scanned after baseline B -> MISMATCH")

; --- enum: UNVERIFIED is the zero value ---
Assert($PC_UNVERIFIED = 0 And $PC_VERIFIED <> 0, "Enum: UNVERIFIED is 0, VERIFIED is not")

ConsoleWrite(@CRLF & ($iFail = 0 ? "ALL PASSED" : $iFail & " FAILED") & @CRLF)
Exit($iFail > 0 ? 1 : 0)
