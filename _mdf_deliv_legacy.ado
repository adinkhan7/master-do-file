*! _mdf_deliv_legacy.ado — the v10.2.0 Deliverables package, kept verbatim
*! version 11.0.0   github.com/adinkhan7/master-do-file
*!
*!  Called by mdf_deliverables when the project's Processing DO is still on a
*!  pre-v11 template (ADR-059). Such a file cannot recognise the v11 package
*!  layout, but it CAN rebuild from the flat v10.2.0 package on standalone
*!  mode — so that is what it gets, exactly as 10.2.0 built it, until its .new
*!  has been merged. The body below is 10.2.0's mdf_deliverables unchanged.
*!
*!  Lives in its own file: a program cannot be defined inside another ado.

program define _mdf_deliv_legacy
    version 16

    di as result _n "--- Building the Deliverables package ---"

    local _dlv "$ROOT/Deliverables"
    _hfc_mkdir "`_dlv'"
    _hfc_mkdir "`_dlv'/Data"
    _hfc_mkdir "`_dlv'/CAPI"
    _hfc_mkdir "`_dlv'/Clean_Reference"

    *==============================================================================*
    *  1  THE RAW DATA THE WORKFLOW READS
    *==============================================================================*
    *  From the run folder's Raw/ snapshot, which is what this run actually
    *  processed — not 02_Data/, which is whatever happens to be sitting there
    *  today. The date stamp is dropped so the package's dataset names match the
    *  project's, and standalone discovery therefore derives the same DS names.
    local _n_data 0
    local _raws : dir "$hfc_raw_snapshot_dir" files "*.dta", respectcase
    local _raws : list sort _raws
    foreach _f of local _raws {
        if strpos("`_f'", "_CLEANED")  > 0 continue
        if strpos("`_f'", "_LABELED_") > 0 continue
        if strpos("`_f'", "_MERGED_")  > 0 continue
        local _base = subinstr("`_f'", ".dta", "", 1)
        local _base = subinstr("`_base'", "_$hfc_folder_date", "", 1)
        cap copy "$hfc_raw_snapshot_dir/`_f'" "`_dlv'/Data/`_base'.dta", replace
        if !_rc {
            local _n_data = `_n_data' + 1
            di as result "  data       → Data/`_base'.dta"
        }
        else di as error "  WARNING: could not copy `_f' into the package."
    }

    if `_n_data' == 0 {
        di as error "  No raw dataset found in $hfc_raw_snapshot_dir — package not built."
        di as txt   "  Run the pipeline once with data present, then set run_deliverables = 1."
        exit
    }

    *==============================================================================*
    *  2  THE WORKFLOW ITSELF
    *==============================================================================*
    *  The Processing DO and the two modules it calls by name. These are the
    *  runtime dependencies of the workflow, and the only DOs the package needs:
    *  every other stage belongs to Master, which the client never runs.
    cap copy "$processing_dir/$processing_file" "`_dlv'/$processing_file", replace
    if !_rc di as result "  workflow   → $processing_file"
    else    di as error  "  WARNING: could not copy $processing_file into the package."

    foreach _m in "01_Labeling.do" "02_Translation.do" {
        cap confirm file "$dofiles_dir/`_m'"
        if !_rc {
            cap copy "$dofiles_dir/`_m'" "`_dlv'/`_m'", replace
            if !_rc di as result "  module     → `_m'"
        }
    }

    *==============================================================================*
    *  3  THE INSTRUMENT
    *==============================================================================*
    *  Labeling reads $capi_dir. Single-dataset projects keep the form at the top
    *  of 02_CAPI/; multi-dataset projects keep one subfolder per form and the
    *  module resolves by folder name, so the subfolder names have to survive.
    *  Archive/ and Excel lock files deliberately do not travel.
    local _n_capi 0
    local _forms : dir "$capi_dir" files "*.xlsx", respectcase
    foreach _f of local _forms {
        if substr("`_f'", 1, 1) == "~" continue
        cap copy "$capi_dir/`_f'" "`_dlv'/CAPI/`_f'", replace
        if !_rc local _n_capi = `_n_capi' + 1
    }
    local _subs : dir "$capi_dir" dirs "*", respectcase
    foreach _s of local _subs {
        if "`_s'" == "Archive" continue
        _hfc_mkdir "`_dlv'/CAPI/`_s'"
        local _sf : dir "$capi_dir/`_s'" files "*.xlsx", respectcase
        foreach _f of local _sf {
            if substr("`_f'", 1, 1) == "~" continue
            cap copy "$capi_dir/`_s'/`_f'" "`_dlv'/CAPI/`_s'/`_f'", replace
            if !_rc local _n_capi = `_n_capi' + 1
        }
    }
    di as result "  instrument → CAPI/ (`_n_capi' form(s))"

    *==============================================================================*
    *  4  TRANSLATION MATERIAL, WHERE THE WORKFLOW NEEDS IT
    *==============================================================================*
    *  Only when the workflow actually re-injects translations. Without the
    *  returned files the client's run would silently reproduce a dataset with
    *  untranslated text, which is the one outcome worth travelling for.
    if "$inputcorrection" == "1" | "$exportopenended" == "1" {
        _hfc_mkdir "`_dlv'/Translation"
        _hfc_mkdir "`_dlv'/Translation/01_Exported"
        _hfc_mkdir "`_dlv'/Translation/02_Translated"
        local _n_trans 0
        foreach _leg in "01_Exported" "02_Translated" {
            local _tdirs : dir "$translation_dir/`_leg'" dirs "*", respectcase
            foreach _td of local _tdirs {
                _hfc_mkdir "`_dlv'/Translation/`_leg'/`_td'"
                local _tf : dir "$translation_dir/`_leg'/`_td'" files "*.xlsx", respectcase
                foreach _f of local _tf {
                    if substr("`_f'", 1, 1) == "~" continue
                    cap copy "$translation_dir/`_leg'/`_td'/`_f'" "`_dlv'/Translation/`_leg'/`_td'/`_f'", replace
                    if !_rc local _n_trans = `_n_trans' + 1
                }
            }
        }
        di as result "  translation→ Translation/ (`_n_trans' file(s))"
    }

    *==============================================================================*
    *  5  THE REFERENCE OUTPUT
    *==============================================================================*
    *  What the managed run produced, so the client can check their reproduction
    *  against it. It lives outside Data/ on purpose: standalone discovery looks
    *  in the package root and then Data/, so a reference copy can never be
    *  mistaken for an input.
    local _n_clean 0
    local _cln : dir "$clean_dir" files "*_CLEANED.dta", respectcase
    foreach _f of local _cln {
        cap copy "$clean_dir/`_f'" "`_dlv'/Clean_Reference/`_f'", replace
        if !_rc local _n_clean = `_n_clean' + 1
    }
    di as result "  reference  → Clean_Reference/ (`_n_clean' dataset(s))"

    *==============================================================================*
    *  6  HOW TO REPRODUCE IT
    *==============================================================================*
    tempname _rf
    cap file close `_rf'
    file open `_rf' using "`_dlv'/README.txt", write text replace
    file write `_rf' "$project_name — reproducible processing package"                    _n
    file write `_rf' "Built $hfcsys_long by Master DO File $hfc_version."                 _n _n
    file write `_rf' "WHAT THIS IS"                                                       _n
    file write `_rf' "  Everything needed to reproduce the clean dataset from the raw"    _n
    file write `_rf' "  survey data, and nothing else. It does not contain the project's" _n
    file write `_rf' "  daily download folders, its check history, or its working files." _n _n
    file write `_rf' "HOW TO REPRODUCE"                                                   _n
    file write `_rf' "  1. Copy this whole folder wherever you like. It has no link to"   _n
    file write `_rf' "     the project it came from and no path inside it is fixed."      _n
    file write `_rf' "  2. Open $processing_file in Stata."                               _n
    file write `_rf' "  3. Select all (Ctrl+A) and execute (Ctrl+D)."                     _n
    file write `_rf' "     If you run it that way, first make sure Stata's working"       _n
    file write `_rf' "     directory is this folder: File > Change working directory."    _n
    file write `_rf' "     Launching Stata by double-clicking the DO does that for you."  _n
    file write `_rf' "  4. The rebuilt dataset(s) appear in MDF_Output/."                 _n _n
    file write `_rf' "CHECKING THE RESULT"                                                _n
    file write `_rf' "  Clean_Reference/ holds what the original run produced. To"        _n
    file write `_rf' "  confirm your rebuild matches, in Stata:"                          _n
    file write `_rf' `"      use "Clean_Reference/<name>_CLEANED.dta", clear"'          _n
    file write `_rf' "      datasignature"                                                _n
    file write `_rf' `"      use "MDF_Output/<name>_CLEANED.dta", clear"'                  _n
    file write `_rf' "      datasignature"                                                _n
    file write `_rf' "  The two signatures should be identical."                          _n _n
    file write `_rf' "WHAT IS IN HERE"                                                    _n
    file write `_rf' "  $processing_file    the processing workflow"                      _n
    file write `_rf' "  01_Labeling.do             applies the questionnaire's labels"    _n
    file write `_rf' "  02_Translation.do          re-injects translated open-ended text" _n
    file write `_rf' "  Data/                      the raw survey dataset(s)"             _n
    file write `_rf' "  CAPI/                      the questionnaire the data came from"  _n
    file write `_rf' "  Translation/               translated text, where it was used"    _n
    file write `_rf' "  Clean_Reference/           the original run's clean dataset(s)"   _n
    file write `_rf' "  MDF_Output/                created when you run it"               _n _n
    file write `_rf' "WHAT YOU NEED"                                                      _n
    file write `_rf' "  Stata 16 or newer. The Master DO File framework is NOT required"  _n
    file write `_rf' "  and does not need installing."                                    _n
    file write `_rf' "  Two survey packages are needed only for the steps that use them:" _n
    file write `_rf' "    odksplit         to apply the questionnaire's value labels"     _n
    file write `_rf' "    inputcorrection  to re-inject translated text"                  _n
    file write `_rf' "  Without them those steps say so and are skipped; the rest of the" _n
    file write `_rf' "  workflow still runs, but the result will not match the reference." _n
    file close `_rf'

    di as result "  readme     → README.txt"
    di as result "  Deliverables package ready → $ROOT/Deliverables"
end
