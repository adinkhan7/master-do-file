*! mdf_workdirs.ado — Master DO File pipeline stage 7 of 19
*! version 11.1.0   github.com/adinkhan7/master-do-file
*!
*!  today's raw-data folder and HFC run folder

program define mdf_workdirs
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 6   RAW DATA FOLDER UNDER data_dir
    *==============================================================================*

    if "$hfc_postfield_active" != "1" {
    local _found_today : dir "$data_dir" dirs "*_RAWDATA_$today"
    if `"`_found_today'"' != "" {
        gettoken _raw_fname : _found_today
        global raw_data_dir "$data_dir/`_raw_fname'"
        di as result "Raw data folder (existing) → `_raw_fname'"
    }
    else {
        local _existing : dir "$data_dir" dirs "*_RAWDATA_*"
        local _n 0
        foreach _f of local _existing {
            local _n = `_n' + 1
        }
        local _seq : display %02.0f (`_n' + 1)
    local _raw_fname "`_seq'_${project_name}_RAWDATA_$today"
        _hfc_mkdir "$data_dir/`_raw_fname'"
        global raw_data_dir "$data_dir/`_raw_fname'"
        di as result "Raw data folder (new) → `_raw_fname'"
    }
    }

    *==============================================================================*
    *  SECTION 7   HFC RUN FOLDER  —  hfc_dir/NN_<Project>_HFC_<date>/
    *==============================================================================*

    if "$hfc_postfield_active" != "1" {
    local _found_hfc : dir "$hfc_dir" dirs "*_HFC_$today", respectcase
    if `"`_found_hfc'"' != "" {
        gettoken _hfc_fname : _found_hfc
        global hfc_run_dir "$hfc_dir/`_hfc_fname'"
        di as result "HFC run folder (existing) → `_hfc_fname'"
    }
    else {
        local _existing_hfc : dir "$hfc_dir" dirs "*_HFC_*", respectcase
        local _n 0
        foreach _f of local _existing_hfc {
            local _n = `_n' + 1
        }
        local _seq : display %02.0f (`_n' + 1)
        local _hfc_fname "`_seq'_${project_name}_HFC_$today"

        _hfc_mkdir "$hfc_dir/`_hfc_fname'"
        global hfc_run_dir "$hfc_dir/`_hfc_fname'"
        di as result "HFC run folder (new) → `_hfc_fname'"
    }

    global hfc_raw_snapshot_dir "$hfc_run_dir/Raw"
    global hfc_folder_date      "$today"

    _hfc_mkdir "$hfc_raw_snapshot_dir"

    *  ── Run-folder path aliases ────────────────────────────────────────────────
    global hfc_rawdata_dir   "$hfc_raw_snapshot_dir"
    }

    *  ── Retire superseded _LABELED_ files once a _CLEANED_ file exists ─────────
    local _lb_stale : dir "$hfc_run_dir" files "*_LABELED_*.dta", respectcase
    local _lb_n 0
    foreach _lf of local _lb_stale {
        local _cf = subinstr(`"`_lf'"', "_LABELED_", "_CLEANED_", 1)
        cap confirm file "$hfc_run_dir/`_cf'"
        if !_rc {
            cap erase "$hfc_run_dir/`_lf'"
            if !_rc local _lb_n = `_lb_n' + 1
        }
    }
    if `_lb_n' > 0 {
        di as result "  Removed `_lb_n' superseded _LABELED_ file(s)."
    }

    di as result "HFC run folder: OK"
end
