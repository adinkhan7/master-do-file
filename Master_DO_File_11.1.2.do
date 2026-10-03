*==============================================================================*
*  MASTER DO FILE  —  SURVEY PIPELINE & HIGH-FREQUENCY CHECKS
*  Organisation : Development Research Initiative (dRi)
*  Purpose      : Portable folder setup, data pipeline, and HFC launcher
*
*  EDIT SECTION 0 ONLY.
*  Run 1 builds the folders. Run 2 generates the pipeline files. Run 3+ runs it.
*  Guidance: README.md in the project.   Design decisions: Instruction/DECISIONS.md.

*==============================================================================*

*==============================================================================*
*  DEPENDENCIES

*==============================================================================*
ssc install mrtab
cap noi net install exportopenended, from("https://raw.githubusercontent.com/RanaRedoan/exportopenended/main")
cap noi net install recode_nrep, from("https://raw.githubusercontent.com/ashikpydev/recode_nrep/main/")
cap noi net install recode_rep, from("https://raw.githubusercontent.com/ashikpydev/recode_rep/main/")
cap noi net install multisplit, from("https://raw.githubusercontent.com/ashikpydev/multisplit/main/")
cap noi net install inputcorrection, from("https://raw.githubusercontent.com/RanaRedoan/inputcorrection/main")
net install exporttabs, from("https://raw.githubusercontent.com/RanaRedoan/exporttabs/main")
net install exportables, from("https://raw.githubusercontent.com/ashikpydev/exportables/main/") replace
net install exprep, from("https://raw.githubusercontent.com/ashikpydev/exprep/main")
net install bias_expo, from("https://raw.githubusercontent.com/adinkhan7/bias_expo/main/")
cap noi net install export_hfc, from("https://raw.githubusercontent.com/adinkhan7/export_hfc/main/")
net install recode_oth, from("https://raw.githubusercontent.com/ashikpydev/recode_oth/main/") replace
cap noi ssc install odksplit

*==============================================================================*
*  Master DO File version 11.1.2

*==============================================================================*
clear all
set more off
version 16
if c(stata_version) < 16 {
    di as error "ERROR: Master DO File requires Stata 16 or higher."
    exit 9
}

*==============================================================================*
*  SECTION 0   USER CONFIGURATION                    ← EDIT ONLY THIS SECTION

*==============================================================================*

*  ── Project ────────────────────────────────────────────────────────────────
global project_name         "Monash WEE DiFine"
global sample_size          2400

*  ── Project details: shown in the header of every generated DO file ───────
*  Leave a field "" to leave it out of the headers.
global project_analyst      ""                   // e.g. "A. Analyst, Officer, Data Analytics"
global project_email        ""                   // contact for the project's DO files
global organisation         "Development Research Initiative (dRi)"
global project_description  ""                   // one line on the survey; "" = a standard line

*  ── Stages to run (0 = skip, 1 = run) ──────────────────────────────────────
global run_import           0                    // import DO file(s) from SurveyCTO
global run_labeling         0                    // CAPI value labels — applied INSIDE Processing (needs run_processing 1)
global run_translation      0                    // 05_Processing/01_Do Files/02_Translation.do (open-ended round trip)
global run_processing       1                    // 05_Processing/[Project]_Processing.do (cleaning)
global run_hfc              0                    // 06_HFC/02_[Project]_HFC.do (the checks)
global run_audio            0                    // 05_Processing/01_Do Files/03_Audio.do (audio sampling)
global run_deliverables     0                    // 08_Deliverables/ (client handover package)

*  ── Post-field mode ────────────────────────────────────────────────────────
global post_field           0                    // 0 = field ongoing / 1 = fieldwork complete

*  ── Import ─────────────────────────────────────────────────────────────────
global import_fingerprint   1                    // 1 = check / 0 = skip

*  ── CAPI / labeling ────────────────────────────────────────────────────────
global capi_override        ""                   // leave "" to auto-detect the latest .xlsx in 02_CAPI/
global capi_language        "English"            // Default language for ODKSplit
global capi_verbose         0                    // 1 = Show ODKSplit variable list / 0 = Silent labeling

*  ── Open-ended translation ─────────────────────────────────────────────────
global exportopenended      0                    // 1 = Export text variables for translation / 0 = Skip
global oe_export_all        0                    // 0 = new responses only / 1 = all open-ended responses
global inputcorrection      1                    // 1 = Re-inject translated text variables / 0 = Skip
global exp_openended_vars   ""                   // used when n_datasets == 1
global exp_openended_vars_1 ""                   // DS1 open-ended var list (multi-dataset)
global exp_openended_vars_2 ""                   // DS2 open-ended var list (multi-dataset)
global exp_openended_vars_3 ""                   // DS3 open-ended var list (multi-dataset)

*  ── Audio audit ────────────────────────────────────────────────────────────
global audio_seed           987654321            // Seed for reproducible audio sampling
global audio_sample_count   5                    // Number of surveys to sample per enumerator
global audio_drop_before    ""                   // blank = drop interviews before yesterday; or YYYYMMDD
global audio_keep_enums     ""                   // blank = all enumerators; or space-separated enum IDs

*  ── Post-cleaning merge (multi-dataset only) ───────────────────────────────
global merge_required       0                    // 1 = Merge specified datasets after cleaning, 0 = Skip
global merge_datasets       "1 3"                // Space-separated indices of datasets to merge (e.g., "1 2")
global merge_type           "1:1"                // Linkage type: 1:1, 1:m, m:1, m:m
global merge_key            "hhid"               // Variable key to merge on

*  ── Variable lists ─────────────────────────────────────────────────────────
global meta_front           ""
global meta_ids             ""
global tail                 ""
global timer_start          ""
global timer_end            ""

global meta_front_          1       ""
global meta_ids_            1         ""
global tail_                1             ""
global meta_front_          2       ""
global meta_ids_            2         ""
global tail_                2             ""
global meta_front_          3       ""
global meta_ids_            3         ""
global tail_                3             ""

*  ── Special-response codes (Response Bias check) ───────────────────────────
global code_dk              -999                 // "Don't Know" response code
global code_na              96                   // "Not Applicable" response code
global code_other           99                   // "Other" response code

*  ── Output aliases and verbosity ───────────────────────────────────────────
global hfc_excel_aliases    "HFC_FILE hfc_file excel_file"  // Space-separated aliases pointing to the HFC report
global hfc_dta_aliases      "DTA_FILE dta_file"  // Space-separated aliases pointing to the Target DTA
global verbose              1                    // 1 = use 'cap noi' for debugging, 0 = silent cap

*  ── Framework package ────────────────────────────────────────────────────────
global mdf_autoinstall      1                    // 1 = update the framework when needed, 0 = never touch the network
global mdf_required         "11.1.2"             // framework version this file expects
global mdf_source           "https://raw.githubusercontent.com/adinkhan7/master-do-file/main"  // package home

*==============================================================================*
*  Everything below is for system use, no need to make any change.
*==============================================================================*

*  The framework itself lives at github.com/adinkhan7/master-do-file and is
*  installed on first run. Everything below is a stage of the pipeline, in the
*  order it executes. Nothing here needs editing — and if a stage misbehaves you
*  can run it on its own from the Command window after Master has been run once.
cap which mdf_setup
if _rc {
    di as result "Installing the Master DO File framework from $mdf_source"
    cap noi net install mdf, from("$mdf_source") replace
    if _rc {
        di as error "ERROR: could not install the framework from:"
        di as error "         $mdf_source"
        di as error "       Check the connection and re-run, or install it by hand:"
        di as error `"       net install mdf, from("$mdf_source") replace"'
        exit 601
    }
}
*  A framework from an earlier major version cannot run this Master: it would
*  build the project in the old folder layout and say nothing. Update it, and
*  stop here if that is not possible.
cap qui mdf version
if real(word(subinstr(`"`r(version)'"', ".", " ", .), 1)) < real(word(subinstr("$mdf_required", ".", " ", .), 1)) {
    if "$mdf_autoinstall" == "1" cap noi net install mdf, from("$mdf_source") replace
    cap qui mdf version
    if real(word(subinstr(`"`r(version)'"', ".", " ", .), 1)) < real(word(subinstr("$mdf_required", ".", " ", .), 1)) {
        di as error "ERROR: the installed framework (mdf `r(version)') is older than this Master"
        di as error "       needs (mdf $mdf_required) and could not be updated. Nothing was done."
        di as error `"       net install mdf, from("$mdf_source") replace"'
        exit 601
    }
}

mdf_setup         //  helper programs, ROOT resolution, framework identity
mdf_validate      //  Section 0 sanity checks and switch defaults
mdf_paths         //  run dates and every folder path global
mdf_folders       //  create the project folder tree
mdf_readme        //  write the project README
mdf_resolve       //  post-field resolution
mdf_workdirs      //  today's raw-data folder and HFC run folder
mdf_log           //  open the run log and detect the run type
mdf_generate      //  directory file and overrides, output paths, previous keys
mdf_import        //  carry the import DO forward, fingerprint it, import
mdf_modules       //  pipeline modules, the HFC DO and the Processing DO
mdf_guards        //  stale-processing and open-workbook guards
mdf_stage         //  archive raw data and stage the working copy
mdf_instruments   //  CAPI subfolders, instrument archiving, translation folders
mdf_clean         //  run cleaning
mdf_hfc           //  run the high-frequency checks
mdf_audio         //  audio audit
mdf_keys          //  archive keys and print the run summary
mdf_deliverables  //  build the client handover package (run_deliverables = 1)
