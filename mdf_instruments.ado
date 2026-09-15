*! mdf_instruments.ado — Master DO File pipeline stage 14 of 18
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  CAPI subfolders, instrument archiving, translation folders

program define mdf_instruments
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 19  CAPI SUBFOLDER MANAGEMENT
    *==============================================================================*

    cap mata drop _hfc_rename_dir()





    if $actual_n_dta == 1 {
        di as result _n "--- Single dataset: no CAPI subfolder needed ---"
    }
    else {
        di as result _n "--- Multiple datasets: checking CAPI subfolders ---"
        di as txt       "    (Scanning folder structure — may take a moment for large directories.)"

        local _needs_capi 0
        local _ia 0

    forvalues _ia = 1/$actual_n_dta {
            local _fnum     : display %02.0f `_ia'
            local _base     "${auto_dsname_`_ia'}"
            if "`_base'" == "" {
                di as error "  DS`_ia': dataset name unresolved — skipping folder setup."
                continue
            }
            local _new_name "`_fnum'_SurveyCTO_`_base'"
            local _quest_name "`_fnum'_Questionnaire_`_base'"
            local _others_name "`_fnum'_Others_`_base'"
            local _old_path "$capi_dir/form_`_fnum'"
            local _new_path "$capi_dir/`_new_name'"

            _hfc_mkdir "$quest_dir/`_quest_name'"
            _hfc_mkdir "$others_dir/`_others_name'"

            mata: st_local("_chk_new", strofreal(direxists("`_new_path'")))
            if `_chk_new' {
                di as result "  DS`_ia' — already in place: `_new_name'"
            }
            else {
                mata: st_local("_chk_old", strofreal(direxists("`_old_path'")))
                if !`_chk_old' {
                    _hfc_mkdir "`_old_path'"
                }
                mata: _hfc_rename_dir("`_old_path'", "`_new_path'")

                mata: st_local("_chk_ren", strofreal(direxists("`_new_path'")))
                if !`_chk_ren' {
                    di as error "  DS`_ia': directory rename failed (form_`_fnum' → `_new_name')."
                    _hfc_abort
                }
                di as result "  Renamed: form_`_fnum' → `_new_name'"
            }

            mata: st_local("_chk_dir_ok", strofreal(direxists("`_new_path'")))
            if `_chk_dir_ok' {
                local _xlsx_raw : dir "`_new_path'" files "*.xlsx"
                *  A folder holding only an Excel lock file (~$...) has no usable
                *  form in it. Counting one would report CAPI present and let the
                *  run continue to fail later, at labeling.
                local _xlsx_chk ""
                foreach _xc of local _xlsx_raw {
                    if substr(`"`_xc'"', 1, 1) != "~" local _xlsx_chk `"`_xlsx_chk' `_xc'"'
                }
                if `"`_xlsx_chk'"' == "" {
                    if "$run_labeling" == "1" {
                        local _needs_capi 1
                        di as result "  DS`_ia' — CAPI missing. Place .xlsx in:"
                        di as result "    `_new_path'/"
                    }
                    else {
                        di as result "  DS`_ia' — CAPI missing (Ignored: run_label = 0)"
                    }
                }
                else {
                    di as result "  DS`_ia' — CAPI found in `_new_name'/."
                }
            }
            else {
                local _needs_capi 1
                di as error "  DS`_ia' — Folder not accessible: `_new_path'"
            }
        }

    if `_needs_capi' {
            di as result _n "======================================================="
            di as result    "  INTERMEDIATE STEP REQUIRED"
            di as result    "  Place the SurveyCTO .xlsx form for each dataset"
            di as result    "  in its folder (see paths above). Then re-run."
            di as result    "=======================================================" _n
            _hfc_pause
            global mdf_halt 1
            exit
        }
        di as result "All CAPI forms found — continuing pipeline."
    }

    *  ── Remove any remaining empty form_NN placeholders (multi-dataset) ────────
    if $actual_n_dta > 1 {
        local _all_capi_dirs : dir "$capi_dir" dirs "form_*"
        foreach _d of local _all_capi_dirs {
            local _fcont : dir "$capi_dir/`_d'" files "*"
            if `"`_fcont'"' == "" {
                cap mata: rmdir("$capi_dir/`_d'")
                if _rc di as result "  NOTE: Could not remove placeholder `_d' — left in place."
                else   di as result "  Removed empty placeholder: `_d'"
            }
        }
    }

    *==============================================================================*
    *  SECTION 20  INSTRUMENT ARCHIVING
    *==============================================================================*


    di as result _n "--- Archiving superseded instrument versions ---"
    _hfc_archive_instruments "$quest_dir" "Questionnaire"
    _hfc_archive_instruments "$capi_dir"  "CAPI"
    if $actual_n_dta > 1 {
        foreach _sub in "$quest_dir" "$capi_dir" {
            local _subdirs : dir "`_sub'" dirs "*"
            foreach _sd of local _subdirs {
                if "`_sd'" != "Archive" {
                    _hfc_archive_instruments "`_sub'/`_sd'" "`_sd'"
                }
            }
        }
    }

    *==============================================================================*
    *  SECTION 21  PER-DATASET TRANSLATION FOLDERS
    *==============================================================================*

    di as result _n "--- Translation folders (per dataset) ---"

    forvalues _tz = 1/$actual_n_dta {
        local _tz_base "${auto_dsname_`_tz'}"
        if "`_tz_base'" == "" {
            di as error "  DS`_tz': dataset name unresolved — skipping translation folders."
            continue
        }
        _hfc_mkdir "$trans_exported_dir/`_tz_base'"
        _hfc_mkdir "$trans_translated_dir/`_tz_base'"
    }
    di as result "  Exported → $trans_exported_dir"
    di as result "  Return translated files to → $trans_translated_dir"

    *  ── Exit safely if in Pre-Fieldwork Mode ───────────────────────────────────
    if $ghost_run == 1 {
        di as result _n "======================================================="
        di as result    "  PRE-FIELDWORK ARCHITECTURE COMPLETE"
        di as result    "  Folders and pipeline scripts successfully generated."
        di as result    "  Pipeline pausing until data is submitted to server."
        di as result    "=======================================================" _n
        _hfc_pause
        global mdf_halt 1
        exit
    }
end
