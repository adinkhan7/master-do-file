# master-do-file

**`mdf`** — the Master DO File survey pipeline framework, installed into Stata with `net install`.

```stata
net install mdf, from("https://raw.githubusercontent.com/adinkhan7/master-do-file/main") replace
```

---

## What this is

A project's `Master_DO_File.do` used to be a 4,747-line file that an analyst was told to scroll
past. Everything below the *"Everything below is for system use"* banner now lives here, and the
file a project actually carries is **168 lines**: the switches, and the list of pipeline stages.

```stata
*==============================================================================*
*  SECTION 0   USER CONFIGURATION                    ← EDIT ONLY THIS SECTION
*==============================================================================*
global project_name       "AUS MFS Labour Market 2026"
global run_import         1
global run_labeling       1
...

*==============================================================================*
*  Everything below is for system use, no need to make any change.
*==============================================================================*
cap which mdf_setup
if _rc net install mdf, from("$mdf_source") replace

mdf_setup         //  helper programs, ROOT resolution, framework version check
mdf_validate      //  Section 0 sanity checks and switch defaults
mdf_paths         //  run dates and every folder path global
mdf_folders       //  create the project folder tree
mdf_readme        //  write the project README
mdf_resolve       //  post-field resolution
mdf_workdirs      //  today's raw-data folder and HFC run folder
mdf_log           //  open the run log and detect the run type
mdf_generate      //  00_Directory / 00a_Bootstrap / 00b_Overrides, output paths, previous keys
mdf_import        //  carry the import DO forward, fingerprint it, import
mdf_modules       //  pipeline modules, the HFC DO and the Processing DO
mdf_guards        //  stale-processing and open-workbook guards
mdf_stage         //  archive raw data and stage the working copy
mdf_instruments   //  CAPI subfolders, instrument archiving, translation folders
mdf_clean         //  run cleaning
mdf_hfc           //  run the high-frequency checks
mdf_audio         //  audio audit
mdf_keys          //  archive keys and print the run summary
```

| | before | after |
|---|---|---|
| `Master_DO_File.do` | 4,747 lines · 271 KB | **168 lines · 12 KB** |
| one day's run log | ~62,000 lines | ~2,700 lines |
| fixing a framework bug | edit every copy, in every project, on every machine | `net install … , replace` |
| copies of `_hfc_abort` etc. carried in Master | 4 each | **0** |

The stages are listed individually rather than hidden behind a single `mdf run` on purpose: the
pipeline stays readable, and any one stage can be re-run on its own from the Command window while
debugging. `mdf run` exists too, and does the same thing in one line.

---

## Behaviour is unchanged

The framework was relocated, not rewritten. Verified against the previous release on a real
project, from an identical starting fixture, both runs under `stata -b`:

```
same 32-file inventory
every generated text file byte-identical
all 7 datasets identical by datasignature   (.dta bytes differ only in the
                                             creation timestamp Stata stamps
                                             into every header)
0 errors on both sides, both reached HFC COMPLETE
```

The Mata code generator inside the package was lifted out of Master verbatim and was separately
proven byte-identical on all 10 files it writes.

---

## Requirements

Stata 16 or newer. Network access **once**, to install. After that a run touches the network only
when the installed version differs from the one Master pins.

---

## Three structural facts that shape the whole package

Worth knowing before editing anything here — each of these is load-bearing, and two of them are
the kind of thing that fails silently.

**1. `program define` and `mata:` cannot nest inside an ado.** Both terminate with `end`, so an
inner block would close the outer program instead of itself. That is why every helper program and
every Mata block is its own file rather than sitting inside the stage that uses it.

**2. `exit` inside an ado returns from the ado, not from Master.** Real errors are non-zero returns
and propagate on their own. But the three *clean* stops — Run 1, the CAPI pause, the Ghost Run
pause — would have let the run carry on into stages that had nothing to work with. They set
`$mdf_halt`, and every later stage stands down when it sees it.

**3. `clear all` drops programs and wipes Mata but leaves globals standing.** Verified directly in
Stata 17, and it decides two designs here. Every SurveyCTO import DO issues `clear all` mid-run, so
the Mata load guard has to probe *Mata* — a "loaded" global would still be set at exactly the moment
the Mata it vouched for had gone. And because the helpers are ado files on the adopath, Stata simply
reloads them on demand; Master used to carry four identical copies of each for this reason.

A fourth, purely mechanical: **`net install` ships only a package's *program* files.** A `.do` is
classed as ancillary and left behind for `net get`, so it never reaches the adopath. That is the
entire reason `_mdf_defs.ado` carries an `.ado` extension despite defining no ado-command.

---

## Layout

```
mdf.ado                     `mdf run` / `mdf version`
mdf_<stage>.ado             the 19 pipeline stages, in execution order
mdf_bootstrap.ado           load a project's globals inside a generated module
mdf_core_vars.ado           derive fielddate / total_duration
mdf_finalise.ado            post-cleaning merge and publish
mdf_deliverables.ado        the reproducible client handover package (stage 19)
_hfc_abort.ado              stop: a real error (exit 198)
_hfc_pause.ado              stop: a workflow checkpoint (exit 0) — never the same thing
_hfc_mkdir.ado              create a directory if absent
_hfc_hide.ado               hide framework state on Windows
_hfc_dirof.ado              directory part of a path, returned via c_local
_hfc_capi_lockcheck.ado     count Excel lock files left by an open workbook
_hfc_archive_instruments.ado keep the newest instrument, archive the rest
_mdf_load.ado               bring the Mata layer in, and back after any clear all
_mdf_defs.ado               the Mata layer: framework helpers + the code generator
mdf.sthlp                   help mdf
stata.toc                   net install index — must stay at the repo root
mdf.pkg                     package manifest — a file not listed here does not ship
```

---

## What a project folder holds

`04_DO Files/` holds five files, not eight (ADR-055). `00a_Bootstrap.do`, `04_Finalise.do` and
`05_Core_Variables.do` are commands in this package now.

| file | |
|---|---|
| `00_Directory.do` | project-specific: every path global and Section 0 value, Master-owned |
| `00b_Local_Overrides.do` | analyst-owned; the only override surface that survives regeneration |
| `01_Labeling.do` / `02_Translation.do` / `03_Audio.do` | analyst-owned (Tier 2) |

Retirement is reference-aware: a file is removed only once nothing in the project still calls it by
name, so a project on older generated modules keeps working until the analyst merges the `.new`
files. Tier 2 files are renamed to `.superseded`, never deleted.

---

## A generated DO works away from its project

Copy a generated DO somewhere else, put the dataset(s) it should read beside it, and run it. Finding
no `.hfc_root` above itself, it builds a small context from that folder instead of stopping. The
Master DO File is not needed, **this package does not have to be installed**, and nothing outside
that folder is read or written.

| | |
|---|---|
| works for | the Processing DO, `01_Labeling.do`, `02_Translation.do`, `03_Audio.do`, the HFC DO |
| inputs | `*.dta` beside the DO, else in `Data/`. Sorted by name: first is DS1, second DS2 |
| never an input | `*_CLEANED`, `*_KEYS_`, `*_MERGED_`, `*_LABELED_` — a second run cannot eat the first run's output |
| optional | a `CAPI/` subfolder for labeling, a `Translation/` subfolder for returned text |
| output | `MDF_Output/` beside the DO |
| settings | whatever Section 0 held when the file was generated |

It stops rather than guess. No dataset, or a count that does not match what the file was generated
for, ends the run naming the folder and listing what it found.

The order matters and is the point: the project walk runs **first**, so a file inside a project can
never take this path. Only when that fails is standalone tried — and only then, if the folder cannot
be known at all, the tmpdir root cache. Reaching for the cache first is what used to make a stranded
HFC DO read another project's data and write its report back into that project.

`Ctrl+A` / `Ctrl+D` gives Stata no path for the file, so the **working directory** stands in for the
file's folder. Make them the same — *File > Change working directory*, or launch Stata by
double-clicking the DO. The run always announces the folder it settled on.

---

## Deliverables

`run_deliverables = 1` writes `$ROOT/Deliverables`: the raw data, the processing workflow and the two
modules it calls, the questionnaire, translation material where the workflow uses it, and the current
clean dataset for comparison. No daily download folders, no check history, no Master.

Copy it anywhere and the workflow inside rebuilds the clean dataset on standalone mode, with no link
to the project it came from. `run_deliverables = 0` builds nothing and leaves the run unchanged.

---

## Versioning

Master pins the framework it was written against:

```stata
global mdf_required "10.2.0"      // Section 0
```

`mdf_setup` compares that against the installed version and updates only on a mismatch.

The two failure modes are deliberately not treated alike:

- **No usable framework at all** → hard stop. Nothing can be generated, and a half-built pipeline is
  worse than none.
- **Version mismatch that cannot be repaired because GitHub is unreachable** → loud warning, run
  continues. Fieldwork happens on bad connections, and refusing to run over an unreachable update
  would strand an analyst who already has a working copy.

Set `global mdf_autoinstall 0` to take the network out of the loop entirely.

Bumping the version means changing it in **four** places. Miss one of the first three and the check
re-installs on every run; miss the fourth and every project silently keeps generating against the old
template:

| where | what |
|---|---|
| `mdf.ado` | the `*!` header and **both** `return local version` lines |
| `_mdf_defs.ado` | the `*!` header |
| `mdf_setup.ado` | `global hfc_version` — stamped into every generated file as its Tier 2 template marker |
| a project's Section 0 | `global mdf_required` |

Every other `.ado` carries the stamp in its `*!` header too; those are documentation, not load-bearing.

Raising `hfc_version` makes existing projects write `.do.new` beside their Tier 2 files rather than
overwrite them — that is the ownership rule working, not a fault, but it does mean an existing
project does not get a change to the generated files until the analyst merges.

---

## About Master DO File

A reusable Stata product, not a project-specific do-file: it builds the project folder tree,
imports and archives SurveyCTO data, applies CAPI value labels, runs High-Frequency Checks, manages
the open-ended translation round trip, optionally merges paired datasets — from one configuration
block, with no hardcoded paths.

Built at **Development Research Initiative (dRi)**, following DIME / IPA / J-PAL reproducible
research conventions.

---

## Licence

MIT — see [LICENSE](LICENSE).
