*! _hfc_abort.ado — Master DO File framework helper
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  A real error: close the log and exit 198 so the run stops.
*!
*!  This lives in its own file for two reasons. A `program define` cannot
*!  nest inside another one — the inner `end` would terminate the outer.
*!  And as an ado on the adopath Stata reloads it on demand, so the
*!  `clear all` that every SurveyCTO import DO issues no longer drops it.
*!  Master used to carry four identical copies of this program for exactly
*!  that reason; it now carries none.

program define _hfc_abort
    args msg
    if `"`msg'"' != "" di as error `"`msg'"'
    cap log close hfc_master
    exit 198
end
