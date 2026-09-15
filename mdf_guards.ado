*! mdf_guards.ado — Master DO File pipeline stage 12 of 18
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  stale-processing and open-workbook guards

program define mdf_guards
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 15  STALE-PROCESSING GUARD
    *==============================================================================*

    cap confirm file "$processing_dir/$processing_file"
    if !_rc {
        local _stale_proc 0
        tempname _spf
        cap file open `_spf' using "$processing_dir/$processing_file", read text
        if !_rc {
            file read `_spf' _spline
            while r(eof) == 0 {
                local _spt = strtrim(`"`_spline'"')
                if substr(`"`_spt'"', 1, 1) != "*" {
                    if strpos(`"`_spline'"', "_LABELED_") > 0 local _stale_proc 1
                }
                file read `_spf' _spline
            }
            cap file close `_spf'
        }
        if `_stale_proc' == 1 {
            di as error _n "======================================================================="
            di as error    "  WARNING: 06_Processing Files/$processing_file is from an older build."
            di as error    " "
            di as error    "  It loads a _LABELED_ dataset that this version no longer writes."
            di as error    "  Labeling now hands the data to cleaning in memory."
            di as error    " "
            di as error    "  LEFT ALONE, YOUR CLEANING WILL RUN ON UNLABELED RAW DATA."
            di as error    " "
            di as error    "  Fix it once:"
            di as error    "   1) Open  06_Processing Files/${processing_file}.new  (written beside it)"
            di as error    "   2) Copy your cleaning code from the old file into the SECTION A /"
            di as error    "      SECTION B slots of the .new file."
            di as error    "   3) Replace $processing_file with the .new file."
            di as error    " "
            di as error    "  Your file has NOT been modified."
            di as error    "======================================================================="
        }
    }

    *==============================================================================*
    *  SECTION 16  SURVEYCTO FORM OPEN IN EXCEL
    *==============================================================================*



    _hfc_capi_lockcheck

    *  ── run_archive is retired, not honoured ───────────────────────────────────
    if "$run_archive" == "0" {
        di as txt _n "  NOTE: run_archive is no longer a switch and has been ignored."
        di as txt    "        Archiving the raw data into the run folder is now part of the"
        di as txt    "        pipeline: labeling reads from it and dataset detection depends"
        di as txt    "        on it, so a run with it off would produce nothing."
    }

    *  ── run_labeling has no effect without run_processing ──────────────────────
    if "$run_labeling" == "1" & "$run_processing" != "1" {
        di as error _n "========================================================================="
        di as error    "  run_labeling = 1 BUT run_processing = 0 — NOTHING WILL BE LABELED"
        di as error    "========================================================================="
        di as text     "  Labeling is not a stage in its own right. It runs inside Processing,"
        di as text     "  per dataset, immediately before that dataset is cleaned, and hands the"
        di as text     "  labeled data over in memory. With run_processing = 0 there is"
        di as text     "  nothing for it to label and no cleaned dataset to label into."
        di as text     " "
        di as result   "  Set run_processing = 1 to apply CAPI value labels."
        di as error    "========================================================================="
    }
end
