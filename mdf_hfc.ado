*! mdf_hfc.ado — Master DO File pipeline stage 16 of 19
*! version 11.1.0   github.com/adinkhan7/master-do-file
*!
*!  run the high-frequency checks

program define mdf_hfc
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 23  HIGH FREQUENCY CHECKS
    *==============================================================================*

    if "$run_hfc" == "1" {
        di as result _n "--- HFC Checks ---"
        cd "$ROOT"
        cap noi do "$hfc_dir/02_${project_name}_HFC.do"
        local _st_rc = _rc
        if `_st_rc' {
            di as error _n "========================================================================="
            di as error    "  RUN FAILED — HFC checks"
            di as error    "========================================================================="
            di as text     "  Stata error code : r(`_st_rc')"
            di as text     "  Stata says       :"
            cap noi error `_st_rc'
            di as text     "  Failed in        : $hfcsys_rel_hfc_dir/02_${project_name}_HFC.do"
            di as text     "  Full log         : $log_file"
            di as error    "  The run stopped here. Nothing after this stage ran."
            di as error    "========================================================================="
            cap log close hfc_master
            exit `_st_rc'
        }
        di as result "HFC complete."
    }
    else di as result _n "--- HFC skipped (run_hfc = 0) ---"
end
