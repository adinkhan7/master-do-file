*! _mdf_odk_names.ado — Master DO File framework helper
*! version 11.1.2   github.com/adinkhan7/master-do-file
*!
*!  odksplit names Stata local macros after each form field it labels:
*!  <field>_y, <field>_ch and <field>_l1. A local's name stops at 31
*!  characters, so a field whose name has 29 or more characters stops
*!  odksplit with "local macro name ... too long", r(198), and the whole
*!  dataset goes unlabeled. Stata itself accepts names up to 32.
*!
*!  This helper is the boundary between the two limits (ADR-063). Such a
*!  variable is known to odksplit by a short temporary name, _mdf001,
*!  _mdf002, ..., for the length of the one odksplit call and nowhere else:
*!
*!    _mdf_odk_names prepare, data(file) form(file) [declared(names) ds(#)]
*!        Before odksplit, on the two working copies odksplit is about to
*!        read. Renames each variable that needs it in the data copy AND its
*!        row in the form copy, so odksplit labels it under the short name.
*!        Needs it: a form field of 29+ characters that is in the data, or a
*!        variable the analyst lists in 01_Labeling.do (odksplit_rename).
*!        Leaves no data in memory. Returns r(map) = "orig1 _mdf001 ...".
*!
*!    _mdf_odk_names restore, map(string) [ds(#)]
*!        After odksplit, on the data it loaded. Every original name comes
*!        back with what odksplit gave the short one: variable label, value
*!        label (under the original's own name, as odksplit names it) and
*!        select_multiple indicators (<orig>_<choice>).
*!
*!  The real form and the archived data are never touched: both commands
*!  work on copies the labeling engine erases straight after.
*!  Anything that cannot be done cleanly stops the run: a temporary name
*!  already in use, a listed variable that does not exist, a name that does
*!  not come back. Silent-but-wrong names are the outcome this prevents.

program define _mdf_odk_names, rclass
    version 16
    gettoken _sub 0 : 0, parse(" ,")

    if "`_sub'" == "prepare" {
        syntax , Data(string) Form(string) [DEClared(string) DS(string)]
        return local map ""
        return scalar n = 0

        *  ── Which variables need a short name ──────────────────────────────
        *  odksplit's own limits, read from its code: <field>_l1 and
        *  <field>_ch must fit in 31 characters (otherwise r(198), the whole
        *  dataset unlabeled), and for a select field so must
        *  <field>_<choice>la (otherwise that choice's label text is lost
        *  without a word: odksplit captures that one).
        qui describe using `"`data'"', varlist
        local _vars `r(varlist)'
        local _decl : list uniq declared
        foreach _v of local _decl {
            local _hit : list _v in _vars
            if !`_hit' {
                di as error "  odksplit_rename (01_Labeling.do) lists `_v', but DS`ds' has no"
                di as error "  variable of that name. Correct or remove it there, then run again."
                _hfc_abort
            }
        }

        local _fields ""
        local _risky ""
        local _multi ""
        local _ncol ""
        tempfile _cmax
        clear
        cap import excel using `"`form'"', sheet("choices") firstrow clear allstring
        if !_rc {
            cap confirm string variable list_name
            local _lrc = _rc
            local _vcol ""
            cap confirm string variable name
            if !_rc local _vcol name
            else {
                cap confirm string variable value
                if !_rc local _vcol value
            }
            if !`_lrc' & "`_vcol'" != "" {
                qui gen _mdf_list = strtrim(list_name)
                qui gen _mdf_clen = ustrlen(regexr(strtrim(`_vcol'), "-", "_"))
                qui drop if _mdf_list == ""
                qui collapse (max) _mdf_clen, by(_mdf_list)
                qui save `"`_cmax'"'
            }
        }
        clear
        cap import excel using `"`form'"', sheet("survey") firstrow clear allstring
        if !_rc {
            *  odksplit reads the field names from -name-, or -value-.
            cap confirm string variable name
            if !_rc local _ncol name
            else {
                cap confirm string variable value
                if !_rc local _ncol value
            }
            cap confirm string variable type
            if _rc local _ncol ""
        }
        *  A form odksplit cannot read fails odksplit too, and the engine
        *  already reports that: nothing to rename for it here.
        if "`_ncol'" != "" {
            qui replace `_ncol' = strtrim(`_ncol')
            qui levelsof `_ncol', local(_fields) clean
            qui keep `_ncol' type
            qui gen _mdf_list = word(strtrim(type), 2) if regexm(type, "select_one") | regexm(type, "select_multiple")
            qui gen _mdf_clen = .
            cap confirm file `"`_cmax'"'
            if !_rc qui merge m:1 _mdf_list using `"`_cmax'"', keep(master match match_update) update nogenerate
            qui gen _mdf_need = ustrlen(`_ncol') + 3
            qui replace _mdf_need = ustrlen(`_ncol') + 3 + _mdf_clen if _mdf_list != "" & _mdf_clen < .
            qui levelsof `_ncol' if _mdf_need > 31 & `_ncol' != "", local(_risky) clean
            qui levelsof `_ncol' if regexm(type, "select_multiple") & `_ncol' != "", local(_multi) clean
        }
        clear
        local _cand : list _risky & _vars
        if "`_cand'`_decl'" == "" exit

        *  Dataset order, so the same data always get the same short names.
        local _from ""
        foreach _v of local _vars {
            local _a : list _v in _cand
            local _b : list _v in _decl
            if `_a' | `_b' local _from `_from' `_v'
        }
        local _n : word count `_from'
        if `_n' == 0 exit
        if `_n' > 999 {
            di as error "  odksplit names: `_n' variables need a short name; at most 999 can have one."
            _hfc_abort
        }

        *  ── The short names must be free: in the data, the form, the labels ─
        foreach _v of local _vars {
            if ustrregexm("`_v'", "^_mdf[0-9]{3}($|_|t_)") {
                di as error "  DS`ds' has a variable named `_v'. MDF needs the names"
                di as error "  _mdf001, _mdf002, ... for odksplit; rename that variable first."
                _hfc_abort
            }
        }
        foreach _v of local _fields {
            if ustrregexm("`_v'", "^_mdf[0-9]{3}$") {
                di as error "  The CAPI form has a field named `_v'. MDF needs the names"
                di as error "  _mdf001, _mdf002, ... for odksplit; rename that field first."
                _hfc_abort
            }
        }

        *  ── Form copy: the field's row takes the short name ────────────────
        *  Every other cell is written back as odksplit reads it (all text,
        *  same column names), so only the renamed rows differ for it.
        if "`_ncol'" != "" {
            qui import excel using `"`form'"', sheet("survey") firstrow clear allstring
            local _i 0
            foreach _o of local _from {
                local ++_i
                local _s = "_mdf" + string(`_i', "%03.0f")
                qui replace `_ncol' = "`_s'" if strtrim(`_ncol') == "`_o'"
            }
            qui export excel using `"`form'"', sheet("survey", replace) firstrow(variables)
        }

        *  ── Data copy: the variable takes the short name ───────────────────
        qui use `"`data'"', clear
        qui label dir
        foreach _l in `r(names)' {
            if ustrregexm("`_l'", "^_mdf[0-9]{3}$") {
                di as error "  DS`ds' has a value label named `_l'. MDF needs the names"
                di as error "  _mdf001, _mdf002, ... for odksplit; rename that label first."
                _hfc_abort
            }
        }
        local _map ""
        local _i 0
        di as result "  odksplit names (DS`ds'): `_n' variable(s) known to odksplit by a short name"
        foreach _o of local _from {
            local ++_i
            local _s = "_mdf" + string(`_i', "%03.0f")
            local _why "a choice label name would pass 31 characters"
            if ustrlen("`_o'") >= 29 local _why "29+ characters: too long for odksplit"
            local _b : list _o in _decl
            if `_b' local _why "listed in 01_Labeling.do"
            rename `_o' `_s'
            local _map `_map' `_o' `_s'
            di as txt "    " %-32s "`_o'" " -> `_s'   (`_why')"
        }
        qui save `"`data'"', replace
        clear
        local _multi : list _multi & _from
        return local map "`_map'"
        return local multi "`_multi'"
        return scalar n = `_n'
        exit
    }

    if "`_sub'" == "restore" {
        syntax , Map(string) [MULTi(string) DS(string)]
        local _w : word count `map'
        local _gone 0
        forvalues _i = 1(2)`_w' {
            local _o : word `_i' of `map'
            local _s : word `=`_i' + 1' of `map'
            cap confirm variable `_s', exact
            if _rc {
                di as error "  odksplit names: `_s' (`_o') is missing after odksplit; its name cannot be restored."
                _hfc_abort
            }
            cap confirm variable `_o', exact
            if !_rc {
                di as error "  odksplit names: `_o' already exists after odksplit; `_s' cannot take its name back."
                _hfc_abort
            }
            rename `_s' `_o'

            *  odksplit labels a field with no label text by its own name.
            local _vl : variable label `_o'
            if `"`_vl'"' == "`_s'" label variable `_o' "`_o'"

            *  odksplit names a select_one's value label after the field and
            *  adds to a label of that name if there is one (label define,
            *  modify). The same here, from the label it made for the short name.
            cap label list `_s'
            if !_rc {
                cap label list `_o'
                if _rc label copy `_s' `_o'
                else {
                    mata: _mdf_odk_V = .; _mdf_odk_T = ""; st_vlload("`_s'", _mdf_odk_V, _mdf_odk_T); st_vlmodify("`_o'", _mdf_odk_V, _mdf_odk_T)
                    cap mata: mata drop _mdf_odk_V _mdf_odk_T
                }
                if "`: value label `_o''" == "`_s'" label values `_o' `_o'
                label drop `_s'
            }

            *  select_multiple: one indicator per choice, <field>_<choice>.
            *  odksplit drops a variable of that name before it makes one, and
            *  cannot make one longer than 32 characters; the same here.
            cap ds `_s'_*
            if !_rc {
                foreach _d in `r(varlist)' {
                    local _t = "`_o'" + substr("`_d'", strlen("`_s'") + 1, .)
                    if ustrlen("`_t'") > 32 {
                        drop `_d'
                        local ++_gone
                    }
                    else {
                        cap drop `_t'
                        rename `_d' `_t'
                    }
                }
            }
        }

        *  odksplit places a select_multiple's indicators straight after it
        *  (order <field>_*, after(<field>) sequential) whenever the field has
        *  answers. -sequential- sorts by name, so it is repeated here under
        *  the original name, in odksplit's own field order: the result is the
        *  order odksplit gives the field when it can process it directly.
        local _multi : list sort multi
        foreach _o of local _multi {
            cap confirm string variable `_o', exact
            if !_rc {
                qui count if `_o' != ""
                if r(N) > 0 cap order `_o'_*, after(`_o') sequential
            }
        }

        *  Nothing may leave this boundary under a temporary name.
        foreach _v of varlist _all {
            if ustrregexm("`_v'", "^_mdf[0-9]{3}($|_|t_)") {
                di as error "  odksplit names: `_v' is still in DS`ds' after the names were restored."
                _hfc_abort
            }
        }
        qui label dir
        foreach _l in `r(names)' {
            if ustrregexm("`_l'", "^_mdf[0-9]{3}$") {
                di as error "  odksplit names: value label `_l' is still in DS`ds' after the names were restored."
                _hfc_abort
            }
        }
        di as result "  odksplit names (DS`ds'): original names restored (" `_w' / 2 ")."
        if `_gone' di as txt "    `_gone' select_multiple indicator(s) dropped: <field>_<choice> would exceed 32 characters."
        exit
    }

    di as error "_mdf_odk_names: use prepare or restore."
    exit 198
end
