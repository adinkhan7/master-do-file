*! mdf_folders.ado — Master DO File pipeline stage 4 of 18
*! version 10.1.0   github.com/adinkhan7/master-do-file
*!
*!  create the project folder tree

program define mdf_folders
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 4   CREATE MAIN FOLDER STRUCTURE
    *==============================================================================*

    di as result _n "--- Verifying project folder structure ---"

    _hfc_mkdir "$surv_inst_dir"
    _hfc_mkdir "$quest_dir"
    _hfc_mkdir "$capi_dir"
    _hfc_mkdir "$others_dir"
    _hfc_mkdir "$data_dir"
    _hfc_mkdir "$hfc_dir"
    _hfc_mkdir "$dofiles_dir"
    _hfc_mkdir "$translation_dir"
    _hfc_mkdir "$processing_dir"
    _hfc_mkdir "$clean_dir"

    *  ── 03_HFC: keys grouped by kind ───────────────────────────────────────────
    _hfc_mkdir "$hfc_keys_dir"
    _hfc_mkdir "$hfc_keys_hfc_dir"
    _hfc_mkdir "$hfc_keys_audio_dir"
    _hfc_mkdir "$hfc_keys_trans_dir"
    _hfc_mkdir "$hfc_flag_dir"
    _hfc_hide  "$hfc_flag_dir" 1

    *  ── Consolidate flag stores into KEYS/.flag_history ────────────────────────
    local _fl_old : dir "$hfc_keys_hfc_dir" files "*_FLAGS_*.dta", respectcase
    local _fl_n 0
    foreach _ff of local _fl_old {
        cap copy "$hfc_keys_hfc_dir/`_ff'" "$hfc_flag_dir/`_ff'", replace
        cap confirm file "$hfc_flag_dir/`_ff'"
        if !_rc {
            cap erase "$hfc_keys_hfc_dir/`_ff'"
            local _fl_n = `_fl_n' + 1
        }
        else di as error "  KEPT (copy failed): `_ff'"
    }
    if `_fl_n' > 0 {
        di as result "  Moved `_fl_n' flag store(s) → KEYS/.flag_history/ (issue history preserved)."
    }

    *  ── 05_Translation: one place for the whole round-trip ─────────────────────
    _hfc_mkdir "$trans_exported_dir"
    _hfc_mkdir "$trans_translated_dir"

    *  ── 06_Processing: the current working data ────────────────────────────────
    _hfc_mkdir "$processing_data_dir"

    di as result "Main folder structure: OK  (v10 layout)"

    *  ── Write the ROOT sentinel ────────────────────────────────────────────────

    local _sentinel "$ROOT/.hfc_root"
    local _created  ""

    cap confirm file "`_sentinel'"
    if !_rc {
        tempname _shr
        cap file open `_shr' using "`_sentinel'", read text
        if !_rc {
            file read `_shr' _sline
            while r(eof) == 0 {
                if strpos(`"`_sline'"', "created") == 1 {
                    local _eq = strpos(`"`_sline'"', "=")
                    if `_eq' > 0 local _created = strtrim(substr(`"`_sline'"', `_eq' + 1, .))
                }
                file read `_shr' _sline
            }
            file close `_shr'
        }
    }
    if "`_created'" == "" local _created "$today"

    tempname _shw
    cap file open `_shw' using "`_sentinel'", write replace text
    if !_rc {
        file write `_shw' "project_name = $project_name"       _n
        file write `_shw' "framework    = $hfc_version"        _n
        file write `_shw' "layout       = $hfc_layout_version" _n
        file write `_shw' "created      = `_created'"          _n
        file write `_shw' "stamped      = $today"              _n
        file close `_shw'
        _hfc_hide "`_sentinel'"
        di as result "ROOT sentinel: OK  (.hfc_root, hidden, created `_created')"
    }
    else di as error "WARNING: could not write .hfc_root — standalone files will fall back to the tempdir cache."
end
