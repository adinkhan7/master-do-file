*! mdf_log.ado — Master DO File pipeline stage 8 of 19
*! version 11.1.0   github.com/adinkhan7/master-do-file
*!
*!  open the run log and detect the run type

program define mdf_log
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 8   LOGGING
    *==============================================================================*

    cap log close _all
    global log_file "$hfc_run_dir/${project_name}_HFC_Log_$hfc_real_today.log"

    *  ── Log rotation: remove logs older than 30 days ───────────────────────────
    local _log_cutoff = $hfcsys_num - 30
    local _old_logs : dir "$hfc_run_dir" files "*_HFC_Log_????????.log"
    foreach _lf of local _old_logs {
        local _ldate_str = substr("`_lf'", -12, 8)
        local _ldate_num = daily("`_ldate_str'", "YMD")
        if !missing(`_ldate_num') & `_ldate_num' < `_log_cutoff' {
            cap erase "$hfc_run_dir/`_lf'"
            if !_rc di as result "  Rotated old log: `_lf'"
        }
    }

    log using "$log_file", append text name(hfc_master)

    di as result _n "════════════════════════════════════════════"
    di as result    "  PROJECT  : $project_name"
    di as result    "  DATE     : $today  ($hfcsys_long)"
    di as result    "  TIME     : `c(current_time)'"
    di as result    "  ROOT     : $ROOT"

    *  ── SWITCHES IN EFFECT ─────────────────────────────────────────────────────
    di as result    "  SWITCHES : import=$run_import  labeling=$run_labeling  translation=$run_translation"
    di as result    "             processing=$run_processing  hfc=$run_hfc  audio=$run_audio"
    di as result    "════════════════════════════════════════════" _n

    *==============================================================================*
    *  SECTION 9   DETECT RUN TYPE
    *==============================================================================*

    local _import_list : dir "$raw_data_dir" files "*.do"
    local _dta_list_init : dir "$raw_data_dir" files "*.dta"
    local _csv_list_init : dir "$raw_data_dir" files "*.csv"

    global hfcsys_n_raw 0
    foreach _f of local _import_list {
        global hfcsys_n_raw = $hfcsys_n_raw + 1
    }
    foreach _f of local _dta_list_init {
        global hfcsys_n_raw = $hfcsys_n_raw + 1
    }
    foreach _f of local _csv_list_init {
        global hfcsys_n_raw = $hfcsys_n_raw + 1
    }

    if $hfcsys_n_raw == 0 & "$hfc_postfield_active" != "1" {
        di as result _n "======================================================="
        di as result    "  RUN 1 COMPLETE"
        di as result    "  All project folders created. Pipeline DO files will generate on Run 2."
        di as result    " "
        di as result    "  Next steps:"
        di as result    "  1)  $hfcsys_rel_quest_dir/  ← questionnaire documents"
        di as result    "  2)  $hfcsys_rel_capi_dir/  ← SurveyCTO .xlsx form(s)"
        di as result    "      Single dataset : place .xlsx directly in $hfcsys_rel_capi_dir/."
        di as result    "      Multiple datasets: CAPI subfolders are created automatically"
        di as result    "        on Run 2 once import DO(s) are present in $hfcsys_rel_data_dir/."
        di as result    "  3)  $raw_data_dir"
        di as result    "                             ← import .do(s) / .dta(s) / .csv(s) from server"
        di as result    "  4)  Re-run this DO file."
        di as result    "=======================================================" _n
    }
end
