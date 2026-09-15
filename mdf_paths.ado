*! mdf_paths.ado — Master DO File pipeline stage 3 of 18
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  run dates and every folder path global

program define mdf_paths
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 2   DATE SETUP
    *==============================================================================*

    global hfcsys_num  = daily("`c(current_date)'", "DMY")
    local _fmt  : display %tdCCYYNNDD $hfcsys_num
    global today = strtrim("`_fmt'")

    local _num_y = $hfcsys_num - 1
    local _fmt_y : display %tdCCYYNNDD `_num_y'
    global yesterday = strtrim("`_fmt_y'")

    global hfcsys_long  : display %tdDDmonCCYY $hfcsys_num

    *==============================================================================*
    *  SECTION 3   FOLDER PATH GLOBALS
    *==============================================================================*

    *  ── Top-level directories ──────────────────────────────────────────────────
    global surv_inst_dir   "$ROOT/01_Survey_Instruments"
    global quest_dir       "$surv_inst_dir/01_Questionnaire"
    global capi_dir        "$surv_inst_dir/02_CAPI"
    global others_dir      "$surv_inst_dir/03_Others"
    global data_dir        "$ROOT/02_Data"
    global hfc_dir         "$ROOT/03_HFC"
    global dofiles_dir     "$ROOT/04_DO Files"
    global translation_dir "$ROOT/05_Translation"
    global processing_dir  "$ROOT/06_Processing Files"
    global processing_file "${project_name}_Processing.do"
    global clean_dir       "$ROOT/07_Cleaned Dataset"

    *  ── 03_HFC internals ───────────────────────────────────────────────────────
    global hfc_keys_dir        "$hfc_dir/KEYS"
    global hfc_keys_hfc_dir    "$hfc_keys_dir/01_HFC_Keys"
    global hfc_keys_audio_dir  "$hfc_keys_dir/02_Audio_Keys"
    global hfc_keys_trans_dir  "$hfc_keys_dir/03_Translation_Keys"

    *  ── Issue-flag history ─────────────────────────────────────────────────────
    global hfc_flag_dir        "$hfc_keys_dir/.flag_history"

    *  ── 05_Translation internals ───────────────────────────────────────────────
    global trans_exported_dir   "$translation_dir/01_Exported"
    global trans_translated_dir "$translation_dir/02_Translated"

    *  ── 06_Processing internals ────────────────────────────────────────────────
    global processing_data_dir  "$processing_dir/Data"

    global hfc_dofiles_dir     "$dofiles_dir"
    global hfc_keys_master_dir "$hfc_keys_hfc_dir"
end
