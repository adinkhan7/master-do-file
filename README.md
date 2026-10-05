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
global project_name         "Sample Project"
global run_import           1
global run_labeling         1
...
global run_deliverables     1                    // 08_Deliverables/ — client handover package
global mdf_required         "11.1.2"

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
├─ Master_DO_File_11.1.2.do
├─ README.md                         generated; explains the project
├─ 01_Questionnaire/                 questionnaire documents        (NN_<dataset>/ per dataset)
├─ 02_CAPI/                          SurveyCTO form(s); Archive/    (NN_<dataset>/ per dataset)
├─ 03_Data/                          NN_<Project>_RAWDATA_<date>/: import DO + CSV + DTA
├─ 04_Others/                        support and preload material   (NN_<dataset>/ per dataset)
├─ 05_Processing/
│  ├─ <Project>_Processing.do        THE cleaning file (yours)
│  ├─ 01_Do Files/                   00a_Directory.do, 00b_Local_Overrides.do,
│  │                                 01_Labeling.do, 02_Translation.do, 03_Audio.do,
│  │                                 _mdf/ (the engines — framework, hidden)
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

## The DO files an analyst works in

`<Project>_Processing.do`, `01_Labeling.do`, `02_Translation.do` and `03_Audio.do` are short and read
top to bottom: a header (project, purpose, project analyst, organisation, contact, date — from Section 0's
`project_analyst`, `project_email`, `organisation`, `project_description`; an unset field is left out),
a `DIRECTORY REFERENCE` (Processing and HFC DOs: the path globals — `$clean_dir`, `$processing_dir`, `$hfc_run_dir`
and the rest — with the folder each stands for, so an output can be sent somewhere by hand without looking the
name up), one `0. INITIALISE` block, then the stages in the order they run. Every section is marked
**[SAFE TO EDIT]** or **[MDF GENERATED - DO NOT EDIT]**:

| file | where your own code goes |
|---|---|
| `<Project>_Processing.do` | `2. FIELD CLEANING` and `3. POST-FIELD CLEANING`, per dataset |
| `01_Labeling.do` | `1. ODKSPLIT NAME OVERRIDES` — variables odksplit should see under a short name (see below); `3. MANUAL LABELING` — applied after the CAPI labels |
| `02_Translation.do` | `2. MANUAL TRANSLATION OVERRIDES` — applied after the returned files |
| `02_<Project>_HFC.do` | `CHECK SETTINGS` and `CUSTOM CHECKS` |

The labeling and translation engines are framework files in `01_Do Files/_mdf/`, rewritten on every
run. Master never overwrites a file you edit; when its template changes it writes `<file>.new` beside
it, and the Processing DO's `.new` already carries your cleaning.

### Variable names too long for odksplit

`odksplit` names Stata macros after each form field (`<field>_y`, `<field>_ch`, `<field>_l1`,
`<field>_<choice>la`), and a macro name stops at 31 characters. A field of 29 or more characters stops
it with `local macro name ... too long`; a select field whose `<field>_<choice>la` passes 31 loses that
choice's label without a word. Stata itself accepts names up to 32, so these variables are legal in
the data.

The labeling engine handles both. For the one `odksplit` call, each such variable takes a short
temporary name (`_mdf001`, `_mdf002`, ... in dataset order) in the working copies of the data and the
form; straight after, it gets its own name back with the labels `odksplit` gave the short one. The log
lists every pair. The real form and the archived raw data are never changed, and a project with no such
variable is processed exactly as before. To have `odksplit` treat another variable the same way, list it
in `01_Labeling.do`, section `1. ODKSPLIT NAME OVERRIDES`:

```stata
global odksplit_rename "var_one var_two"
```

A listed variable that does not exist, a short name already in use, or a name that does not come back
stops the run.

## Where a generated DO file runs

| where it sits | what it does |
|---|---|
| **inside its project** | finds the project's `.hfc_root` above the working directory, checks it is its own project by name, loads the project's directory file |
| **inside its Deliverables package** | finds the package's runtime, checks it is its own package, loads the package's own settings, checks the raw data by name and `datasignature`, rebuilds into `04_Cleaned Data/` |
| **anywhere else** | the Processing, Labeling, Translation and Audio DOs stop and say so; the HFC DO runs on the `.dta` beside it, output to `MDF_Output/` |

A context left in the Stata session by another project or package is never used: every global is
cleared before a file loads its own. In a package neither the Master DO file nor this framework needs
to be installed.

**Stata does not tell a running DO file where it is saved** — not from the Do button, not with
Ctrl+A then Ctrl+D (measured: `c(do_current)` and `c(filename)` are empty in Stata 17). Every
generated file therefore starts from Stata's **working directory** and goes up. Double-clicking a DO
file to launch Stata sets it; otherwise use *File > Change working directory*. A run that looks in the
wrong place stops and says which folder it searched.

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
│  │  └─ _mdf/  (hidden)                the runtime: the engines the project ran, byte for byte,
│  │                                    and mdf_package.do — the package's identity and settings
│  ├─ 02_Translation/                   the returned translation files (only if there are any)
│  └─ 03_Data/                          your support files from 05_Processing/03_Data/
├─ 04_Cleaned Data/                     the cleaned dataset
└─ README.md                            how the client rebuilds it
```

With several datasets the same four folders appear once per dataset, under
`08_Deliverables/NN_<dataset>/`, each carrying that dataset alone; its returned translation files
sit in `02_Translation/NN_<dataset>/`. The post-cleaning merge is not part of a per-dataset package.

`_mdf/` stays where it is because every Processing, Labeling and Translation DO since 11.1.0 finds its
package by that path; it is hidden, as the project's own `_mdf/` is. Zip a package with File Explorer
or 7-Zip — PowerShell's `Compress-Archive` leaves hidden folders out.

**Debugging in the package.** The package's copy of the Processing DO opens each dataset's block with
a line marked `LOAD DATASET INTO MEMORY`. Run section `0. INITIALISE` once, then that one line —
`use "${mdf_raw_<project>}/<dataset>.dta", clear` — and the dataset's raw data is in memory, wherever
the package has been moved. The global is set only by that project's package, so after another
project's INITIALISE the line finds no file rather than the wrong one. The project's own Processing
DO is not changed.

No daily download folders, no HFC history, no keys, no logs, no Master.

**The client** copies the folder anywhere, opens `03_Processing Files/<Project>_Processing.do`, and
runs it (Ctrl+A, Ctrl+D). The cleaned dataset is written to `04_Cleaned Data/`. If the machine lacks
`odksplit` or `inputcorrection` and the rebuild needs them, they are installed first; if that is
impossible the run stops before writing anything, rather than produce a dataset that would not match.
Every setting comes from the package itself, never from the Stata session; the raw data must be the
data the package was built from; and at the end the rebuild compares itself with the cleaned dataset
shipped in `04_Cleaned Data/` and says **REPRODUCED** or **NOT REPRODUCED**.

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

Master pins the framework it was written against: `global mdf_required "11.1.2"`.

- **Installed framework older than Master** → updated from GitHub; if that is impossible, the run
  stops before doing anything. An older framework cannot know the folders and stages a newer Master
  expects, and would otherwise build the project wrong without saying so.
- **Installed framework newer than Master** → a warning, and the run continues. This is how a
  10.2.0 project keeps running when a machine has 11.1.0.
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
can rebuild from; one on the 11.0 template gets the 11.0 package, with a warning that it depends on
the Stata session and may not reproduce.

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
mdf_bootstrap.ado             give a generated file its own project's context (identity-checked)
mdf_core_vars.ado             derive fielddate / total_duration
mdf_finalise.ado              post-cleaning merge and publish
mdf_deliverables.ado          the client handover package (stage 19)
_mdf_deliv_legacy.ado         the v10.2.0 package, for Processing DOs on an older template
_mdf_dlv_copy.ado             copy one file into the package, or say why not
_mdf_dlv_readme.ado           the README each package opens with
_mdf_rt_package.ado           the runtime a package carries (a do-file; named .ado so it ships)
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
