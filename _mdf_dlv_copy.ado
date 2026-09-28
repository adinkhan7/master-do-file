*! _mdf_dlv_copy.ado — copy one file into the Deliverables package, or say why not
*! version 11.0.0   github.com/adinkhan7/master-do-file
*!
*!  Every file the package carries goes through here, so none can go missing
*!  quietly. A failed copy is counted in $hfcsys_dlv_fail and named on screen;
*!  mdf_deliverables refuses to call a package with failures "ready" (ADR-059).
*!
*!  The usual cause is Windows' 260-character path limit, which Stata is held
*!  to: a package nests a project's folders two levels deeper, and a long
*!  dataset name appears twice on the path to its translation files. The
*!  message says so when the destination path is that long.
*!
*!  Lives in its own file: a program cannot be defined inside another ado.

program define _mdf_dlv_copy, rclass
    version 16
    args _src _dst

    cap copy `"`_src'"' `"`_dst'"', replace
    local _rc = _rc
    if !`_rc' {
        cap confirm file `"`_dst'"'
        local _rc = _rc
    }
    if `_rc' {
        if "$hfcsys_dlv_fail" == "" global hfcsys_dlv_fail 0
        global hfcsys_dlv_fail = $hfcsys_dlv_fail + 1
        local _leaf = ustrregexra(`"`_src'"', "^.*[/\\]", "")
        local _n = strlen(`"`_dst'"')
        di as error "    NOT COPIED: `_leaf'"
        if `_n' >= 250 di as error "      the path it needs is `_n' characters long; Windows stops at 260."
        else           di as error "      Stata error r(`_rc') copying it."
        return scalar ok = 0
        exit 0
    }
    return scalar ok = 1
end
