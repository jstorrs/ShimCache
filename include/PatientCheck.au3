#include-once

; -----------------------------------------------------------------------------
; PatientCheck
; -----------------------------------------------------------------------------
;
; Parses the raw-data directory listing printed by Siemens' RaidTool
; ("RaidTool -a <ip> -p <port> -k -t <secs> -d") so ShimCache can check that
; the patient in the scanner matches the one saved shims were taken from.
;
; At Get, PC_MakeBaseline/PC_FormatBaseline produce a one-line trailer
; ("#ShimCachePatientCheck v1 ...") naming the patient key of the newest keyed
; measurement (closed or still running) and its FID. At Set, PC_ParseBaseline
; reads it back and PC_Verdict compares it with a fresh listing: VERIFIED (no
; other patient since), MISMATCH (another patient seen, in a completed or a
; running measurement) or UNVERIFIED (cannot tell).
;
; Pure functions only: no GUI, no logging, no file IO.
; -----------------------------------------------------------------------------

#include <Crypt.au3>
#include <Date.au3>
#include <StringConstants.au3>

; column indices of the 2D array returned by PC_ParseRaidList
Global Enum $PC_FID, $PC_MID, $PC_PROT, $PC_PAT, $PC_PATKEY, $PC_STATUS, $PC_CREATE, $PC_CLOSE, $PC_NCOLS

; Salt for PC_PatKey. This is a permanent on-disk contract: changing it
; invalidates every saved baseline and requires a trailer version bump.
; The key is pseudonymous, not anonymous: the salt is public and a name plus
; birthdate can be guessed, so shim files must not be treated as de-identified.
Global Const $PC_SALT = "ShimCache-PC-v1|"

; MeasIDs from here up are retro-reconstructions of earlier raw data, possibly of
; a previous patient, not new measurements (YarraClient, rds_raid.cpp, skips them
; the same way). PC_ParseRaidList leaves such rows out.
Global Const $PC_RETRO_MEASID = 3000000


; salted, truncated SHA-256 of a patient field (16 lowercase hex chars),
; or "" for an empty/blank field. Sets @error = 1 (and returns "") if hashing fails.
Func PC_PatKey($sPatField)
	Local $s = StringStripWS($sPatField, 3)
	If $s == "" Then Return ""
	Local $dHash = _Crypt_HashData(StringToBinary($PC_SALT & $s, $SB_UTF8), $CALG_SHA_256)
	If @error Then Return SetError(1, 0, "")
	Return StringLower(StringMid(String($dHash), 3, 16))
EndFunc ;==>PC_PatKey


; True if a listing line is a retro-recon row: MeasID >= $PC_RETRO_MEASID, read
; from its fixed column (%7d FileID in columns 1-7, %11d MeasID in 8-18). Hiding
; a row from the check is unsafe if its MeasID is in doubt, since it could hide a
; new patient (a false VERIFIED), so each number must sit wholly inside its own
; column. That rejects non-row lines, a blank FileID (the MeasID would be read
; as the FileID), a FileID overflowing into the MeasID column, and a layout
; shifted left. Nothing is assumed about column 19 on: the protocol may or may
; not have a separator before it.
Func __PC_IsRetroRecon($sLine)
	If Not StringRegExp(StringLeft($sLine, 7), '^ *\d+$') Then Return False		; FileID ends at column 7
	If Not StringRegExp(StringMid($sLine, 8, 11), '^ +\d+$') Then Return False		; column 8 blank, MeasID ends at column 18
	Return Number(StringMid($sLine, 8, 11)) >= $PC_RETRO_MEASID
EndFunc ;==>__PC_IsRetroRecon


; Parse a RaidTool -d listing into a 2D array [n][$PC_NCOLS], one row per file
; after the "FileID" header line. Invariant:
;   STATUS "cld": closed measurement, fully parsed; PATKEY is always 16 hex
;                 chars; CREATE and CLOSE are set.
;   STATUS "wip": measurement still running, parsed like "cld"; PATKEY is always
;                 16 hex chars; CREATE is set and CLOSE is "" (RaidTool prints
;                 a placeholder close time, epoch 0, which must never be used).
;   STATUS "?"  : FileID/MeasID found but the rest is an unknown status or
;                 layout, or a patient field that is not keyed (see below). Only
;                 FID and MID are set; callers must treat it as unverifiable.
; Retro-recon rows (MeasID >= $PC_RETRO_MEASID, see __PC_IsRetroRecon) are
; omitted entirely, whether keyed or "?", and are not counted in @extended.
; Sets @error = 1 (and returns zero rows) if no header line is found.
; Otherwise @extended = number of non-blank lines after the header that could
; not be parsed at all. Only exact repeats of the detected header line (compared
; after trimming) are left out; any other unparsed line counts. Callers must treat
; @extended > 0 as "listing not fully understood".
Func PC_ParseRaidList($sText, $iPatWidth = 32)
	Local $aLines = StringSplit(StringStripCR($sText), @LF, $STR_NOCOUNT)
	Local $aRows[UBound($aLines)][$PC_NCOLS]		; preallocated, trimmed once at the end
	; Layout confirmed from real captures (tests\fixtures\raid_real_phantom.txt,
	; raid_real_longname.txt): fixed-width, every column right-aligned. ProtName
	; ends at column 50; PatName is one separator space plus a %31s field ending
	; at column 82 (seen when a long name overflows); the status is "cld" or
	; "wip"; the listing is newest-first. A "wip" row has the full layout, with
	; CloseTime 31.12.1969 19:00:00 (epoch 0 in local time). Trailing columns such
	; as "dependent files" are ignored: the pattern is not anchored at the end.
	; Unconfirmed: whether ProtName also has a separator space (no protocol of 32+
	; characters seen yet). If not, such a protocol abuts MeasID, so MeasID and
	; ProtName are split by \s* rather than \s+, which works either way. A protocol
	; name longer than its field overflows it and pushes the rest of the
	; line right; the patient window still works because it is anchored on the
	; status column. A digit-leading protocol may lose digits to MeasID, so both
	; MID and PROT can be off for such a row; the verdict uses neither.
	; An all-digit protocol of 32+ characters next to a 32-character patient name
	; can shift the patient window by one character: only a safe false mismatch.
	; Both patterns allow at most 7 leading spaces, anchoring the first number to
	; the %7d FileID column. Otherwise a row with a blank FileID and a digit-leading
	; protocol (e.g. "3D_localizer") would parse with FID = MeasID and MID = the
	; protocol digits; a new patient's row would then fall below $iFrom and be
	; ignored, a false VERIFIED. Such a row is now an unparsed line (@extended).
	; If a patient field were ever printed left-aligned, the lazy protocol group
	; would let the window slide left: PROT loses its last characters and the key
	; changes, giving a safe false mismatch; a short left-aligned name leaves a
	; long whitespace run before the status and becomes a "?" row (gap rule).
	; A name longer than the field (tests\fixtures\raid_real_longname.txt, VE11C)
	; overflows it: printed after one separator space, it pushes the rest of the
	; line right, and the gap before the status is unchanged. It is keyed on its
	; last $iPatWidth characters (the rest of the name lands in PROT), so two such
	; patients whose names share those characters cannot be told apart. A very
	; long name (62 characters seen on VE11C) is truncated by RaidTool and loses
	; the comma and birthdate. A patient registered without a birthdate prints as
	; "Name," and is keyed on that.
	; A blank patient field lets the window slide onto the protocol name, which
	; must not become a key. The whitespace run from the window's last visible
	; character to the status is then longer than the field itself, so such a
	; row is never keyed (gap rule; it counts trailing whitespace inside the
	; window, where a short protocol leaves it).
	Local $sStrict = '^\s{0,7}(\d+)\s+(\d+)\s*(.+?)(.{' & $iPatWidth & '})(\s+)(cld|wip)\s+(\d+)\s+(\d+)\s+(\d\d)\.(\d\d)\.(\d{4}) (\d\d:\d\d:\d\d)\s+(\d\d)\.(\d\d)\.(\d{4}) (\d\d:\d\d:\d\d)'
	Local $sLoose = '^\s{0,7}(\d+)\s+(\d+)'
	Local $iStart = -1, $n = 0, $iUnknown = 0, $i, $aM, $sPat, $sKey
	Local $sPrevPat = "", $sPrevKey = ""		; consecutive rows usually share a patient

	For $i = 0 To UBound($aLines) - 1
		If StringInStr($aLines[$i], "FileID", $STR_CASESENSE) Then
			$iStart = $i + 1
			ExitLoop
		EndIf
	Next
	If $iStart < 0 Then
		ReDim $aRows[0][$PC_NCOLS]
		Return SetError(1, 0, $aRows)
	EndIf

	For $i = $iStart To UBound($aLines) - 1
		If __PC_IsRetroRecon($aLines[$i]) Then ContinueLoop
		$aM = StringRegExp($aLines[$i], $sStrict, $STR_REGEXPARRAYMATCH)
		If IsArray($aM) Then
			; key only when the gap rules out a blank field, the name part (before
			; the first comma, if any) is not just whitespace and commas, and it is
			; "Name,BirthDate"-shaped (an empty birthdate included, an empty name
			; not) or fills the window (an overflowed name)
			$sPat = StringStripWS($aM[3], 3)
			$sKey = ""
			If StringLen($aM[4]) + StringLen($aM[3]) - StringLen(StringStripWS($aM[3], 2)) <= $iPatWidth And StringRegExp($sPat, '^[^,]*[^\s,]') And (StringInStr($sPat, ",") Or Not StringRegExp($aM[3], '\s')) Then
				If Not ($sPat == $sPrevPat) Then
					$sPrevPat = $sPat
					$sPrevKey = PC_PatKey($sPat)
				EndIf
				$sKey = $sPrevKey
			EndIf
			If $sKey <> "" Then
				$aRows[$n][$PC_FID] = Number($aM[0])
				$aRows[$n][$PC_MID] = Number($aM[1])
				$aRows[$n][$PC_PROT] = StringStripWS($aM[2], 3)
				$aRows[$n][$PC_PAT] = $sPat
				$aRows[$n][$PC_PATKEY] = $sKey
				$aRows[$n][$PC_STATUS] = $aM[5]
				$aRows[$n][$PC_CREATE] = $aM[10] & "/" & $aM[9] & "/" & $aM[8] & " " & $aM[11]		; yyyy/mm/dd hh:mm:ss for _DateDiff
				; a running measurement prints a placeholder close time: never use it
				$aRows[$n][$PC_CLOSE] = ($aM[5] == "cld" ? $aM[14] & "/" & $aM[13] & "/" & $aM[12] & " " & $aM[15] : "")
				$n += 1
				ContinueLoop
			EndIf
			; bad patient field: fall through to a "?" row (groups 0/1 are FID/MID)
		Else
			$aM = StringRegExp($aLines[$i], $sLoose, $STR_REGEXPARRAYMATCH)
		EndIf

		If IsArray($aM) Then
			; keep the IDs, mark unverifiable (preallocated cells are already "")
			$aRows[$n][$PC_FID] = Number($aM[0])
			$aRows[$n][$PC_MID] = Number($aM[1])
			$aRows[$n][$PC_STATUS] = "?"
			$n += 1
		ElseIf StringStripWS($aLines[$i], 8) <> "" And Not (StringStripWS($aLines[$i], 3) == StringStripWS($aLines[$iStart - 1], 3)) Then
			$iUnknown += 1
		EndIf
	Next

	ReDim $aRows[$n][$PC_NCOLS]
	Return SetError(0, $iUnknown, $aRows)
EndFunc ;==>PC_ParseRaidList


; -----------------------------------------------------------------------------
; Baseline and verdict
; -----------------------------------------------------------------------------

; verdicts returned in element [0] of PC_Verdict. UNVERIFIED is deliberately 0:
; an uninitialised, "" or 0 verdict compares equal to it, and must never be
; mistaken for VERIFIED.
Global Enum $PC_UNVERIFIED, $PC_MISMATCH, $PC_VERIFIED

; A baseline is a 3-element 1D array, captured at Get and checked at Set:
;   [0] patKey: 16 lowercase hex chars, or "" if no keyed row was listed
;   [1] fid:    FID (Number) of the row the key came from, 0 if none
;   [2] time:   capture time "yyyy/mm/dd hh:mm:ss" (the _DateDiff format)


; True for a keyed row status: "cld" or "wip" (always has a 16-hex PATKEY)
Func __PC_IsKeyed($sStatus)
	Return $sStatus == "cld" Or $sStatus == "wip"
EndFunc ;==>__PC_IsKeyed


; index of the keyed row ("cld" or "wip") with the largest FID, or -1 if there
; is none (rows are in listing order, which need not be FID order)
Func __PC_NewestKeyed(ByRef $aRows)
	Local $iBest = -1, $i
	For $i = 0 To UBound($aRows) - 1
		If __PC_IsKeyed($aRows[$i][$PC_STATUS]) And ($iBest < 0 Or $aRows[$i][$PC_FID] > $aRows[$iBest][$PC_FID]) Then $iBest = $i
	Next
	Return $iBest
EndFunc ;==>__PC_NewestKeyed


; Baseline from the listing taken at Get time.
; The keyed row is the newest "cld" or "wip" row, so a Get during a patient's
; first measurement still records them.
; fid is the FID of the KEYED row, not the largest FID overall. This is
; deliberate: an unreadable row at Get ("?") is newer than the keyed row, so
; PC_Verdict re-checks it at Set instead of trusting it unseen.
Func PC_MakeBaseline(ByRef $aRows, $sNowCalc)
	Local $aBase[3] = ["", 0, $sNowCalc]
	Local $i = __PC_NewestKeyed($aRows)
	If $i >= 0 Then
		$aBase[0] = $aRows[$i][$PC_PATKEY]
		$aBase[1] = $aRows[$i][$PC_FID]
	EndIf
	Return $aBase
EndFunc ;==>PC_MakeBaseline


; One-line baseline trailer for the shim file, e.g.
;   #ShimCachePatientCheck v1 pat=4af9e7f2cece32cc fid=101 at=20261015101000
; This is a PERMANENT on-disk format. Any change to it needs a "v2" tag, and the
; v1 parser (PC_ParseBaseline) must keep rejecting every other version.
; Sets @error = 1 (and returns "") if the time is not "yyyy/mm/dd hh:mm:ss" or
; fid is not a whole number in 0..999999999999999 (the parser's \d{1,15}), so
; a line PC_ParseBaseline would reject or misread is never written.
Func PC_FormatBaseline($aBase)
	If Not StringRegExp($aBase[2], '^\d{4}/\d\d/\d\d \d\d:\d\d:\d\d$') Then Return SetError(1, 0, "")
	If $aBase[1] < 0 Or $aBase[1] > 999999999999999 Or $aBase[1] <> Int($aBase[1]) Then Return SetError(1, 0, "")
	Return "#ShimCachePatientCheck v1 pat=" & ($aBase[0] == "" ? "-" : $aBase[0]) & " fid=" & $aBase[1] & " at=" & StringRegExpReplace($aBase[2], "\D", "")
EndFunc ;==>PC_FormatBaseline


; Parse a PC_FormatBaseline line back into a baseline array.
; Surrounding whitespace (including CRLF) is ignored; anything else that is not
; an exact v1 line sets @error = 1 and returns 0. fid is limited to 15 digits so
; Number() stays an exact integer.
Func PC_ParseBaseline($sLine)
	Local $aM = StringRegExp(StringStripWS($sLine, 3), '^#ShimCachePatientCheck v1 pat=([0-9a-f]{16}|-) fid=(\d{1,15}) at=(\d{14})$', $STR_REGEXPARRAYMATCH)
	If Not IsArray($aM) Then Return SetError(1, 0, 0)
	Local $aBase[3]
	$aBase[0] = ($aM[0] == "-" ? "" : $aM[0])
	$aBase[1] = Number($aM[1])
	$aBase[2] = StringRegExpReplace($aM[2], '(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)', '$1/$2/$3 $4:$5:$6')
	Return $aBase
EndFunc ;==>PC_ParseBaseline


; [verdict, reason, currentPat] for PC_Verdict
Func __PC_Result($iVerdict, $sReason, $sPat)
	Local $aOut[3] = [$iVerdict, $sReason, $sPat]
	Return $aOut
EndFunc ;==>__PC_Result


; keep the first candidate reason found: $sNew only if $sCur is still ""
Func __PC_First($sCur, $sNew)
	Return ($sCur == "" ? $sNew : $sCur)
EndFunc ;==>__PC_First


; Compare a baseline with a fresh listing taken at Set time.
; $iUnknown is PC_ParseRaidList's @extended (lines it could not parse at all).
; Returns [verdict, reason, currentPat]; currentPat is the PAT of the newest
; keyed ("cld" or "wip") row (or "") for display only, never for logging.
; A false VERIFIED is the dangerous direction, so every doubt (unreadable rows
; or lines, date errors, clock skew, stale shims, an idle scanner) ends in
; UNVERIFIED or MISMATCH. MISMATCH wins over UNVERIFIED; within each, the first
; reason found is kept.
; $iIdleMin = 0 and $iMaxAgeHours = 0 turn the idle and age checks off.
; The idle check assumes the scanner clock matches this computer (normally true:
; the recon system takes its time from the console at boot); a persistent skew
; larger than 5 minutes would delay it by that skew.
Func PC_Verdict($aBase, ByRef $aRows, $iUnknown, $sNowCalc, $iIdleMin, $iMaxAgeHours)
	Local $iNewest = __PC_NewestKeyed($aRows)
	Local $sPat = "", $iMaxFid = -1, $iFrom, $sMis = "", $sUnv = "", $i, $iDiff
	If $iNewest >= 0 Then $sPat = $aRows[$iNewest][$PC_PAT]

	; (a)-(d): nothing reliable to compare against, return at once. The one
	; exception is (c) with a different patient on the RAID: that is a MISMATCH.
	If Not IsArray($aBase) Or UBound($aBase, 0) <> 1 Or UBound($aBase) <> 3 Then Return __PC_Result($PC_UNVERIFIED, "These shims were saved without readable patient information (older file, damaged trailer, or RaidTool was unavailable when they were saved).", $sPat)
	If $aBase[0] == "" Then Return __PC_Result($PC_UNVERIFIED, "No patient data was on the RAID when these shims were saved.", $sPat)
	For $i = 0 To UBound($aRows) - 1
		If $aRows[$i][$PC_FID] > $iMaxFid Then $iMaxFid = $aRows[$i][$PC_FID]
	Next
	If UBound($aRows) = 0 Or $iMaxFid < $aBase[1] Then
		; RAID cleared or IDs reset: the newest keyed rows (every "cld" or "wip" row
		; at the newest keyed FID, whatever the listing order) still tell us who is there
		If $iNewest >= 0 Then
			For $i = 0 To UBound($aRows) - 1
				If __PC_IsKeyed($aRows[$i][$PC_STATUS]) And $aRows[$i][$PC_FID] = $aRows[$iNewest][$PC_FID] And Not ($aRows[$i][$PC_PATKEY] == $aBase[0]) Then Return __PC_Result($PC_MISMATCH, "The most recent measurement belongs to a different patient.", $sPat)
			Next
		EndIf
		Return __PC_Result($PC_UNVERIFIED, "The RAID listing is older than these shims (RAID cleared or IDs reset).", $sPat)
	EndIf
	If $iNewest < 0 Then Return __PC_Result($PC_UNVERIFIED, "No measurement with readable patient information is on the RAID.", $sPat)

	; (e)/(f) every row from $iFrom up must be keyed ("cld" or "wip") and the same
	; patient. A running measurement names its patient too, so a different patient
	; in it is a MISMATCH and the same patient is fine.
	; $iFrom is the row after the keyed baseline row, or the newest keyed row if
	; that is lower (IDs reused), so duplicate FIDs are checked whatever their
	; listing order and a "?" row above the newest keyed row is never skipped.
	$iFrom = $aBase[1] + 1
	If $aRows[$iNewest][$PC_FID] < $iFrom Then $iFrom = $aRows[$iNewest][$PC_FID]
	For $i = 0 To UBound($aRows) - 1
		If $aRows[$i][$PC_FID] < $iFrom Then ContinueLoop
		If Not __PC_IsKeyed($aRows[$i][$PC_STATUS]) Then
			; "?" (or any status other than "cld"/"wip") cannot be checked
			$sUnv = __PC_First($sUnv, "A newer measurement could not be read.")
		ElseIf Not ($aRows[$i][$PC_PATKEY] == $aBase[0]) Then
			$sMis = __PC_First($sMis, ($aRows[$i][$PC_FID] > $aBase[1] ? "A different patient has been scanned since these shims were saved." : "The most recent measurement belongs to a different patient."))
		EndIf
	Next

	; lines the parser could not read may hide a newer measurement
	If $iUnknown > 0 Then $sUnv = __PC_First($sUnv, "Part of the RAID listing could not be read.")

	; (g) shims too old to trust, or dated in the future (clock changed)
	If $iMaxAgeHours > 0 Then
		$iDiff = _DateDiff("h", $aBase[2], $sNowCalc)
		If @error Then
			$sUnv = __PC_First($sUnv, "Could not compare the scanner's dates with this computer's clock.")
		ElseIf $iDiff < -1 Then
			$sUnv = __PC_First($sUnv, "These shims are dated in the future; this computer's clock may have changed.")
		ElseIf $iDiff >= $iMaxAgeHours Then
			$sUnv = __PC_First($sUnv, "These shims were saved " & $iDiff & " hours ago.")
		EndIf
	EndIf

	; (h) scanner idle: a new patient may be registered but not yet scanned.
	; Measured from the newest keyed row's CLOSE. Skipped while that row is "wip"
	; (its CLOSE is "" and never reaches _DateDiff): an aborted scan ends as "cld",
	; and the patient cannot change while a row is "wip" (the table is locked by
	; the acquisition), so a "wip" row means that patient is in the scanner now.
	; If it is another patient, the loop above has already found a MISMATCH.
	; A "wip" row that never closes (e.g. recon crashed mid-acquisition) would
	; bypass this check until another patient's row appears; $iMaxAgeHours still
	; bounds it, and the README checklist covers it.
	; _DateDiff floors negative results, so allow 5 minutes of ordinary skew.
	If $iIdleMin > 0 And Not ($aRows[$iNewest][$PC_STATUS] == "wip") Then
		$iDiff = _DateDiff("n", $aRows[$iNewest][$PC_CLOSE], $sNowCalc)
		If @error Then
			$sUnv = __PC_First($sUnv, "Could not compare the scanner's dates with this computer's clock.")
		ElseIf $iDiff < -5 Then
			$sUnv = __PC_First($sUnv, "The scanner clock is ahead of this computer; cannot tell how long the scanner has been idle.")
		ElseIf $iDiff > $iIdleMin Then
			$sUnv = __PC_First($sUnv, "No measurement has finished in the last " & $iIdleMin & " minutes; a new patient may be registered but not yet scanned.")
		EndIf
	EndIf

	If $sMis <> "" Then Return __PC_Result($PC_MISMATCH, $sMis, $sPat)
	If $sUnv <> "" Then Return __PC_Result($PC_UNVERIFIED, $sUnv, $sPat)
	Return __PC_Result($PC_VERIFIED, "No other patient has been scanned since these shims were saved.", $sPat)
EndFunc ;==>PC_Verdict
