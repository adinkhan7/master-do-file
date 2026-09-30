*! _hfc_hide.ado — Master DO File framework helper
*! version 11.1.0   github.com/adinkhan7/master-do-file
*!
*!  Mark framework state hidden on Windows; a no-op elsewhere.
*!
*!  This lives in its own file for two reasons. A `program define` cannot
*!  nest inside another one — the inner `end` would terminate the outer.
*!  And as an ado on the adopath Stata reloads it on demand, so the
*!  `clear all` that every SurveyCTO import DO issues no longer drops it.
*!  Master used to carry four identical copies of this program for exactly
*!  that reason; it now carries none.

program define _hfc_hide
    args _path _isdir
    if c(os) != "Windows" exit 0
    local _w = subinstr(`"`_path'"', "/", "\", .)
    cap python: import ctypes; from sfi import Macro as M; _p=M.getLocal("_w"); _a=ctypes.windll.kernel32.GetFileAttributesW(_p); ctypes.windll.kernel32.SetFileAttributesW(_p, (_a|2) if _a!=-1 else 2)
    if _rc {
        if "`_isdir'" == "1" cap qui shell attrib +h "`_w'" /d
        else                 cap qui shell attrib +h "`_w'"
    }
end
