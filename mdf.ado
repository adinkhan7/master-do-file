*! mdf.ado — Master DO File framework
*! version 11.1.1   github.com/adinkhan7/master-do-file
*!
*!  `mdf run` executes every stage in order. Master normally lists the stages
*!  itself instead, so the pipeline is visible and any one stage can be re-run
*!  on its own while debugging.

program define mdf, rclass
    version 16
    gettoken _sub _rest : 0

    if `"`_sub'"' == "version" | `"`_sub'"' == "" {
        di as result "mdf 11.1.1"
        return local version "11.1.1"
        exit 0
    }

    if `"`_sub'"' != "run" {
        di as error `"mdf: unknown subcommand "`_sub'"  — expected: run | version"'
        exit 198
    }

    mdf_setup
    mdf_validate
    mdf_paths
    mdf_folders
    mdf_readme
    mdf_resolve
    mdf_workdirs
    mdf_log
    mdf_generate
    mdf_import
    mdf_modules
    mdf_guards
    mdf_stage
    mdf_instruments
    mdf_clean
    mdf_hfc
    mdf_audio
    mdf_keys
    mdf_deliverables

    return local version "11.1.1"
end
