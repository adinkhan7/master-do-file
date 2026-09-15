*! mdf_clean.ado — Master DO File pipeline stage 15 of 19
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  run cleaning

program define mdf_clean
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 22  CLEANING
    *==============================================================================*

    if "$run_processing" == "1" {
        cd "$ROOT"
        cap noi do "$processing_dir/$processing_file"
        local _st_rc = _rc
        if `_st_rc' {
            di as error _n "========================================================================="
            di as error    "  RUN FAILED — Processing"
            di as error    "========================================================================="
            di as text     "  Stata error code : r(`_st_rc')"
            di as text     "  Stata says       :"
            cap noi error `_st_rc'
            di as text     "  Failed in        : 06_Processing Files/$processing_file"
            di as text     "  Full log         : $log_file"
            di as error    "  The run stopped here. Nothing after this stage ran."
            di as error    "========================================================================="
            cap log close hfc_master
            exit `_st_rc'
        }
    }
    else di as result _n "--- Processing skipped (run_processing = 0) ---"





    di as result _n "--- Resolving Pipeline Data Dependencies ---"

    forvalues _i = 1/$actual_n_dta {
        local _base "${auto_dsname_`_i'}"
        local _d_raw "$raw_data_dir/`_base'.dta"
        local _d_cur "$clean_dir/`_base'_CLEANED.dta"

        cap confirm file "`_d_cur'"
        if !_rc {
            global target_dta_`_i' "`_d_cur'"
            di as txt "  DS`_i': Using CURRENT cleaned dataset (07_Cleaned Dataset/)."
        }
        else {
            cap confirm file "${dta_cleaned_`_i'}"
            if !_rc {
                global target_dta_`_i' "${dta_cleaned_`_i'}"
                di as error "  DS`_i': 07_Cleaned Dataset/ has no current file. Fallback -> dated CLEANED snapshot."
            }
            else {
                cap confirm file "${dta_labeled_`_i'}"
                if !_rc {
                    global target_dta_`_i' "${dta_labeled_`_i'}"
                    di as error "  DS`_i': CLEANED missing. Fallback -> RAW snapshot."
                }
                else {
                    cap confirm file "`_d_raw'"
                    if !_rc {
                        global target_dta_`_i' "`_d_raw'"
                        di as error "  DS`_i': no run snapshot. Fallback -> archived RAW."
                    }
                    else if "$ghost_run" == "1" {
                        global target_dta_`_i' ""
                        di as txt "  DS`_i': no data yet (pre-fieldwork). Skipping."
                        continue
                    }
                    else {
                        _hfc_abort "  CRITICAL: No dataset found for DS`_i'. Halting pipeline."
                    }
                }
            }
        }
    }

    if $actual_n_dta == 1 {
        global target_dta "$target_dta_1"
    }
    else {
        global target_dta "$target_dta_1" // Ensure base pointer exists for multi-dataset too
    }

    *  ── Map dynamic dataset aliases (Master Memory) ────────────────────────────
    foreach _alias in $hfc_dta_aliases {
        global `_alias' "$target_dta"
        forvalues _i = 1/$actual_n_dta {
            global `_alias'_`_i' "${target_dta_`_i'}"
        }
    }

    if "$hfcsys_required_vars" != "" & "$run_hfc" == "1" {
        di as result _n "--- Checking HFC variable coverage ---"
        forvalues _i = 1/$actual_n_dta {
            local _missing ""
            cap use "${target_dta_`_i'}", clear
            if _rc {
                di as error "  DS`_i': target dataset could not be opened — coverage not checked."
                continue
            }
            foreach _v in $hfcsys_required_vars {
                cap confirm variable `_v'
                if _rc local _missing "`_missing' `_v'"
            }
            if "`_missing'" != "" {
                di as error "  DS`_i': HFC modules use variable(s) this dataset does not have:"
                di as error "         `_missing'"
                di as error "         Source: ${target_dta_`_i'}"
                di as error "         The checks that need them will report less than the full picture."
                di as error "         If cleaning dropped them, fix $processing_file. If this survey simply"
                di as error "         has no such variable, nothing is wrong — the note is informational."
            }
            else di as result "  DS`_i': all commonly-used variables present."
        }
    }
end
