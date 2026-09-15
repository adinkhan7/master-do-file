*! mdf_audio.ado — Master DO File pipeline stage 17 of 19
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  audio audit

program define mdf_audio
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 24  AUDIO AUDIT

    *==============================================================================*

    if "$run_audio" == "1" {
        di as result _n "--- Audio Audit ---"
        cd "$ROOT"
        cap noi do "$dofiles_dir/03_Audio.do"
        local _st_rc = _rc
        if `_st_rc' {
            di as error _n "========================================================================="
            di as error    "  RUN FAILED — Audio audit"
            di as error    "========================================================================="
            di as text     "  Stata error code : r(`_st_rc')"
            di as text     "  Stata says       :"
            cap noi error `_st_rc'
            di as text     "  Failed in        : 04_DO Files/03_Audio.do"
            di as text     "  Full log         : $log_file"
            di as error    "  The run stopped here. Nothing after this stage ran."
            di as error    "========================================================================="
            cap log close hfc_master
            exit `_st_rc'
        }
        di as result "Audio audit complete."
    }
    else di as result _n "--- Audio skipped (run_audio = 0) ---"

    *==============================================================================*
    *  REDEFINE HELPERS

    *==============================================================================*
end
