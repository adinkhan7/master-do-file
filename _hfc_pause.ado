*! _hfc_pause.ado — Master DO File framework helper
*! version 11.0.0   github.com/adinkhan7/master-do-file
*!
*!  A workflow checkpoint, not a failure: exit 0. Never conflate the two.
*!
*!  This lives in its own file for two reasons. A `program define` cannot
*!  nest inside another one — the inner `end` would terminate the outer.
*!  And as an ado on the adopath Stata reloads it on demand, so the
*!  `clear all` that every SurveyCTO import DO issues no longer drops it.
*!  Master used to carry four identical copies of this program for exactly
*!  that reason; it now carries none.

program define _hfc_pause
    args msg
    if `"`msg'"' != "" di as result `"`msg'"'
    cap log close hfc_master
    exit 0
end
