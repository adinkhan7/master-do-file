*! mdf_validate.ado — Master DO File pipeline stage 2 of 19
*! version 11.1.1   github.com/adinkhan7/master-do-file
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

    *  Project details reach the generated file headers (ADR-061) only from a
    *  Master that sets them. One written for an earlier framework does not, and
    *  what another project's Master left in this Stata session is not this
    *  project's author.
    local _rq = subinstr("$mdf_required", ".", " ", .)
    local _rq1 = real(word("`_rq'", 1))
    local _rq2 = real(word("`_rq'", 2))
    local _rq3 = real(word("`_rq'", 3))
    foreach _n in _rq1 _rq2 _rq3 {
        if missing(``_n'') local `_n' 0
    }
    local _rqn = `_rq1' * 10000 + `_rq2' * 100 + `_rq3'
    if `_rqn' < 110100 {
        foreach _g in project_analyst project_email organisation project_description {
            global `_g' ""
        }
    }

    *  ── Masters written before 11.1.1 use the earlier names ─────────────────────
    *  project_lead became project_analyst and hfc_openended_vars* became
    *  exp_openended_vars* in 11.1.1. A Master pinned to an earlier framework
    *  still sets the old names, and the framework reads only the new ones, so
    *  its values are carried across here — otherwise a live project would lose
    *  its open-ended variable list and export every text variable instead.
    *  A Master at 11.1.1 or later sets the new names itself; what an earlier
    *  Master left in the session under the old ones is never read for it.
    if `_rqn' < 110101 {
        local _legacy 0
        if `_rqn' >= 110100 {
            if `"$project_lead"' != "" local _legacy 1
            global project_analyst `"$project_lead"'
        }
        foreach _s in "" "_1" "_2" "_3" {
            if `"${hfc_openended_vars`_s'}"' != "" local _legacy 1
            global exp_openended_vars`_s' `"${hfc_openended_vars`_s'}"'
        }
        if `_legacy' {
            di as txt "  NOTE: this Master uses the earlier setting names project_lead and"
            di as txt "        hfc_openended_vars*. They are read as project_analyst and"
            di as txt "        exp_openended_vars*. Rename them in Section 0 when convenient."
        }
    }
end
