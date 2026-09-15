*! mdf_generate.ado — Master DO File pipeline stage 9 of 19
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  00_Directory / 00a_Bootstrap / 00b_Overrides, output paths, previous keys

program define mdf_generate
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 10  GENERATE THE DIRECTORY, BOOTSTRAP AND OVERRIDES FILES
    *==============================================================================*

    di as result _n "--- Checking pipeline DO files ---"
    *  ── Write 00_Directory.do, 00a_Bootstrap.do, 00b_Local_Overrides.do ─────
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
    local _nds     "1"   // placeholder; actual_n_dta is auto-detected inside 00_Directory.do
    _mdf_load
    mata: mdf_directory_main()

    *  ── Exit cleanly on Run 1 ──────────────────────────────────────────────────
    if $hfcsys_n_raw == 0 & "$hfc_postfield_active" != "1" {
        global mdf_halt 1
        exit
    }

    *==============================================================================*
    *  SECTION 11  OUTPUT FILE PATHS
    *==============================================================================*

    if "`c(os)'" == "Windows" {
        local bs = char(92)
        global hfc_report    = subinstr("$hfc_run_dir/HFC_${project_name}_$today.xlsx",         "/", "`bs'", .)
    }
    else {
        global hfc_report    "$hfc_run_dir/HFC_${project_name}_$today.xlsx"
    }

    global keys_today  "$hfc_keys_master_dir/${project_name}_KEYS_$today.dta"

    *  ── Map dynamic team aliases ───────────────────────────────────────────────
    global excel_file "$hfc_report" // Base pointer
    foreach _alias in $hfc_excel_aliases {
        global `_alias' "$hfc_report"
    }

    *==============================================================================*
    *  SECTION 12  PREVIOUS KEYS  (same-day re-run safe)
    *==============================================================================*

    global LAST_RUN_DATE ""
    global has_pre_keys  0

    local _m_num = daily("`c(current_date)'", "DMY")
    local _m_fmt : display %tdCCYYNNDD `_m_num'
    local _current_run_date = strtrim("`_m_fmt'")

    tempname _lrf
    cap file open `_lrf' using "$hfc_keys_master_dir/${project_name}_hfc_last_run.txt", read text
    if !_rc {
        file read `_lrf' _line1
        file read `_lrf' _line2
        file close `_lrf'

        local _l1 = strtrim(subinstr("`_line1'", char(13), "", .))
        local _l2 = strtrim(subinstr("`_line2'", char(13), "", .))

        if "`_l1'" != "" & (length("`_l1'") != 8 | real("`_l1'") == .) {
            di as error "WARNING: breadcrumb Line 1 is not a valid YYYYMMDD date: `_l1'"
            local _l1 ""
        }

        if "`_l2'" != "" & (length("`_l2'") != 8 | real("`_l2'") == .) {
            di as error "WARNING: breadcrumb Line 2 is not a valid YYYYMMDD date: `_l2'"
            local _l2 ""
        }

        if "`_l2'" == "" local _l2 "`_l1'"

        if "`_l2'" == "`_current_run_date'" {
            global LAST_RUN_DATE "`_l1'"
            di as result "Same-day re-run detected — historical pointer preserved."
        }
        else {
            global LAST_RUN_DATE "`_l2'"
        }

        if "$LAST_RUN_DATE" != "" {
            global has_pre_keys 1
            di as result "Last run date → $LAST_RUN_DATE"
        }
    }

    if $has_pre_keys == 0 {
        di as result "NOTE: No historical run file found — treating this as the baseline run."
    }
end
