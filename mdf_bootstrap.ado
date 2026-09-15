*! mdf_bootstrap.ado — load a project's globals from inside a generated pipeline file
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  Replaces the generated 04_DO Files/00a_Bootstrap.do (ADR-055).
*!
*!  A generated module resolves its own ROOT — that stays in the module, because
*!  it depends on `c(do_current)` of the file being run and cannot be delegated.
*!  Everything after that is identical for every project and every module, so it
*!  lives here: load 00_Directory.do if this session has not already.
*!
*!  The helper programs the old bootstrap defined (_hfc_abort, _hfc_pause,
*!  _hfc_mkdir, _hfc_hide) are ado files in this package now. Stata loads them
*!  from the adopath on demand, which is why they are not redefined here.

program define mdf_bootstrap
    version 16
    args _root

    if "$hfc_dofiles_dir" != "" exit 0

    if `"`_root'"' == "" local _root "$ROOT"
    if `"`_root'"' == "" {
        di as error "mdf_bootstrap: no project root was given and " _char(36) "ROOT is not set."
        di as error "               Run the project's Master DO file once, then retry."
        exit 198
    }

    cap confirm file `"`_root'/04_DO Files/00_Directory.do"'
    if _rc {
        di as error `"mdf_bootstrap: 00_Directory.do not found under `_root'."'
        di as error  "               Run the project's Master DO file once, then retry."
        exit 601
    }

    do `"`_root'/04_DO Files/00_Directory.do"'
end
