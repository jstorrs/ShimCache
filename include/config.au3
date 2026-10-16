#include-once

; -----------------------------------------------------------------------------
; Build-time settings for ShimCache. Edit these for your scanner before compiling.
; -----------------------------------------------------------------------------

; shim list layout
Global Const $CFG_INITIAL_SHIM_CHANNELS = 12	; columns shown before any shimset exists: 8 = 2nd order, 12 = with 3rd order

; RaidTool patient check
; The address and port are compiled in on purpose. RaidTool.exe also has
; destructive operations (-i formats the RAID; -A and -R write to it). Only -d
; is ever run, and its arguments come only from these constants.
Global Const $CFG_PC_ENABLED = True	; patient check on/off
Global Const $CFG_RAIDTOOL = ""	; full path to RaidTool.exe; "" = search MED_BIN, CustomerBin, MEDHOME\bin (never C:\Temp; set this for test builds)
Global Const $CFG_RAID_ADDRESS = "192.168.2.2"
Global Const $CFG_RAID_PORT = 8010
Global Const $CFG_RAID_TIMEOUT_SEC = 10	; passed to RaidTool -t; process killed after this + 5 s
Global Const $CFG_PAT_FIELD_WIDTH = 32	; width of the patient column in the RaidTool -d listing
Global Const $CFG_IDLE_MINUTES = 30	; 0 = off
Global Const $CFG_MAX_AGE_HOURS = 12	; 0 = off
Global Const $CFG_BLOCK_ON_MISMATCH = False	; True = refuse a mismatch outright instead of asking
