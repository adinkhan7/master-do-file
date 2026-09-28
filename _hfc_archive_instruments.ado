*! _hfc_archive_instruments.ado — Master DO File framework helper
*! version 11.0.0   github.com/adinkhan7/master-do-file
*!
*!  Keep the newest instrument, archive superseded versions.
*!
*!  This lives in its own file for two reasons. A `program define` cannot
*!  nest inside another one — the inner `end` would terminate the outer.
*!  And as an ado on the adopath Stata reloads it on demand, so the
*!  `clear all` that every SurveyCTO import DO issues no longer drops it.
*!  Master used to carry four identical copies of this program for exactly
*!  that reason; it now carries none.

program define _hfc_archive_instruments
    args _dir _label
    cap confirm file "`_dir'"
    mata: st_local("_de", strofreal(direxists(`"`_dir'"')))
    if !`_de' exit 0

    local _files_raw : dir "`_dir'" files "*.xlsx"
    *  Drop Excel lock files (~$...). '~' sorts after digits and letters, so a
    *  lock file left by an open workbook would otherwise be treated as the
    *  current form and every genuine instrument archived away behind it.
    local _files ""
    foreach _xf of local _files_raw {
        if substr(`"`_xf'"', 1, 1) != "~" local _files `"`_files' `_xf'"'
    }
    local _sorted : list sort _files
    local _n : word count `_sorted'
    if `_n' <= 1 exit 0

    local _keep : word `_n' of `_sorted'
    _hfc_mkdir "`_dir'/Archive"
    local _moved 0
    forvalues _i = 1/`=`_n'-1' {
        local _f : word `_i' of `_sorted'
        cap copy "`_dir'/`_f'" "`_dir'/Archive/`_f'", replace
        cap confirm file "`_dir'/Archive/`_f'"
        if !_rc {
            cap erase "`_dir'/`_f'"
            local _moved = `_moved' + 1
            di as txt "    archived: `_f'"
        }
        else di as error "    WARNING: could not archive `_f' — left in place."
    }
    if `_moved' > 0 {
        di as result "  `_label': `_moved' superseded file(s) moved to Archive/. Current: `_keep'"
    }
end
