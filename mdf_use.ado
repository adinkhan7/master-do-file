*! mdf_use.ado — put one dataset's raw data in memory, for working on a block
*! version 11.1.3   github.com/adinkhan7/master-do-file
*!
*!  The LOAD DATASET line of the Processing, Labeling and Translation DOs
*!  (ADR-065):
*!
*!      if "`_mdf_full'" == "" mdf_use 1, project("<project>")
*!
*!  A full run of the file skips the line (its INITIALISE sets _mdf_full). Run
*!  on its own after section 0 (select it, Ctrl+D), it loads dataset k's raw
*!  data exactly as the labeling step loads it: by running the labeling engine
*!  with labeling off, so the file is the one the pipeline would use, found the
*!  same way, in a project or in a Deliverables package. Nothing else changes:
*!  every global the engine touched is put back as it was.
*!
*!  It loads nothing, and says why, when section 0 has not been run, when the
*!  settings in Stata are another project's, or when a Deliverables package
*!  does not carry dataset k.
*!
*!  Lives in its own file: a program cannot be defined inside another ado. It
*!  is copied into every Deliverables package's _mdf/ado/.

program define mdf_use
    version 16
    syntax anything(name=k id="dataset number"), Project(string)
    cap confirm integer number `k'
    if _rc | real("`k'") < 1 {
        di as error "  mdf_use: the dataset number must be 1, 2, ... (found: `k')."
        exit 198
    }

    *  ── Whose settings are loaded? ───────────────────────────────────────────
    if `"$ROOT"' == "" | "$actual_n_dta" == "" | `"$mdf_rt_dir"' == "" {
        di as error "  Nothing loaded: this project's settings are not in Stata yet."
        di as error "  Run section 0. INITIALISE of this file first (select it, Ctrl+D),"
        di as error "  then this line again."
        exit 198
    }
    if `"$project_name"' != `"`project'"' {
        di as error `"  Nothing loaded: this line belongs to the project "`project'","'
        di as error `"  but the settings in Stata are those of "$project_name"."'
        di as error "  Run section 0. INITIALISE of this file first, then this line again."
        exit 198
    }
    if `k' > $actual_n_dta {
        di as error "  Nothing loaded: this project has $actual_n_dta dataset(s); there is no DS`k'."
        exit 198
    }
    if "$mdf_package" == "1" & "${mdf_ds_here_`k'}" != "1" {
        di as error "  Nothing loaded: this Deliverables package does not carry DS`k'"
        di as error "  (${auto_dsname_`k'}). Its own package folder does."
        exit 198
    }
    cap confirm file `"$mdf_rt_dir/mdf_labeling.do"'
    if _rc {
        di as error "  Nothing loaded: the labeling engine is missing:"
        di as error `"    $mdf_rt_dir/mdf_labeling.do"'
        di as error "  Run Master once to write it."
        exit 601
    }

    *  ── The labeling engine, with labeling off: it loads the raw data ────────
    *  Every global as it was, so nothing but the data in memory changes.
    *  (One-line Mata cannot hold a loop with an -if- body: measured, r(3000).
    *  Stata's own S_* globals are left out up front instead.)
    mata: _mdf_use_G = st_dir("global", "macro", "*")
    mata: _mdf_use_G = select(_mdf_use_G, substr(_mdf_use_G, 1, 2) :!= "S_")
    mata: _mdf_use_V = J(rows(_mdf_use_G), 1, "")
    mata: for (_mdf_use_i = 1; _mdf_use_i <= rows(_mdf_use_G); _mdf_use_i++) _mdf_use_V[_mdf_use_i] = st_global(_mdf_use_G[_mdf_use_i])

    global run_labeling 0
    global run_label    0
    cap qui do `"$mdf_rt_dir/mdf_labeling.do"' `k'
    local _rc = _rc
    local _ok "$hfc_label_ok"
    local _nm "${auto_dsname_`k'}"

    *  Every non-S_ global cleared, then each one that existed before set back.
    mata: _mdf_use_N = st_dir("global", "macro", "*")
    mata: _mdf_use_N = select(_mdf_use_N, substr(_mdf_use_N, 1, 2) :!= "S_")
    mata: for (_mdf_use_i = 1; _mdf_use_i <= rows(_mdf_use_N); _mdf_use_i++) st_global(_mdf_use_N[_mdf_use_i], "")
    mata: for (_mdf_use_i = 1; _mdf_use_i <= rows(_mdf_use_G); _mdf_use_i++) st_global(_mdf_use_G[_mdf_use_i], _mdf_use_V[_mdf_use_i])
    cap mata: mata drop _mdf_use_G _mdf_use_V _mdf_use_N _mdf_use_i

    if `_rc' {
        di as error "  Nothing loaded: the labeling engine stopped with r(`_rc') while finding"
        di as error "  DS`k''s raw data. Run the file in full to see the message."
        exit `_rc'
    }
    if "`_ok'" != "1" {
        di as error "  Nothing loaded: no raw dataset was found for DS`k' (`_nm')."
        exit 601
    }
    di as result "  DS`k' (`_nm'): raw data in memory, " _N " observations, " c(k) " variables."
end
