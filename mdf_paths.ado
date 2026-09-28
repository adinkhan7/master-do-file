*! mdf_paths.ado — Master DO File pipeline stage 3 of 19
*! version 11.0.0   github.com/adinkhan7/master-do-file
*!
*!  run dates, the project's folder layout, and every folder path global

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
    *  SECTION 3a  WHICH FOLDER LAYOUT THIS PROJECT USES  (ADR-058)
    *==============================================================================*
    *  v11 organises the project into eight numbered folders in the order the
    *  work flows. A project built before v11 keeps the layout it was built
    *  with: nothing in a live project is moved, renamed or re-homed.
    *
    *  The sentinel says which layout a project uses. A project with no
    *  sentinel line for it is v10 if any v10 folder is present, and a brand-new
    *  folder is v11. Anything else the sentinel might say is read as v10,
    *  because v10 is what every earlier framework built.
    local _lay ""
    tempname _lh
    cap file open `_lh' using "$ROOT/.hfc_root", read text
    if !_rc {
        file read `_lh' _lline
        while r(eof) == 0 {
            if strpos(`"`_lline'"', "layout") == 1 {
                local _eq = strpos(`"`_lline'"', "=")
                if `_eq' > 0 local _lay = strtrim(substr(`"`_lline'"', `_eq' + 1, .))
            }
            file read `_lh' _lline
        }
        file close `_lh'
    }
    if "`_lay'" == "" {
        local _lay "v11"
        foreach _v10 in "01_Survey_Instruments" "03_HFC" "04_DO Files" "05_Translation" "06_Processing Files" {
            mata: st_local("_v10hit", strofreal(direxists(st_global("ROOT") + "/" + "`_v10'")))
            if `_v10hit' == 1 local _lay "v10"
        }
    }
    if "`_lay'" != "v11" local _lay "v10"
    global hfc_layout_version "`_lay'"

    *==============================================================================*
    *  SECTION 3   FOLDER PATH GLOBALS
    *==============================================================================*

    if "$hfc_layout_version" == "v11" {
        *  ── v11: eight folders, numbered in the order the work flows ──────────
        global quest_dir           "$ROOT/01_Questionnaire"
        global capi_dir            "$ROOT/02_CAPI"
        global data_dir            "$ROOT/03_Data"
        global others_dir          "$ROOT/04_Others"
        global processing_dir      "$ROOT/05_Processing"
        global dofiles_dir         "$processing_dir/01_Do Files"
        global translation_dir     "$processing_dir/02_Translation"
        global processing_data_dir "$processing_dir/03_Data"
        global hfc_dir             "$ROOT/06_HFC"
        global clean_dir           "$ROOT/07_Cleaned Dataset"
        global deliv_dir           "$ROOT/08_Deliverables"
        *  The instrument folders no longer share a parent; the alias points at
        *  the root so code that reads it still gets a folder that exists.
        global surv_inst_dir       "$ROOT"
        global directory_file      "00a_Directory.do"
        *  Multi-dataset instrument subfolders: NN_<dataset>.
        global hfcsys_capi_sub     ""
        global hfcsys_quest_sub    ""
        global hfcsys_others_sub   ""
    }
    else {
        *  ── v10: unchanged ─────────────────────────────────────────────────────
        global surv_inst_dir   "$ROOT/01_Survey_Instruments"
        global quest_dir       "$surv_inst_dir/01_Questionnaire"
        global capi_dir        "$surv_inst_dir/02_CAPI"
        global others_dir      "$surv_inst_dir/03_Others"
        global data_dir        "$ROOT/02_Data"
        global hfc_dir         "$ROOT/03_HFC"
        global dofiles_dir     "$ROOT/04_DO Files"
        global translation_dir "$ROOT/05_Translation"
        global processing_dir  "$ROOT/06_Processing Files"
        global clean_dir       "$ROOT/07_Cleaned Dataset"
        global deliv_dir       "$ROOT/Deliverables"
        global processing_data_dir  "$processing_dir/Data"
        global directory_file  "00_Directory.do"
        *  Multi-dataset instrument subfolders: NN_SurveyCTO_<dataset> and so on.
        global hfcsys_capi_sub     "SurveyCTO_"
        global hfcsys_quest_sub    "Questionnaire_"
        global hfcsys_others_sub   "Others_"
    }
    global processing_file "${project_name}_Processing.do"

    *  ── HFC internals: the same in both layouts, under $hfc_dir ─────────────
    global hfc_keys_dir        "$hfc_dir/KEYS"
    global hfc_keys_hfc_dir    "$hfc_keys_dir/01_HFC_Keys"
    global hfc_keys_audio_dir  "$hfc_keys_dir/02_Audio_Keys"
    global hfc_keys_trans_dir  "$hfc_keys_dir/03_Translation_Keys"

    *  ── Issue-flag history ─────────────────────────────────────────────────────
    global hfc_flag_dir        "$hfc_keys_dir/.flag_history"

    *  ── Translation internals ──────────────────────────────────────────────────
    global trans_exported_dir   "$translation_dir/01_Exported"
    global trans_translated_dir "$translation_dir/02_Translated"

    global hfc_dofiles_dir     "$dofiles_dir"
    global hfc_keys_master_dir "$hfc_keys_hfc_dir"

    *  ── Folder names relative to ROOT, for messages ────────────────────────────
    *  Messages name folders the way the analyst sees them, whichever layout the
    *  project uses.
    foreach _g in quest_dir capi_dir data_dir others_dir processing_dir dofiles_dir ///
                  translation_dir processing_data_dir hfc_dir clean_dir deliv_dir {
        global hfcsys_rel_`_g' = subinstr("${`_g'}", "$ROOT/", "", 1)
    }
end
