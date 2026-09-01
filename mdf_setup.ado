*! mdf_setup.ado — Master DO File pipeline stage 1 of 18
*! version 10.1.0   github.com/adinkhan7/master-do-file
*!
*!  helper programs, ROOT resolution, framework identity

program define mdf_setup
    version 16
    global mdf_halt 0

    _mdf_load


    global hfc_version                "10.1.0"
    global hfc_layout_version         "v10"
    global hfcsys_clean_delta_pct_max 5
    global hfcsys_required_vars       "key enum fielddate duration"



    local _dirof ""
    global ROOT  ""

    local _current_execution `"`c(do_current)'"'
    if `"`c(filename)'"' != "" local _current_execution `"`c(filename)'"'

    if strpos(`"`_current_execution'"', "AppData/Local/Temp") > 0 | ///
       strpos(`"`_current_execution'"', "STD") > 0 {
        di as error "========================================================================="
        di as error "  SELECTION RUN DETECTED — PATH AUTOMATION PAUSED"
        di as error "========================================================================="
        di as txt   "  You highlighted code before running. This forces Stata to execute an"
        di as txt   "  anonymous temp file, blinding the pipeline from detecting its own folder."
        di as txt   " "
        di as result"  FOR 100% AUTOMATION:"
        di as txt   "  1. Click anywhere inside this DO file to clear your text highlight."
        di as txt   "  2. Click the 'Do' button on the toolbar (or press Ctrl+R / Ctrl+D directly)."
        di as txt   " "
        di as txt   "  This allows Stata to hand over the true file path seamlessly."
        di as error "========================================================================="
        exit 198
    }

    if `"`c(do_current)'"' != "" {
        _hfc_dirof `"`c(do_current)'"'
        if `"`_dirof'"' != "" global ROOT "`_dirof'"
    }

    if "${ROOT}" == "" & `"`c(filename)'"' != "" {
        _hfc_dirof `"`c(filename)'"'
        if `"`_dirof'"' != "" global ROOT "`_dirof'"
    }

    *  Master DEFINES the project root: it is the folder this file sits in, and
    *  never a folder above it. When Stata reports no filename — batch mode, a
    *  selection run, some IDE integrations — the working directory is the best
    *  remaining evidence. It is taken as-is and deliberately NOT walked upward.
    *  Walking up would find an enclosing project's .hfc_root and silently build
    *  into it, which is exactly what happened when a Master was moved one folder
    *  deeper: the new folders kept appearing at the old root.
    if "${ROOT}" == "" {
        global ROOT "`c(pwd)'"
        di as result "  ROOT taken from the working directory (Stata reported no filename)."
    }

    cd "${ROOT}"
    global ROOT = subinstr("`c(pwd)'", "\", "/", .)
    di as result "ROOT dynamically anchored → ${ROOT}"

    *  Nested-project check. If any ancestor carries a sentinel, this Master is
    *  sitting inside another project. That is legal, but it is almost never what
    *  was intended, and before this check it happened silently.
    local _parent_root ""
    local _up = subinstr("${ROOT}", "\", "/", .)
    local _cut = strrpos("`_up'", "/")
    if `_cut' > 1 {
        local _up = substr("`_up'", 1, `_cut' - 1)
        mata: st_local("_parent_root", _hfc_find_root(`"`_up'"', 12))
    }
    if `"`_parent_root'"' != "" {
        di as error _n "======================================================================="
        di as error    "  THIS MASTER IS INSIDE ANOTHER PROJECT"
        di as error    "======================================================================="
        di as txt      "  Enclosing project : `_parent_root'"
        di as txt      "  Building here     : ${ROOT}"
        di as txt      " "
        di as txt      "  A separate, nested project is being built at the second path. If you"
        di as txt      "  meant to relocate an existing project, move the whole project folder,"
        di as txt      "  not just this file."
        di as error    "======================================================================="
    }

    if "${hfc_active_project}" != "" & "${hfc_active_project}" != "$project_name" {
        di as error "WARNING: Globals already claimed by project '${_hfc_active_project}'."
        di as error "         Running multiple HFC projects in the same Stata session risks"
        di as error "         global macro bleed. Open a fresh Stata session per project."
    }

    global hfc_active_project "$project_name"





    global hfcsys_vcap = cond($verbose == 1, "cap noi", "cap")

    *  ── Write tempdir cache so standalone pipeline files can find ROOT ─────────
    tempname _fhpw
    cap file open  `_fhpw' using `"`c(tmpdir)'hfc_root_cache_${project_name}.txt"', write replace text
    cap file write `_fhpw' `"${ROOT}"'
    cap file close `_fhpw'

    *  ── Framework version check ────────────────────────────────────────────
    *  Master pins the framework it was written against. Once the right version
    *  is installed this costs nothing and touches no network, so field runs
    *  work offline.
    *
    *  The two failure modes are deliberately not treated alike. A framework
    *  that will not run at all is a hard stop — nothing can be generated and a
    *  half-built pipeline is worse than none. A version mismatch that cannot be
    *  repaired because GitHub is unreachable is a loud warning and the run
    *  continues: fieldwork happens on bad connections, and refusing to run over
    *  an unreachable update would strand an analyst who already has a working
    *  copy.
    local _v ""
    cap qui mdf version
    if !_rc local _v `"`r(version)'"'

    if `"`_v'"' != "$mdf_required" & "$mdf_autoinstall" == "1" {
        di as result "Updating the framework (`_v' -> $mdf_required)"
        cap noi net install mdf, from("$mdf_source") replace
        local _v ""
        cap qui mdf version
        if !_rc local _v `"`r(version)'"'
    }

    if `"`_v'"' == "" {
        di as error "ERROR: the Master DO File framework will not run."
        di as error `"       net install mdf, from("$mdf_source") replace"'
        exit 601
    }
    if `"`_v'"' != "$mdf_required" {
        di as error "WARNING: running framework `_v'; this Master expects $mdf_required."
        di as error "         Generated pipeline files may not match this version."
    }
    di as result "Framework     : mdf `_v'"
end
