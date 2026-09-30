*! mdf_modules.ado — Master DO File pipeline stage 11 of 19
*! version 11.1.0   github.com/adinkhan7/master-do-file
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
    *  The runtime is framework code, not the analyst's (ADR-033, ADR-061).
    _hfc_hide "$mdf_rt_dir" 1

    *  ── Retire framework files nothing references any more ─────────────────
    *  10.1.1 turned 00a_Bootstrap.do, 04_Finalise.do and 05_Core_Variables.do
    *  into package commands (mdf_bootstrap, mdf_finalise, mdf_core_vars).
    *
    *  They are NOT removed on sight. A project whose generated modules are
    *  still on an older template goes on calling them by name, and Tier 2
    *  protection means those modules are not rewritten — they get a .new beside
    *  them for the analyst to merge. Deleting the file first would break the
    *  project until that merge happened, which is precisely the silent breakage
    *  this framework exists to avoid.
    *
    *  So each file is removed only once nothing in the project still refers to
    *  it. The check runs every time, so a project converges to five files in
    *  04_DO Files/ as soon as its modules are current, and never breaks getting
    *  there. Tier 2 files are renamed, never deleted: an analyst was allowed to
    *  edit them.
    *  Order matters: 04_Finalise.do and 05_Core_Variables.do both carry the
    *  old standalone header that calls 00a_Bootstrap.do, so they have to be
    *  retired first or they keep it alive for an extra run.
    foreach _ret in 04_Finalise 05_Core_Variables 00a_Bootstrap {
        cap confirm file "$dofiles_dir/`_ret'.do"
        if _rc continue

        local _refs 0
        foreach _rd in "$dofiles_dir" "$hfc_dir" "$processing_dir" {
            local _rlist : dir "`_rd'" files "*.do", respectcase
            foreach _rf of local _rlist {
                if "`_rf'" == "`_ret'.do" continue
                tempname _rfh
                cap file open `_rfh' using "`_rd'/`_rf'", read text
                if _rc continue
                file read `_rfh' _rline
                while r(eof) == 0 {
                    if strpos(`"`_rline'"', "`_ret'.do") > 0 {
                        local _refs = `_refs' + 1
                        continue, break
                    }
                    file read `_rfh' _rline
                }
                cap file close `_rfh'
            }
        }

        if `_refs' > 0 {
            di as txt "  `_ret'.do kept — `_refs' file(s) still call it by name."
            continue
        }

        if "`_ret'" == "00a_Bootstrap" {
            cap erase "$dofiles_dir/00a_Bootstrap.do"
            if !_rc di as result "  Retired 00a_Bootstrap.do — the mdf_bootstrap command replaces it."
        }
        else {
            cap copy "$dofiles_dir/`_ret'.do" "$dofiles_dir/`_ret'.do.superseded", replace
            if !_rc {
                cap erase "$dofiles_dir/`_ret'.do"
                di as result _n "  Retired `_ret'.do — nothing calls it any more."
                if "`_ret'" == "04_Finalise"       di as txt "    The pipeline now calls: mdf_finalise"
                if "`_ret'" == "05_Core_Variables" di as txt "    The pipeline now calls: mdf_core_vars"
                di as txt "    Your copy was kept as `_ret'.do.superseded. If you had edited"
                di as txt "    it, re-apply those changes or keep calling your copy explicitly."
            }
        }
    }

end
