*! _hfc_dirof.ado — Master DO File framework helper
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  Return the directory part of a path, via c_local, to the caller.
*!
*!  This lives in its own file for two reasons. A `program define` cannot
*!  nest inside another one — the inner `end` would terminate the outer.
*!  And as an ado on the adopath Stata reloads it on demand, so the
*!  `clear all` that every SurveyCTO import DO issues no longer drops it.
*!  Master used to carry four identical copies of this program for exactly
*!  that reason; it now carries none.

program define _hfc_dirof
    local _p = subinstr(`"`0'"', "\", "/", .)
    local _len = length(`"`_p'"')
    forvalues _j = `_len'(-1)1 {
        if substr(`"`_p'"', `_j', 1) == "/" {
            c_local _dirof = substr(`"`_p'"', 1, `_j' - 1)
            continue, break
        }
    }
end
