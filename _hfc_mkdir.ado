*! _hfc_mkdir.ado — Master DO File framework helper
*! version 11.0.0   github.com/adinkhan7/master-do-file
*!
*!  Create a directory if it is not already there, and say so if it cannot.
*!
*!  This lives in its own file for two reasons. A `program define` cannot
*!  nest inside another one — the inner `end` would terminate the outer.
*!  And as an ado on the adopath Stata reloads it on demand, so the
*!  `clear all` that every SurveyCTO import DO issues no longer drops it.
*!  Master used to carry four identical copies of this program for exactly
*!  that reason; it now carries none.

program define _hfc_mkdir
    args _path
    cap mkdir "`_path'"
    mata: st_local("_ok", strofreal(direxists("`_path'")))
    if !`_ok' {
        di as error `"ERROR: Could not create directory "`_path'". Check permissions."'
        cap log close hfc_master
        exit 198
    }
end
