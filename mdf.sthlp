{smcl}
{* *! version 11.1.0  29sep2026}{...}
{vieweralsosee "[R] net" "help net"}{...}
{viewerjumpto "Syntax" "mdf##syntax"}{...}
{viewerjumpto "Description" "mdf##description"}{...}
{viewerjumpto "Stages" "mdf##stages"}{...}
{viewerjumpto "Remarks" "mdf##remarks"}{...}
{title:Title}

{phang}
{bf:mdf} {hline 2} the Master DO File survey pipeline framework


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}{cmd:mdf run}{p_end}
{p 8 17 2}{cmd:mdf version}{p_end}

{pstd}
or, as a project's {bf:Master_DO_File.do} normally does it, one stage at a time:

{p 8 17 2}{cmd:mdf_setup}{break}{cmd:mdf_validate}{break}{cmd:mdf_paths}{break}{it:...}{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:mdf} is the machinery behind a Master DO File project. A project's
{bf:Master_DO_File.do} contains only {bf:Section 0} — the switches an analyst
edits — and the list of pipeline stages. Everything under the hood is installed
from
{browse "https://github.com/adinkhan7/master-do-file":github.com/adinkhan7/master-do-file}.

{pstd}
The framework builds the project folder tree, imports and archives SurveyCTO
data, applies CAPI value labels, runs High-Frequency Checks, manages the
open-ended translation round trip, optionally merges paired datasets, and
writes every pipeline DO file the project runs.

{pstd}
Stages are listed individually in Master rather than hidden behind
{cmd:mdf run} on purpose: the pipeline stays readable, and any single stage can
be re-run from the Command window while debugging, once Master has been run
once in that session.


{marker stages}{...}
{title:Stages, in execution order}

{synoptset 20 tabbed}{...}
{synopthdr:stage}
{synoptline}
{synopt :{bf:mdf_setup}}helper programs, ROOT resolution, framework version check{p_end}
{synopt :{bf:mdf_validate}}Section 0 sanity checks and switch defaults{p_end}
{synopt :{bf:mdf_paths}}run dates, the project's folder layout, every folder path global{p_end}
{synopt :{bf:mdf_folders}}create the project folder tree{p_end}
{synopt :{bf:mdf_readme}}write the project README{p_end}
{synopt :{bf:mdf_resolve}}post-field resolution{p_end}
{synopt :{bf:mdf_workdirs}}today's raw-data folder and HFC run folder{p_end}
{synopt :{bf:mdf_log}}open the run log and detect the run type{p_end}
{synopt :{bf:mdf_generate}}the directory file and overrides, output paths, previous keys{p_end}
{synopt :{bf:mdf_import}}carry the import DO forward, fingerprint it, import{p_end}
{synopt :{bf:mdf_modules}}pipeline modules, the HFC DO and the Processing DO{p_end}
{synopt :{bf:mdf_guards}}stale-processing and open-workbook guards{p_end}
{synopt :{bf:mdf_stage}}archive raw data and stage the working copy{p_end}
{synopt :{bf:mdf_instruments}}CAPI subfolders, instrument archiving, translation folders{p_end}
{synopt :{bf:mdf_clean}}run cleaning{p_end}
{synopt :{bf:mdf_hfc}}run the high-frequency checks{p_end}
{synopt :{bf:mdf_audio}}audio audit{p_end}
{synopt :{bf:mdf_keys}}archive keys and print the run summary{p_end}
{synopt :{bf:mdf_deliverables}}build the client handover package (run_deliverables = 1){p_end}
{synoptline}

{pstd}
Three further commands are called by the {it:generated} pipeline files rather
than by Master, and replace DO files those projects used to carry:

{synoptset 20 tabbed}{...}
{synopt :{bf:mdf_bootstrap}}load a project's globals from inside a generated module (was {bf:00a_Bootstrap.do}){p_end}
{synopt :{bf:mdf_core_vars}}derive {bf:fielddate} / {bf:total_duration} (was {bf:05_Core_Variables.do}){p_end}
{synopt :{bf:mdf_finalise}}post-cleaning merge and publish (was {bf:04_Finalise.do}){p_end}
{synoptline}

{pstd}
{bf:The project folder.} A project created by 11.x has eight folders in the
order the work flows: {bf:01_Questionnaire}, {bf:02_CAPI}, {bf:03_Data},
{bf:04_Others}, {bf:05_Processing} (the Processing DO, with {bf:01_Do Files},
{bf:02_Translation} and {bf:03_Data} inside it), {bf:06_HFC},
{bf:07_Cleaned Dataset} and {bf:08_Deliverables}. A project built by an earlier
version keeps its own folders: the layout is read from the hidden
{bf:.hfc_root} sentinel and nothing is moved.


{marker remarks}{...}
{title:Remarks}

{pstd}
{bf:Stopping cleanly.} {cmd:exit} inside an ado returns from the ado, not from
Master. Real errors are non-zero returns and propagate on their own, but the
three {it:clean} stops — Run 1, the CAPI pause and the Ghost Run pause — set
{bf:$mdf_halt}, and every later stage stands down when it sees it.

{pstd}
{bf:Version pinning.} Master pins the framework it was written against in
{bf:$mdf_required}. An installed framework {it:older} than that is updated, and
if it cannot be the run stops before doing anything. One {it:newer} than that
is a warning and the run continues, which is how a 10.2.0 project keeps working
on a machine with 11.1.0. Set {bf:$mdf_autoinstall 0} to suppress updating.

{pstd}
{bf:clear all and the helpers.} Every SurveyCTO import DO issues {cmd:clear all},
which drops programs and wipes Mata but leaves globals standing. The helpers are
ado files on the adopath, so Stata reloads them on demand.

{pstd}
{bf:Where a generated DO file runs.} Its {bf:0. INITIALISE} block searches upward
from the working directory for its Deliverables package (which holds
{bf:_mdf/mdf_runtime.do}) or its project ({bf:.hfc_root}), and accepts what it finds
only if it is {it:its own} project, by name. In a project, {cmd:mdf_bootstrap} loads
the directory file; in a package, the package's runtime loads the package's own
settings ({bf:_mdf/mdf_package.do}) and checks the raw data by name and by
{cmd:datasignature}. Neither ever takes a context left in the Stata session by
another project or package. Anywhere else the Processing, Labeling, Translation and
Audio DOs stop and say so; the HFC DO still runs on the {bf:.dta} file(s) beside it,
writing to {bf:MDF_Output/}.

{pstd}
{bf:What an analyst edits.} Every generated DO file marks its sections
{bf:[SAFE TO EDIT]} or {bf:[MDF GENERATED - DO NOT EDIT]}. Manual labels go in
{bf:01_Labeling.do} (MANUAL LABELING), manual translation corrections in
{bf:02_Translation.do} (MANUAL TRANSLATION OVERRIDES). The engines behind them are
framework files in {bf:01_Do Files/_mdf/}, rewritten on every run. The file headers
take {bf:$project_lead}, {bf:$project_email}, {bf:$organisation} and
{bf:$project_description} from Section 0.

{pstd}
{bf:The working directory.} Stata does not tell a running DO file where it is
saved: {cmd:c(do_current)} is empty in Stata 17 from the Do button, from
Ctrl+A / Ctrl+D and from a nested {cmd:do}. Every generated file therefore starts
from the working directory. Double-clicking the DO to launch Stata sets it;
otherwise use File > Change working directory.

{pstd}
{bf:Deliverables.} With {bf:$run_deliverables 1}, {cmd:mdf_deliverables} rebuilds
{bf:08_Deliverables/}: {bf:01_CAPI & Questionnaire}, {bf:02_Import & Raw files},
{bf:03_Processing Files} and {bf:04_Cleaned Data} — once per dataset, under
{bf:NN_<dataset>/}, when there are several. Copied anywhere, the Processing DO
inside rebuilds the cleaned dataset with no project and no framework installed,
from the package's own runtime and settings, and reports whether the result is
identical to the cleaned dataset shipped with it (REPRODUCED). A file that cannot
be copied in, or a path too long for Windows, is named and the build ends with an
error.

{pstd}
{bf:Reproducible cleaning.} Each dataset block of the Processing DO fixes
Stata's sort tie-breaking ({cmd:set sortseed}) before it starts, so a
{cmd:duplicates drop} keeps the same row wherever the file runs.


{title:Author}

{pstd}
Adin Khan{break}
Development Research Initiative (dRi){break}
{browse "https://github.com/adinkhan7/master-do-file":github.com/adinkhan7/master-do-file}


{title:Also see}

{psee}
Help:  {helpb net}, {helpb adopath}
{p_end}
