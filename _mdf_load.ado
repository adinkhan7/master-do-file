*! _mdf_load.ado — bring the Mata layer into memory
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  The guard probes MATA, not a global flag, and that distinction is
*!  load-bearing. `clear all` drops programs and wipes Mata but LEAVES GLOBALS
*!  STANDING (verified, Stata 17). Every SurveyCTO import DO issues `clear all`,
*!  and the framework generates files on both sides of that boundary — so a
*!  "loaded" global would still be set at exactly the moment the Mata it
*!  vouched for had gone.

program define _mdf_load
    version 16
    cap mata: mdf_probe()
    if !_rc exit 0

    cap findfile _mdf_defs.ado
    if _rc {
        di as error "mdf: _mdf_defs.ado is not on the adopath — the package is"
        di as error "     installed incompletely. Re-run:"
        di as error `"     net install mdf, from("$mdf_source") replace"'
        exit 601
    }
    qui do `"`r(fn)'"'

    cap mata: mdf_probe()
    if _rc {
        di as error "mdf: the Mata layer failed to compile."
        exit 3499
    }
end
