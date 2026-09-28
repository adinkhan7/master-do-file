# master-do-file

**`mdf`** — the Master DO File survey pipeline framework, installed into Stata with one command.

```stata
net install mdf, from("https://raw.githubusercontent.com/adinkhan7/master-do-file/main") replace
```

A project's Master DO file installs it on first run, so an analyst normally never types this.

---

## What this is

A project's `Master_DO_File.do` carries only **Section 0** — the switches an analyst edits — and the
list of pipeline stages. Everything under the hood lives here.

```stata
*  SECTION 0   USER CONFIGURATION                    ← EDIT ONLY THIS SECTION
global project_name         "AUS MFS Labour Market 2026"
global run_import           1
global run_labeling         1
...
global run_deliverables     1                    // 08_Deliverables/ — client handover package
global mdf_required         "11.0.0"

*  Everything below is for system use, no need to make any change.
mdf_setup         //  helper programs, ROOT resolution, framework version check
mdf_validate      //  Section 0 sanity checks and switch defaults
mdf_paths         //  run dates, the project's folder layout, every path global
mdf_folders       //  create the project folder tree
...
mdf_keys          //  archive keys and print the run summary
mdf_deliverables  //  build the client handover package (run_deliverables = 1)
```

The stages are listed individually on purpose: the pipeline stays readable, and any one stage can be
re-run from the Command window while debugging. `mdf run` does the same thing in one line.

---

## The project folder (v11)

```
<Project>/
├─ Master_DO_File_11.0.0.do
├─ README.md                         generated; explains the project
├─ 01_Questionnaire/                 questionnaire documents        (NN_<dataset>/ per dataset)
├─ 02_CAPI/                          SurveyCTO form(s); Archive/    (NN_<dataset>/ per dataset)
├─ 03_Data/                          NN_<Project>_RAWDATA_<date>/: import DO + CSV + DTA
├─ 04_Others/                        support and preload material   (NN_<dataset>/ per dataset)
├─ 05_Processing/
│  ├─ <Project>_Processing.do        THE cleaning file (yours)
│  ├─ 01_Do Files/                   00a_Directory.do, 00b_Local_Overrides.do,
│  │                                 01_Labeling.do, 02_Translation.do, 03_Audio.do
│  ├─ 02_Translation/                01_Exported/, 02_Translated/
│  └─ 03_Data/                       working data; your support files for cleaning
├─ 06_HFC/                           02_<Project>_HFC.do, KEYS/, one dated folder per run
├─ 07_Cleaned Dataset/               <dataset>_CLEANED.dta — what every consumer reads
└─ 08_Deliverables/                  the client package, when run_deliverables = 1
```

**A project built before v11 keeps its folders.** The layout is recorded in the hidden `.hfc_root`
sentinel; v11 reads it and runs a v10 project (`01_Survey_Instruments/`, `02_Data/`, `03_HFC/`,
`04_DO Files/`, `05_Translation/`, `06_Processing Files/`) exactly where it is. Nothing is moved.

---

## Three ways a generated DO file runs

| where it sits | what it does |
|---|---|
| **inside a project** | finds the project's `.hfc_root` above it and runs as part of the project |
| **inside a Deliverables package** | finds `02_Import & Raw files/` around it and rebuilds the cleaned dataset into `04_Cleaned Data/` |
| **anywhere else** | runs on the `.dta` file(s) beside it (or in `Data/`, `03_Data/` …), output to `MDF_Output/` |

In the last two, neither the Master DO file nor this package needs to be installed.

**Stata does not tell a running DO file where it is saved** — not from the Do button, not with
Ctrl+A then Ctrl+D (measured: `c(do_current)` is always empty in Stata 17). Every generated file
therefore starts from Stata's **working directory**. Double-clicking a DO file to launch Stata sets
it; otherwise use *File > Change working directory*. A run that looks in the wrong place stops and
says which folder it searched.

---

## Deliverables

`global run_deliverables 1` rebuilds `08_Deliverables/` from scratch on the next run:

```
08_Deliverables/                        one dataset
├─ 01_CAPI & Questionnaire/             the form labeling used, and the questionnaire
├─ 02_Import & Raw files/               the raw dataset, its import DO and CSV
├─ 03_Processing Files/
│  ├─ <Project>_Processing.do
│  ├─ 01_Do Files/                      01_Labeling.do, 02_Translation.do
│  ├─ 02_Translation/                   01_Exported/, 02_Translated/
│  └─ 03_Data/                          your support files from 05_Processing/03_Data/
└─ 04_Cleaned Data/                     the cleaned dataset
```

With several datasets the same four folders appear once per dataset, under
`08_Deliverables/NN_<dataset>/`, each carrying that dataset alone. The post-cleaning merge is not
part of a per-dataset package.

No daily download folders, no HFC history, no keys, no logs, no Master.

**The client** copies the folder anywhere, opens `03_Processing Files/<Project>_Processing.do`, and
runs it (Ctrl+A, Ctrl+D). The cleaned dataset is written to `04_Cleaned Data/`. If the machine lacks
`odksplit` or `inputcorrection` and the rebuild needs them, they are installed first; if that is
impossible the run stops before writing anything, rather than produce a dataset that would not match.

**Every file is accounted for.** A file that cannot be copied into the package — usually because the
path passes Windows' 260-character limit — is named, and the build ends with an error instead of
calling the package ready.

---

## Reproducible cleaning

Stata breaks ties in `sort` with a random stream that every earlier sort in the session advances, so a
`duplicates drop` or `bysort id: keep if _n == 1` in cleaning code could keep a different row
depending on what ran before it. From 11.0.0 each dataset's block in the Processing DO fixes that
stream first (`set sortseed`), so the same raw data gives the same cleaned data in the project, in
its Deliverables package, and on any machine.

---

## Requirements

Stata 16 or newer. Network access once, to install. After that a run touches the network only when
the installed version differs from the one Master pins in `$mdf_required`.

---

## Versioning

Master pins the framework it was written against: `global mdf_required "11.0.0"`.

- **Installed framework older than Master** → updated from GitHub; if that is impossible, the run
  stops before doing anything. An older framework cannot know the folders and stages a newer Master
  expects, and would otherwise build the project wrong without saying so.
- **Installed framework newer than Master** → a warning, and the run continues. This is how a
  10.2.0 project keeps running when a machine has 11.0.0.
- **No usable framework at all** → hard stop.

Set `global mdf_autoinstall 0` to take the network out of the loop entirely.

A version bump changes these, or the check re-installs on every run:

| where | what |
|---|---|
| `mdf.ado` | the `*!` header and **both** `return local version` lines |
| `_mdf_defs.ado` | the `*!` header |
| `mdf_setup.ado` | `global hfc_version` — stamped into generated files as their template marker |
| Master's Section 0 | `global mdf_required` |

Raising `hfc_version` makes an existing project write `.do.new` beside its generated files instead of
overwriting them. Until the analyst merges them the project keeps its current generated files — and,
for a Processing DO older than 11.0.0, gets the flat v10.2.0 Deliverables package, which is the one it
can rebuild from.

---

## Structural facts that shape the package

**`program define` and `mata:` cannot nest inside an ado** — both close with `end`. Every helper and
every Mata block is its own file.

**`exit` inside an ado returns from the ado, not from Master.** The clean stops (Run 1, the CAPI
pause, the Ghost Run) set `$mdf_halt`, and every later stage stands down.

**`clear all` drops programs and wipes Mata but leaves globals standing.** The Mata load guard probes
Mata itself; helpers are ado files Stata reloads on demand.

**`net install` ships only program files**, which is why `_mdf_defs.ado` has an `.ado` extension.

**A line of a DO file read into a Stata macro has its own macro references expanded when used.**
Anything that scans DO-file text does it in Mata.

---

## Layout of this repository

```
mdf.ado                       `mdf run` / `mdf version`
mdf_<stage>.ado               the 19 pipeline stages, in execution order
mdf_bootstrap.ado             load a project's globals inside a generated module (either layout)
mdf_core_vars.ado             derive fielddate / total_duration
mdf_finalise.ado              post-cleaning merge and publish
mdf_deliverables.ado          the client handover package (stage 19)
_mdf_deliv_legacy.ado         the v10.2.0 package, for Processing DOs on an older template
_mdf_dlv_copy.ado             copy one file into the package, or say why not
_hfc_*.ado                    helpers: abort, pause, mkdir, hide, dirof, lock check, archiving
_mdf_load.ado                 bring the Mata layer in, and back after any clear all
_mdf_defs.ado                 the Mata layer: helpers and the code generator
mdf.sthlp                     help mdf
stata.toc / mdf.pkg           net install index and manifest — a file not listed does not ship
```

---

## About Master DO File

A reusable Stata product, not a project-specific do-file: it builds the project folder tree,
imports and archives SurveyCTO data, applies CAPI value labels, runs High-Frequency Checks, manages
the open-ended translation round trip, optionally merges paired datasets, and hands over a package
that rebuilds the cleaned data — from one configuration block, with no hardcoded paths.

Built at **Development Research Initiative (dRi)**, following DIME / IPA / J-PAL reproducible
research conventions.

## Licence

MIT — see [LICENSE](LICENSE).
