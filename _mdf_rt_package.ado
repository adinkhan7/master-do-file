*! _mdf_rt_package.ado — the runtime a Deliverables package carries (ADR-061)
*! version 11.1.0   github.com/adinkhan7/master-do-file
*!
*!  Not an ado-command: a do-file with an .ado extension, because -net install-
*!  ships program files only (the reason _mdf_defs.ado is named as it is). The
*!  Deliverables builder copies it into every package as
*!
*!      03_Processing Files/01_Do Files/_mdf/mdf_runtime.do
*!
*!  and the package's DO files run it from their INITIALISE block, having found
*!  the package by walking up from Stata's working directory. It gives them a
*!  context built from the package alone — nothing from this machine, the
*!  project the package came from, or anything else run in this Stata session:
*!
*!    1. the package must be this file's project's package
*!    2. every file in it must be openable (Windows' 260-character limit)
*!    3. every raw dataset must be one the package was built for, by name, and
*!       hold the data it was built from, by datasignature
*!    4. every setting comes from _mdf/mdf_package.do, written at build time
*!
*!  Anything that fails stops the run and says what was expected and what was
*!  found. Nothing is guessed.

version 16

*  Where each survey command a rebuild may need is installed from — the same
*  sources as the DEPENDENCIES block of the Master DO file.
cap program drop _mdf_rt_install
program define _mdf_rt_install
    args _c
    local _gh "https://raw.githubusercontent.com"
    if "`_c'" == "odksplit"        cap noi ssc install odksplit
    if "`_c'" == "mrtab"           cap noi ssc install mrtab
    if "`_c'" == "inputcorrection" cap noi net install inputcorrection, from("`_gh'/RanaRedoan/inputcorrection/main")
    if "`_c'" == "exporttabs"      cap noi net install exporttabs, from("`_gh'/RanaRedoan/exporttabs/main")
    if "`_c'" == "recode_nrep"     cap noi net install recode_nrep, from("`_gh'/ashikpydev/recode_nrep/main/")
    if "`_c'" == "recode_rep"      cap noi net install recode_rep, from("`_gh'/ashikpydev/recode_rep/main/")
    if "`_c'" == "multisplit"      cap noi net install multisplit, from("`_gh'/ashikpydev/multisplit/main/")
    if "`_c'" == "exportables"     cap noi net install exportables, from("`_gh'/ashikpydev/exportables/main/") replace
    if "`_c'" == "exprep"          cap noi net install exprep, from("`_gh'/ashikpydev/exprep/main")
    if "`_c'" == "recode_oth"      cap noi net install recode_oth, from("`_gh'/ashikpydev/recode_oth/main/") replace
    if "`_c'" == "bias_expo"       cap noi net install bias_expo, from("`_gh'/adinkhan7/bias_expo/main/")
    if "`_c'" == "export_hfc"      cap noi net install export_hfc, from("`_gh'/adinkhan7/export_hfc/main/")
end

*  ── Who is asking, and where the package is ─────────────────────────────────
local _id   `"$mdf_want_id"'
local _role "$mdf_want_role"
local _pk   `"$mdf_want_at"'
global mdf_want_id   ""
global mdf_want_role ""
global mdf_want_at   ""
local _rt `"`_pk'/03_Processing Files/01_Do Files/_mdf"'

*  ── A module called by this package's own Processing DO keeps its context ──
if "`_role'" != "processing" & "$mdf_package" == "1" & `"$ROOT"' == `"`_pk'"' & `"$mdf_pk_project"' == `"`_id'"' exit

*  ── Everything else starts from nothing ─────────────────────────────────────
*  Stata's globals outlive -clear all-. A switch left behind by another package
*  or project would otherwise change what this one produces. Every global is
*  cleared except Stata's own (S_ADO is the adopath) and the function keys;
*  -macro drop _all- would take this file's locals with them (measured).
cap mata: mata drop _mdf_rt_clear()
mata:
void _mdf_rt_clear()
{
    string colvector G
    real scalar i
    G = st_dir("global", "macro", "*")
    for (i = 1; i <= rows(G); i++) {
        if (substr(G[i], 1, 2) == "S_") continue
        if (regexm(G[i], "^F[0-9]+$")) continue
        st_global(G[i], "")
    }
}
end
mata: _mdf_rt_clear()

cap confirm file `"`_rt'/mdf_package.do"'
if _rc {
    di as error "====================================================================="
    di as error "  DELIVERABLES PACKAGE  —  ITS SETTINGS FILE IS MISSING"
    di as error "====================================================================="
    di as txt   "  This package's runtime is here, but the file that says what the"
    di as txt   "  package is and how it was built is not:"
    di as result `"    `_rt'/mdf_package.do"'
    di as txt   "  The package is incomplete. Use a complete copy of it."
    di as error "====================================================================="
    exit 601
}
qui do `"`_rt'/mdf_package.do"'

*==============================================================================*
*  1  IS THIS THE RIGHT PACKAGE?
*==============================================================================*
if `"$mdf_pk_project"' != `"`_id'"' {
    local _pwd `"`c(pwd)'"'
    di as error "====================================================================="
    di as error "  WRONG PACKAGE  —  NOTHING HAS BEEN RUN"
    di as error "====================================================================="
    di as txt   `"  This file belongs to the project : `_id'"'
    di as txt   `"  The package found here is for    : $mdf_pk_project"'
    di as result `"    `_pk'"'
    di as txt   "  It was found by searching upward from Stata's working directory:"
    di as result `"    `_pwd'"'
    di as txt   "  Set the working directory to this file's own package (File > Change"
    di as txt   "  Working Directory) and run it again."
    di as error "====================================================================="
    exit 198
}

*==============================================================================*
*  2  CAN EVERY FILE IN IT BE OPENED?
*==============================================================================*
*  Stata cannot open a file whose full path is longer than Windows allows, and
*  the error it gives then is "file not found". Measured here, so the run can
*  say what is really wrong before anything misleading happens.
cap mata: mata drop _mdf_rt_longest()
mata:
string scalar _mdf_rt_longest(string scalar root)
{
    string colvector D, F
    string scalar best, d
    real scalar i, j
    D = root
    best = ""
    for (i = 1; i <= rows(D); i++) {
        d = D[i]
        F = dir(d, "files", "*")
        for (j = 1; j <= rows(F); j++) {
            if (ustrlen(d + "/" + F[j]) > ustrlen(best)) best = d + "/" + F[j]
        }
        F = dir(d, "dirs", "*")
        for (j = 1; j <= rows(F); j++) D = D \ (d + "/" + F[j])
    }
    return(best)
}
end
local _long ""
mata: st_local("_long", _mdf_rt_longest(st_local("_pk")))
forvalues _k = 1/$mdf_pk_nds {
    if "${mdf_pk_here_`_k'}" == "1" {
        local _out `"`_pk'/04_Cleaned Data/${mdf_pk_name_`_k'}_CLEANED.dta"'
        if ustrlen(`"`_out'"') > ustrlen(`"`_long'"') local _long `"`_out'"'
    }
}
if ustrlen(`"`_long'"') > $mdf_pk_maxpath {
    di as error "====================================================================="
    di as error "  DELIVERABLES PACKAGE  —  ITS FOLDER PATH IS TOO LONG FOR WINDOWS"
    di as error "====================================================================="
    di as txt   "  Windows cannot open a file whose full path is longer than 260"
    di as txt   "  characters, and Stata then reports it as not found. This one is " ustrlen(`"`_long'"') ":"
    di as result `"    `_long'"'
    di as txt   "  Move or extract the package to a short folder, for example"
    di as result "    C:\Projects\" _c
    di as result `"$mdf_pk_short"'
    di as txt   "  and run it again from there. Nothing has been written."
    di as error "====================================================================="
    exit 603
}

*==============================================================================*
*  3  IS THE RAW DATA THE DATA THIS PACKAGE WAS BUILT FROM?
*==============================================================================*
*  By name first: every Stata dataset in 02_Import & Raw files/ must answer to a
*  dataset this package carries — its .dta name, SurveyCTO's _wide dropped, as
*  Master names datasets. Then by content: the datasignature recorded when the
*  package was built. The framework's own output is never read as input.
local _raw `"`_pk'/02_Import & Raw files"'
local _all ""
cap local _all : dir `"`_raw'"' files "*.dta", respectcase
local _all : list sort _all
local _cand ""
foreach _f of local _all {
    local _ok 1
    foreach _tag in "_KEYS_" "_CLEANED" "_MERGED_" "_LABELED_" {
        if strpos(`"`_f'"', "`_tag'") > 0 local _ok 0
    }
    if substr(`"`_f'"', 1, 1) == "_" local _ok 0
    if `_ok' local _cand `"`_cand' `"`_f'"'"'
}

global actual_n_dta $mdf_pk_nds
global n_datasets   $mdf_pk_nds
forvalues _k = 1/$mdf_pk_nds {
    global auto_dsname_`_k' `"${mdf_pk_name_`_k'}"'
    global mdf_ds_here_`_k' "${mdf_pk_here_`_k'}"
    global target_dta_`_k'  ""
    global dta_labeled_`_k' ""
    global dta_cleaned_`_k' ""
    global capi_override_`_k' ""
}

local _bad ""
foreach _f of local _cand {
    local _stem = substr(`"`_f'"', 1, strlen(`"`_f'"') - 4)
    if strlen(`"`_stem'"') > 5 & lower(substr(`"`_stem'"', -5, 5)) == "_wide" local _stem = substr(`"`_stem'"', 1, strlen(`"`_stem'"') - 5)
    local _hit 0
    forvalues _k = 1/$mdf_pk_nds {
        if `_hit' == 0 & "${mdf_pk_here_`_k'}" == "1" & lower(`"`_stem'"') == lower(`"${mdf_pk_name_`_k'}"') local _hit `_k'
    }
    *  Two files answering to one dataset is as bad as a stranger.
    if `_hit' > 0 {
        if `"${target_dta_`_hit'}"' != "" local _hit 0
    }
    if `_hit' == 0 local _bad `"`_bad' `"`_f'"'"'
    else {
        global target_dta_`_hit'  `"`_raw'/`_f'"'
        global dta_labeled_`_hit' `"`_raw'/`_f'"'
    }
}
local _miss ""
forvalues _k = 1/$mdf_pk_nds {
    if "${mdf_pk_here_`_k'}" == "1" & `"${target_dta_`_k'}"' == "" local _miss `"`_miss' `"${mdf_pk_name_`_k'}.dta"'"'
}
if `"`_bad'`_miss'"' != "" {
    di as error "====================================================================="
    di as error "  DELIVERABLES PACKAGE  —  THE RAW DATA IS NOT WHAT IT SHOULD BE"
    di as error "====================================================================="
    di as txt   "  This package rebuilds these dataset(s), and nothing else:"
    forvalues _k = 1/$mdf_pk_nds {
        if "${mdf_pk_here_`_k'}" == "1" di as result `"    ${mdf_pk_name_`_k'}.dta"'
    }
    if `"`_miss'"' != "" {
        di as txt   "  MISSING from 02_Import & Raw files/:"
        foreach _f of local _miss {
            di as error `"    `_f'"'
        }
        di as txt   "  Put the raw dataset that came with the package back, or run its"
        di as txt   "  import DO in that folder to rebuild it from the CSV."
    }
    if `"`_bad'"' != "" {
        di as txt   "  FOUND, but not a dataset this package was built for (or a second"
        di as txt   "  file answering to the same dataset):"
        foreach _f of local _bad {
            di as error `"    `_f'"'
        }
        di as txt   "  Which file is which dataset cannot be guessed, and guessing would"
        di as txt   "  clean the wrong data. Remove or rename the file(s) above."
    }
    di as txt   "  Looked in:"
    di as result `"    `_raw'"'
    di as error "====================================================================="
    exit 198
}

forvalues _k = 1/$mdf_pk_nds {
    if "${mdf_pk_here_`_k'}" == "1" & `"${mdf_pk_sig_`_k'}"' != "" {
        qui use `"${target_dta_`_k'}"', clear
        qui datasignature
        local _sig `"`r(datasignature)'"'
        if `"`_sig'"' != `"${mdf_pk_sig_`_k'}"' {
            di as error "====================================================================="
            di as error "  DELIVERABLES PACKAGE  —  THE RAW DATA HAS CHANGED"
            di as error "====================================================================="
            di as txt   "  The file has the right name but not the data this package was"
            di as txt   "  built from, so the rebuild could not reproduce its cleaned dataset:"
            di as result `"    ${target_dta_`_k'}"'
            di as txt   `"  built from : ${mdf_pk_sig_`_k'}"'
            di as txt   `"  found      : `_sig'"'
            di as txt   "  (observations:variables(width):checksums — see -help datasignature-)"
            di as txt   "  If you replaced the raw data on purpose, delete the line"
            di as result `"    global mdf_pk_sig_`_k' ..."'
            di as txt   "  from _mdf/mdf_package.do and run again: the result will then not"
            di as txt   "  match the cleaned dataset the package was shipped with."
            di as error "====================================================================="
            exit 459
        }
    }
}
clear

*==============================================================================*
*  4  THE CONTEXT: EVERY PATH AND SETTING FROM THE PACKAGE
*==============================================================================*
global ROOT                 `"`_pk'"'
global mdf_standalone       1
global mdf_package          1
global mdf_rt_dir           `"`_rt'"'
global processing_dir       `"`_pk'/03_Processing Files"'
global dofiles_dir          `"$processing_dir/01_Do Files"'
global hfc_dofiles_dir      `"$dofiles_dir"'
global processing_data_dir  `"$processing_dir/03_Data"'
global translation_dir      `"$processing_dir/02_Translation"'
global trans_exported_dir   `"$translation_dir/01_Exported"'
global trans_translated_dir `"$translation_dir/02_Translated"'
global surv_inst_dir        `"`_pk'"'
global capi_dir             `"`_pk'/01_CAPI & Questionnaire"'
global quest_dir            `"$capi_dir"'
global data_dir             `"`_raw'"'
global raw_data_dir         `"`_raw'"'
global hfc_rawdata_dir      `"`_raw'"'
global hfc_raw_snapshot_dir `"`_raw'"'
global clean_dir            `"`_pk'/04_Cleaned Data"'
foreach _d in "$trans_exported_dir" "$trans_translated_dir" "$clean_dir" {
    cap mkdir `"`_d'"'
}

*  The cleaned dataset is the only thing written into the package. The dated
*  working copy the workflow saves on the way goes to Stata's temp folder.
local _tmp = subinstr(`"`c(tmpdir)'"', "\", "/", .)
if substr(`"`_tmp'"', -1, 1) == "/" local _tmp = substr(`"`_tmp'"', 1, strlen(`"`_tmp'"') - 1)
global mdf_out              `"`_tmp'/mdf_package_work"'
global hfc_run_dir          `"$mdf_out"'
global hfc_dir              `"$mdf_out"'
global hfc_keys_dir         `"$mdf_out/KEYS"'
global hfc_keys_hfc_dir     `"$hfc_keys_dir/01_HFC_Keys"'
global hfc_keys_audio_dir   `"$hfc_keys_dir/02_Audio_Keys"'
global hfc_keys_trans_dir   `"$hfc_keys_dir/03_Translation_Keys"'
global hfc_keys_master_dir  `"$hfc_keys_hfc_dir"'
global hfc_flag_dir         `"$hfc_keys_dir/.flag_history"'
foreach _d in "$mdf_out" "$hfc_keys_dir" "$hfc_keys_hfc_dir" "$hfc_keys_audio_dir" "$hfc_keys_trans_dir" "$hfc_flag_dir" {
    cap mkdir `"`_d'"'
}

local _dt = daily("`c(current_date)'", "DMY")
local _ds : display %tdCCYYNNDD `_dt'
global today           = strtrim("`_ds'")
local _ds : display %tdCCYYNNDD (`_dt' - 1)
global yesterday       = strtrim("`_ds'")
global hfc_folder_date "$today"
global LAST_RUN_DATE   "$today"
global hfc_report      `"$mdf_out/HFC_${project_name}_$today.xlsx"'

forvalues _k = 1/$mdf_pk_nds {
    global pre_keys_`_k' `"$hfc_keys_master_dir/${auto_dsname_`_k'}_KEYS_$LAST_RUN_DATE.dta"'
    *  A working copy left by an earlier run must never be published as this one.
    cap erase `"$mdf_out/${auto_dsname_`_k'}_CLEANED_$today.dta"'
}
global target_dta  `"$target_dta_1"'
global dta_labeled `"$dta_labeled_1"'

*  Stages that only mean anything inside a project, and two that a rebuild
*  never performs: sending text to translators, and a cross-dataset merge.
global post_field           0
global run_import           0
global import_fingerprint   0
global hfc_postfield_active 0
global exportopenended      0
global merge_required       0

*  ── The SurveyCTO form: the one workbook with survey and choices sheets ────
local _form ""
local _nf 0
local _xl ""
cap local _xl : dir `"$capi_dir"' files "*.xlsx", respectcase
local _xl : list sort _xl
foreach _f of local _xl {
    if substr(`"`_f'"', 1, 1) == "~" continue
    cap qui import excel using `"$capi_dir/`_f'"', describe
    if _rc continue
    local _s 0
    local _c 0
    local _nw = r(N_worksheet)
    forvalues _w = 1/`_nw' {
        local _wn = lower(strtrim(`"`r(worksheet_`_w')'"'))
        if `"`_wn'"' == "survey"  local _s 1
        if `"`_wn'"' == "choices" local _c 1
    }
    if `_s' & `_c' {
        local _form `"`_f'"'
        local _nf = `_nf' + 1
    }
}
if `_nf' > 1 {
    di as error "====================================================================="
    di as error "  DELIVERABLES PACKAGE  —  MORE THAN ONE SURVEYCTO FORM"
    di as error "====================================================================="
    di as txt   "  01_CAPI & Questionnaire/ holds `_nf' SurveyCTO forms. The package"
    di as txt   "  carries exactly one, and which one labelled the data cannot be"
    di as txt   "  guessed. Remove the extra form(s) and run again:"
    di as result `"    $capi_dir"'
    di as error "====================================================================="
    exit 198
}
if `_nf' == 0 & "$run_labeling" == "1" {
    di as error "====================================================================="
    di as error "  DELIVERABLES PACKAGE  —  THE SURVEYCTO FORM IS MISSING"
    di as error "====================================================================="
    di as txt   "  The cleaned dataset was labelled from a SurveyCTO form, and none is"
    di as txt   "  in 01_CAPI & Questionnaire/. Without it the rebuild would carry no"
    di as txt   "  labels and would not match. Nothing has been written."
    di as result `"    $capi_dir"'
    di as error "====================================================================="
    exit 198
}
if `_nf' == 1 {
    global capi_override `"`_form'"'
    forvalues _k = 1/$mdf_pk_nds {
        if "${mdf_pk_here_`_k'}" == "1" global capi_override_`_k' `"`_form'"'
    }
    if `"$mdf_pk_form"' != "" & lower(`"`_form'"') != lower(`"$mdf_pk_form"') {
        di as error `"  WARNING: the package was built with the form $mdf_pk_form;"'
        di as error `"           the form here is `_form'. Labels may differ."'
    }
}

*  ── The framework helpers this package needs, from the package itself ─────
cap adopath - `"`_rt'/ado"'
adopath ++ `"`_rt'/ado"'

*  ── Survey commands the rebuild uses ───────────────────────────────────────
*  A client machine has no reason to have them. Without odksplit the labels are
*  missing and without inputcorrection the translations are, and the rebuild
*  would silently differ — so each is installed when absent, and the run stops
*  before writing anything if that fails. Other commands the analyst's own code
*  names are installed when absent too; a missing one stops the run by itself.
*  The sources are the ones Master's DEPENDENCIES block lists.
if `"$mdf_pkg_deps_ok"' != `"`_pk'"' {
    local _need ""
    if "$run_labeling" == "1" local _need "odksplit"
    if "$inputcorrection" == "1" {
        local _tx ""
        cap local _tx : dir `"$trans_translated_dir"' files "*.xlsx"
        local _ntx : word count `_tx'
        if `_ntx' > 0 local _need "`_need' inputcorrection"
    }
    foreach _c of local _need {
        cap which `_c'
        if _rc {
            di as txt "  `_c' is not installed on this machine; installing it..."
            _mdf_rt_install `_c'
            cap which `_c'
            if _rc {
                di as error "====================================================================="
                di as error "  DELIVERABLES PACKAGE  —  `_c' IS NOT AVAILABLE"
                di as error "====================================================================="
                di as txt   "  The cleaned dataset was produced with the Stata command `_c',"
                di as txt   "  which is not installed here and could not be installed (no"
                di as txt   "  connection?). Without it the rebuild would not match, so nothing"
                di as txt   "  has been written. Install it, then run this file again."
                di as error "====================================================================="
                exit 199
            }
        }
    }
    *  The rest: only what the analyst's own files actually name. Read in Mata,
    *  so the analyst's macro references are never expanded here.
    local _want ""
    foreach _file in `"$processing_dir/$mdf_pk_procfile"' `"$dofiles_dir/01_Labeling.do"' `"$dofiles_dir/02_Translation.do"' {
        cap confirm file `"`_file'"'
        if _rc continue
        mata: _mdf_rt_L = strtrim(cat(st_local("_file")))
        mata: _mdf_rt_L = select(_mdf_rt_L, substr(_mdf_rt_L, 1, 1) :!= "*")
        foreach _c in mrtab recode_nrep recode_rep multisplit exporttabs exportables exprep bias_expo export_hfc recode_oth {
            local _h 0
            mata: st_local("_h", strofreal(sum(strpos(_mdf_rt_L, st_local("_c")) :> 0) > 0))
            if `_h' & strpos(" `_want' ", " `_c' ") == 0 local _want "`_want' `_c'"
        }
        cap mata: mata drop _mdf_rt_L
    }
    foreach _c of local _want {
        cap which `_c'
        if _rc {
            di as txt "  `_c' is used by the cleaning code and is not installed; installing it..."
            _mdf_rt_install `_c'
            cap which `_c'
            if _rc di as error "  WARNING: `_c' could not be installed. If the cleaning needs it, the run will stop there."
        }
    }
    global mdf_pkg_deps_ok `"`_pk'"'
}

global mdf_pk_ready 1
di as result "====================================================================="
di as result "  DELIVERABLES PACKAGE  —  rebuilding the cleaned data here"
di as result "====================================================================="
di as txt    `"    project  : $mdf_pk_project"'
di as txt    `"    package  : `_pk'"'
forvalues _k = 1/$mdf_pk_nds {
    if "${mdf_pk_here_`_k'}" == "1" di as result `"    DS`_k'      : ${mdf_pk_name_`_k'}   (raw data verified)"'
}
di as txt    `"    form     : `_form'"'
di as txt    `"    settings : _mdf/mdf_package.do (built $mdf_pk_built, mdf $mdf_pk_version)"'
di as txt    `"    output   : $clean_dir"'
di as result "====================================================================="
