*! mdf_validate.ado — Master DO File pipeline stage 2 of 19
*! version 10.2.0   github.com/adinkhan7/master-do-file
*!
*!  Section 0 sanity checks and switch defaults

program define mdf_validate
    version 16
    *  A clean stop upstream (Run 1, a CAPI pause, a Ghost Run) sets this.
    *  `exit` inside an ado returns from the ado, not from Master, so every
    *  later stage has to stand down of its own accord.
    if "$mdf_halt" == "1" exit

    _mdf_load

    *==============================================================================*
    *  SECTION 1   CONFIGURATION VALIDATION
    *==============================================================================*
    if $merge_required == 1 {
        if !inlist("$merge_type", "1:1", "1:m", "m:1", "m:m") {
            di as error "ERROR: merge_type must be one of: 1:1 | 1:m | m:1 | m:m"
            di as error "       Got: '$merge_type'  — update global merge_type in Section 0."
            _hfc_abort
        }
        if "$merge_key" == "" {
            di as error "ERROR: merge_key is empty. Set a variable name in Section 0."
            di as error "       Example: global merge_key " + char(34) + "hhid" + char(34)
            _hfc_abort
        }
    }

    foreach _sw in run_import run_labeling run_translation run_processing run_hfc run_audio run_deliverables {
        if "${`_sw'}" == "" global `_sw' 0
    }

    if "$capi_language" == "" global capi_language "English"
    if "$audio_seed" == "" global audio_seed 987654321
    if "$audio_sample_count" == "" global audio_sample_count 1

    if "$exportopenended" == "" global exportopenended 0
    if "$oe_export_all" == "" global oe_export_all 0
    if "$inputcorrection" == "" global inputcorrection 0

    if "$verbose" == "" global verbose 0
end
