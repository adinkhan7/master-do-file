*! mdf_finalise.ado — post-cleaning merge and publish
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  Replaces the generated 04_DO Files/04_Finalise.do (ADR-055). The logic is
*!  unchanged; only the standalone header it used to carry is gone, because an
*!  ado is never run on its own.
*!
*!      mdf_finalise merge     post-cleaning merge only
*!      mdf_finalise publish   publish cleaned datasets only
*!      mdf_finalise           both
*!
*!  Two copies of each cleaned dataset are written, on purpose:
*!    07_Cleaned Dataset/<ds>_CLEANED.dta        CURRENT, stable name, undated.
*!                                               What every consumer reads.
*!    03_HFC/NN_..._HFC_<date>/<ds>_CLEANED.dta  DATED SNAPSHOT, authoritative
*!                                               for reproducing that date.
*!  Without the snapshot an undated current file cannot reproduce yesterday.
*!  Without the current file every consumer would have to guess a date.

program define mdf_finalise
    version 16
    args _mode

    if "`_mode'" == "" local _mode "all"

    if !inlist("`_mode'", "merge", "publish", "all") {
        di as error `"mdf_finalise: unknown mode "`_mode'" — expected merge | publish"'
        exit 198
    }

    if "`_mode'" == "merge" | "`_mode'" == "all" {
        if $merge_required == 1 {
            di as result _n "--- Executing Post-Cleaning Merge ---"
            local _ds1 : word 1 of $merge_datasets
            local _ds2 : word 2 of $merge_datasets
            local _cln1 "${dta_cleaned_`_ds1'}"
            local _cln2 "${dta_cleaned_`_ds2'}"
            if "`_cln1'" != "" & "`_cln2'" != "" {
                * Pre-align datatypes: force merge keys to string in using dataset
                use "`_cln2'", clear
                * Auto-prefix using dataset to prevent overlap
                rename * u_*
                rename u_$merge_key $merge_key
                cap tostring $merge_key, replace force format(%20.0g)
                tempfile _using_tmp
                save "`_using_tmp'", replace

                * Pre-align datatypes: force merge keys to string in master dataset
                use "`_cln1'", clear
                * Auto-prefix master dataset to prevent overlap
                rename * m_*
                rename m_$merge_key $merge_key
                cap rename m_key key  // Protect pipeline key for archiving
                cap tostring $merge_key, replace force format(%20.0g)

                di as result "  Merging via $merge_type on $merge_key..."
                merge $merge_type $merge_key using "`_using_tmp'", gen(_merge_post) force

                local _sfx = subinstr("$merge_datasets", " ", "_", .)
                local _merged_name "${project_name}_`_sfx'_MERGED_$hfc_folder_date"
                save "$hfc_run_dir/`_merged_name'.dta", replace
                di as result "  Successfully merged dataset saved -> `_merged_name'.dta"
            }
        }
    }

    if "`_mode'" == "publish" | "`_mode'" == "all" {
        forvalues _ds = 1/$actual_n_dta {
            local _src "${dta_cleaned_`_ds'}"
            cap confirm file "`_src'"
            if _rc {
                di as txt "  DS`_ds': no cleaned dataset produced — nothing to publish."
                continue
            }
            local _nm "${auto_dsname_`_ds'}"
            if "`_nm'" == "" local _nm "DS`_ds'"
            cap copy "`_src'" "$clean_dir/`_nm'_CLEANED.dta", replace
            if !_rc di as result "  Published → 07_Cleaned Dataset/`_nm'_CLEANED.dta"
            else     di as error "  WARNING: could not publish DS`_ds' to 07_Cleaned Dataset."
        }
    }
end
