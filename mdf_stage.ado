*! mdf_stage.ado — Master DO File pipeline stage 13 of 19
*! version 11.0.0   github.com/adinkhan7/master-do-file
*!
*!  archive raw data and stage the working copy

program define mdf_stage
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 17  ARCHIVE RAW DATA TO THE RUN FOLDER
    *==============================================================================*

    if 1 {
        if $ghost_run == 1 {
            di as result _n "--- Archiving skipped (Ghost Run: no DTAs to archive yet) ---"
        }
        else {
            di as result _n "--- Archiving dataset(s) to HFC folder ---"

            local _all_raw : dir "$raw_data_dir" files "*.dta", respectcase
            local _n_archived 0

            foreach _f of local _all_raw {
                local _base = subinstr("`_f'", ".dta", "", 1)
                local _dest "$hfc_raw_snapshot_dir/`_base'_$today.dta"
                $hfcsys_vcap copy "$raw_data_dir/`_f'" "`_dest'", replace
                if _rc {
                    di as error "  WARNING: Could not copy `_f' — check file permissions."
                }
                else {
                    local _n_archived = `_n_archived' + 1
                    di as result "  Archived: `_f' → `_base'_$today.dta"
                }
            }

            if `_n_archived' == 0 {
                di as error "ERROR: No datasets could be archived. Check file permissions."
                _hfc_abort
            }
            di as result "`_n_archived' dataset(s) archived."
        }
    }

    *==============================================================================*
    *  SECTION 18  STAGE THE CURRENT WORKING DATA  →  processing_data_dir
    *==============================================================================*

    di as result _n "--- Staging current working data → $hfcsys_rel_processing_data_dir ---"

    local _staged 0
    foreach _pat in "*.do" "*.csv" "*.dta" {
        local _stage_list : dir "$raw_data_dir" files "`_pat'"
        foreach _sf of local _stage_list {
            cap copy "$raw_data_dir/`_sf'" "$processing_data_dir/`_sf'", replace
            if !_rc {
                local _staged = `_staged' + 1
            }
            else {
                di as error "  WARNING: could not stage `_sf' — left in $hfcsys_rel_data_dir only."
            }
        }
    }

    if `_staged' > 0 {
        di as result "  `_staged' file(s) staged for processing."
    }
    else {
        di as txt    "  Nothing to stage yet — $hfcsys_rel_data_dir/ has no import DO, CSV or DTA."
    }
end
