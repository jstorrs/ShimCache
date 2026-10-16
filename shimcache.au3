; -----------------------------------------------------------------------------
; ShimCache
; -----------------------------------------------------------------------------
;
; A small GUI for saving and recalling shim sets on Siemens scanners. Uses the
; command-line AdjValidate tool available on the IDEA website.
;
; Patrick Bolan, UMN CMRR
; Chris Rodgers, Cambridge
; Edward Auerbach, UMN CMRR
;
; Versions:
;   2009.10.10 - PB - Created
;   2012.08.13 - PB - Updated for VB17
;   2017.12.12 - CR - Updated to support 7T Terra VE11R
;   2022.12.01 - EA - Refreshed UI, added more error checking/validation,
;                     added B1 and FASTMAP mode options, updated to support
;                     all current versions including Numaris X (XA30A)
;   2024.12.03 - EA - Updated AdjValidate syntax for XA60A+ multi-GPA configs,
;                     improved error handling and reporting
;   2026.10.15 - JS - Added RaidTool patient check before Set; build-time
;                     config.au3 (incl. initial shim columns)
; -----------------------------------------------------------------------------

Const $PgmVersion = "2026.10.15"

#AutoIt3Wrapper_Res_Icon_Add=include/icons/b0_icon.ico
#AutoIt3Wrapper_Res_Icon_Add=include/icons/b1_icon.ico
#AutoIt3Wrapper_Res_Icon_Add=include/icons/m_icon_new.ico
#AutoIt3Wrapper_Icon=include/icons/m_icon_new.ico
#AutoIt3Wrapper_UseX64=y

#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <GuiListView.au3>
#include <GuiEdit.au3>
#include <FontConstants.au3>
#include <AutoItConstants.au3>
#include <Misc.au3>
#include "include/GuiListViewEx.au3"
#include "include/ListViewCustomDraw.au3"
#include "include/config.au3"
#include "include/PatientCheck.au3"

Opt('MustDeclareVars', 1)
Opt("GUIOnEventMode", 1)

; set default GUI mode, can be overridden by command line: 0=B0, 1=B1, 2=FASTMAP
Global $GUIMode = 0

Global $PgmName, $ShimFilePrefix, $ShimFileSuffix	; global text
Global $AdjValidate, $ScratchDir					; filenames/paths
Global $idGet = 0, $idSet = 0							; Get/Set buttons (0 if not created in this mode)
Global $hGUI, $idExit, $hList, $idList, $idEdit		; window handles
Global $winW, $winH									; window dimensions (minimum)
Global $winWFull, $winMinW							; width with 3rd-order columns; narrowest that fits the buttons

; 3rd-order shim columns (B0/FASTMAP), dropped when every shimset is 2nd order
Global Const $ThirdOrderCols[4] = ["Z3", "Z2X", "Z2Y", "Z(X2-Y2)"]
Global Const $ThirdOrderFirstCol = 10				; 2 label columns + 8 2nd-order shims
Global $listHasThirdOrder = True
Global $FM_LastLog = -1								; remember last displayed FASTMAP logfile
Global $NoOfGPAs = 1								; number of GPAs in system (important >XA60)
Global $debugLog = 0								; debug log level (0 = release, 1 = debug)
Global $RaidTool = ""									; resolved path to RaidTool.exe
Global $PC_Enabled = False								; runtime switch for the patient check

; for multi-line list view (B1 mode)
Global $hListFont, $fListHasFocus=0, $listRows, $listData[1][1]
#include "include/GlobalUI.au3"

; get parameters from the environment, can use to customize
Global $screenH = @DesktopHeight
Global $screenW = @DesktopWidth

; 0=default, 1=NX widescreen
Global $screenType = 0
if (($screenH == 1200) And ($screenW = 1920)) Then
	$screenType = 1
EndIf

; read optional command line parameters (GUIMode, working directory)
If ($CmdLine[0] > 0) Then
	$GUIMode = $CmdLine[1]
	If ($CmdLine[0] > 1) Then
		$ScratchDir = $CmdLine[2]
	EndIf
EndIf

; set some parameters based on mode
If ($GUIMode == 2) Then
	$PgmName = "Set FASTMAP Shims"
	$ShimFilePrefix = ""
	$ShimFileSuffix = ""
ElseIf ($GUIMode == 1) Then
	$PgmName = "ShimCache B1"
	$ShimFilePrefix = "shimsetb1_"
	$ShimFileSuffix = ".txt"
Else
	$PgmName = "ShimCache B0"
	$ShimFilePrefix = "shimset_"
	$ShimFileSuffix = ".txt"
EndIf


; -----------------------------------------------------------------------------
; execution
; -----------------------------------------------------------------------------

; allow one instance per mode; if this mode is already running, raise its
; window instead of opening a second copy
RaiseExistingInstance()

; execute the main loop
_Main()


; -----------------------------------------------------------------------------
; single instance
; -----------------------------------------------------------------------------

Func RaiseExistingInstance()
	; the mutex is held for the lifetime of this process; _Singleton returns 0
	; if another process already owns it
	If (_Singleton("ShimCache_" & $PgmName, 1) <> 0) Then Return

	; match the exact title and AutoIt GUI class so we don't grab an unrelated
	; window (e.g. an editor with "ShimCache" in its title); wait briefly in
	; case the other instance has not created its window yet
	Local $sWin = "[TITLE:" & $PgmName & "; CLASS:AutoIt v3 GUI]"
	Local $hWin = WinWait($sWin, "", 3)
	If ($hWin == 0) Then
		; no window: the other instance was likely just closing, so if the
		; mutex has been released, carry on as the new instance
		If (_Singleton("ShimCache_" & $PgmName, 1) <> 0) Then Return
		Exit 0
	EndIf

	If BitAND(WinGetState($hWin), $WIN_STATE_MINIMIZED) Then WinSetState($hWin, "", @SW_RESTORE)
	WinActivate($hWin)

	; FASTMAP values come from a log that changes on every FASTMAP run, so the
	; raised window must reload it or "Apply Selected" would use stale shims
	If ($GUIMode == 2) Then ControlClick($hWin, "", "[CLASS:Button; TEXT:Refresh]")
	Exit 0
EndFunc ;==>RaiseExistingInstance


; -----------------------------------------------------------------------------
; common functions
; -----------------------------------------------------------------------------

; main loop
Func _Main()
	; set parameters which will determine the window dimensions (was fixed: VB17=740x204; VE11=940x204)
	Const $lhB = 2		; left hand border
	Const $rhB = 2		; right hand border
	Const $topB = 2		; top border
	Const $btmB = 2		; bottom border
	Const $btnH = 20	; button height
	Const $hPad = 5		; button horizontal padding
	Const $vPad = 4		; vertical padding between boxes and buttons

	; define a starting window width (this will be the minimum)
	$winW = 940			; 940 pixels wide should be enough for 3rd orders

	; define default height of list box and console log box in lines
	Local $nListBoxLines = 5
	Local $nEditBoxLines = 5

	; set the fonts of the list and edit boxes so we know the exact height to calculate the size of the boxes
	Const $mainFontSz = 8.5
	Const $mainFontNm = "Microsoft Sans Serif"
	Const $mainFontH = 14
	Local $editFontSz = $mainFontSz
	Local $editFontNm = $mainFontNm
	Local $editFontH = $mainFontH

	; default parameters are for B0 mode; modify parameters for different modes
	If ($GUIMode == 1) Then
		; for B1 mode we may want to change the window width
		$winW = 1245 ; this is good for 16Tx in VE12
	ElseIf ($GUIMode == 2) Then
		; FASTMAP mode can use a narrower window width since it stores integer shim DAC/currents
		; the edit box is much larger and monospaced
		$winW = 770
		$nListBoxLines = 4
		$editFontSz = 8
		$editFontNm = "Lucida Console"
		$editFontH = 11
		$nEditBoxLines = 75
		If $screenType == 1 Then $nEditBoxLines = 90
	EndIf

	$winWFull = $winW

	; calculate dependent parameters
	Local $listBoxH = $nListBoxLines*($mainFontH+3) + 28 ; +28 for header row, +3 per line for selection border?
	Local $editBoxH = $nEditBoxLines*$editFontH
	$winH = $topB + $btnH + $vPad + $listBoxH + $editBoxH + $btmB;

	; create the main window
	$hGUI = GUICreate($PgmName, $winW+2, $winH+24, -1, -1, $WS_SIZEBOX + $WS_SYSMENU)
	GUISetFont($mainFontSz, $FW_NORMAL, $GUI_FONTNORMAL, $mainFontNm)

    ; set icon (uses negative numbers starting with -5 for first included)
	If ($GUIMode == 0) Then
		GUISetIcon(@AutoItExe, -5)
	ElseIf ($GUIMode == 1) Then
		GUISetIcon(@AutoItExe, -6)
	EndIf

	; top row of buttons, left side
	Local $left, $btnW
	If ($GUIMode == 2) Then
		; special UI for FASTMAP
		$left = $lhB
		$btnW = 90
		Local $ApplyID = GUICtrlCreateButton("Apply Selected", $left, $topB, $btnW, $btnH)
		GUICtrlSetResizing($ApplyID, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKLEFT)
		$left += $btnW + $hPad
		$btnW = 60
		Local $RefreshID = GUICtrlCreateButton("Refresh", $left, $topB, $btnW, $btnH)
		GUICtrlSetResizing($RefreshID, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKLEFT)

		; button press callbacks
		GUICtrlSetOnEvent($ApplyID, "OnSet")
		GUICtrlSetOnEvent($RefreshID, "UpdateListView")
	Else
		; general UI for B0/B1 shimming
		$left = $lhB
		$btnW = 50
		$idGet = GUICtrlCreateButton("Get", $left, $topB, $btnW, $btnH)
		GUICtrlSetResizing($idGet, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKLEFT)
		$left += $btnW + $hPad
		$btnW = 50
		$idSet = GUICtrlCreateButton("Set", $left, $topB, $btnW, $btnH)
		GUICtrlSetResizing($idSet, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKLEFT)
		;$left += $btnW + $hPad
		;$btnW = 60
		;Local $RefreshID = GUICtrlCreateButton("Refresh", $left, $topB, $btnW, $btnH)
		;GUICtrlSetResizing($RefreshID, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKLEFT)
		$left += $btnW + $hPad
		$btnW = 100
		Local $ClearID = GUICtrlCreateButton("Delete Selected", $left, $topB, $btnW, $btnH)
		GUICtrlSetResizing($ClearID, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKLEFT)
		$left += $btnW + $hPad
		$btnW = 110
		Local $ClearUnSelID = GUICtrlCreateButton("Delete Unselected", $left, $topB, $btnW, $btnH)
		GUICtrlSetResizing($ClearUnSelID, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKLEFT)
		$left += $btnW + $hPad
		$btnW = 70
		Local $ClearAllID = GUICtrlCreateButton("Delete All", $left, $topB, $btnW, $btnH)
		GUICtrlSetResizing($ClearAllID, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKLEFT)

		; button press callbacks
		GUICtrlSetOnEvent($idGet, "OnGet")
		GUICtrlSetOnEvent($idSet, "OnSet")
		;GUICtrlSetOnEvent($RefreshID, "UpdateListView")
		GUICtrlSetOnEvent($ClearID, "OnClear")
		GUICtrlSetOnEvent($ClearUnSelID, "OnClearUnselected")
		GUICtrlSetOnEvent($ClearAllID, "OnClearAll")
	EndIf

	; narrowest width that fits the left buttons plus About/Exit on the right
	$winMinW = $left + $btnW + $hPad + 50 + $hPad + 50 + $rhB

	; top row of buttons, right side
	$left = $winW - $rhB
	$btnW = 50
	$idExit = GUICtrlCreateButton("Exit", $left-$btnW, $topB, $btnW, $btnH)
	GUICtrlSetResizing($idExit, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKRIGHT)
	$left -= $btnW + $hPad
	$btnW = 50
	Local $AboutID = GUICtrlCreateButton("About", $left-$btnW, $topB, $btnW, $btnH)
	GUICtrlSetResizing($AboutID, $GUI_DOCKSIZE + $GUI_DOCKTOP + $GUI_DOCKRIGHT)

	; button press callbacks
	GUICtrlSetOnEvent($AboutID, "OnAbout")
	GUICtrlSetOnEvent($idExit, "OnExit")

    ; event callbacks
	GUISetOnEvent($GUI_EVENT_CLOSE, "OnExit")
	GUIRegisterMsg($WM_GETMINMAXINFO, "WM_GETMINMAXINFO") ; monitors resizing of the GUI

	; list box (global)
	Local $header = "#|Description|X|Y|Z|Z2|ZX|ZY|X2-Y2|XY|Z3|Z2X|Z2Y|Z(X2-Y2)"
	If ($GUIMode == 1) Then
		$header = "#|Description        |Tx1    |Tx2    |Tx3    |Tx4    |Tx5    |Tx6    |Tx7    |Tx8    |Tx9    |Tx10   |Tx11   |Tx12   |Tx13   |Tx14   |Tx15   |Tx16   "
	ElseIf ($GUIMode == 2) Then
		$header = "Set   |Date/Time|X|Y|Z|Z2|ZX|ZY|X2-Y2|XY|Z3|Z2X|Z2Y|Z(X2-Y2)"
	EndIf
	Local $listStyle = $LVS_REPORT + $LVS_NOSORTHEADER + $LVS_SHOWSELALWAYS
	Local $listExStyle = $WS_EX_CLIENTEDGE + $LVS_EX_DOUBLEBUFFER + $LVS_EX_FULLROWSELECT ; + $LVS_EX_GRIDLINES
	If ($GUIMode == 2) Then $listStyle += $LVS_SINGLESEL ; only one selection at at time for FASTMAP
	$idList = GUICtrlCreateListView($header, $lhB, $btnH+$vPad, $winW-$lhB-$rhB, $listBoxH, $listStyle, $listExStyle)
	$hList = GUICtrlGetHandle($idList)
	If ($GUIMode == 1) Then $hListFont = _GUICtrlListView_SetItemHeightByFont($hList, $mainFontH*2-4) ; double row height for B1 mode

	; console log box (global)
	If ($GUIMode == 2) Then GUISetFont($editFontSz, $FW_NORMAL, $GUI_FONTNORMAL, $editFontNm) ; use monospaced log window font for FASTMAP
	$idEdit = GUICtrlCreateEdit("", $lhB, $topB+$btnH+$listBoxH+$vPad, $winW-$lhB-$rhB, $editBoxH, _
		BitOr($ES_READONLY, $ES_MULTILINE, $WS_VSCROLL, $ES_AUTOVSCROLL), $WS_EX_STATICEDGE + $WS_EX_NOACTIVATE)
	_GUICtrlEdit_SetLimitText($idEdit, -1) ; remove 30000 char limit!

	If ($GUIMode == 2) Then
		; for FASTMAP, fix size of list box, allow enlarging edit box
		GUICtrlSetResizing($idList, $GUI_DOCKTOP + $GUI_DOCKHEIGHT)
		GUICtrlSetResizing($idEdit, $GUI_DOCKTOP + $GUI_DOCKBOTTOM)
	Else
		; for B0/B1 shim, allow enlarging list box only
		GUICtrlSetResizing($idList, $GUI_DOCKTOP + $GUI_DOCKBOTTOM)
		GUICtrlSetResizing($idEdit, $GUI_DOCKHEIGHT + $GUI_DOCKBOTTOM)
	EndIf

	_Setup()			; set/check defaults
	UpdateListView()	; initialize the list (may narrow the window for 2nd-order shims)
	GUISetState()		; display the GUI once it has its final width, so it doesn't flash wide
	GUICtrlSetState($idList, $GUI_FOCUS) ; focus set while hidden may not survive showing the window

	; idle until the user exits; in OnEvent mode, events are dispatched to the
	; registered handlers (OnExit etc.) while the script sleeps
	While 1
		Sleep(100)
	WEnd
EndFunc ;==>Main


Func _Setup()
	; verify location of AdjValidate program and scratch directory
	; since XA, AdjValidate will be in either MED_BIN or CustomerBin
	; fallback to MEDHOME\bin on older versions
	$AdjValidate = FindSiemensTool("AdjValidate.exe")
	If ($AdjValidate == "" And FileExists("C:\Temp\AdjValidate.exe")) Then $AdjValidate = "C:\Temp\AdjValidate.exe" ; for testing only

	If ($AdjValidate == "") Then
		MsgBox($MB_SYSTEMMODAL + $MB_TOPMOST, $PgmName & ": Setup Error", "ERROR! Could not locate AdjValidate.exe!" & @CRLF & @CRLF _
			   & "Please make sure it is installed and matches this software version!")
		Exit 1
	EndIf

	LogMessage("Found " & $AdjValidate)

	; verify working directory, which will be used for our temporary files
	If (FileExists($ScratchDir) == 1) Then
		; user set explicitly on command line, always use this
	ElseIf (($GUIMode == 2) And (FileExists(EnvGet("CustomerSeq")) == 1)) Then
		; FASTMAP files are in %CustomerSeq%
		$ScratchDir = EnvGet("CustomerSeq")
	ElseIf (FileExists(EnvGet("TEMP")) == 1) Then
		; general default is %TEMP%
		$ScratchDir = EnvGet("TEMP")
	Else
		MsgBox($MB_SYSTEMMODAL + $MB_TOPMOST, $PgmName & ": Setup Error", "ERROR! Invalid working directory!")
		Exit 1
	EndIf

	FileChangeDir($ScratchDir)
	LogMessage("Working directory is " & $ScratchDir)

	; patient check (FASTMAP is excluded in v1)
	If ($GUIMode == 2) Then
		$PC_Enabled = False
	ElseIf (Not $CFG_PC_ENABLED) Then
		LogMessage("Patient check disabled in this build")
	Else
		$PC_Enabled = True
		$RaidTool = ($CFG_RAIDTOOL <> "" ? $CFG_RAIDTOOL : FindSiemensTool("RaidTool.exe"))
		If ($RaidTool <> "" And Not FileExists($RaidTool)) Then $RaidTool = ""
		If ($RaidTool == "") Then
			; stay enabled so that Set fails safe by asking for confirmation
			LogMessage("WARNING: RaidTool.exe not found; every Set will ask for confirmation")
		Else
			LogMessage("Patient check using " & $RaidTool & " (" & $CFG_RAID_ADDRESS & ":" & $CFG_RAID_PORT & ")")
		EndIf
	EndIf
EndFunc ;==>_Setup


; return the first existing copy of a Siemens tool, or "" if none is found
Func FindSiemensTool($exe)
	; since XA, tools will be in either MED_BIN or CustomerBin
	; fallback to MEDHOME\bin on older versions
	Local $aDirs[3] = [EnvGet("MED_BIN"), EnvGet("CustomerBin"), EnvGet("MEDHOME") & "\bin"]
	If (EnvGet("MEDHOME") == "") Then $aDirs[2] = ""
	For $i = 0 To 2
		If ($aDirs[$i] <> "" And FileExists($aDirs[$i] & "\" & $exe) == 1) Then Return $aDirs[$i] & "\" & $exe
	Next
	Return ""
EndFunc ;==>FindSiemensTool


; disable/enable the Get and Set buttons and show a busy cursor during slow operations
Func SetBusy($bBusy)
	Local $iState = ($bBusy ? $GUI_DISABLE : $GUI_ENABLE)
	If ($idGet <> 0) Then GUICtrlSetState($idGet, $iState)
	If ($idSet <> 0) Then GUICtrlSetState($idSet, $iState)
	If ($bBusy) Then
		GUISetCursor(15, 1, $hGUI)
	Else
		GUISetCursor(2, 0, $hGUI)
	EndIf
EndFunc ;==>SetBusy


; run "RaidTool -d" and parse the listing of measurements on the RAID
; on success sets $aRows and $iUnknown; on failure sets $sReason
Func RaidSnapshot(ByRef $aRows, ByRef $iUnknown, ByRef $sReason)
	; clear outputs so no failure path leaves stale values from an earlier call
	$sReason = ""
	$iUnknown = 0
	Local $aEmpty[0][$PC_NCOLS]
	$aRows = $aEmpty
	If ($RaidTool == "") Then
		$sReason = "RaidTool.exe not found"
		Return False
	EndIf

	; -d is the only operation ever run; the other arguments come only from config.au3
	Local $sArgs = ' -a ' & $CFG_RAID_ADDRESS & ' -p ' & $CFG_RAID_PORT & ' -k -t ' & $CFG_RAID_TIMEOUT_SEC & ' -d'
	Local $sCmd = '"' & $RaidTool & '"' & $sArgs
	If (StringRegExp($RaidTool, '(?i)\.(cmd|bat)$')) Then $sCmd = @ComSpec & ' /s /c ""' & $RaidTool & '"' & $sArgs & '"'

	Local $bOk = False, $bTimedOut = False
	Local $sOut = "", $bEof = 0, $iGot = 0, $iParseErr = 0, $iParseExt = 0
	Local $aParsed
	SetBusy(True)
	LogMessage("Checking patient on RAID...")
	Local $hTimer = TimerInit()
	Local $pid = Run($sCmd, @WorkingDir, @SW_HIDE, $STDOUT_CHILD + $STDERR_CHILD)
	If ($pid == 0) Then
		$sReason = "could not start RaidTool"
	Else
		; drain both pipes while the process runs, so a large listing cannot fill the buffer and deadlock
		; stderr is discarded: it could contain patient data
		While 1
			$sOut &= StdoutRead($pid)
			$bEof = @error
			$iGot = @extended
			StderrRead($pid)
			$iGot += @extended
			If ($bEof) Then ExitLoop
			If (TimerDiff($hTimer) > ($CFG_RAID_TIMEOUT_SEC + 5) * 1000) Then
				ProcessClose($pid)
				$bTimedOut = True
				$sReason = "RaidTool timed out after " & ($CFG_RAID_TIMEOUT_SEC + 5) & " s"
				ExitLoop
			EndIf
			If ($iGot == 0) Then Sleep(50)
		WEnd
		StdioClose($pid)
		If (Not $bTimedOut) Then
			; the exit code is not checked: RaidTool lists newest-first (RAID space is freed from the end of the list),
			; so a truncated listing only loses old rows, which the verdict never examines
			$aParsed = PC_ParseRaidList($sOut, $CFG_PAT_FIELD_WIDTH)
			$iParseErr = @error
			$iParseExt = @extended
			If ($iParseErr <> 0) Then
				$sReason = "unrecognized RaidTool output"
			Else
				$aRows = $aParsed
				$iUnknown = $iParseExt
				$bOk = True
				; never log $sOut: it names every patient on the RAID
				LogMessage("RAID listing: " & UBound($aRows) & " measurements" & ($iUnknown > 0 ? ", " & $iUnknown & " unreadable lines" : ""))
			EndIf
		EndIf
	EndIf
	SetBusy(False)
	Return $bOk
EndFunc ;==>RaidSnapshot


; get the current shims, save to file
Func OnGet()
	Local $validShims = False
	Local $ShimsetFilename = $ShimFilePrefix & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC & $ShimFileSuffix

	LogMessage("Get shims to " & $ShimsetFilename)

	Local $cmdArgs
	If ($GUIMode == 1) Then
		; for B1 mode
		$cmdArgs = " -txscale -get > "
	Else
		; for B0 mode, add mp flag for uT/m
		$cmdArgs = " -shim -mp -get > "
	EndIf

	LogMessage("AdjValidate" & $cmdArgs & $ShimsetFilename)
	Local $runCmd = @ComSpec & ' /s /c ""' & $AdjValidate & '"' & $cmdArgs & $ShimsetFilename & '"'
	Local $ProcID = Run($runCmd, @WorkingDir, @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
	Local $procRet = ProcessWaitClose($ProcID)
	Local $procErr = @extended
	Local $sOut = StdoutRead($ProcID)
	Local $sErr = StderrRead($ProcID)
	Local $dumpErr = 0

	If ($procRet == 1) Then
		If ($procErr <> 0) Then
			; error returns nonzero exit code
			LogMessage("ERROR attempting to read current shims!")
			$dumpErr += 1
		Else
			; N4 returned "OK" on stderr; throw a warning if we see anything else
			If ((UBound($sErr) > 1) And (StringCompare(StringStripWS($sErr, $STR_STRIPALL), "OK"))) Then
				LogMessage("WARNING: unexpected response reading current shims!")
				$dumpErr += 1
			EndIf

			; otherwise, success = exit code zero
			Local $shimarr = GetShimValuesFromFile($ShimsetFilename)
			If (UBound($shimarr) > 1) Then
				LogMessage("Succeeded!")
				$validShims = True
			Else
				LogMessage("ERROR: shimset is empty!")
				$dumpErr += 1
			EndIf
		EndIf
	Else
		LogMessage("UNEXPECTED ERROR: Failed to execute AdjValidate command!")
	EndIf

	If ($dumpErr > 0) Then
        ; try to catch and parse common errors
		If (StringInStr($sOut, "loading current online prot failed")) Then
			; note: in N4 at least, no message is printed in this case, only the error code is set!
			LogMessage("Current protocol is not open!")
			$dumpErr = 0
		ElseIf ($procErr == 1) Then
			LogMessage("Is the current protocol open?")
		EndIf
	EndIf
	If ($dumpErr > 0) Or ($debugLog > 1) Then
		LogMessage("Debug: last cmd = " & $runCmd)
		LogMessage("Debug: process returned status " & $procRet & " / code " & $procErr)
		If (StringLen($sOut)) Then LogMessage("Debug: stdout = '" & $sOut & "'")
		If (StringLen($sErr)) Then LogMessage("Debug: stderr = '" & $sErr & "'")
	EndIf

	If (Not $validShims) Then
		FileDelete($ShimsetFilename)
		MsgBox($MB_SYSTEMMODAL + $MB_TOPMOST, $PgmName & ": Error", "Failed to read the current shims!" & @CRLF & "Please check the error log.")
		GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
		Return
	EndIf

	; record who is on the RAID now, so Set can check it is still the same patient
	; unreadable lines ($iRaidUnknown) do not block this; Set re-checks the listing and treats them as UNVERIFIED
	If ($PC_Enabled) Then
		Local $aRaidRows, $iRaidUnknown, $sRaidReason
		If (RaidSnapshot($aRaidRows, $iRaidUnknown, $sRaidReason)) Then
			Local $sTrailer = PC_FormatBaseline(PC_MakeBaseline($aRaidRows, _NowCalc()))
			If (@error) Then
				LogMessage("WARNING: could not record patient information; shims saved without it")
			Else
				; leading CRLF: AdjValidate output may not end with a newline; blank lines are skipped by the parser
				If (FileWrite($ShimsetFilename, @CRLF & $sTrailer & @CRLF)) Then
					LogMessage("Recorded patient information for the patient check")
				Else
					LogMessage("WARNING: could not write patient information; shims saved without it")
				EndIf
			EndIf
		Else
			LogMessage("WARNING: patient check unavailable (" & $sRaidReason & "); shims saved without patient information")
		EndIf
	EndIf

	UpdateListView()
EndFunc ;==>OnGet


; set the current selected shimset
Func OnSet()
	Local $validShims = False
	Local $itemCount = _GUICtrlListView_GetSelectedCount($hList)

	If ($itemCount <> 1) Then
		MsgBox($MB_SYSTEMMODAL + $MB_TOPMOST, $PgmName & ": Error", "One shimset must be selected!")
		GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
		Return
	EndIf

	Local $selIdx = _GUICtrlListView_GetSelectedIndices($hList)
	Local $shimvalStr = _GUICtrlListView_GetItemTextString($hList, $selIdx)
	Local $shimvalArr = StringSplit($shimvalStr, "|")

	; display filename
	Local $fname
	If ($GUIMode == 2) Then
		Switch ($shimvalArr[1])
			Case "Newest"
				$fname = "FASTMAP_Shims.txt"
			Case "Old 1"
				$fname = "FASTMAP_Shims.txt.001"
			Case "Old 2"
				$fname = "FASTMAP_Shims.txt.002"
			Case "Old 3"
				$fname = "FASTMAP_Shims.txt.003"
		EndSwitch
	Else
		$fname = GetFilenameFromTimeStamp($shimvalArr[2])
	EndIf
	LogMessage("Set shims from " & $fname)

	; refuse or confirm shims that may belong to a previous patient
	; (not FASTMAP in v1: _Setup excludes it via $PC_Enabled, which the gate checks)
	If (Not PatientCheckGate($fname)) Then
		GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
		Return
	EndIf

	; format array
	Local $cmdArgs
	If ($GUIMode == 1) Then
		; for B1 mode
		$cmdArgs = " -txscale -set "
		; need also to reformat data array to account for multi-line list
		; interleave last 16 elements (magnitudes) with phases from $listData
		Local $shimvalArr2[19+16] ; was 19 (size + idx + tstamp + 16 mag)
		For $idx=0 To 16-1
			$shimvalArr2[3+$idx*2] = $shimvalArr[3+$idx]
			$shimvalArr2[3+$idx*2+1] = $listData[$selIdx][2+$idx]
		Next
		$shimvalArr = $shimvalArr2
	ElseIf ($GUIMode == 2) Then
		; for FASTMAP, we are using DAC and mA units, so no mp flag
		$cmdArgs = " -shim -set "
		; if we have multiple GPAs, need to replicate gradient offsets (pos. 3,4,5)
		If ($NoOfGPAs > 1) Then
			Local $ssize = UBound($shimvalArr)
			Local $shimvalArr2[$ssize+3*($NoOfGPAs-1)]
			Local $ctr = 0
			For $idx=0 To $ssize-1
				If ($idx = 6) Then
					For $gpaidx=1 To $NoOfGPAs-1
						$shimvalArr2[$ctr]   = $shimvalArr[$idx-3]
						$shimvalArr2[$ctr+1] = $shimvalArr[$idx-2]
						$shimvalArr2[$ctr+2] = $shimvalArr[$idx-1]
						$ctr += 3
					Next
				EndIf
				$shimvalArr2[$ctr] = $shimvalArr[$idx]
				$ctr += 1
			Next
			$shimvalArr = $shimvalArr2
		EndIf
	Else
		; for B0 mode, add mp flag for uT/m
		$cmdArgs = " -shim -mp -set "
	EndIf

	; remove first two fields, format string with space delimiters
	_ArrayDelete($shimvalArr, "0-2")
	$shimvalStr = _ArrayToString($shimvalArr, " ")

	LogMessage("AdjValidate" & $cmdArgs & $shimvalStr)
	Local $runCmd = @ComSpec & ' /s /c ""' & $AdjValidate & '"' & $cmdArgs & $shimvalStr & '"'
	Local $ProcID = Run($runCmd, @WorkingDir, @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
	Local $procRet = ProcessWaitClose($ProcID)
	Local $procErr = @extended
	Local $sOut = StdoutRead($ProcID)
	Local $sErr = StderrRead($ProcID)
	Local $dumpErr = 0

	If ($procRet == 1) Then
		If ($procErr <> 0) Then
			; error returns nonzero exit code
			LogMessage("ERROR attempting to set shims!")
			$dumpErr += 1
		Else
			If ((UBound($sErr) > 1) And (StringCompare(StringStripWS($sErr, $STR_STRIPALL), "OK"))) Then
				; N4 returned "OK" on stderr; throw a warning if we see anything else
				LogMessage("WARNING: unexpected response setting shims!")
				$dumpErr += 1
			EndIf

			; otherwise, success = exit code zero
			LogMessage("Succeeded!")
			$validShims = True
		EndIf
	Else
		LogMessage("UNEXPECTED ERROR: Failed to execute AdjValidate command!")
	EndIf

	If ($dumpErr > 0) Then
        ; try to catch and parse common errors
		If (StringInStr($sOut, "loading current online prot failed")) Then
			LogMessage("Current protocol is not open!")
			$dumpErr = 0
		EndIf
	EndIf
	If ($dumpErr > 0) Or ($debugLog > 1) Then
		LogMessage("Debug: last cmd = " & $runCmd)
		LogMessage("Debug: process returned status " & $procRet & " / code " & $procErr)
		If (StringLen($sOut)) Then LogMessage("Debug: stdout = '" & $sOut & "'")
		If (StringLen($sErr)) Then LogMessage("Debug: stderr = '" & $sErr & "'")
	EndIf

	If (Not $validShims) Then
		MsgBox($MB_SYSTEMMODAL + $MB_TOPMOST, $PgmName & ": Error", "Failed to set the shims!" & @CRLF & "Please check the error log.")
		GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
	EndIf
EndFunc ;==>OnSet


; read the patient check trailer from a shimset file
; returns a baseline array, or 0 if the file has no readable trailer
Func ReadShimBaseline($fname)
	Local $sTag = "#ShimCachePatientCheck"
	Local $aBase = 0
	Local $fh = FileOpen($fname, $FO_READ)
	If ($fh == -1) Then Return 0

	While 1
		Local $line = FileReadLine($fh)
		If (@error) Then ExitLoop
		; only the first trailer counts; PC_ParseBaseline returns 0 if it does not parse
		If (StringLeft(StringStripWS($line, $STR_STRIPLEADING), StringLen($sTag)) == $sTag) Then
			$aBase = PC_ParseBaseline($line)
			ExitLoop
		EndIf
	WEnd

	FileClose($fh)
	Return $aBase
EndFunc ;==>ReadShimBaseline


; check that the shims in $fname were saved for the patient now in the scanner
; returns True to go ahead with Set, False to cancel
; never log $aV[2]: it is the patient name (dialogs only)
Func PatientCheckGate($fname)
	If (Not $PC_Enabled) Then Return True

	Local $aBase = ReadShimBaseline($fname)
	Local $aRows, $iUnknown, $sReason, $aV
	If (RaidSnapshot($aRows, $iUnknown, $sReason)) Then
		$aV = PC_Verdict($aBase, $aRows, $iUnknown, _NowCalc(), $CFG_IDLE_MINUTES, $CFG_MAX_AGE_HOURS)
	Else
		Local $aFail[3] = [$PC_UNVERIFIED, "The patient check could not run: " & $sReason & ".", ""]
		$aV = $aFail
	EndIf

	; same label as the list shows (B0/B1)
	Local $sShimset = "Shimset: " & GetTimeStampFromFilename($fname)
	; empty when there is no name, so no doubled blank line
	Local $sCurLine = ($aV[2] <> "" ? @CRLF & "Patient in the most recent measurement: " & $aV[2] : "")
	Local $sTitle, $sBody

	; only an explicit VERIFIED proceeds silently; anything unexpected is treated as UNVERIFIED
	Switch $aV[0]
		Case $PC_VERIFIED
			LogMessage("Patient check OK: " & $aV[1])
			Return True
		Case $PC_MISMATCH
			If ($CFG_BLOCK_ON_MISMATCH) Then
				MsgBox($MB_ICONERROR + $MB_SYSTEMMODAL + $MB_TOPMOST, $PgmName & ": Patient check", _
						$sShimset & @CRLF & $aV[1] & $sCurLine & @CRLF & @CRLF & "Shims were NOT applied.", 0, $hGUI)
				LogMessage("Set refused by patient check: " & $aV[1])
				Return False
			EndIf
			$sTitle = $PgmName & ": DIFFERENT PATIENT"
			$sBody = $sShimset & @CRLF & $aV[1] & $sCurLine & @CRLF & @CRLF & "Another patient has been scanned since these shims were saved. Apply them anyway?"
		Case Else
			$sTitle = $PgmName & ": Patient not verified"
			$sBody = $sShimset & @CRLF & $aV[1] & @CRLF & @CRLF & "Cannot confirm these shims belong to the patient now in the scanner. Apply them anyway?"
	EndSwitch

	; default button is No; any answer other than Yes cancels (a Yes/No dialog has no close button)
	If ($IDYES <> MsgBox($MB_YESNO + $MB_ICONWARNING + $MB_DEFBUTTON2 + $MB_SYSTEMMODAL + $MB_TOPMOST, $sTitle, $sBody, 0, $hGUI)) Then
		LogMessage("Set cancelled by patient check (" & ($aV[0] = $PC_MISMATCH ? "different patient" : "not verified") & "): " & $aV[1])
		Return False
	EndIf
	LogMessage("Patient check overridden by user (" & ($aV[0] = $PC_MISMATCH ? "different patient" : "not verified") & "): " & $aV[1])
	Return True
EndFunc ;==>PatientCheckGate


; delete all of the shim files
Func OnClearAll()
	; call support function with argument 0 to delete all (error checking is done there)
	DeleteFiles(0)
EndFunc ;==>OnClearAll


; delete the selected shim file(s)
Func OnClear()
	; call support function with argument 1 to delete selected
	DeleteFiles(1)
EndFunc ;==>OnClear


; delete all but the selected shim file(s)
Func OnClearUnselected()
	; call support function with argument 2 to delete all but selected
	DeleteFiles(2)
EndFunc ;==>OnClearUnselected


; refresh list of files
Func UpdateListView()
	; FASTMAP has its own function, redirect to it
	If ($GUIMode == 2) Then
		FM_UpdateListView()
		Return
	EndIf

	; read files from folder
	Local $files = GetShimsetFiles()
	Local $count = UBound($files)

	; read all shimsets first: the column set must match them before rows are added
	Local $shimSets[$count]
	For $idx=0 To $count-1
		$shimSets[$idx] = GetShimValuesFromFile($files[$idx])
	Next

	; build the list
	_GUICtrlListView_DeleteAllItems($idList)
	Local $orderChanged = SetThirdOrderColumns(MaxShimCount($shimSets))
	$listRows = 0

	If ($GUIMode == 1) Then
		; suspend row resizing handlers while repopulating multi-line list
		GUIRegisterMsg($WM_NOTIFY, "")
		GUIRegisterMsg($WM_ACTIVATE, "")
	EndIf

	; loop through all candidate files
	For $idx=0 To $count-1
		; only add to list if valid
		Local $shimarr = $shimSets[$idx]
		If (UBound($shimarr) > 1) Then
			$listRows += 1
			Local $timestamp = GetTimeStampFromFilename($files[$idx]) ; get readable timestamp

			If ($GUIMode == 1) Then
				; for B1 mode, separate mag/pha values and populate multi-line list
				Local $listCols = _GUICtrlListView_GetColumnCount($hList)
				ReDim $listData[$listRows][$listCols]
				Local $shims = UBound($shimarr)/2
				Local $i = $listRows - 1

				; top line of each multiline row are stored as items (first column) and subitems (remaining columns)
				Local $iIndex = _GUICtrlListView_AddItem($hList, $i+1) ; first item is line number
				_GUICtrlListView_AddSubItem($hList, $iIndex, $timestamp, 1) ; first subitem is timestamp
				For $idx2=0 To $shims-1 ; top line are magnitudes
					_GUICtrlListView_AddSubItem($hList, $iIndex, $shimarr[$idx2*2], $idx2+2) ; remaining subitems
				Next
				_GUICtrlListView_SetItemParam($hList, $iIndex, $listRows-1+1000) ; 1000 => See remarks for _GUICtrlListView_SetItemParam in helpfile
				; second line of each multiline row are stored in the data array
				$listData[$i][0] = ""
				$listData[$i][1] = ""
				For $idx3=0 To $shims-1 ; second line are phases
					$listData[$i][$idx3+2] = $shimarr[$idx3*2+1]
				Next
			Else
				; for B0 mode, simple list
				GUICtrlCreateListViewItem($listRows & "|" & $timestamp & "|" & _ArrayToString($shimarr, "|"), $idList)
			EndIf
		EndIf
	Next

	If ($GUIMode == 1) Then
		; for multi-line list for B1 mode, need these handlers to resize rows
		GUIRegisterMsg($WM_NOTIFY, "WM_NOTIFY")
		GUIRegisterMsg($WM_ACTIVATE, "WM_ACTIVATE")
	EndIf

	If ($orderChanged) Then FitWindowToColumns()

	GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
EndFunc ;==>UpdateListView


; returns the largest number of shim values among the shimsets (0 if none are valid)
Func MaxShimCount(ByRef $shimSets)
	Local $max = 0
	For $idx=0 To UBound($shimSets)-1
		If (UBound($shimSets[$idx]) > $max) Then $max = UBound($shimSets[$idx])
	Next
	Return $max
EndFunc ;==>MaxShimCount


; show the 3rd-order columns only if some shimset has 3rd-order values (B0/FASTMAP)
; call with the list empty, before adding rows; returns True if the columns changed
; with no valid shimsets ($nShims = 0) the build default $CFG_INITIAL_SHIM_CHANNELS (config.au3) decides,
; so deleting every shimset returns the columns to that default
Func SetThirdOrderColumns($nShims)
	If ($GUIMode == 1) Then Return False
	If ($nShims == 0) Then $nShims = $CFG_INITIAL_SHIM_CHANNELS	; no shimsets yet: use the build default

	Local $want = ($nShims > 8)
	If ($want == $listHasThirdOrder) Then Return False

	Local $nCols = UBound($ThirdOrderCols)
	If ($want) Then
		For $idx=0 To $nCols-1
			_GUICtrlListView_InsertColumn($hList, $ThirdOrderFirstCol+$idx, $ThirdOrderCols[$idx])
		Next
	Else
		For $idx=$nCols-1 To 0 Step -1
			_GUICtrlListView_DeleteColumn($hList, $ThirdOrderFirstCol+$idx)
		Next
	EndIf
	$listHasThirdOrder = $want
	Return True
EndFunc ;==>SetThirdOrderColumns


; resize the window after the 3rd-order columns were added or removed (call after adding rows)
; 3rd order: back to the full default width; 2nd order: just wide enough for the columns
; FASTMAP keeps its width either way: its log box below the list needs it
Func FitWindowToColumns()
	Local $nCols = _GUICtrlListView_GetColumnCount($hList)
	If ($listHasThirdOrder Or ($GUIMode == 2)) Then
		$winW = $winWFull
	Else
		; the last column may have been stretched to fill the full-width list, so size it
		; to its contents (but no narrower than its header) before adding up the widths
		Local $last = $nCols-1
		_GUICtrlListView_SetColumnWidth($hList, $last, $LVSCW_AUTOSIZE)
		Local $lastCol = _GUICtrlListView_GetColumn($hList, $last) ; [5] is the header text
		Local $hdrW = _GUICtrlListView_GetStringWidth($hList, $lastCol[5]) + 12
		If (_GUICtrlListView_GetColumnWidth($hList, $last) < $hdrW) Then _GUICtrlListView_SetColumnWidth($hList, $last, $hdrW)

		Local $colsW = 0
		For $idx=0 To $nCols-1
			$colsW += _GUICtrlListView_GetColumnWidth($hList, $idx)
		Next
		; +4 list border, +20 vertical scrollbar, +4 window borders (see list width in _Main)
		$winW = $colsW + 28
		If ($winW < $winMinW) Then $winW = $winMinW
		If ($winW > $winWFull) Then $winW = $winWFull
	EndIf

	; leave a minimized or maximized window alone; $winW still sets the new minimum
	Local $state = WinGetState($hGUI)
	If (Not BitAND($state, $WIN_STATE_MINIMIZED + $WIN_STATE_MAXIMIZED)) Then
		; window was created with client width $winW+2; keep the frame size the OS added
		Local $pos = WinGetPos($hGUI)
		Local $client = WinGetClientSize($hGUI)
		Local $newW = $winW + 2 + ($pos[2] - $client[0])
		Local $newX = $pos[0]
		; at startup the window is not shown yet, so keep it centered like GUICreate did
		If (Not BitAND($state, $WIN_STATE_VISIBLE)) Then $newX += Int(($pos[2] - $newW) / 2)
		WinMove($hGUI, "", $newX, $pos[1], $newW, $pos[3])
	EndIf

	; size re-added columns to their contents now that the list is full width again
	If ($listHasThirdOrder) Then
		For $idx=$ThirdOrderFirstCol To $nCols-1
			_GUICtrlListView_SetColumnWidth($hList, $idx, $LVSCW_AUTOSIZE_USEHEADER)
		Next
	EndIf
EndFunc ;==>FitWindowToColumns


; display about info box
Func OnAbout()
	MsgBox($MB_SYSTEMMODAL + $MB_TOPMOST, "About " & $PgmName, "An AutoIt GUI wrapper for AdjValidate." _
		& @CRLF & @CRLF & "Version: " & $PgmVersion _
		& @CRLF & @CRLF & "https://github.com/CMRR-C2P/shimcache" _
		& @CRLF & @CRLF & "Contributors:" _
		& @CRLF & "    Edward Auerbach (eja@umn.edu)" _
		& @CRLF & "    Christopher Rodgers (ctr28@cam.ac.uk)" _
		& @CRLF & "    Patrick Bolan (bola0035@umn.edu)" _
		)
	GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
EndFunc ;==>OnAbout


; exit when exit button is pressed
Func OnExit()
	Exit
EndFunc ;==>OnExit


; support function to actually delete shimset files
; arguments: 0=all, 1=selected, 2=!selected
Func DeleteFiles($arg)
	Local $dirNeedsRefresh = False
	Local $selItems = _GUICtrlListView_GetSelectedIndices($idList, True)
	Local $numItems = _GUICtrlListView_GetItemCount($idList)

	If (($arg < 0) Or ($arg > 2)) Then Exit 1 ; developer error - should never happen!

	Local $numDel = $numItems
	If ($arg == 1) Then $numDel = $selItems[0]
	If ($arg == 2) Then $numDel = $numItems - $selItems[0]

	; throw an error if there is nothing to do
	If ($numDel <= 0) Then
		MsgBox($MB_SYSTEMMODAL + $MB_TOPMOST, $PgmName & ": Error", "No shimset files to delete!")
		GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
		Return
	EndIf

	; get confirmation if more than one file
	If ($numDel > 1) Then
		If ($IDYES <> MsgBox($MB_SYSTEMMODAL + $MB_ICONQUESTION + $MB_YESNO + $MB_TOPMOST, _
				$PgmName & ": Confirm", "Delete " & $numDel & " shimset files?")) Then
			GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
			Return
		EndIf
	EndIf

	; make a list of indexes to delete
	Local $arrItems[$numItems]
	If ($arg == 1) Then
		For $idx=0 To $numItems-1
			$arrItems[$idx] = 0
		Next
		For $idx=1 To $selItems[0]
			$arrItems[$idx-1] = $selItems[$idx]+1
		Next
	ElseIf ($arg == 2) Then
		For $idx=0 To $numItems-1
			$arrItems[$idx] = $idx+1
		Next
		For $idx=1 To $selItems[0]
			$arrItems[$selItems[$idx]] = 0
		Next
	Else
		For $idx=0 To $numItems-1
			$arrItems[$idx] = $idx+1
		Next
	EndIf

	; now loop through and delete the specified file(s)
	For $idx=0 To $numItems-1
		If ($arrItems[$idx] == 0) Then ContinueLoop

		; get filename to delete
		Local $values = StringSplit(_GUICtrlListView_GetItemTextString($idList, $arrItems[$idx]-1) , "|")
		Local $shimsetFilename = GetFilenameFromTimeStamp($values[2])

		; delete it
		FileDelete($shimsetFilename)
		$dirNeedsRefresh = True
	Next

	If ($dirNeedsRefresh) Then UpdateListView()
EndFunc ;==>DeleteFiles


; returns an array of the names of the shimset filenames
; note: does not look for valid data here
Func GetShimsetFiles()
	Local $filenameArray[0]

	Local $searchStr = $ShimFilePrefix & "*" & $ShimFileSuffix
	Local $hSearch = FileFindFirstFile($searchStr)

	; check if the search was successful
	If $hSearch = -1 Then
		Return $filenameArray
	EndIf

	; add each file to the array
	While 1
		Local $fname = FileFindNextFile($hSearch)
		If (@error) Then ExitLoop
		_ArrayAdd($filenameArray, $fname)
	WEnd

	; close the search handle
	FileClose($hSearch)

	; sort in descending order (newest on top)
	_ArraySort($filenameArray, 1)

	Return $filenameArray
EndFunc ;==>GetShimsetFiles


; reads shimset file
; if valid after parsing, returns array of values
Func GetShimValuesFromFile($fname)
	; open file, check for error
	Local $fh = FileOpen($fname, $FO_READ)
	If ($fh == -1) Then	Return ""

	; loop to read lines of file
	While 1
		Local $line = FileReadLine($fh)
		If (@error) Then
			If ($debugLog > 0) Then LogMessage("WARNING: " & $fname & " is invalid!")
			FileClose($fh)
			ExitLoop
		EndIf

		; skip comment/metadata lines (e.g. #ShimCachePatientCheck)
		If (StringLeft(StringStripWS($line, $STR_STRIPLEADING), 1) == "#") Then ContinueLoop

		; valid AdjValidate output will always be a list of numbers separated by spaces
		; FASTMAP can have multiple spaces between elements, so add $STR_STRIPSPACES
		Local $arr = StringSplit(StringStripWS($line, $STR_STRIPLEADING + $STR_STRIPTRAILING + $STR_STRIPSPACES), " ", $STR_NOCOUNT)
		Local $found = UBound($arr)
		If (Not $found) Then ContinueLoop

		; check if we have a flag indicating multiple GPAs (currently only relevant for FASTMAP >XA60)
		If ($found > 2) And (StringCompare($arr[$found-2], "#GPAs") == 0) Then
			If ($NoOfGPAs == 1) Then
				$NoOfGPAs = Number($arr[$found-1], $NUMBER_32BIT)
				If ($NoOfGPAs < 2) Then
					$NoOfGPAs = 1
				Else
					LogMessage("This system has " & $NoOfGPAs & " GPAs!")
				EndIf
			EndIf
			_ArrayDelete($arr, $found-1)
			_ArrayDelete($arr, $found-2)
			$found -= 2;
		EndIf

		; check for correct number of items based on what we are expecting
		If ($GUIMode == 1) Then
			; for B1 mode, expect 16 or 32 values (8ch or 16ch, mag + phase)
			If (($found <> 16) And ($found <> 32)) Then ContinueLoop
		ElseIf ($GUIMode == 2) Then
			; FASTMAP returns 9 or 13 values, last one is frequency in Hz which we will remove
			If ($found == 13) Then
				_ArrayDelete($arr, 12)
				$found = 12
			ElseIf ($found == 9) Then
				_ArrayDelete($arr, 8)
				$found = 8
			Else
				ContinueLoop
			EndIf
		Else
			; for B0 mode, expect 8 or 12 values depending on 2nd or 3rd order capability
			If (($found <> 8) And ($found <> 12)) Then ContinueLoop
		EndIf

		; double check the items are all numeric and in valid range
		For $idx=0 To $found-1
			; TODO
		Next

		; everything checks out at this point, so return the | delimited string
		FileClose($fh)
		Return $arr
	WEnd

	; only for empty file, or no valid data
	Return 0
EndFunc ;==>GetShimValuesFromFile


Func GetTimeStampFromFilename($fname)
	; This is hardwired, assuming the filename is shimset_YYYYMMDDHHMMSS.txt
	; For human readable format we will use YYYY-MM-DD HH:MM:SS
	; Pass through any filenames that do not contain timestamps

	; remove head and tail
	Local $tStr = StringTrimLeft(StringTrimRight($fname, StringLen($ShimFileSuffix)), StringLen($ShimFilePrefix))

	; determine if this is really a timestamp
	; ignore any trailing text, but only convert if the first 14 chars are a valid number
	Local $isTimeStamp = False
	If (StringLen($tStr) >= 14) Then
		If (StringIsDigit(StringLeft($tStr, 14))) Then
			$isTimeStamp = True
		EndIf
	EndIf

	If ($isTimeStamp) Then
		; this is any extra label text (e.g. " - Copy", doesn't seem to be a reason to disallow it)
		Local $tRem = StringTrimLeft($tStr, 14)

		; reformat datetime string in a more human readable format for display
		$tStr = StringLeft($tStr, 4) & "-" & StringMid($tStr, 5, 2) & "-" & StringMid($tStr, 7, 2) & " " _
			& StringMid($tStr, 9, 2) & ":" & StringMid($tStr, 11, 2) & ":" & StringMid($tStr, 13, 2)
		$tStr = $tStr & $tRem
	EndIf

	Return $tStr
EndFunc ;==>GetTimeStampFromFilename


Func GetFilenameFromTimeStamp($timestamp)
	; This is hardwired, assuming the filename is shimset_YYYYMMDDHHMMSS.txt
	; For human readable format we will use YYYY-MM-DD HH:MM:SS
	; Pass through any filenames that do not contain timestamps

	Local $tStr = $timestamp

	; determine if this is really a timestamp
	Local $isTimeStamp = False
	If (StringLen($tStr) >= 19) Then
		Local $testNum = StringLeft($tStr, 4) & StringMid($tStr, 6, 2) & StringMid($tStr, 9, 2) _
			& StringMid($tStr, 12, 2) & StringMid($tStr, 15, 2) & StringMid($tStr, 18, 2)
		Local $testSep = StringMid($tStr, 5, 1) & StringMid($tStr, 8, 1) & StringMid($tStr, 11, 1) _
			& StringMid($tStr, 14, 1) & StringMid($tStr, 17, 1)
		If ((StringIsDigit($testNum)) And (StringCompare($testSep, "-- ::") == 0)) Then
			$isTimeStamp = True
		EndIf
	EndIf

	If ($isTimeStamp) Then
		; this is any extra label text (e.g. " - Copy")
		Local $tRem = StringTrimLeft($timestamp, 19)

		; convert human readable format back into datetime string
		$tStr = StringLeft($timestamp, 4) & StringMid($timestamp, 6, 2) & StringMid($timestamp, 9, 2) _
			& StringMid($timestamp, 12, 2) & StringMid($timestamp, 15, 2) & StringMid($timestamp, 18, 2)
		$tStr = $tStr & $tRem
	EndIf

	Return $ShimFilePrefix & $tStr & $ShimFileSuffix
EndFunc ;==>GetFilenameFromTimeStamp


; print a message to the console log (edit box)
Func LogMessage($msg)
	If (_GUICtrlEdit_GetTextLen($idEdit) > 0) Then
		_GUICtrlEdit_AppendText($idEdit, @CRLF & StringRegExpReplace($msg, "[\r\n]", ""))
	Else
		_GUICtrlEdit_AppendText($idEdit, StringRegExpReplace($msg, "[\r\n]", ""))
	EndIf
EndFunc ;==>LogMessage


; -----------------------------------------------------------------------------
; FASTMAP-specific functions
; -----------------------------------------------------------------------------

; refresh list of FASTMAP files
Func FM_UpdateListView()
	; read files from folder
	Local $fileArr[0], $descArr[0]
	_ArrayAdd($fileArr, "FASTMAP_Shims.txt")
	_ArrayAdd($fileArr, "FASTMAP_Shims.txt.001")
	_ArrayAdd($fileArr, "FASTMAP_Shims.txt.002")
	_ArrayAdd($fileArr, "FASTMAP_Shims.txt.003")
	_ArrayAdd($descArr, "Newest")
	_ArrayAdd($descArr, "Old 1")
	_ArrayAdd($descArr, "Old 2")
	_ArrayAdd($descArr, "Old 3")

	; read all shimsets first: the column set must match them before rows are added
	Local $shimSets[4]
	For $idx=0 To 3
		$shimSets[$idx] = GetShimValuesFromFile($fileArr[$idx])
	Next

	; build the list
	_GUICtrlListView_DeleteAllItems($idList)
	Local $orderChanged = SetThirdOrderColumns(MaxShimCount($shimSets))
	For $idx=0 To 3
		; only add to list if valid
		Local $shimarr = $shimSets[$idx]
		If (UBound($shimarr) > 1) Then
			Local $timestamp = GetTimeStampFromFilename(FileGetTime($fileArr[$idx], $FT_MODIFIED, $FT_STRING))
			GUICtrlCreateListViewItem($descArr[$idx] & "|" & $timestamp & "|" & _ArrayToString($shimarr, "|"), $idList)
			GUICtrlSetOnEvent(-1, "FM_ShowLog")
		EndIf
	Next

	If ($orderChanged) Then FitWindowToColumns()

	; ClickItem below is a real mouse click, so the window must be visible; at
	; startup this runs before _Main shows it
	GUISetState(@SW_SHOW, $hGUI)

	; reset log history and select Newest which will show the newest log
	; note: ClickItem seems to be too fast sometimes for GUICtrlSetOnEvent to register,
	;       so we will retry for e.g. 2 seconds to make sure it does
	$FM_LastLog = -1
	If (_GUICtrlListView_GetItemCount($idList) > 0) Then
		_GUICtrlListView_ClickItem($idList, 0)
		Local $clickTries = 1
		While (($FM_LastLog == -1) And ($clickTries <= 20))
			Sleep(100)
			_GUICtrlListView_ClickItem($idList, 0)
			$clickTries += 1
		WEnd
	EndIf

	GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
EndFunc ;==>FM_UpdateListView


; display FASTMAP log in edit window
Func FM_ShowLog()
	; get the current selection
	Local $sel = _GUICtrlListView_GetSelectedIndices($idList, True)

	; only proceed if one item is selected, and we haven't displayed this log since the last refresh
	If ($sel[0] <> 1) Then Return
	Local $idx = $sel[1]
	if ($idx == $FM_LastLog) Then Return

	; get log filename & description
	Local $fname = "FASTMAP.log"
	Local $desc = "Newest"
	If (($idx > 0) And ($idx <= 3)) Then
		$fname = "FASTMAP.log.00" & $idx
		$desc = "Old " & $idx
	EndIf

	; open file, check for error
	Local $fh = FileOpen($fname, $FO_READ)
	If ($fh == -1) Then	Return

	; print header
	LogMessage("")
	LogMessage("=====================================================================================")
	LogMessage("    " & $desc & " FASTMAP results:")
	LogMessage("=====================================================================================")

	; loop to read and display all lines of file
	While 1
		Local $line = FileReadLine($fh)
		If (@error) Then
			$FM_LastLog = $idx
			FileClose($fh)
			Return
		EndIf

		LogMessage($line)
	WEnd

	$FM_LastLog = $idx
	FileClose($fh)

	GUICtrlSetState($idList, $GUI_FOCUS) ; put focus back on list after any popup
EndFunc ;==>FM_ShowLog
