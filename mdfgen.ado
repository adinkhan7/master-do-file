*! mdfgen.ado  —  code generator for the Master DO File survey pipeline
*! version 10.1.0   adinkhan7   https://github.com/adinkhan7/master-do-file
*!
*!  Master_DO_File.do used to carry ~2,650 lines of Mata that wrote the
*!  project's pipeline DO files.  That layer now lives here, so it can be
*!  versioned and installed with `net install` instead of being duplicated
*!  into every copy of Master on every machine.
*!
*!  Inputs arrive as globals rather than options on purpose: project paths
*!  routinely contain spaces and parentheses (e.g. "Demo Project (Multi
*!  Dataset)"), which Stata's -syntax- option parser cannot carry intact.
*!
*!  Usage
*!      global mdfgen_pname   "<project name>"
*!      global mdfgen_dodir   "<.../04_DO Files>"
*!      ... (see _mdfgen_require below for the full list)
*!      mdfgen directory      // writes 00_Directory / 00a_Bootstrap / 00b_Overrides
*!      mdfgen modules        // writes pipeline modules, HFC DO, Processing DO

program define mdfgen, rclass
    version 16
    gettoken _sub _rest : 0

    if `"`_sub'"' == "" {
        di as error "mdfgen: subcommand required — directory | modules | version"
        exit 198
    }

    if `"`_sub'"' == "version" {
        di as result "mdfgen 10.1.0"
        return local version "10.1.0"
        exit 0
    }

    if !inlist(`"`_sub'"', "directory", "modules") {
        di as error `"mdfgen: unknown subcommand "`_sub'""'
        di as error "        expected: directory | modules | version"
        exit 198
    }

    _mdfgen_load

    if `"`_sub'"' == "directory" _mdfgen_directory
    else                         _mdfgen_modules

    return local version "10.1.0"
end


*  ── Load the Mata layer, and reload it after any clear all ─────────────────
*  clear all wipes Mata but NOT globals, so the guard has to probe Mata
*  itself rather than trust a "loaded" flag.
program define _mdfgen_load
    version 16
    cap mata: mdfgen_probe()
    if !_rc exit 0

    cap findfile _mdfgen_defs.ado
    if _rc {
        di as error "mdfgen: _mdfgen_defs.ado is not on the adopath."
        di as error "        The package is installed incompletely. Re-run:"
        di as error `"        net install mdfgen, from("https://raw.githubusercontent.com/adinkhan7/master-do-file/main") replace"'
        exit 601
    }
    qui do `"`r(fn)'"'

    cap mata: mdfgen_probe()
    if _rc {
        di as error "mdfgen: the Mata layer failed to compile."
        exit 3499
    }
end


*  ── Fail loudly on a missing input rather than writing a broken file ───────
program define _mdfgen_require
    version 16
    args _name
    local _val `"${`_name'}"'
    if `"`_val'"' == "" {
        di as error "mdfgen: required global `_name' is empty."
        di as error "        Master must set every mdfgen_* global before calling mdfgen."
        exit 198
    }
end


program define _mdfgen_directory
    version 16
    foreach g in mdfgen_pname mdfgen_dodir mdfgen_hfcdir mdfgen_tver {
        _mdfgen_require `g'
    }

    local _pname   `"$mdfgen_pname"'
    local _ssize   `"$mdfgen_ssize"'
    local _meta    `"$mdfgen_meta"'
    local _tail    `"$mdfgen_tail"'
    local _tstart  `"$mdfgen_tstart"'
    local _tend    `"$mdfgen_tend"'
    local _nds     `"$mdfgen_nds"'
    local _dodir   `"$mdfgen_dodir"'
    local _hfcdir  `"$mdfgen_hfcdir"'
    local _tver    `"$mdfgen_tver"'
    local _procdir `"$mdfgen_procdir"'

    mata: mdfgen_directory_main()
end


program define _mdfgen_modules
    version 16
    foreach g in mdfgen_pname mdfgen_dodir mdfgen_hfcdir mdfgen_tver ///
                 mdfgen_procdir mdfgen_procfile {
        _mdfgen_require `g'
    }

    local _pname    `"$mdfgen_pname"'
    local _ssize    `"$mdfgen_ssize"'
    local _meta     `"$mdfgen_meta"'
    local _tail     `"$mdfgen_tail"'
    local _tstart   `"$mdfgen_tstart"'
    local _tend     `"$mdfgen_tend"'
    local _nds      `"$mdfgen_nds"'
    local _dodir    `"$mdfgen_dodir"'
    local _hfcdir   `"$mdfgen_hfcdir"'
    local _tver     `"$mdfgen_tver"'
    local _procdir  `"$mdfgen_procdir"'
    local _procfile `"$mdfgen_procfile"'

    mata: mdfgen_modules_main()
end
