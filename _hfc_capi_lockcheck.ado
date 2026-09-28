*! _hfc_capi_lockcheck.ado — Master DO File framework helper
*! version 11.0.0   github.com/adinkhan7/master-do-file
*!
*!  Count Excel lock files (~$*.xlsx) left by an open workbook.
*!
*!  This lives in its own file for two reasons. A `program define` cannot
*!  nest inside another one — the inner `end` would terminate the outer.
*!  And as an ado on the adopath Stata reloads it on demand, so the
*!  `clear all` that every SurveyCTO import DO issues no longer drops it.
*!  Master used to carry four identical copies of this program for exactly
*!  that reason; it now carries none.

program define _hfc_capi_lockcheck
    global hfc_capi_locks ""
    global hfc_capi_nlock 0
    mata: _hfc_scan_locks(st_global("capi_dir"))
    if $hfc_capi_nlock > 0 {
        di as txt _n "  NOTE: $hfc_capi_nlock SurveyCTO form(s) currently open in Excel."
        di as txt    "        Labeling is unaffected — the lock file is ignored, not used as"
        di as txt    "        the form. Listed so an odd labeling result has a breadcrumb:"
        foreach _lk in $hfc_capi_locks {
            di as txt "          `_lk'"
        }
    }
end
