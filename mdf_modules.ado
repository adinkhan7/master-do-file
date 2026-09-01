*! mdf_modules.ado — Master DO File pipeline stage 11 of 18
*! version 10.1.0   github.com/adinkhan7/master-do-file
*!
*!  pipeline modules, the HFC DO and the Processing DO

program define mdf_modules
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 14  GENERATE THE PIPELINE MODULES AND THE PROCESSING FILE
    *==============================================================================*
    *  ── Carry an older Processing.do over to the project-named file ────────────
    local _proc_old "$processing_dir/Processing.do"
    local _proc_new "$processing_dir/$processing_file"
    cap confirm file "`_proc_old'"
    if !_rc {
        cap confirm file "`_proc_new'"
        if _rc {
            cap copy "`_proc_old'" "`_proc_new'"
            cap confirm file "`_proc_new'"
            if !_rc {
                cap erase "`_proc_old'"
                di as result "  Renamed Processing.do → $processing_file (your cleaning code moved with it)."
            }
            else di as error "  WARNING: could not rename Processing.do. Left it in place."
        }
        else di as error "  NOTE: both Processing.do and $processing_file exist. Using $processing_file; the old file was left untouched."
    }

    *==============================================================================*

    di as result _n "--- Checking pipeline DO files (01-03) ---"

    local _raw_dtas : dir "$raw_data_dir" files "*.dta", respectcase

    *  ── NEW: Ghost Run CSV Fallback ────────────────────────────────────────────
    if "$ghost_run" == "1" {
        local _raw_dtas : dir "$raw_data_dir" files "*.csv", respectcase
    }

    local _raw_dtas : list sort _raw_dtas
    local _dname_idx 1
    foreach _f of local _raw_dtas {
        local _base = subinstr("`_f'", ".dta", "", 1)
        local _base = subinstr("`_base'", ".csv", "", 1)

        *  ── Strip the SurveyCTO "_wide" tag ────────────────────────────────────────
        if strlen("`_base'") > 5 & lower(substr("`_base'", -5, 5)) == "_wide" {
            local _base = substr("`_base'", 1, strlen("`_base'") - 5)
        }

        global auto_dsname_`_dname_idx' "`_base'"
        local _dname_idx = `_dname_idx' + 1
    }
    *  ── Write the pipeline modules, the HFC DO and the Processing DO ─────────
    local _pname   "$project_name"
    local _ssize   "$sample_size"
    local _meta    "$meta_front"
    local _tail    "$tail"
    local _tstart  "$timer_start"
    local _tend    "$timer_end"
    local _dodir   "$dofiles_dir"
    local _hfcdir  "$hfc_dir"
    local _tver    "$hfc_version"
    local _procdir "$processing_dir"
    local _procfile "$processing_file"
    local _nds      "$actual_n_dta"   // force the generator loops to the exact DTA count
    _mdf_load
    mata: mdf_modules_main()
end
