#include-once

; -----------------------------------------------------------------------------
; PatientCheck
; -----------------------------------------------------------------------------
;
; Parses the raw-data directory listing printed by Siemens' RaidTool
; ("RaidTool -a <ip> -p <port> -k -t <secs> -d") so ShimCache can check that
; the patient in the scanner matches the one saved shims were taken from.
;
; Pure functions only: no GUI, no logging, no file IO.
; -----------------------------------------------------------------------------

#include <Crypt.au3>
#include <StringConstants.au3>

; column indices of the 2D array returned by PC_ParseRaidList
Global Enum $PC_FID, $PC_MID, $PC_PROT, $PC_PAT, $PC_PATKEY, $PC_STATUS, $PC_CREATE, $PC_CLOSE, $PC_NCOLS

; Salt for PC_PatKey. This is a permanent on-disk contract: changing it
; invalidates every saved baseline and requires a trailer version bump.
; The key is pseudonymous, not anonymous: the salt is public and a name plus
; birthdate can be guessed, so shim files must not be treated as de-identified.
Global Const $PC_SALT = "ShimCache-PC-v1|"


; salted, truncated SHA-256 of a patient field (16 lowercase hex chars),
; or "" for an empty/blank field. Sets @error = 1 (and returns "") if hashing fails.
Func PC_PatKey($sPatField)
	Local $s = StringStripWS($sPatField, 3)
	If $s == "" Then Return ""
	Local $dHash = _Crypt_HashData(StringToBinary($PC_SALT & $s, $SB_UTF8), $CALG_SHA_256)
	If @error Then Return SetError(1, 0, "")
	Return StringLower(StringMid(String($dHash), 3, 16))
EndFunc ;==>PC_PatKey


; Parse a RaidTool -d listing into a 2D array [n][$PC_NCOLS], one row per file
; after the "FileID" header line.
;   STATUS "cld": closed file, fully parsed; PATKEY is always 16 hex chars.
;   STATUS "?"  : FileID/MeasID found but the rest is in progress, an unknown
;                 layout, or a patient field that fails the shape check. Only
;                 FID and MID are set; callers must treat it as unverifiable.
; Sets @error = 1 (and returns zero rows) if no header line is found.
; Otherwise @extended = number of non-blank lines after the header that could
; not be parsed at all. Only exact repeats of the detected header line (compared
; after trimming) are left out; any other unparsed line counts. Callers must treat
; @extended > 0 as "listing not fully understood".
Func PC_ParseRaidList($sText, $iPatWidth = 32)
	Local $aLines = StringSplit(StringStripCR($sText), @LF, $STR_NOCOUNT)
	Local $aRows[UBound($aLines)][$PC_NCOLS]		; preallocated, trimmed once at the end
	; The patient field is assumed to be right-aligned. If it is left-aligned,
	; the lazy protocol group lets the window slide left: PROT loses its last
	; characters and the key changes, giving a safe false mismatch.
	; A name longer than the field is keyed only on its last $iPatWidth characters,
	; and a field cut short at the width can lose birthdate digits. Both cases
	; still need checking against a real RaidTool capture.
	Local $sStrict = '^\s*(\d+)\s+(\d+)\s+(.+?)(.{' & $iPatWidth & '})\s+cld\s+(\d+)\s+(\d+)\s+(\d\d)\.(\d\d)\.(\d{4}) (\d\d:\d\d:\d\d)\s+(\d\d)\.(\d\d)\.(\d{4}) (\d\d:\d\d:\d\d)'
	Local $sLoose = '^\s*(\d+)\s+(\d+)(?:\s|$)'
	Local $iStart = -1, $n = 0, $iUnknown = 0, $i, $aM, $sPat
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
		$aM = StringRegExp($aLines[$i], $sStrict, $STR_REGEXPARRAYMATCH)
		If IsArray($aM) Then
			; key only "Name,BirthDate"-shaped fields; a blank field lets the
			; window slide onto the protocol name, which must not become a key
			$sPat = StringStripWS($aM[3], 3)
			If Not ($sPat == $sPrevPat) Then
				$sPrevPat = $sPat
				$sPrevKey = StringRegExp($sPat, '^\S.*,.*\S$') ? PC_PatKey($sPat) : ""
			EndIf
			If $sPrevKey <> "" Then
				$aRows[$n][$PC_FID] = Number($aM[0])
				$aRows[$n][$PC_MID] = Number($aM[1])
				$aRows[$n][$PC_PROT] = StringStripWS($aM[2], 3)
				$aRows[$n][$PC_PAT] = $sPat
				$aRows[$n][$PC_PATKEY] = $sPrevKey
				$aRows[$n][$PC_STATUS] = "cld"
				$aRows[$n][$PC_CREATE] = $aM[8] & "/" & $aM[7] & "/" & $aM[6] & " " & $aM[9]		; yyyy/mm/dd hh:mm:ss for _DateDiff
				$aRows[$n][$PC_CLOSE] = $aM[12] & "/" & $aM[11] & "/" & $aM[10] & " " & $aM[13]
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
