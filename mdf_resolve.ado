*! mdf_resolve.ado — Master DO File pipeline stage 6 of 18
*! version 10.1.1   github.com/adinkhan7/master-do-file
*!
*!  post-field resolution

program define mdf_resolve
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 5b  POST-FIELD RESOLUTION
    *==============================================================================*
    *  When post_field = 1 the framework must not invent a new dated run folder.
    *  It binds instead to the newest 03_HFC run folder whose Raw/ actually holds
    *  a .dta, and leaves folder creation and import switched off. Sections 6 and 7
    *  are skipped wholesale in this mode.

    global hfc_postfield_active 0
    global hfc_real_today "$today"

    if "$post_field" == "1" {

        local _pf_all : dir "$hfc_dir" dirs "*_HFC_*", respectcase
        local _pf_sorted : list sort _pf_all
        local _pf_hit ""
        foreach _pf_d of local _pf_sorted {
            local _pf_dta ""
            cap local _pf_dta : dir "$hfc_dir/`_pf_d'/Raw" files "*.dta", respectcase
            local _pf_n 0
            foreach _pf_f of local _pf_dta {
                local _pf_n = `_pf_n' + 1
            }
            if `_pf_n' > 0 local _pf_hit "`_pf_d'"
        }

        if "`_pf_hit'" == "" {
            di as error "======================================================================="
            di as error "  POST-FIELD MODE: no run folder under 03_HFC/ contains any data."
            di as error "======================================================================="
            di as txt   "  post_field = 1 re-runs the last archived dataset. It never imports"
            di as txt   "  new data, so there must already be an archived run to work from."
            di as txt   " "
            di as result"  FIX: set post_field = 0, put the export in 02_Data/, and run once."
            di as error "======================================================================="
            _hfc_abort
        }

        global hfc_run_dir          "$hfc_dir/`_pf_hit'"
        global hfc_raw_snapshot_dir "$hfc_run_dir/Raw"
        global hfc_folder_date = substr("`_pf_hit'", -8, 8)
        global hfc_rawdata_dir      "$hfc_raw_snapshot_dir"
        global hfc_postfield_active 1

        *  Outputs reproduce in place: everything downstream that stamps with
        *  $today now stamps with the run folder's own date. The log keeps the
        *  real calendar date via $hfc_real_today so run history is not overwritten.
        global today "$hfc_folder_date"

        *  Newest raw-data folder that actually holds an export. Never created in
        *  this mode, and an empty folder left by a no-data run is skipped.
        local _pf_raw : dir "$data_dir" dirs "*_RAWDATA_*"
        local _pf_raw_s : list sort _pf_raw
        local _pf_rd ""
        local _pf_rd_any ""
        foreach _pf_r of local _pf_raw_s {
            local _pf_rd_any "`_pf_r'"
            local _pf_rf ""
            cap local _pf_rf : dir "$data_dir/`_pf_r'" files "*.dta"
            local _pf_rn 0
            foreach _pf_x of local _pf_rf {
                local _pf_rn = `_pf_rn' + 1
            }
            if `_pf_rn' > 0 local _pf_rd "`_pf_r'"
        }
        if "`_pf_rd'" == "" local _pf_rd "`_pf_rd_any'"
        if "`_pf_rd'" != "" global raw_data_dir "$data_dir/`_pf_rd'"
        else                global raw_data_dir "$data_dir"

        *  There is no new export to bring in.
        global run_import 0

        di as result _n "======================================================================="
        di as result    "  POST-FIELD MODE  —  no folders created, no data imported"
        di as result    "======================================================================="
        di as result    "  Run folder : `_pf_hit'"
        di as result    "  Data date  : $hfc_folder_date"
        di as result    "  Outputs are stamped $hfc_folder_date and overwrite in place."
        di as result    "  Log is stamped $hfc_real_today so earlier run logs survive."
        di as result    "======================================================================="  _n
    }
end
