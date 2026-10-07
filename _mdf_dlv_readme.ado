*! _mdf_dlv_readme.ado — the README a Deliverables package opens with (ADR-061)
*! version 11.1.3   github.com/adinkhan7/master-do-file
*!
*!  One per dataset package: what is in it, how to rebuild the cleaned dataset,
*!  and what the rebuild checks before it does. Written by mdf_deliverables.
*!
*!  Lives in its own file: a program cannot be defined inside another ado.

program define _mdf_dlv_readme
    version 16
    args _pk _nm _k _nds

    local _title "$project_name"
    if `_nds' > 1 local _title "$project_name — DS`_k': `_nm'"

    tempname _fh
    cap file open `_fh' using `"`_pk'/README.md"', write replace text
    if _rc {
        di as error "    NOT WRITTEN: README.md"
        global hfcsys_dlv_fail = $hfcsys_dlv_fail + 1
        exit 0
    }
    file write `_fh' "# `_title' — Deliverables package" _n _n
    file write `_fh' "Built on $hfcsys_long by Master DO File $hfc_version. Dataset: **`_nm'**." _n _n
    file write `_fh' "| Folder | What it holds |" _n
    file write `_fh' "|---|---|" _n
    file write `_fh' "| 01_CAPI & Questionnaire/ | the SurveyCTO form the data were labelled with, and the questionnaire |" _n
    file write `_fh' "| 02_Import & Raw files/ | the raw dataset, and the import DO and CSV export that produced it |" _n
    file write `_fh' "| 03_Processing Files/ | $processing_file, which rebuilds the cleaned dataset, and what it calls |" _n
    file write `_fh' "| 04_Cleaned Data/ | the cleaned dataset |" _n _n
    file write `_fh' "## Rebuilding the cleaned dataset" _n _n
    file write `_fh' "1. Keep this folder at a short path, e.g. C:\Projects\. Windows cannot open files whose" _n
    file write `_fh' "   full path is longer than 260 characters." _n
    file write `_fh' "2. In Stata (16 or newer), make 03_Processing Files/ the working directory" _n
    file write `_fh' "   (File > Change Working Directory), or open Stata by double-clicking the Processing DO." _n
    file write `_fh' "3. Open $processing_file and run it (Ctrl+A, then Ctrl+D)." _n _n
    file write `_fh' "Before it runs, it checks that it is inside this package, that the raw dataset is the one" _n
    file write `_fh' "the package was built from, and that every setting comes from the package itself — nothing" _n
    file write `_fh' "from the Stata session or the machine. Anything wrong stops the run with an explanation." _n
    file write `_fh' "It then writes the cleaned dataset to 04_Cleaned Data/ and reports whether it is identical" _n
    file write `_fh' "to the one shipped (a shipped copy that differs is kept as *_CLEANED_REFERENCE.dta)." _n _n
    file write `_fh' "No installation of the Master DO File framework is needed. The survey commands the" _n
    file write `_fh' "processing uses (odksplit, inputcorrection and any the cleaning names) are installed" _n
    file write `_fh' "automatically when missing, which needs an internet connection." _n _n
    local _tr "02_Translation/"
    if `_nds' > 1 {
        local _nn : display %02.0f `_k'
        local _tr "02_Translation/`_nn'_`_nm'/"
    }
    file write `_fh' "## Looking at the data step by step" _n _n
    file write `_fh' "In $processing_file each dataset's block opens with a line under **LOAD DATASET**." _n
    file write `_fh' "Run section 0. INITIALISE once (select it, Ctrl+D), then select that one line and press" _n
    file write `_fh' "Ctrl+D: the dataset's raw data is in memory, and the steps below it can be run one at a" _n
    file write `_fh' "time. A full run of the file skips the line." _n _n
    file write `_fh' "## Where to look" _n _n
    file write `_fh' "- The cleaning itself: $processing_file, sections marked **SAFE TO EDIT**." _n
    file write `_fh' "- Labels added by hand: 01_Do Files/01_Labeling.do, section MANUAL LABELING." _n
    file write `_fh' "- Translation corrections added by hand: 01_Do Files/02_Translation.do." _n
    file write `_fh' "- Returned translation files: 03_Processing Files/`_tr' (absent if there were none)." _n _n
    file write `_fh' "## Keep the package whole" _n _n
    file write `_fh' "The framework code the DO files call is in 03_Processing Files/01_Do Files/_mdf/, a" _n
    file write `_fh' "hidden folder: nothing in it is for editing, but the package cannot run without it. Copy" _n
    file write `_fh' "or zip the whole package folder with File Explorer (Send to > Compressed folder) or" _n
    file write `_fh' "7-Zip. PowerShell's Compress-Archive leaves hidden folders out." _n
    file close `_fh'
end
