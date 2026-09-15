{smcl}
{* *! version 10.2.0  15sep2026}{...}
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
{synopt :{bf:mdf_paths}}run dates and every folder path global{p_end}
{synopt :{bf:mdf_folders}}create the project folder tree{p_end}
{synopt :{bf:mdf_readme}}write the project README{p_end}
{synopt :{bf:mdf_resolve}}post-field resolution{p_end}
{synopt :{bf:mdf_workdirs}}today's raw-data folder and HFC run folder{p_end}
{synopt :{bf:mdf_log}}open the run log and detect the run type{p_end}
{synopt :{bf:mdf_generate}}00_Directory.do / 00b_Local_Overrides.do, output paths, previous keys{p_end}
{synopt :{bf:mdf_import}}carry the import DO forward, fingerprint it, import{p_end}
{synopt :{bf:mdf_modules}}pipeline modules, the HFC DO and the Processing DO{p_end}
{synopt :{bf:mdf_guards}}stale-processing and open-workbook guards{p_end}
{synopt :{bf:mdf_stage}}archive raw data and stage the working copy{p_end}
{synopt :{bf:mdf_instruments}}CAPI subfolders, instrument archiving, translation folders{p_end}
{synopt :{bf:mdf_clean}}run cleaning{p_end}
{synopt :{bf:mdf_hfc}}run the high-frequency checks{p_end}
{synopt :{bf:mdf_audio}}audio audit{p_end}
{synopt :{bf:mdf_keys}}archive keys and print the run summary{p_end}
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
A project's {bf:04_DO Files/} therefore holds five files, not eight: the
Master-owned {bf:00_Directory.do}, and the four an analyst may edit —
{bf:00b_Local_Overrides.do}, {bf:01_Labeling.do}, {bf:02_Translation.do} and
{bf:03_Audio.do}.


{marker remarks}{...}
{title:Remarks}

{pstd}
{bf:Stopping cleanly.} {cmd:exit} inside an ado returns from the ado, not from
Master. Real errors are non-zero returns and propagate on their own, but the
three {it:clean} stops — Run 1, the CAPI pause and the Ghost Run pause — set
{bf:$mdf_halt}, and every later stage stands down when it sees it.

{pstd}
{bf:Version pinning.} Master pins the framework it was written against in
{bf:$mdf_required}. {cmd:mdf_setup} compares that against the installed version
and updates only on a mismatch, so once the right version is present no network
call is made and field runs work offline. Set {bf:$mdf_autoinstall 0} to
suppress updating entirely.

{pstd}
{bf:Offline behaviour is not uniform.} A framework that will not run at all is a
hard stop. A version mismatch that cannot be repaired because GitHub is
unreachable is a loud warning and the run continues — fieldwork happens on bad
connections.

{pstd}
{bf:clear all and the helpers.} Every SurveyCTO import DO issues {cmd:clear all},
which drops programs and wipes Mata but leaves globals standing. Because the
helpers ({bf:_hfc_abort}, {bf:_hfc_pause}, {bf:_hfc_mkdir}, {bf:_hfc_hide}) are
ado files on the adopath, Stata reloads them on demand. Master used to carry
four identical copies of each for this reason and now carries none.


{title:Author}

{pstd}
Adin Khan{break}
Development Research Initiative (dRi){break}
{browse "https://github.com/adinkhan7/master-do-file":github.com/adinkhan7/master-do-file}


{title:Also see}

{psee}
Help:  {helpb net}, {helpb adopath}
{p_end}
