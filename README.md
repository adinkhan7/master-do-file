# master-do-file

**`mdfgen`** — the code-generation layer for the [Master DO File](#what-master-do-file-is)
survey pipeline, packaged for Stata's `net install`.

```stata
net install mdfgen, from("https://raw.githubusercontent.com/adinkhan7/master-do-file/main") replace
```

---

## What this repository is

`Master_DO_File.do` is a single portable Stata program that turns raw SurveyCTO exports into a
managed survey-processing pipeline. Until v10.1.0 it carried roughly **2,650 lines of inline
Mata** whose only job was to *write* the project's pipeline DO files — a do-file that writes
do-files.

That layer now lives here instead. Master keeps the workflow; `mdfgen` writes the files.

Three things this buys:

| | Before (v10.0.x) | After (v10.1.0) |
|---|---|---|
| `Master_DO_File.do` | 4,747 lines | **2,208 lines** |
| One day's run log | ~62,000 lines | **~2,700 lines** |
| Fixing a generator bug | edit every copy of Master, in every project, on every machine | `net install ... , replace` |

The log figure is the one analysts notice. Stata echoes the body of a `mata:` block into the
log as it executes, so every run was dumping the generator's own source — three times over —
into the file you were meant to read.

**The generated output is byte-identical.** The Mata source was relocated verbatim; only the
wrapper around it changed. See [Verification](#verification).

---

## Installation

```stata
net install mdfgen, from("https://raw.githubusercontent.com/adinkhan7/master-do-file/main") replace
```

Master installs it automatically on first use and then leaves the network alone — once the
expected version is present, daily runs work offline.

Requires **Stata 16** or newer.

Check what you have:

```stata
mdfgen version
```

---

## Usage

`mdfgen` is not meant to be run by hand; `Master_DO_File.do` drives it. It is documented so the
contract is inspectable (`help mdfgen`).

```stata
mdfgen directory     // 00_Directory.do, 00a_Bootstrap.do, 00b_Local_Overrides.do
mdfgen modules       // pipeline modules, the project HFC DO, the Processing DO
mdfgen version       // returns r(version)
```

Inputs arrive as **globals**, not as options:

| global | meaning |
|---|---|
| `mdfgen_pname` | project name |
| `mdfgen_ssize` | sample size |
| `mdfgen_meta` | front metadata variable list |
| `mdfgen_tail` | tail variable list |
| `mdfgen_tstart` / `mdfgen_tend` | timer variables |
| `mdfgen_nds` | dataset count the generator loops expand to |
| `mdfgen_dodir` | target folder for the DO files |
| `mdfgen_hfcdir` | project `03_HFC` folder |
| `mdfgen_tver` | framework version stamped into generated files |
| `mdfgen_procdir` | project `06_Processing Files` folder |
| `mdfgen_procfile` | file name of the Processing DO (`modules` only) |

Globals rather than options, because project paths routinely contain spaces *and parentheses* —
`Demo Project (Multi Dataset)` is a real one — and Stata's `syntax` option parser cannot carry
such a value intact.

A missing required global is an error, not a silently truncated file.

---

## How it is put together

```
mdfgen.ado          dispatcher. Parses the subcommand, checks its inputs,
                    loads the Mata layer, calls one entry point.
_mdfgen_defs.ado    the Mata layer: ~30 generator functions plus the two
                    entry points, lifted verbatim out of Master.
mdfgen.sthlp        help file
stata.toc           net install index
mdfgen.pkg          package manifest
```

Two details worth knowing before you edit anything:

**`_mdfgen_defs.ado` is named `.ado` for a mechanical reason.** `net install` ships only a
package's *program* files; a `.do` is classed as ancillary and left behind for `net get`, so it
would never reach the adopath. Nothing in that file defines an ado-command. `mdfgen.ado` finds
it with `findfile` and runs it with `qui do`.

**The load guard probes Mata, not a flag.** `clear all` wipes Mata but leaves globals standing
(verified, Stata 17 — programs go, globals stay). SurveyCTO import DO files issue `clear all`,
and Master calls `mdfgen` on both sides of that boundary, so a "already loaded" global would be
wrong exactly when it mattered. `_mdfgen_load` calls `mdfgen_probe()` and recompiles if it has
gone away.

---

## Verification

Equivalence was established by running the original in-Master Mata blocks and the packaged
generator against identical inputs and diffing the results:

```
10 generated files — 00_Directory.do, 00a_Bootstrap.do, 00b_Local_Overrides.do,
01_Labeling.do, 02_Translation.do, 03_Audio.do, 04_Finalise.do,
05_Core_Variables.do, the project HFC DO, the Processing DO

diff -r old new  ->  no differences
all 10 MD5 checksums match
```

---

## What Master DO File is

A reusable Stata product, not a project-specific do-file: it builds the project folder tree,
imports and archives data, applies CAPI value labels, runs High-Frequency Checks, manages
open-ended translation, optionally merges paired datasets, and does it all from one
configuration block with no hardcoded paths.

Built at **Development Research Initiative (dRi)**, following DIME / IPA / J-PAL reproducible
research conventions.

---

## Versioning

`mdfgen`'s version tracks the framework version it was cut from. Master pins the generator it
expects in `$mdfgen_required` and refuses to run if no usable generator can be found — writing
pipeline files with the wrong generator is the silent-but-wrong outcome the framework exists to
prevent.

---

## Licence

MIT — see [LICENSE](LICENSE).
