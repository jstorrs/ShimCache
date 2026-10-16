@echo off
rem Fake RaidTool for testing ShimCache's patient check without a scanner.
rem Set CFG_RAIDTOOL in include/config.au3 to this file's path, and
rem SHIMCACHE_FAKE_RAID to a listing file (e.g. tests\fixtures\raid_sample.txt).
rem The expected argument string below must match the values in include/config.au3.
rem ShimCache reports every fake failure as "unrecognized RaidTool output"; run the fake
rem by hand to see the real failure reason.
rem Set SHIMCACHE_FAKE_RAID_HANG (to anything) to stall ~30 s first, to test the timeout.
if not "%*"=="-a 192.168.2.2 -p 8010 -k -t 10 -d" (
	echo unexpected arguments: %* >&2
	exit /b 9
)
if "%SHIMCACHE_FAKE_RAID%"=="" exit /b 3
if not "%SHIMCACHE_FAKE_RAID_HANG%"=="" ping -n 30 127.0.0.1 >nul
type "%SHIMCACHE_FAKE_RAID%" || exit /b 2
exit /b 0
