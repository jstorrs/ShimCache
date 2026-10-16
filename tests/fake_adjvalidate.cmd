@echo off
rem Fake AdjValidate for testing ShimCache's Get and Set without a scanner.
rem Set CFG_ADJVALIDATE in include/config.au3 to this file's path.
rem Set stores the values; Get returns the last values set, or a default line if none.
rem State is one file per family in %TEMP%: shimcache_fake_adj_shim.txt and
rem shimcache_fake_adj_txscale.txt. Deleting them also resets the fake.
rem Environment variables (all optional, tested with "defined"):
rem   FAKE_ADJ_SECOND_ORDER  default -shim Get returns 8 values instead of 12
rem   FAKE_ADJ_NOPROT        fail like AdjValidate with no protocol open
rem   FAKE_ADJ_RESET         delete both state files before doing anything else
rem Handles: -shim [-mp] -get | -set v1 ... vN   and   -txscale -get | -set v1 ... vN
setlocal
set "STATE_SHIM=%TEMP%\shimcache_fake_adj_shim.txt"
set "STATE_TX=%TEMP%\shimcache_fake_adj_txscale.txt"
if defined FAKE_ADJ_RESET del /q "%STATE_SHIM%" "%STATE_TX%" 2>nul
if defined FAKE_ADJ_NOPROT goto noprot

rem The first argument selects the family. Quotes are stripped by %~1.
set "FAMILY=%~1"
set "STATE="
if "%FAMILY%"=="-shim" set "STATE=%STATE_SHIM%"
if "%FAMILY%"=="-txscale" set "STATE=%STATE_TX%"
if not defined STATE goto usage

rem Scan the arguments. Only the exact tokens -get and -set set the mode. Once
rem -set has been seen, every later argument is a value and is never tested as a
rem flag, so negative values such as -12.5 are safe. VALS is built without a
rem leading or trailing space. "set VALS=..." is quoted so that special
rem characters in a value cannot be taken as shell syntax.
set "MODE="
set "VALS="
:scan
if "%~1"=="" goto scanned
if "%MODE%"=="set" goto addval
if "%~1"=="-get" set "MODE=get"
if "%~1"=="-set" set "MODE=set"
goto next
:addval
if defined VALS (set "VALS=%VALS% %~1") else (set "VALS=%~1")
:next
shift
goto scan
:scanned

if "%MODE%"=="set" goto doset
if "%MODE%"=="get" goto doget
goto usage

:doset
if not defined VALS (
	echo -set needs at least one value >&2
	exit /b 2
)
rem The parentheses around echo matter. Without them, "echo 1 2 3 4> file" would
rem treat a trailing digit before ">" as a file handle number.
(echo %VALS%)> "%STATE%"
exit /b 0

:doget
if exist "%STATE%" (
	type "%STATE%"
	exit /b 0
)
if "%FAMILY%"=="-txscale" (
	echo 1 0 1 45 1 90 1 135 1 180 1 225 1 270 1 315
	exit /b 0
)
if defined FAKE_ADJ_SECOND_ORDER (
	echo 0 0 0 10 -20 30 -40 50
	exit /b 0
)
echo 0 0 0 10 -20 30 -40 50 1 2 3 4
exit /b 0

:noprot
echo loading current online prot failed
exit /b 1

:usage
echo usage: fake_adjvalidate.cmd -shim or -txscale, then -get or -set followed by values >&2
exit /b 2
