*! mdf_import.ado — Master DO File pipeline stage 10 of 19
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  carry the import DO forward, fingerprint it, import

program define mdf_import
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 13  RUN IMPORT DO FILE(S)
    *==============================================================================*

    *  ── Carry the import DO forward from the previous raw-data folder ─────────
    *  SurveyCTO hands you an import .do beside the .csv on the first download.
    *  On later days analysts pull only the .csv, so the folder arrives holding
    *  data with no way to read it. Nothing would then import, no .dta would
    *  appear, and the detection below would read the bare .csv as a pre-fieldwork
    *  Ghost Run — a silently wrong answer, which is the one outcome this
    *  framework does not tolerate.
    *
    *  The donor is the NEWEST earlier dated folder that actually holds an import
    *  DO, so an edit made on any day is the version that propagates from then on.
    *  Nothing is ever copied over a file already present: an import DO edited
    *  today is always the one that runs.
    *
    *  respectcase matters — without it -dir- lowercases what it returns, which is
    *  harmless on Windows and breaks the copy on macOS and Linux.
    if "$run_import" == "1" {
        local _here_csv : dir "$raw_data_dir" files "*.csv", respectcase
        local _here_do  : dir "$raw_data_dir" files "*.do",  respectcase

        if `"`_here_csv'"' != "" & `"`_here_do'"' == "" {
            local _all_raw    : dir "$data_dir" dirs "*_RAWDATA_*", respectcase
            local _sorted_raw : list sort _all_raw
            local _nraw       : word count `_sorted_raw'
            local _this_fold  = substr("$raw_data_dir", strrpos("$raw_data_dir", "/") + 1, .)

            local _donor ""
            forvalues _i = `_nraw'(-1)1 {
                local _cand : word `_i' of `_sorted_raw'
                if `"`_cand'"' != `"`_this_fold'"' {
                    local _cdo : dir "$data_dir/`_cand'" files "*.do", respectcase
                    if `"`_cdo'"' != "" {
                        local _donor `"`_cand'"'
                        continue, break
                    }
                }
            }

            if `"`_donor'"' != "" {
                di as result _n "--- Carrying the import DO forward ---"
                di as txt       "    donor: `_donor'"
                local _cdo : dir "$data_dir/`_donor'" files "*.do", respectcase
                local _ncarried 0

                foreach _f of local _cdo {
                    *  Only carry a DO whose CSV is actually here. A multi-dataset
                    *  project can have a quiet day on one form, and importing a DO
                    *  whose CSV is absent hard-aborts the run.
                    local _wantcsv ""
                    tempname _cfh
                    cap file open `_cfh' using `"$data_dir/`_donor'/`_f'"', read text
                    if !_rc {
                        file read `_cfh' _cline
                        while r(eof) == 0 & `"`_wantcsv'"' == "" {
                            if strpos(`"`_cline'"', "local csvfile") > 0 {
                                local _p = strpos(`"`_cline'"', `"""')
                                if `_p' > 0 {
                                    local _rest = substr(`"`_cline'"', `_p' + 1, .)
                                    local _e = strpos(`"`_rest'"', `"""')
                                    if `_e' > 1 local _wantcsv = substr(`"`_rest'"', 1, `_e' - 1)
                                }
                            }
                            file read `_cfh' _cline
                        }
                        cap file close `_cfh'
                    }

                    if `"`_wantcsv'"' != "" {
                        cap confirm file `"$raw_data_dir/`_wantcsv'"'
                        if _rc {
                            di as txt "    skipped: `_f'  (`_wantcsv' is not in this folder)"
                            continue
                        }
                    }

                    cap copy `"$data_dir/`_donor'/`_f'"' `"$raw_data_dir/`_f'"'
                    cap confirm file `"$raw_data_dir/`_f'"'
                    if !_rc {
                        local _ncarried = `_ncarried' + 1
                        di as result "    carried: `_f'"
                    }
                    else di as error "    WARNING: could not carry forward `_f'."
                }

                if `_ncarried' == 0 {
                    di as error "    WARNING: nothing was carried forward. Download the"
                    di as error "             SurveyCTO import .do into:"
                    di as error "             $raw_data_dir"
                }
            }
            else {
                di as error _n "  WARNING: this folder holds a .csv but no import .do, and no"
                di as error    "           earlier raw-data folder has one to lend."
                di as error    "           Download the SurveyCTO import .do into:"
                di as error    "           $raw_data_dir"
            }
        }
    }

    if "$run_import" == "1" & "$import_fingerprint" != "0" {
        *  ── ONE IMPORT DO, ONE CSV — pair them, never cross-compare ────────────────
        local _dos : dir "$raw_data_dir" files "*.do"
        foreach _do of local _dos {
            local _declared ""
            local _parsed 0
            local _mycsv ""

            tempname _dfh
            cap file open `_dfh' using "$raw_data_dir/`_do'", read text
            if _rc continue
            file read `_dfh' _line
            while r(eof) == 0 {
                if "`_mycsv'" == "" & strpos(`"`_line'"', "local csvfile") > 0 {
                    local _p = strpos(`"`_line'"', `"""')
                    if `_p' > 0 {
                        local _rest = substr(`"`_line'"', `_p'+1, .)
                        local _e = strpos(`"`_rest'"', `"""')
                        if `_e' > 1 local _mycsv = substr(`"`_rest'"', 1, `_e'-1)
                    }
                }
                foreach _kind in text_fields date_fields datetime_fields other_fields {
                    if strpos(`"`_line'"', "`_kind'") > 0 {
                        local _parsed 1
                        local _p = strpos(`"`_line'"', `"""')
                        if `_p' > 0 {
                            local _rest = substr(`"`_line'"', `_p'+1, .)
                            local _e = strpos(`"`_rest'"', `"""')
                            if `_e' > 1 {
                                local _piece = substr(`"`_rest'"', 1, `_e'-1)
                                local _declared `"`_declared' `_piece'"'
                            }
                        }
                    }
                }
                file read `_dfh' _line
            }
            cap file close `_dfh'

            if `_parsed' == 0 {
                di as error "  WARNING: could not parse field lists from `_do'."
                di as error "           Fingerprint check SKIPPED — this is a warning, not a failure."
                continue
            }
            if `"`_mycsv'"' == "" {
                di as error "  WARNING: `_do' does not name its CSV. Fingerprint check SKIPPED."
                continue
            }

            local _header ""
            tempname _cfh
            cap file open `_cfh' using "$raw_data_dir/`_mycsv'", read text
            if _rc {
                di as txt "  `_do' expects `_mycsv' — not present in this folder. Skipping check."
                continue
            }
            file read `_cfh' _header
            cap file close `_cfh'
            if `"`_header'"' == "" continue

            *  ── WHICH DIRECTION THIS COMPARES, AND WHY ─────────────────────────────────
            local _hdr = subinstr(`"`_header'"', `"""', "", .)
            local _hdr = subinstr(`"`_hdr'"', ",", " ", .)
            local _hdr = subinstr(`"`_hdr'"', char(13), "", .)
            local _hdr = lower(`"`_hdr'"')

            local _decl ""
            foreach _d of local _declared {
                if strpos("`_d'", "*") == 0 local _decl "`_decl' `_d'"
            }
            local _decl = lower("`_decl'")

            local _missing : list _decl - _hdr
            local _n_missing : word count `_missing'
            if `_n_missing' > 0 {
                di as error "========================================================================="
                di as error "  IMPORT FINGERPRINT MISMATCH — `_mycsv'"
                di as error "========================================================================="
                di as error "  `_do' expects fields this CSV does not contain:"
                di as error "    `_missing'"
                di as error ""
                di as error "  The import script and the data came from different versions of the"
                di as error "  form. Re-download BOTH from SurveyCTO so they match, otherwise the"
                di as error "  import will mishandle those fields."
                di as error ""
                di as error "  To proceed anyway (not recommended): set global import_fingerprint 0"
                _hfc_abort "  Halting before import."
            }
            else di as result "  Import fingerprint OK — `_mycsv' matches `_do'."
        }
    }

    if "$run_import" == "1" {
        di as result _n "--- Running import DO file(s) ---"
        cd "$raw_data_dir"

        local _import_list : dir "$raw_data_dir" files "*.do"
        foreach _f of local _import_list {
            di as result "  Running: `_f'"
            $hfcsys_vcap do "`_f'"
            local _imprc = _rc

            cd "${ROOT}"

            if `_imprc' {
                di as error "  FATAL: Import DO `_f' returned error `_imprc'. Halting pipeline."
                cap log close hfc_master
                exit `_imprc'
            }

            cd "$raw_data_dir"
        }
        cd "${ROOT}"
    }
    else di as result _n "--- Import skipped (run_import = 0) ---"

    *  Post-field re-runs detect datasets from the archived snapshot, not from
    *  02_Data/. There is no fresh export in post-field mode, so the snapshot is
    *  the authoritative record of what this project actually holds.
    local _detect_dir "$raw_data_dir"
    if "$hfc_postfield_active" == "1" local _detect_dir "$hfc_raw_snapshot_dir"

    local _dta_list : dir "`_detect_dir'" files "*.dta", respectcase
    local _n_dta 0
    foreach _f of local _dta_list {
        local _n_dta = `_n_dta' + 1
    }
    global actual_n_dta = `_n_dta'

    if `_n_dta' == 0 {
        local _csv_list : dir "`_detect_dir'" files "*.csv", respectcase
        local _n_csv 0
        foreach _c of local _csv_list {
            local _n_csv = `_n_csv' + 1
        }

        if `_n_csv' == 0 {
            di as error "ERROR: No .dta AND no .csv found in:"
            di as error "       `_detect_dir'"
            di as error "       Check that folder and try again."
            _hfc_abort
        }
        else {
            di as result _n "======================================================="
            di as result    "  PRE-FIELDWORK MODE DETECTED (GHOST RUN)"
            di as result    "  0 data on server. Using .csv names to build architecture."
            di as result    "======================================================="
            global actual_n_dta = `_n_csv'
            global ghost_run = 1
        }
    }
    else {
        global ghost_run = 0
    }

    di as result "$actual_n_dta dataset(s) detected in `_detect_dir'"
    if $actual_n_dta == 0 _hfc_abort "CRITICAL: actual_n_dta resolved to 0 after import. Cannot continue pipeline."

    *  ── Architecture Guard: Prevent Single/Multi Global Bleed ──────────────────
    if $actual_n_dta == 1 {
        forvalues _i = 1/5 {  // Adjust upper limit if you use more than 5 datasets
            global meta_front_`_i' ""
            global meta_ids_`_i'   ""
            global tail_`_i'       ""
            global hfc_openended_vars_`_i' ""
            global gate_vars_`_i'  ""
        }
        di as result "Architecture Guard: Multi-dataset overrides wiped for single-dataset run."
    }

    *  ── Auto-correct merge intent if there aren't enough datasets ──────────────
    if $merge_required == 1 & $actual_n_dta < 2 {
        di as result "NOTE: merge_required is 1, but only 1 dataset was found. Auto-disabling merge."
        global merge_required 0
    }
end
