# ShimCache
GUI tool for managing B0/B1 shim settings on Siemens scanners

Requires AdjValidate tool from Siemens

Compile with AutoIt v3

## Building for your scanner

Edit `include/config.au3` before compiling (64-bit AutoIt build, as before). All settings are compiled in. Defaults are shown in brackets.

- `$CFG_INITIAL_SHIM_CHANNELS` [12]: columns shown before any shimset exists. 8 = 2nd order, 12 = with 3rd order.
- `$CFG_PC_ENABLED` [True]: patient check on or off.
- `$CFG_RAIDTOOL` [""]: full path to RaidTool.exe. An empty string searches MED_BIN, CustomerBin and MEDHOME\bin (never C:\Temp). Set it for test builds.
- `$CFG_ADJVALIDATE` [""]: full path to AdjValidate.exe. An empty string searches MED_BIN, CustomerBin, MEDHOME\bin, then C:\Temp. A non-empty path is used as is, with no fallback search. Set it to a `.cmd` file for test builds.
- `$CFG_RAID_ADDRESS` [192.168.2.2] and `$CFG_RAID_PORT` [8010]: where RaidTool finds the RAID.
- `$CFG_RAID_TIMEOUT_SEC` [10]: passed to RaidTool as `-t`. The process is killed after this plus 5 s.
- `$CFG_PAT_FIELD_WIDTH` [32]: width of the patient column in the `RaidTool -d` listing.
- `$CFG_IDLE_MINUTES` [0]: Set is unverified if the newest measurement finished more than this many minutes ago (a measurement of the same patient that is still running counts as current). 0 = off. Off by default: long gaps within one session are normal (a phantom left running), and a new patient gets at least a localizer before anyone sets shims, which the check reports as a mismatch.
- `$CFG_MAX_AGE_HOURS` [12]: Set is unverified if the shims were saved longer ago than this. 0 = off.
- `$CFG_BLOCK_ON_MISMATCH` [False]: True refuses a mismatch outright instead of asking.

## Patient check

Get records who is on the RAID. It runs `RaidTool -d -k` and appends a `#ShimCachePatientCheck v1` trailer to the shim file, holding a hashed patient key, a FileID and a time. Older ShimCache versions read these files unchanged.

Set lists the RAID again and compares it with the trailer. There are three outcomes:

- VERIFIED: no other patient has been measured since Get. Set proceeds silently.
- MISMATCH: a measurement of a different patient, completed or still running, is on the RAID after the one recorded at Get. A warning is shown, default No. With `$CFG_BLOCK_ON_MISMATCH = True` Set is refused instead.
- UNVERIFIED: the check cannot tell. Causes include a file saved without a readable trailer (older version, or RaidTool failed at Get), RaidTool missing or timing out at Set, a listing older than the shims (RAID cleared or IDs reset), no measurement with readable patient information on the RAID, a newer measurement that could not be read, listing lines that could not be parsed, shims older than `$CFG_MAX_AGE_HOURS`, the newest measurement finished more than `$CFG_IDLE_MINUTES` minutes ago (if enabled), or scanner and computer clocks that disagree. A confirmation is shown, default No.

FASTMAP mode is not checked.

The `-k` flag is required, because RaidTool anonymizes the listing without it. Only `-d` is ever run, with arguments compiled in from config.au3, because RaidTool also has destructive options (`-i` formats the RAID; `-A` and `-R` write to it).

### Limits

- RaidTool lists acquired data, not the registered patient. If patient B is registered after Get and Set is used before B's first measurement starts, the check cannot tell. As soon as B's first measurement is running (status "wip"), the check sees B. In practice a localizer always runs before shims are set. `$CFG_IDLE_MINUTES` can narrow this window if wanted.
- With the idle check enabled, it is skipped while the newest measurement is running (wip): an aborted scan ends as cld, and the patient cannot change during an acquisition. Aborted scans have been confirmed to end as cld. The RAID holds raw data written before recon, so a recon crash should not leave a measurement wip unless it aborts the acquisition. A measurement that somehow stayed wip without ever closing would keep the idle check off until another patient's measurement appears; `$CFG_MAX_AGE_HOURS` still applies.
- Names longer than the 32-character listing field are compared on their last 32 characters only. A very long name (62 characters seen on VE11C) is truncated by RaidTool and loses the birth date. A patient registered without a birth date is compared on the name alone.
- The idle check, if enabled, assumes the scanner and this computer share a clock (the recon system takes its time from the console at boot).
- The check relies on RaidTool listing newest-first.

### Privacy

The trailer stores a 16-hex-character salted hash of "Name,BirthDate". This is pseudonymous, not anonymous. Shim files must not be treated as de-identified. The log never contains patient names. Dialogs may show the patient of the most recent measurement.

## Testing

`tests\PatientCheck_test.au3` runs with `AutoIt3.exe /ErrorStdOut tests\PatientCheck_test.au3` and exits 0 on success.

`tests\fake_raidtool.cmd` stands in for RaidTool on a Windows machine without a scanner. Set `$CFG_RAIDTOOL` to its path, and set the environment variable `SHIMCACHE_FAKE_RAID` to a listing file such as `tests\fixtures\raid_sample.txt`. Its expected arguments must match config.au3. Set `SHIMCACHE_FAKE_RAID_HANG` to test the timeout.

`tests\fake_adjvalidate.cmd` stands in for AdjValidate. Set `$CFG_ADJVALIDATE` to its path. Set stores the values it is given, and Get returns the last values set, or a default line if none were set. State is kept in `%TEMP%\shimcache_fake_adj_shim.txt` and `%TEMP%\shimcache_fake_adj_txscale.txt`. Options, set as environment variables: `FAKE_ADJ_SECOND_ORDER` makes the default B0 Get return 8 values instead of 12; `FAKE_ADJ_NOPROT` makes every call fail as if no protocol were open; `FAKE_ADJ_RESET` deletes both state files first. Deleting the files by hand also resets it.

To test end to end, configure both fakes and point `SHIMCACHE_FAKE_RAID` at a scratch copy of `tests\fixtures\raid_sample.txt`. ShimCache's environment is fixed when it starts, so edit the file's contents rather than the variable. The newest row of that fixture (104) is a running (wip) measurement, so a plain Get then Set gives VERIFIED: Get records row 104 (if `$CFG_IDLE_MINUTES` is enabled, it is skipped while that patient's measurement is running). To see MISMATCH, click Get, then add a newer row for a different patient at the top of the scratch copy (the listing is newest-first), copying the exact column layout of a fixture row, and click Set: expect the DIFFERENT PATIENT dialog.

`tests\ShimCacheGui_test.au3` runs the whole thing automatically. It launches a patched copy of ShimCache (in a scratch directory under `%TEMP%`, deleted afterwards) against both fakes and drives Get, Set and the patient check dialogs through the real window, in B0 and B1 mode, including a RaidTool that hangs. Run it from a desktop session with `AutoIt3.exe /ErrorStdOut tests\ShimCacheGui_test.au3`. It takes about 1 to 2 minutes; do not touch the mouse or keyboard while it runs. It prints PASS or FAIL for each check and a final `RESULT` line, and exits 0 on success. It refuses to run while ShimCache is open, and it never calls the real AdjValidate or RaidTool. Under Wine on Linux it needs a display: `xvfb-run -a wine AutoIt3_x64.exe /ErrorStdOut tests\ShimCacheGui_test.au3` (without one, AutoIt exits silently with code 0, so scripted runs should check for the `RESULT` line).

## Before enabling on a new scanner

Build with `$CFG_PC_ENABLED = False` until this list passes. The listing format (32-character right-aligned patient column, cld/wip status, newest-first), aborted scans ending as cld, and detection of a patient change have been confirmed on one system; the checklist still applies to each new scanner and software version.

- Capture `RaidTool -a <ip> -p <port> -k -t 10 -d` and confirm: the header contains "FileID", the closed-status token is "cld", the patient column is 32 characters and right-aligned, and the listing is newest-first.
- Check a non-ASCII name, and names of about 40 and of 60+ characters.
- Find where RaidTool.exe lives, and the RAID address and port (especially on XA).
- Confirm an in-progress measurement shows status wip with the patient column filled.
- Confirm that an aborted measurement ends as cld and never stays wip (a host restart during acquisition has not been tried).
- Confirm that a protocol name of 32 or more characters parses (not yet seen in a capture; it may abut the MeasID column).
- Check that Get followed by Set gives VERIFIED, and that registering a new patient and scanning a localizer gives MISMATCH.
