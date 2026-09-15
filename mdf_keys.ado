*! mdf_keys.ado — Master DO File pipeline stage 18 of 19
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  archive keys and print the run summary

program define mdf_keys
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 25  KEY ARCHIVE — PER DATASET
    *==============================================================================*

    di as result _n "--- Archiving unique keys for $actual_n_dta dataset(s) ---"

    preserve

        forvalues _i = 1/$actual_n_dta {

            cap use "${target_dta_`_i'}", clear
            if _rc {
                di as error "  DS`_i': cleaned data not found — skipping key archive."
                continue
            }

            local _fpath = subinstr("${dta_cleaned_`_i'}", "\", "/", .)
            local _fname = ustrregexra("`_fpath'", "^.*/", "")

            local _clean_pos = strpos("`_fname'", "_CLEANED")
            if `_clean_pos' > 0 {
                local _dname = substr("`_fname'", 1, `_clean_pos' - 1)
            }
            else {
                local _dname = subinstr("`_fname'", ".dta", "", 1)
            }

            if "${ds`_i'_name}" != "" local _dname "${ds`_i'_name}"

            keep key

            local _this_key_today "$hfc_keys_master_dir/`_dname'_KEYS_$today.dta"
            save "`_this_key_today'", replace
            di as result "  DS`_i' keys archived → `_dname'_KEYS_$today.dta"

        if $has_pre_keys == 1 {
                di as txt "    └── pre_keys  : `_dname'_KEYS_${LAST_RUN_DATE}.dta"
            }
            else {
                di as txt "    └── pre_keys  : [none — baseline run]"
            }
            di as txt "    └── next_keys : `_dname'_KEYS_${today}.dta"
        }

        if $merge_required == 1 {
            local _sfx = subinstr("$merge_datasets", " ", "_", .)
            local _merged_name "${project_name}_`_sfx'_MERGED_$hfc_folder_date"
            local _merged_file "$hfc_run_dir/`_merged_name'.dta"
            cap confirm file "`_merged_file'"
            if !_rc {
                use "`_merged_file'", clear
                keep key
                local _this_key_today "$hfc_keys_master_dir/`_merged_name'_KEYS_$today.dta"
                save "`_this_key_today'", replace
                di as result "  Merged keys archived → `_merged_name'_KEYS_$today.dta"
                if $has_pre_keys == 1 {
                    di as txt "    └── pre_keys  : `_merged_name'_KEYS_${LAST_RUN_DATE}.dta"
                }
                else {
                    di as txt "    └── pre_keys  : [none — baseline run]"
                }
                di as txt "    └── next_keys : `_merged_name'_KEYS_${today}.dta"
            }
        }

        tempname _lrfw
        cap file open `_lrfw' using "$hfc_keys_master_dir/${project_name}_hfc_last_run.txt", write replace text
        if !_rc {
            file write `_lrfw' "$LAST_RUN_DATE" _n
            file write `_lrfw' "$today"
            file close `_lrfw'
            di as result _n "Run breadcrumb written (YYYYMMDD format)."
            di as txt    "  ├── Line 1 (historical pointer) : $LAST_RUN_DATE"
            di as txt    "  └── Line 2 (current run date)   : $today"
        }

    restore

    *==============================================================================*
    *  LOAD THE FINAL CLEANED DATASET INTO MEMORY
    *==============================================================================*

    local _final ""
    local _final_label ""

    if "$merge_required" == "1" {
        local _sfx = subinstr("$merge_datasets", " ", "_", .)
        local _mname "${project_name}_`_sfx'_MERGED"
        cap confirm file "$clean_dir/`_mname'.dta"
        if !_rc {
            local _final "$clean_dir/`_mname'.dta"
            local _final_label "merged dataset"
        }
        else {
            cap confirm file "$hfc_run_dir/`_mname'_$today.dta"
            if !_rc {
                local _final "$hfc_run_dir/`_mname'_$today.dta"
                local _final_label "merged dataset (run folder)"
            }
        }
    }

    if "`_final'" == "" {
        local _nm1 "${auto_dsname_1}"
        if "`_nm1'" != "" {
            cap confirm file "$clean_dir/`_nm1'_CLEANED.dta"
            if !_rc {
                local _final "$clean_dir/`_nm1'_CLEANED.dta"
                local _final_label "cleaned dataset (DS1)"
            }
        }
    }

    if "`_final'" == "" {
        cap confirm file "$target_dta"
        if !_rc {
            local _final "$target_dta"
            local _final_label "resolved target dataset"
        }
    }

    if "`_final'" != "" {
        cap use "`_final'", clear
        if !_rc {
            qui count
            di as result _n "--- Final dataset loaded into memory ---"
            di as txt      "  `_final_label': `_final'"
            di as txt      "  Observations: " r(N)
        }
        else {
            di as error _n "  NOTE: could not load `_final' into memory. Nothing else failed."
        }
    }
    else {
        di as txt _n "  No cleaned dataset to load into memory yet (nothing produced this run)."
    }

    di as result _n "════════════════════════════════════════════════════════════"
    di as result    "  HFC COMPLETE — $project_name — $today"
    di as result    "  ──────────────────────────────────────────────────────────"
    di as result    "  HFC Report   → $hfc_report"
    di as result    "  Datasets     → $hfc_run_dir"
    di as result    "  Keys         → $keys_today"
    di as result    "  Log          → $log_file"
    di as result    "  DO Files     → $hfc_dofiles_dir"
    di as result    "  In memory    → `_final_label'"
    di as result    "════════════════════════════════════════════════════════════" _n

    log close hfc_master
end
