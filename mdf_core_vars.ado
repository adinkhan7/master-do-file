*! mdf_core_vars.ado — derive the core variables the HFC modules depend on
*! version 10.1.1   github.com/adinkhan7/master-do-file
*!
*!  Replaces the generated 04_DO Files/05_Core_Variables.do (ADR-055). That file
*!  was 91 lines, 77 of which were the standalone header every generated module
*!  carries; the logic below is the other 14, unchanged.
*!
*!  Part of the Thanos Protocol (ADR-044): a survey that does not ship
*!  `fielddate` or `total_duration` gets them derived rather than failing, so a
*!  module degrades instead of erroring.

program define mdf_core_vars
    version 16

    cap confirm variable fielddate
    if _rc {
        cap confirm variable starttime
        if !_rc {
            cap gen double fielddate = dofc(starttime)
            cap format fielddate %td
        }
    }

    cap confirm variable total_duration
    if _rc {
        cap confirm variable duration
        if !_rc {
            cap destring duration, replace force
            cap gen total_duration = duration / 60
        }
    }
end
