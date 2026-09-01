{smcl}
{* *! version 10.1.0  01sep2026}{...}
{vieweralsosee "[R] net" "help net"}{...}
{viewerjumpto "Syntax" "mdfgen##syntax"}{...}
{viewerjumpto "Description" "mdfgen##description"}{...}
{viewerjumpto "Inputs" "mdfgen##inputs"}{...}
{viewerjumpto "Remarks" "mdfgen##remarks"}{...}
{viewerjumpto "Examples" "mdfgen##examples"}{...}
{title:Title}

{phang}
{bf:mdfgen} {hline 2} code-generation layer for the Master DO File survey pipeline


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:mdfgen} {it:subcommand}

{synoptset 16 tabbed}{...}
{synopthdr:subcommand}
{synoptline}
{synopt :{opt directory}}write {bf:00_Directory.do}, {bf:00a_Bootstrap.do} and
{bf:00b_Local_Overrides.do} into {bf:$mdfgen_dodir}{p_end}
{synopt :{opt modules}}write the pipeline modules, the project HFC DO file and
the Processing DO file{p_end}
{synopt :{opt version}}display the installed package version{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:mdfgen} writes the Stata DO files that a Master DO File project runs. It is
the code-generation layer that {bf:Master_DO_File.do} used to carry inline as
roughly 2,650 lines of Mata.

{pstd}
Moving it into a package means a project's Master file no longer has to carry
the generator, the generator can be fixed once and picked up everywhere by
{helpb net:net install}, and a run's log is no longer flooded with the
generator's own Mata source.

{pstd}
{cmd:mdfgen} is not intended to be run by hand. {bf:Master_DO_File.do} sets the
inputs and calls it. It is documented here so that the contract is inspectable.


{marker inputs}{...}
{title:Inputs}

{pstd}
Inputs are passed as {bf:globals}, not as options. This is deliberate: project
paths routinely contain spaces and parentheses (for example
{bf:Demo Project (Multi Dataset)}), and Stata's {helpb syntax} option parser
cannot carry such values intact.

{synoptset 22 tabbed}{...}
{synopthdr:global}
{synoptline}
{synopt :{bf:mdfgen_pname}}project name{p_end}
{synopt :{bf:mdfgen_ssize}}sample size{p_end}
{synopt :{bf:mdfgen_meta}}front metadata variable list{p_end}
{synopt :{bf:mdfgen_tail}}tail variable list{p_end}
{synopt :{bf:mdfgen_tstart}}timer start variable{p_end}
{synopt :{bf:mdfgen_tend}}timer end variable{p_end}
{synopt :{bf:mdfgen_nds}}dataset count to expand loops to{p_end}
{synopt :{bf:mdfgen_dodir}}target folder for the DO files{p_end}
{synopt :{bf:mdfgen_hfcdir}}project {bf:03_HFC} folder{p_end}
{synopt :{bf:mdfgen_tver}}framework version stamped into generated files{p_end}
{synopt :{bf:mdfgen_procdir}}project {bf:06_Processing Files} folder{p_end}
{synopt :{bf:mdfgen_procfile}}file name of the Processing DO ({cmd:modules} only){p_end}
{synoptline}

{pstd}
{cmd:mdfgen} additionally reads the Section 0 configuration globals
({bf:meta_ids}, {bf:merge_required}, {bf:audio_seed}, {bf:hfc_openended_vars} and
the rest) directly from the global scope, exactly as the in-Master blocks did.

{pstd}
A missing required global is an error, not a silently truncated file.


{marker remarks}{...}
{title:Remarks}

{pstd}
{bf:Reloading after clear all.} {cmd:clear all} wipes Mata but leaves globals
standing, so {cmd:mdfgen} probes Mata itself rather than trusting a "loaded"
flag. The Mata layer is recompiled on demand whenever it has gone away. This
matters because SurveyCTO import DO files issue {cmd:clear all}, and Master
calls {cmd:mdfgen} on both sides of that boundary.

{pstd}
{bf:Output is byte-identical} to the Mata blocks it replaces. The generator
source was relocated verbatim; only the surrounding wrapper changed.


{marker examples}{...}
{title:Examples}

{pstd}Install or update:{p_end}
{phang2}{cmd:. net install mdfgen, from("https://raw.githubusercontent.com/adinkhan7/master-do-file/main") replace}{p_end}

{pstd}Check the installed version:{p_end}
{phang2}{cmd:. mdfgen version}{p_end}

{pstd}Generate (as Master does it):{p_end}
{phang2}{cmd:. global mdfgen_pname "My Project"}{p_end}
{phang2}{cmd:. global mdfgen_dodir "`c(pwd)'/04_DO Files"}{p_end}
{phang2}{cmd:. mdfgen directory}{p_end}


{title:Author}

{pstd}
Adin Khan{break}
Development Research Initiative (dRi){break}
{browse "https://github.com/adinkhan7/master-do-file":github.com/adinkhan7/master-do-file}


{title:Also see}

{psee}
Help:  {helpb net}, {helpb adopath}
{p_end}
