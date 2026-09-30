*! _mdf_defs.ado — the Mata layer for the Master DO File framework
*! version 11.1.0   github.com/adinkhan7/master-do-file
*!
*!  Loaded on demand by _mdf_load.ado. Never run this file directly.
*!
*!  Why .ado and not .do: `net install` ships only a package's PROGRAM files.
*!  A .do is classed as ancillary and left for `net get`, so it would never
*!  reach the adopath. Nothing here defines an ado-command; the extension is
*!  the only reason.
*!
*!  Contents:
*!    _hfc_find_root / _hfc_scan_locks / _hfc_rename_dir   framework helpers
*!    mdf_directory_main()                                 writes the directory file
*!                                                         (00a_Directory.do in v11,
*!                                                         00_Directory.do in v10)
*!                                                         and 00b_Local_Overrides.do
*!    mdf_modules_main()                                   writes the pipeline modules,
*!                                                         the HFC DO and Processing.do
*!  The generator functions were lifted verbatim out of Master 10.1.0-rc1
*!  Sections 10 and 14 and produce byte-identical output.

*  matastrict is forced off while these compile: the generator driver code used
*  to run at Mata's interactive level, where matastrict does not apply, and
*  wrapping it in a function brings it under the setting for the first time.
local _mdf_ms = c(matastrict)
mata: mata set matastrict off

mata:

//  probe: _mdf_load calls this to decide whether a (re)load is needed
void mdf_probe()
{
    return
}

string scalar _hfc_find_root(string scalar start, real scalar maxup)
{
    string scalar p
    real scalar i, j

    p = subinstr(start, "\", "/", .)
    if (strlen(p) > 1 & substr(p, -1, 1) == "/") p = substr(p, 1, strlen(p) - 1)

    for (i = 0; i <= maxup; i++) {
        if (fileexists(p + "/.hfc_root")) return(p)
        j = strrpos(p, "/")
        if (j <= 0) break
        p = substr(p, 1, j - 1)
        if (strlen(p) < 3) break          // reached a drive root such as "C:"
    }
    return("")
}

void _hfc_scan_locks(string scalar d)
{
    string colvector f, sub
    string scalar    acc
    real scalar      i, n
    if (!direxists(d)) return
    acc = st_global("hfc_capi_locks")
    n   = strtoreal(st_global("hfc_capi_nlock"))
    f = dir(d, "files", "*.xlsx")
    for (i = 1; i <= length(f); i++) {
        if (substr(f[i], 1, 2) == "~$") {
            n = n + 1
            acc = acc + (acc == "" ? "" : " ") + subinstr(f[i], "~$", "", 1)
        }
    }
    st_global("hfc_capi_locks", acc)
    st_global("hfc_capi_nlock", strofreal(n))
    sub = dir(d, "dirs", "*")
    for (i = 1; i <= length(sub); i++) _hfc_scan_locks(d + "/" + sub[i])
}

void _hfc_rename_dir(string scalar old_p, string scalar new_p)
{
    real scalar i
    string colvector flist
    string scalar dq, src, dst

    dq = char(34)
    if (!direxists(old_p)) {
        errprintf("_hfc_rename_dir: source directory not found: %s\n", old_p)
        exit(198)
    }
    if (!direxists(new_p)) mkdir(new_p)

flist = dir(old_p, "files", "*")
    for (i = 1; i <= rows(flist); i++) {
        src = old_p + "/" + flist[i]
        dst = new_p + "/" + flist[i]
        stata("copy " + dq + src + dq + " " + dq + dst + dq + ", replace")
        if (!fileexists(dst)) {
            errprintf(
                "_hfc_rename_dir: copy failed for '%s'. Source directory left intact to prevent data loss.\n",
                flist[i])
            exit(198)
        }
        unlink(src)
    }
    rmdir(old_p)
}

//  A path global relative to ROOT ("03_HFC/KEYS"; "" for ROOT itself), and
//  the string a generated file carries for it ("<dollar>ROOT/03_HFC/KEYS").
//  The dollar sign is built with char(36): this file is run with -do-, which
//  expands macros in these lines, and a literal one would bake the author's
//  ROOT into every generated file.
string scalar _mdf_rel(string scalar g)
{
    string scalar r, v
    r = subinstr(st_global("ROOT"), char(92), "/", .)
    v = subinstr(st_global(g), char(92), "/", .)
    if (v == r) return("")
    if (substr(v, 1, strlen(r) + 1) == r + "/") return(substr(v, strlen(r) + 2, .))
    return(v)
}

string scalar _mdf_rpath(string scalar g)
{
    string scalar rel
    rel = _mdf_rel(g)
    if (rel == "") return(char(36) + "ROOT")
    return(char(36) + "ROOT/" + rel)
}

//  Is this .xlsx a SurveyCTO / XLSForm form? It is when its workbook holds a
//  "survey" sheet and a "choices" sheet. Questionnaires kept as spreadsheets
//  have neither, which is what lets a package hold both side by side.
real scalar _mdf_is_xlsform(string scalar path)
{
    real scalar i, n, s, c
    real matrix nm
    string scalar w
    if (!fileexists(path)) return(0)
    if (_stata("qui import excel using " + char(34) + path + char(34) + ", describe", 1)) return(0)
    nm = st_numscalar("r(N_worksheet)")
    if (rows(nm) == 0 | cols(nm) == 0) return(0)
    n = nm[1, 1]
    if (n >= .) return(0)
    s = 0
    c = 0
    for (i = 1; i <= n; i++) {
        w = strlower(strtrim(st_global("r(worksheet_" + strofreal(i) + ")")))
        if (w == "survey")  s = 1
        if (w == "choices") c = 1
    }
    return(s & c)
}

//  Does a text file mention either string (case-insensitive)? Read in Mata:
//  a line read into a Stata macro has its own macro references expanded
//  when it is used, which makes a Stata-level scan of a DO file unreliable.
real scalar _mdf_file_has(string scalar path, string scalar a, string scalar b)
{
    string colvector L
    real scalar n
    if (!fileexists(path)) return(0)
    L = strlower(cat(path))
    n = 0
    if (a != "") n = n + sum(strpos(L, strlower(a)) :> 0)
    if (b != "") n = n + sum(strpos(L, strlower(b)) :> 0)
    return(n > 0)
}

//  Remove a directory tree. Used for exactly one folder — the Deliverables
//  package, which is framework output rebuilt from scratch on every build —
//  and refuses anything that is not a folder of that name directly under a
//  project root carrying a .hfc_root sentinel.
real scalar _mdf_rmtree_guarded(string scalar d, string scalar root)
{
    string scalar leaf
    d    = subinstr(d, char(92), "/", .)
    root = subinstr(root, char(92), "/", .)
    leaf = substr(d, strrpos(d, "/") + 1, .)
    if (root == "" | !fileexists(root + "/.hfc_root")) return(1)
    if (d != root + "/" + leaf) return(1)
    if (leaf != "08_Deliverables" & leaf != "Deliverables") return(1)
    if (!direxists(d)) return(0)
    return(_mdf_rmtree(d))
}

//  A fresh context: every global cleared, except Stata's own (S_ADO is the
//  adopath) and the function-key macros. -macro drop _all- is not the same
//  thing: it drops the caller's LOCAL macros too (measured), and with them
//  the very path it was about to load from (ADR-061).
void _mdf_clear_globals()
{
    string colvector G
    real scalar i
    G = st_dir("global", "macro", "*")
    for (i = 1; i <= rows(G); i++) {
        if (substr(G[i], 1, 2) == "S_") continue
        if (regexm(G[i], "^F[0-9]+$")) continue
        st_global(G[i], "")
    }
}

//  The longest file path under a folder, by characters — what Windows' 260-
//  character limit is measured in (ADR-061).
string scalar _mdf_longest(string scalar root)
{
    string colvector D, F
    string scalar best, d
    real scalar i, j
    D = root
    best = ""
    for (i = 1; i <= rows(D); i++) {
        d = D[i]
        F = dir(d, "files", "*")
        for (j = 1; j <= rows(F); j++) {
            if (ustrlen(d + "/" + F[j]) > ustrlen(best)) best = d + "/" + F[j]
        }
        F = dir(d, "dirs", "*")
        for (j = 1; j <= rows(F); j++) D = D \ (d + "/" + F[j])
    }
    return(best)
}

real scalar _mdf_rmtree(string scalar d)
{
    string colvector f, s
    real scalar i, bad
    bad = 0
    f = dir(d, "files", "*", 1)
    for (i = 1; i <= rows(f); i++) {
        if (_unlink(f[i]) != 0) bad = 1
    }
    s = dir(d, "dirs", "*", 1)
    for (i = 1; i <= rows(s); i++) {
        if (_mdf_rmtree(s[i]) != 0) bad = 1
    }
    if (_rmdir(d) != 0) bad = 1
    return(bad)
}

// ═══════════════════════════════════════════════════════════════════════════
//  PART 1 — generators for 00_Directory.do / 00a_Bootstrap.do / 00b_Overrides
//  (verbatim from Master_DO_File 10.1.0-rc1, Section 10)
// ═══════════════════════════════════════════════════════════════════════════

void write_module_helpers(real scalar fh, string scalar q, string scalar bt,
                          string scalar ap, string scalar dol)
{
    string scalar bs
    bs = char(92)
    fput(fh, "*  ── Helper programs ────────────────────────────────────────────────────────")
    fput(fh, "cap program drop _hfc_abort")
    fput(fh, "program define _hfc_abort")
    fput(fh, "    args msg")
    fput(fh, "    if " + bt + q + bt + "msg" + ap + q + ap + " != " + q + q + " di as error " + bt + q + bt + "msg" + ap + q + ap)
    fput(fh, "    cap log close hfc_master")
    fput(fh, "    exit 198")
    fput(fh, "end")
    fput(fh, "cap program drop _hfc_pause")
    fput(fh, "program define _hfc_pause")
    fput(fh, "    args msg")
    fput(fh, "    if " + bt + q + bt + "msg" + ap + q + ap + " != " + q + q + " di as result " + bt + q + bt + "msg" + ap + q + ap)
    fput(fh, "    cap log close hfc_master")
    fput(fh, "    exit 0")
    fput(fh, "end")
    fput(fh, "cap program drop _hfc_mkdir")
    fput(fh, "program define _hfc_mkdir")
    fput(fh, "    args _path")
    fput(fh, "    cap mkdir " + q + bt + "_path" + ap + q)
    fput(fh, "    mata: st_local(" + q + "_ok" + q + ", strofreal(direxists(" + q + bt + "_path" + ap + q + ")))")
    fput(fh, "    if !" + bt + "_ok" + ap + " {")
    fput(fh, "        di as error " + bt + q + "ERROR: Could not create directory " + bt + "_path" + ap + ". Check permissions." + q + ap)
    fput(fh, "        exit 198")
    fput(fh, "    }")
    fput(fh, "end")
    fput(fh, "")
    fput(fh, "*  ── Hide framework-internal state (.hfc_root, .flag_history) ───────────────")
    fput(fh, "cap program drop _hfc_hide")
    fput(fh, "program define _hfc_hide")
    fput(fh, "    args _path _isdir")
    fput(fh, "    if c(os) != " + q + "Windows" + q + " exit 0")
    fput(fh, "    local _w = subinstr(" + bt + q + bt + "_path" + ap + q + ap + ", " + q + "/" + q + ", " + q + bs + q + ", .)")
    fput(fh, "    cap python: import ctypes; from sfi import Macro as M; _p=M.getLocal(" + q + "_w" + q + "); _a=ctypes.windll.kernel32.GetFileAttributesW(_p); ctypes.windll.kernel32.SetFileAttributesW(_p, (_a|2) if _a!=-1 else 2)")
    fput(fh, "    if _rc {")
    fput(fh, "        if " + q + bt + "_isdir" + ap + q + " == " + q + "1" + q + " cap qui shell attrib +h " + q + bt + "_w" + ap + q + " /d")
    fput(fh, "        else                 cap qui shell attrib +h " + q + bt + "_w" + ap + q + "")
    fput(fh, "    }")
    fput(fh, "end")
}

void write_bootstrap_do(string scalar path, string scalar q, string scalar bt,
                        string scalar ap, string scalar dol, string scalar pname)
{
    real scalar fh
    if (fileexists(path)) unlink(path)
    fh = fopen(path, "w")

    fput(fh, "*==============================================================================*")
    fput(fh, "*  BOOTSTRAP  —  " + pname)
    fput(fh, "*==============================================================================*")
    fput(fh, "*  Tier 1: Master owns this file and overwrites it. Do not edit.")
    fput(fh, "")
    fput(fh, "args _root")
    fput(fh, "")
    fput(fh, "if " + q + dol + "hfc_dofiles_dir" + q + " == " + q + q + " {")
    fput(fh, "    if " + bt + q + bt + "_root" + ap + q + ap + " == " + q + q + " local _root " + q + dol + "ROOT" + q)
    fput(fh, "    do " + bt + q + bt + "_root" + ap + "/04_DO Files/00_Directory.do" + q + ap)
    fput(fh, "}")
    fput(fh, "")

    write_module_helpers(fh, q, bt, ap, dol)

    fclose(fh)
}

//  The switches the processing workflow reads. Until 11.1.0 the directory
//  file left them out, so a DO file run on its own took whatever an earlier
//  run in the same Stata session had left behind (ADR-061). Split out of
//  standalone_block, which is at Mata's string-literal limit.
void _dir_switches(real scalar fh, string scalar q)
{
    fput(fh, "    *  ── Processing switches, as Section 0 set them on the last Master run ───")
    fput(fh, "    global run_labeling    " + q + st_global("run_labeling")    + q)
    fput(fh, "    global inputcorrection " + q + st_global("inputcorrection") + q)
    fput(fh, "    global capi_verbose    " + q + st_global("capi_verbose")    + q)
    fput(fh, "")
}

void _dir_rtdir(real scalar fh, string scalar q, string scalar dol)
{
    fput(fh, "    global mdf_rt_dir           " + q + dol + "dofiles_dir/_mdf" + q)
}

//  The newest dated raw-data folder: what Master calls today's. The directory
//  file never set it, so a module run on its own read it empty (ADR-061).
void _dir_rawdir(real scalar fh, string scalar q, string scalar bt,
                 string scalar ap, string scalar dol)
{
    fput(fh, "    *  ── The newest raw-data folder ───────────────────────────────────────")
    fput(fh, "    local _rdl : dir " + q + dol + "data_dir" + q + " dirs " + q + "*_RAWDATA_*" + q + ", respectcase")
    fput(fh, "    local _rdl : list sort _rdl")
    fput(fh, "    foreach _x of local _rdl {")
    fput(fh, "        global raw_data_dir " + q + dol + "data_dir/" + bt + "_x" + ap + q)
    fput(fh, "    }")
    fput(fh, "")
}

void standalone_block(
    real scalar fh,
    string scalar q, string scalar bt, string scalar ap, string scalar dol,
    string scalar root, string scalar pname, string scalar ssize,
    string scalar meta,  string scalar tail_v,
    string scalar tstart, string scalar tend, string scalar nds,
    real scalar detect_cleaned)
{
    pragma unset root  // root is unused; ROOT is derived at runtime inside the generated block
    pragma unset nds   // nds is unused now that global n_datasets is auto-detected at runtime
    string scalar bs
    bs = char(92)

    fput(fh, "*  ── Auto-skipped when called from Master (globals already set) ─────────────")
    fput(fh, "if " + q + dol + "hfc_dofiles_dir" + q + " == " + q + q + " {")
    fput(fh, "")

    //  ── Core project globals ───────────────────────────────────────────────────
    fput(fh, "    *  ── Core project globals ───────────────────────────────────────────────")
    fput(fh, "    global project_name   " + q + pname + q)
    fput(fh, "    global sample_size    " + ssize)
    fput(fh, "    global meta_front     " + q + meta + q)
    fput(fh, "    global meta_ids       " + q + st_global("meta_ids") + q)
    fput(fh, "    global tail           " + q + tail_v + q)
    fput(fh, "    global timer_start    " + q + tstart + q)
    fput(fh, "    global timer_end      " + q + tend + q)
    fput(fh, "")
    fput(fh, "    *  ── Per-dataset meta overrides ────────────────────────────────────────")
    for (_mk = 1; _mk <= 3; _mk++) {
    fput(fh, "    global meta_front_" + strofreal(_mk) + " " + q + st_global("meta_front_" + strofreal(_mk)) + q)
    fput(fh, "    global meta_ids_" + strofreal(_mk)   + " " + q + st_global("meta_ids_" + strofreal(_mk))   + q)
    fput(fh, "    global tail_" + strofreal(_mk)       + " " + q + st_global("tail_" + strofreal(_mk))       + q)
    }
    fput(fh, "")
    fput(fh, "    global hfc_openended_vars   " + q + st_global("hfc_openended_vars")   + q)
    fput(fh, "    global hfc_openended_vars_1 " + q + st_global("hfc_openended_vars_1") + q)
    fput(fh, "    global hfc_openended_vars_2 " + q + st_global("hfc_openended_vars_2") + q)
    fput(fh, "    global hfc_openended_vars_3 " + q + st_global("hfc_openended_vars_3") + q)
    fput(fh, "    global exportopenended " + q + st_global("exportopenended") + q)
    fput(fh, "")
    fput(fh, "    *  ── CAPI settings (01_Labeling.do reads these) ─────────────────────────")
    fput(fh, "    global capi_language " + q + st_global("capi_language") + q)
    fput(fh, "    global capi_override " + q + st_global("capi_override") + q)
    fput(fh, "    global oe_export_all   " + q + st_global("oe_export_all") + q)
    fput(fh, "")
    _dir_switches(fh, q)
    fput(fh, "    global post_field      " + q + st_global("post_field") + q)
    fput(fh, "    global merge_required  " + q + st_global("merge_required") + q)
    fput(fh, "    global merge_datasets  " + q + st_global("merge_datasets") + q)
    fput(fh, "    global merge_type      " + q + st_global("merge_type") + q)
    fput(fh, "    global merge_key       " + q + st_global("merge_key") + q)
    fput(fh, "")
    fput(fh, "    *  ── Audio configuration ──────────────────────────────────────────────────")
    fput(fh, "    global audio_seed         " + q + st_global("audio_seed")         + q)
    fput(fh, "    global audio_sample_count " + q + st_global("audio_sample_count") + q)
    fput(fh, "    global audio_drop_before  " + q + st_global("audio_drop_before")  + q)
    fput(fh, "    global audio_keep_enums   " + q + st_global("audio_keep_enums")   + q)
    fput(fh, "")
    fput(fh, "    *  ── Sentinel / response codes ─────────────────────────────────────────")
    fput(fh, "    *  Match these to your survey coding scheme (set in Master Section 0).")
    fput(fh, "    global code_dk    " + q + st_global("code_dk")    + q)
    fput(fh, "    global code_na    " + q + st_global("code_na")    + q)
    fput(fh, "    global code_other " + q + st_global("code_other") + q)
    fput(fh, "")
    fput(fh, "    *  ── Verbosity ──────────────────────────────────────────────────────────")
    fput(fh, "    global verbose    " + q + st_global("verbose")    + q)
    fput(fh, "    local _vcap = cond(" + dol + "verbose == 1, " + q + "cap noi" + q + ", " + q + "cap" + q + ")")
    fput(fh, "")

    //  ── Date (YYYYMMDD format) ─────────────────────────────────────────────────
    fput(fh, "    *  ── Date (YYYYMMDD) ────────────────────────────────────────────────────")
    fput(fh, "    local _n = daily(" + q + bt + "c(current_date)" + ap + q + ", " + q + "DMY" + q + ")")
    fput(fh, "    local _f : display %tdCCYYNNDD " + bt + "_n" + ap)
    fput(fh, "    global today = strtrim(" + q + bt + "_f" + ap + q + ")")
    fput(fh, "")

    //  ── Portable ROOT detection ────────────────────────────────────────────────
    fput(fh, "    *  ── Portable ROOT detection ─────────────────────────────────────────")
    fput(fh, "    *  This file lives in ROOT/" + _mdf_rel("dofiles_dir") + "/.")
    fput(fh, "    *  ROOT is derived at run-time — no hardcoded paths.")
    fput(fh, "    if " + q + dol + "ROOT" + q + " == " + q + q + " {")
    fput(fh, "")
    fput(fh, "        cap program drop _hfc_dirof")
    fput(fh, "        program define _hfc_dirof")
    fput(fh, "            local _p = subinstr(" + bt + q + bt + "0" + ap + q + ap + ", " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, "            local _len = length(" + bt + q + bt + "_p" + ap + q + ap + ")")
    fput(fh, "            forvalues _j = " + bt + "_len" + ap + "(-1)1 {")
    fput(fh, "                if substr(" + bt + q + bt + "_p" + ap + q + ap + ", " + bt + "_j" + ap + ", 1) == " + q + "/" + q + " {")
    fput(fh, "                    c_local _dirof = substr(" + bt + q + bt + "_p" + ap + q + ap + ", 1, " + bt + "_j" + ap + " - 1)")
    fput(fh, "                    continue, break")
    fput(fh, "                }")
    fput(fh, "            }")
    fput(fh, "        end")
    fput(fh, "")
    fput(fh, "        local _this_root " + q + q)
    fput(fh, "        local _dirof     " + q + q)
    fput(fh, "")

    //  ── ROOT via the .hfc_root sentinel ────────────────────────────────────────
    fput(fh, "        *  Method 0: .hfc_root sentinel (folder-name independent)")
    fput(fh, "        *  Walks UP until it finds the sentinel. No folder name appears here,")
    fput(fh, "        *  so renaming any folder in the tree cannot break ROOT detection.")
    fput(fh, "        cap mata: mata drop _hfc_find_root()")
    fput(fh, "        mata:")
    fput(fh, "        string scalar _hfc_find_root(string scalar start, real scalar maxup)")
    fput(fh, "        {")
    fput(fh, "            string scalar p")
    fput(fh, "            real scalar i, j")
    fput(fh, "            p = subinstr(start, " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, "            if (strlen(p) > 1 & substr(p, -1, 1) == " + q + "/" + q + ") p = substr(p, 1, strlen(p) - 1)")
    fput(fh, "            for (i = 0; i <= maxup; i++) {")
    fput(fh, "                if (fileexists(p + " + q + "/.hfc_root" + q + ")) return(p)")
    fput(fh, "                j = strrpos(p, " + q + "/" + q + ")")
    fput(fh, "                if (j <= 0) break")
    fput(fh, "                p = substr(p, 1, j - 1)")
    fput(fh, "                if (strlen(p) < 3) break")
    fput(fh, "            }")
    fput(fh, "            return(" + q + q + ")")
    fput(fh, "        }")
    fput(fh, "        end")
    fput(fh, "")
    fput(fh, "        *  Candidates, best first: this file's own folder, then the working dir.")
    fput(fh, "        if " + bt + q + bt + "c(do_current)" + ap + q + ap + " != " + q + q + " {")
    fput(fh, "            local _dirof " + q + q)
    fput(fh, "            _hfc_dirof " + bt + q + bt + "c(do_current)" + ap + q + ap)
    fput(fh, "            if " + q + bt + "_dirof" + ap + q + " != " + q + q + " {")
    fput(fh, "                mata: st_local(" + q + "_this_root" + q + ", _hfc_find_root(" + q + bt + "_dirof" + ap + q + ", 12))")
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "        if " + q + bt + "_this_root" + ap + q + " == " + q + q + " & " + bt + q + bt + "c(filename)" + ap + q + ap + " != " + q + q + " {")
    fput(fh, "            local _dirof " + q + q)
    fput(fh, "            _hfc_dirof " + bt + q + bt + "c(filename)" + ap + q + ap)
    fput(fh, "            if " + q + bt + "_dirof" + ap + q + " != " + q + q + " {")
    fput(fh, "                mata: st_local(" + q + "_this_root" + q + ", _hfc_find_root(" + q + bt + "_dirof" + ap + q + ", 12))")
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "        if " + q + bt + "_this_root" + ap + q + " == " + q + q + " {")
    fput(fh, "            mata: st_local(" + q + "_this_root" + q + ", _hfc_find_root(" + q + bt + "c(pwd)" + ap + q + ", 12))")
    fput(fh, "        }")
    fput(fh, "        if " + q + bt + "_this_root" + ap + q + " != " + q + q + " di as result " + q + "  ROOT via .hfc_root sentinel." + q)
    fput(fh, "")

    fput(fh, "        *  Method 1: c(do_current)")
    fput(fh, "        if " + q + bt + "_this_root" + ap + q + " == " + q + q + " & " + bt + q + bt + "c(do_current)" + ap + q + ap + " != " + q + q + " {")
    fput(fh, "            _hfc_dirof " + bt + q + bt + "c(do_current)" + ap + q + ap)
    fput(fh, "            if " + q + bt + "_dirof" + ap + q + " != " + q + q + " {")
    fput(fh, "                local _p2 = subinstr(" + q + bt + "_dirof" + ap + q + ", " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, "                local _rt = subinstr(" + q + bt + "_p2" + ap + q + ", " + q + "/" + _mdf_rel("dofiles_dir") + q + ", " + q + q + ", 1)")
    fput(fh, "                if " + q + bt + "_rt" + ap + q + " != " + q + bt + "_p2" + ap + q + " local _this_root " + q + bt + "_rt" + ap + q)
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "")
    fput(fh, "        *  Method 2: c(filename)")
    fput(fh, "        if " + q + bt + "_this_root" + ap + q + " == " + q + q + " & " + bt + q + bt + "c(filename)" + ap + q + ap + " != " + q + q + " {")
    fput(fh, "            local _dirof " + q + q)
    fput(fh, "            _hfc_dirof " + bt + q + bt + "c(filename)" + ap + q + ap)
    fput(fh, "            if " + q + bt + "_dirof" + ap + q + " != " + q + q + " {")
    fput(fh, "                local _p2 = subinstr(" + q + bt + "_dirof" + ap + q + ", " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, "                local _rt = subinstr(" + q + bt + "_p2" + ap + q + ", " + q + "/" + _mdf_rel("dofiles_dir") + q + ", " + q + q + ", 1)")
    fput(fh, "                if " + q + bt + "_rt" + ap + q + " != " + q + bt + "_p2" + ap + q + " local _this_root " + q + bt + "_rt" + ap + q)
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "")
    fput(fh, "        *  Method 3: project-level cache")
    fput(fh, "        if " + q + bt + "_this_root" + ap + q + " == " + q + q + " {")
    fput(fh, "            tempname _fhrc")
    fput(fh, "            local _cached_r " + q + q)
    fput(fh, "            cap {")
    fput(fh, "                file open " + bt + "_fhrc" + ap + " using " + q + bt + "c(pwd)" + ap + "/_hfc_root.txt" + q + ", read text")
    fput(fh, "                file read " + bt + "_fhrc" + ap + " _cached_r")
    fput(fh, "                file close " + bt + "_fhrc" + ap)
    fput(fh, "            }")
    fput(fh, "            if " + q + bt + "_cached_r" + ap + q + " != " + q + q + " {")
    fput(fh, "                mata: st_local(" + q + "_cr_ok" + q + ", strofreal(direxists(" + q + bt + "_cached_r" + ap + q + ")))")
    fput(fh, "                if " + bt + "_cr_ok" + ap + " local _this_root " + q + bt + "_cached_r" + ap + q)
    fput(fh, "                else di as result " + q + "  Method 3: cached path not on this machine — skipping." + q)
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "")
    fput(fh, "        *  Method 4: tempdir cache")
    fput(fh, "        if " + q + bt + "_this_root" + ap + q + " == " + q + q + " {")
    fput(fh, "            tempname _fhrc2")
    fput(fh, "            local _cached_r " + q + q)
    fput(fh, "            cap file open " + bt + "_fhrc2" + ap + " using " + bt + q + bt + "c(tmpdir)" + ap + "hfc_root_cache_" + pname + ".txt" + q + ap + ", read text")
    fput(fh, "            if !_rc {")
    fput(fh, "                file read " + bt + "_fhrc2" + ap + " _cached_r")
    fput(fh, "                file close " + bt + "_fhrc2" + ap)
    fput(fh, "            }")
    fput(fh, "            if " + q + bt + "_cached_r" + ap + q + " != " + q + q + " {")
    fput(fh, "                mata: st_local(" + q + "_cr_ok" + q + ", strofreal(direxists(" + q + bt + "_cached_r" + ap + q + ")))")
    fput(fh, "                if " + bt + "_cr_ok" + ap + " local _this_root " + q + bt + "_cached_r" + ap + q)
    fput(fh, "                else di as result " + q + "  Method 4: cached path not on this machine — skipping." + q)
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "")
    fput(fh, "        *  Method 5: c(pwd) last resort")
    fput(fh, "        if " + q + bt + "_this_root" + ap + q + " == " + q + q + " {")
    fput(fh, "            local _this_root " + bt + "c(pwd)" + ap)
    fput(fh, "            di as error " + q + "WARNING: ROOT could not be auto-detected. Falling back to c(pwd)." + q)
    fput(fh, "            di as error " + q + "         If paths look wrong, cd to your project root and re-run." + q)
    fput(fh, "        }")
    fput(fh, "")
    fput(fh, "        mata: st_local(" + q + "_root_valid" + q + ", strofreal(direxists(" + q + bt + "_this_root" + ap + q + ")))")
    fput(fh, "        if !" + bt + "_root_valid" + ap + " {")
    fput(fh, "            di as error " + q + "WARNING: ROOT not found on this machine. Using c(pwd)." + q)
    fput(fh, "            local _this_root " + bt + "c(pwd)" + ap)
    fput(fh, "        }")
    fput(fh, "")
    fput(fh, "        global ROOT " + q + bt + "_this_root" + ap + q)
    fput(fh, "        cd " + q + dol + "ROOT" + q)
    fput(fh, "        global ROOT " + bt + "c(pwd)" + ap)
    fput(fh, "        di as result " + q + "ROOT (standalone) → " + dol + "ROOT" + q)
    fput(fh, "    }")
    fput(fh, "    else {")
    fput(fh, "        di as result " + q + "ROOT (already in memory) → " + dol + "ROOT" + q)
    fput(fh, "    }")
    fput(fh, "")

    //  ── Helper programs, for a module run on its own ───────────────────────────
    fput(fh, "    *  ── Helper programs (needed when a module runs standalone) ─────────────")
    fput(fh, "    cap program drop _hfc_abort")
    fput(fh, "    program define _hfc_abort")
    fput(fh, "        args msg")
    fput(fh, "        if " + bt + q + bt + "msg" + ap + q + ap + " != " + q + q + " di as error " + bt + q + bt + "msg" + ap + q + ap)
    fput(fh, "        cap log close hfc_master")
    fput(fh, "        exit 198")
    fput(fh, "    end")
    fput(fh, "    cap program drop _hfc_pause")
    fput(fh, "    program define _hfc_pause")
    fput(fh, "        args msg")
    fput(fh, "        if " + bt + q + bt + "msg" + ap + q + ap + " != " + q + q + " di as result " + bt + q + bt + "msg" + ap + q + ap)
    fput(fh, "        cap log close hfc_master")
    fput(fh, "        exit 0")
    fput(fh, "    end")
    fput(fh, "    cap program drop _hfc_mkdir")
    fput(fh, "    program define _hfc_mkdir")
    fput(fh, "        args _path")
    fput(fh, "        cap mkdir " + q + bt + "_path" + ap + q)
    fput(fh, "        mata: st_local(" + q + "_ok" + q + ", strofreal(direxists(" + q + bt + "_path" + ap + q + ")))")
    fput(fh, "        if !" + bt + "_ok" + ap + " {")
    fput(fh, "            di as error " + bt + q + "ERROR: Could not create directory " + bt + "_path" + ap + ". Check permissions." + q + ap)
    fput(fh, "            exit 198")
    fput(fh, "        }")
    fput(fh, "    end")
    fput(fh, "")
    fput(fh, "    *  ── Hide framework-internal state (.hfc_root, .flag_history) ─────────")
    fput(fh, "    *  Re-applied after every write: write-replace clears the hidden bit.")
    fput(fh, "    *  Python, not shell attrib: shell is a silent no-op in Stata batch mode.")
    fput(fh, "    cap program drop _hfc_hide")
    fput(fh, "    program define _hfc_hide")
    fput(fh, "        args _path _isdir")
    fput(fh, "        if c(os) != " + q + "Windows" + q + " exit 0")
    fput(fh, "        local _w = subinstr(" + bt + q + bt + "_path" + ap + q + ap + ", " + q + "/" + q + ", " + q + bs + q + ", .)")
    fput(fh, "        cap python: import ctypes; from sfi import Macro as M; _p=M.getLocal(" + q + "_w" + q + "); _a=ctypes.windll.kernel32.GetFileAttributesW(_p); ctypes.windll.kernel32.SetFileAttributesW(_p, (_a|2) if _a!=-1 else 2)")
    fput(fh, "        if _rc {")
    fput(fh, "            if " + q + bt + "_isdir" + ap + q + " == " + q + "1" + q + " cap qui shell attrib +h " + q + bt + "_w" + ap + q + " /d")
    fput(fh, "            else                 cap qui shell attrib +h " + q + bt + "_w" + ap + q + "")
    fput(fh, "        }")
    fput(fh, "    end")

    //  ── Folder globals ─────────────────────────────────────────────────────────
    //  Emitted from the path globals mdf_paths set, relative to ROOT, so the
    //  file describes whichever layout this project uses (ADR-058). For a v10
    //  project every line is the string the v10 generator hard-coded.
    fput(fh, "    *  ── Folder globals (" + st_global("hfc_layout_version") + " layout) ────────────────────────────────────────")
    fput(fh, "    global hfc_layout_version   " + q + st_global("hfc_layout_version") + q)
    fput(fh, "    global surv_inst_dir        " + q + _mdf_rpath("surv_inst_dir") + q)
    fput(fh, "    global quest_dir            " + q + _mdf_rpath("quest_dir") + q)
    fput(fh, "    global capi_dir             " + q + _mdf_rpath("capi_dir") + q)
    fput(fh, "    global others_dir           " + q + _mdf_rpath("others_dir") + q)
    fput(fh, "    global data_dir             " + q + _mdf_rpath("data_dir") + q)
    fput(fh, "    global hfc_dir              " + q + _mdf_rpath("hfc_dir") + q)
    fput(fh, "    global dofiles_dir          " + q + _mdf_rpath("dofiles_dir") + q)
    fput(fh, "    global translation_dir      " + q + _mdf_rpath("translation_dir") + q)
    fput(fh, "    global processing_dir       " + q + _mdf_rpath("processing_dir") + q)
    fput(fh, "    global processing_file      " + q + dol + "{project_name}_Processing.do" + q)
    fput(fh, "    global clean_dir            " + q + _mdf_rpath("clean_dir") + q)
    fput(fh, "    global deliv_dir            " + q + _mdf_rpath("deliv_dir") + q)
    fput(fh, "    global directory_file       " + q + st_global("directory_file") + q)
    fput(fh, "")
    fput(fh, "    global hfc_keys_dir         " + q + _mdf_rpath("hfc_keys_dir") + q)
    fput(fh, "    global hfc_keys_hfc_dir     " + q + _mdf_rpath("hfc_keys_hfc_dir") + q)
    fput(fh, "    global hfc_keys_audio_dir   " + q + _mdf_rpath("hfc_keys_audio_dir") + q)
    fput(fh, "    global hfc_keys_trans_dir   " + q + _mdf_rpath("hfc_keys_trans_dir") + q)
    fput(fh, "    global hfc_flag_dir         " + q + _mdf_rpath("hfc_flag_dir") + q)
    fput(fh, "    cap mkdir " + q + dol + "hfc_flag_dir" + q)
    fput(fh, "    _hfc_hide " + q + dol + "hfc_flag_dir" + q + " 1")
    fput(fh, "    global trans_exported_dir   " + q + _mdf_rpath("trans_exported_dir") + q)
    fput(fh, "    global trans_translated_dir " + q + _mdf_rpath("trans_translated_dir") + q)
    fput(fh, "    global processing_data_dir  " + q + _mdf_rpath("processing_data_dir") + q)
    fput(fh, "")
    fput(fh, "    *  ── Path aliases ──────────────────────────────────────")
    fput(fh, "    global hfc_dofiles_dir      " + q + dol + "dofiles_dir" + q)
    _dir_rtdir(fh, q, dol)
    fput(fh, "    global hfc_keys_master_dir  " + q + dol + "hfc_keys_hfc_dir" + q)
    fput(fh, "")
    fput(fh, "    *  ── Output path aliases ─────────────────────────────")
    fput(fh, "    *  The run-folder-dependent aliases are set below, once the latest")
    fput(fh, "    *  dated run folder has actually been detected.")
    fput(fh, "")

    //  ── Read last-run date breadcrumb (YYYYMMDD format) ────────────────────────
    fput(fh, "    *  ── Read last-run date breadcrumb (YYYYMMDD) ───────────────────────────")
    fput(fh, "    global LAST_RUN_DATE " + q + q)
    fput(fh, "    global has_pre_keys 0")
    fput(fh, "    local _m_num = daily(" + q + bt + "c(current_date)" + ap + q + ", " + q + "DMY" + q + ")")
    fput(fh, "    local _m_fmt : display %tdCCYYNNDD " + bt + "_m_num" + ap)
    fput(fh, "    local _current_run_date = strtrim(" + q + bt + "_m_fmt" + ap + q + ")")
    fput(fh, "    tempname _lrf")
    fput(fh, "    cap file open " + bt + "_lrf" + ap + " using " + q + dol + "hfc_keys_master_dir/" + pname + "_hfc_last_run.txt" + q + ", read text")
    fput(fh, "    if !_rc {")
    fput(fh, "        file read " + bt + "_lrf" + ap + " _line1")
    fput(fh, "        file read " + bt + "_lrf" + ap + " _line2")
    fput(fh, "        file close " + bt + "_lrf" + ap)
    fput(fh, "        local _l1 = strtrim(subinstr(" + q + bt + "_line1" + ap + q + ", char(13), " + q + q + ", .))")
    fput(fh, "        local _l2 = strtrim(subinstr(" + q + bt + "_line2" + ap + q + ", char(13), " + q + q + ", .))")
    fput(fh, "        if " + q + bt + "_l2" + ap + q + " == " + q + q + " local _l2 " + q + bt + "_l1" + ap + q)
    fput(fh, "        if " + q + bt + "_l2" + ap + q + " == " + q + bt + "_current_run_date" + ap + q + " {")
    fput(fh, "            global LAST_RUN_DATE " + q + bt + "_l1" + ap + q)
    fput(fh, "        }")
    fput(fh, "        else {")
    fput(fh, "            global LAST_RUN_DATE " + q + bt + "_l2" + ap + q)
    fput(fh, "        }")
    fput(fh, "        if " + q + dol + "LAST_RUN_DATE" + q + " != " + q + q + " global has_pre_keys 1")
    fput(fh, "    }")
    fput(fh, "")

    fput(fh, "    *  ── Detect the latest HFC dated run folder ─────────────────────────────")
    fput(fh, "    *  v10: run folders sit directly under 03_HFC/ as NN_<Project>_HFC_<date>,")
    fput(fh, "    *  and the report, log, audio list and dated datasets all live inside the")
    fput(fh, "    *  one folder. There is no 00_Datasets/ parent and no 01_Raw_Data/ /")
    fput(fh, "    *  02_Dataset/ split any more; the only child is Raw/.")
    fput(fh, "    *  Pick the newest run folder whose Raw/ actually holds a dataset. A")
    fput(fh, "    *  folder left behind by a run that found no new export is skipped, so")
    fput(fh, "    *  a standalone re-run after fieldwork still resolves to real data.")
    fput(fh, "    local _all_raw : dir " + q + dol + "hfc_dir" + q + " dirs " + q + "*_HFC_*" + q + ", respectcase")
    fput(fh, "    local _all : list sort _all_raw")
    fput(fh, "    local _hf " + q + q)
    fput(fh, "    local _hf_any " + q + q)
    fput(fh, "    foreach _d of local _all {")
    fput(fh, "        local _hf_any " + q + bt + "_d" + ap + q)
    fput(fh, "        local _d_dta " + q + q)
    fput(fh, "        cap local _d_dta : dir " + q + dol + "hfc_dir/" + bt + "_d" + ap + "/Raw" + q + " files " + q + "*.dta" + q + ", respectcase")
    fput(fh, "        local _d_n 0")
    fput(fh, "        foreach _df of local _d_dta {")
    fput(fh, "            local _d_n = " + bt + "_d_n" + ap + " + 1")
    fput(fh, "        }")
    fput(fh, "        if " + bt + "_d_n" + ap + " > 0 local _hf " + q + bt + "_d" + ap + q)
    fput(fh, "    }")
    fput(fh, "    *  Nothing archived anywhere yet: fall back to the newest folder so a")
    fput(fh, "    *  brand-new project still resolves its paths.")
    fput(fh, "    if " + q + bt + "_hf" + ap + q + " == " + q + q + " local _hf " + q + bt + "_hf_any" + ap + q)
    fput(fh, "    global hfc_run_dir          " + q + dol + "hfc_dir/" + bt + "_hf" + ap + q)
    fput(fh, "    global hfc_raw_snapshot_dir " + q + dol + "hfc_run_dir/Raw" + q)
    fput(fh, "    global hfc_folder_date = substr(" + q + bt + "_hf" + ap + q + ", -8, 8)")
    fput(fh, "")
    fput(fh, "    *  ── Run-folder aliases ──────────────────────────────")
    fput(fh, "    global hfc_rawdata_dir   " + q + dol + "hfc_raw_snapshot_dir" + q)
    fput(fh, "")
    _dir_rawdir(fh, q, bt, ap, dol)

    //  ── Discover datasets from the raw snapshot ────────────────────────────────
    fput(fh, "    *  ── Discover datasets from the RAW snapshot ────────────────────────────")
    fput(fh, "    *  The raw snapshot is written")
    fput(fh, "    *  every run and never removed, so it is the reliable discovery source.")
    fput(fh, "    local _rw_raw : dir " + q + dol + "hfc_raw_snapshot_dir" + q + " files " + q + "*.dta" + q + ", respectcase")
    fput(fh, "    local _rw : list sort _rw_raw")
    fput(fh, "    local _li 0")
    fput(fh, "    foreach _f of local _rw {")
    fput(fh, "        local _li = " + bt + "_li" + ap + " + 1")
    fput(fh, "        global dta_labeled_" + bt + "_li" + ap + " " + q + dol + "hfc_raw_snapshot_dir/" + bt + "_f" + ap + q)
    fput(fh, "        local _dn = subinstr(" + q + bt + "_f" + ap + q + ", " + q + "_" + dol + "hfc_folder_date.dta" + q + ", " + q + q + ", 1)")
    fput(fh, "        local _dn = subinstr(" + q + bt + "_dn" + ap + q + ", " + q + ".dta" + q + ", " + q + q + ", 1)")
    fput(fh, "        global auto_dsname_" + bt + "_li" + ap + " " + q + bt + "_dn" + ap + q)
    fput(fh, "        if " + q + dol + "{ds" + bt + "_li" + ap + "_name}" + q + " != " + q + q + " global auto_dsname_" + bt + "_li" + ap + " " + q + dol + "{ds" + bt + "_li" + ap + "_name}" + q)
    fput(fh, "        global dta_cleaned_" + bt + "_li" + ap + " " + q + dol + "hfc_run_dir/" + bt + "_dn" + ap + "_CLEANED_" + dol + "hfc_folder_date.dta" + q)
    fput(fh, "        global pre_keys_" + bt + "_li" + ap + " " + q + dol + "hfc_keys_master_dir/" + bt + "_dn" + ap + "_KEYS_" + dol + "LAST_RUN_DATE.dta" + q)
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "    global dta_labeled " + q + dol + "dta_labeled_1" + q)
    fput(fh, "    global dta_cleaned " + q + dol + "dta_cleaned_1" + q)
    fput(fh, "    global pre_keys    " + q + dol + "pre_keys_1" + q)
    fput(fh, "")

    fput(fh, "    *  ── Detect Merged Dataset Keys ─────────────────────────────────────────")
    fput(fh, "    if " + q + dol + "merge_required" + q + " == " + q + "1" + q + " {")
    fput(fh, "        local _sfx = subinstr(" + q + dol + "merge_datasets" + q + ", " + q + " " + q + ", " + q + "_" + q + ", .)")
    fput(fh, "        local _mname " + q + dol + "{project_name}_" + bt + "_sfx" + ap + "_MERGED" + q)
    fput(fh, "        global pre_keys_merged " + q + dol + "hfc_keys_master_dir/" + bt + "_mname" + ap + "_KEYS_" + dol + "LAST_RUN_DATE.dta" + q)
    fput(fh, "    }")
    fput(fh, "    else global pre_keys_merged " + q + q)
    fput(fh, "")

    //  ── Sync actual_n_dta with detected count ──────────────────────────────────
    fput(fh, "    *  ── Sync actual_n_dta ───────────────────────────────────────────────────")
    fput(fh, "    *  actual_n_dta: auto-detected (authoritative for pipeline logic).")
    fput(fh, "    *  n_datasets  : user-configured intent; updated upward if they diverge.")
    fput(fh, "    global actual_n_dta = " + bt + "_li" + ap)

    fput(fh, "    if " + bt + "_li" + ap + " == 0 {")
    fput(fh, "        di as error " + q + "WARNING: No datasets detected in HFC folder. Run Master_DO_File.do to initialize." + q)
    fput(fh, "    }")
    fput(fh, "")

    //  ── Detect existing cleaned datasets ───────────────────────────────────────
if (detect_cleaned) {
    fput(fh, "    *  ── Override: detect existing cleaned DTAs if present ──────────────────")
    fput(fh, "    local _cl_raw : dir " + q + dol + "hfc_run_dir" + q + " files " + q + "*_CLEANED_*.dta" + q + ", respectcase")
    fput(fh, "    local _cl : list sort _cl_raw")
    fput(fh, "    local _ci 0")
    fput(fh, "    foreach _f of local _cl {")
    fput(fh, "        local _ci = " + bt + "_ci" + ap + " + 1")
    fput(fh, "        global dta_cleaned_" + bt + "_ci" + ap + " " + q + dol + "hfc_run_dir/" + bt + "_f" + ap + q)
    fput(fh, "    }")
    fput(fh, "    if " + bt + "_ci" + ap + " > 0 global dta_cleaned " + q + dol + "dta_cleaned_1" + q)
    fput(fh, "")
    }

    //  ── Pipeline fallback — same cascade as Master ─────────────────────────────
    fput(fh, "    *  ── Pipeline Fallback: Determine Best Available Dataset ────────────────")
    fput(fh, "    *  Same order as Master:")
    fput(fh, "    *    1. 07_Cleaned Dataset/  the CURRENT cleaned file — what every")
    fput(fh, "    *                            consumer reads, and the normal answer")
    fput(fh, "    *    2. dated CLEANED        this run produced it but publishing failed")
    fput(fh, "    *    3. RAW snapshot         cleaning was skipped or did not run")
    fput(fh, "    forvalues _i = 1/" + dol + "actual_n_dta {")
    fput(fh, "        local _nm  " + q + dol + "{auto_dsname_" + bt + "_i" + ap + "}" + q)
    fput(fh, "        local _cur " + q + dol + "clean_dir/" + bt + "_nm" + ap + "_CLEANED.dta" + q)
    fput(fh, "        local _cln " + q + dol + "{dta_cleaned_" + bt + "_i" + ap + "}" + q)
    fput(fh, "        local _lbl " + q + dol + "{dta_labeled_" + bt + "_i" + ap + "}" + q)
    fput(fh, "        global target_dta_" + bt + "_i" + ap + " " + q + q)
    fput(fh, "        if " + q + bt + "_nm" + ap + q + " != " + q + q + " {")
    fput(fh, "            cap confirm file " + q + bt + "_cur" + ap + q)
    fput(fh, "            if !_rc global target_dta_" + bt + "_i" + ap + " " + q + bt + "_cur" + ap + q)
    fput(fh, "        }")
    fput(fh, "        if " + q + dol + "{target_dta_" + bt + "_i" + ap + "}" + q + " == " + q + q + " {")
    fput(fh, "            cap confirm file " + q + bt + "_cln" + ap + q)
    fput(fh, "            if !_rc global target_dta_" + bt + "_i" + ap + " " + q + bt + "_cln" + ap + q)
    fput(fh, "        }")
    fput(fh, "        if " + q + dol + "{target_dta_" + bt + "_i" + ap + "}" + q + " == " + q + q + " {")
    fput(fh, "            cap confirm file " + q + bt + "_lbl" + ap + q)
    fput(fh, "            if !_rc global target_dta_" + bt + "_i" + ap + " " + q + bt + "_lbl" + ap + q)
    fput(fh, "        }")
    fput(fh, "        if " + q + dol + "{target_dta_" + bt + "_i" + ap + "}" + q + " == " + q + bt + "_cur" + ap + q + " di as txt " + q + "  DS" + bt + "_i" + ap + ": using 07_Cleaned Dataset/" + bt + "_nm" + ap + "_CLEANED.dta" + q)
    fput(fh, "        else if " + q + dol + "{target_dta_" + bt + "_i" + ap + "}" + q + " != " + q + q + " di as error " + q + "  DS" + bt + "_i" + ap + ": 07_Cleaned Dataset/ unavailable — using " + dol + "{target_dta_" + bt + "_i" + ap + "}" + q)
    fput(fh, "    }")
    fput(fh, "    global target_dta " + q + dol + "target_dta_1" + q)
    fput(fh, "")

    //  ── Output file paths ──────────────────────────────────────────────────────
    fput(fh, "    *  ── Output file paths ──────────────────────────────────────────────────")
    fput(fh, "    global hfc_report    " + q + dol + "hfc_run_dir/HFC_" + dol + "{project_name}_" + dol + "today.xlsx" + q)
    fput(fh, "    global keys_today    " + q + dol + "hfc_keys_master_dir/" + dol + "{project_name}_KEYS_" + dol + "today.dta" + q)
    fput(fh, "")
    fput(fh, "    *  ── Inject dynamic team aliases ──────────────────────────────────────────")
    fput(fh, "    global excel_file " + q + dol + "hfc_report" + q)
    fput(fh, "    foreach _alias in " + st_global("hfc_excel_aliases") + " {")
    fput(fh, "        global " + bt + "_alias" + ap + " " + q + dol + "hfc_report" + q)
    fput(fh, "    }")
    fput(fh, "    foreach _alias in " + st_global("hfc_dta_aliases") + " {")
    fput(fh, "        global " + bt + "_alias" + ap + " " + q + dol + "target_dta" + q)
    fput(fh, "        forvalues _i = 1/" + dol + "actual_n_dta {")
    fput(fh, "            global " + bt + "_alias" + ap + "_" + bt + "_i" + ap + " " + q + dol + "{target_dta_" + bt + "_i" + ap + "}" + q)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "")

    //  ── Windows path normalisation ─────────────────────────────────────────────
    fput(fh, "    *  ── Normalise paths for Windows ─────────────────────────────────────────")
    fput(fh, "    if " + q + bt + "c(os)" + ap + q + " == " + q + "Windows" + q + " {")
    fput(fh, "        global hfc_report    = subinstr(" + q + dol + "hfc_report"    + q + ", " + q + "/" + q + ", " + q + bs + q + ", .)")
    fput(fh, "    }")
    fput(fh, "")

    fput(fh, "    di as result " + q + "Directory setup complete (" + pname + ")." + q)
    fput(fh, "")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "*  ── Apply Local Overrides (always runs — standalone or Master) ─────────────")
    fput(fh, "cap confirm file " + q + dol + "hfc_dofiles_dir/00b_Local_Overrides.do" + q)
    fput(fh, "if !_rc do " + q + dol + "hfc_dofiles_dir/00b_Local_Overrides.do" + q)
    fput(fh, "")
    }

void generate_local_overrides(string scalar p, string scalar q)
{
    real scalar fh
    if (fileexists(p)) return
    fh = fopen(p, "w")
    fput(fh, "*==============================================================================*")
    fput(fh, "*  LOCAL OVERRIDES  —  optional. Uncomment and edit; never overwritten.")
    fput(fh, "*  global meta_front " + q + "sup enum district new_var" + q)
    fput(fh, "*==============================================================================*")
    fput(fh, "")
    fclose(fh)
    printf("  00b_Local_Overrides.do: created\n")
}

//  entry point: was the driver at the tail of Section 10's mata block
void mdf_directory_main()
{
    string scalar q, bt, ap, dol, bs
    string scalar pname, ssize, meta, tail_v, tstart, tend, nds
    string scalar dodir, hfcdir, tver, procdir
    string scalar p
    real   scalar fh

    q   = char(34)
    bt  = char(96)
    ap  = char(39)
    dol = "$"
    bs  = char(92)

    pname  = st_local("_pname")
    ssize  = st_local("_ssize")
    meta   = st_local("_meta")
    tail_v = st_local("_tail")
    tstart = st_local("_tstart")
    tend   = st_local("_tend")
    nds    = st_local("_nds")
    dodir  = st_local("_dodir")
    hfcdir = st_local("_hfcdir")
    tver   = st_local("_tver")
    procdir = st_local("_procdir")

    //  00a_Directory.do in a v11 project, 00_Directory.do in a v10 one (ADR-058).
    p = dodir + "/" + st_global("directory_file")
    if (fileexists(p)) unlink(p)
    fh = fopen(p, "w")
    fput(fh, "*==============================================================================*")
    fput(fh, "*  DIRECTORY DO FILE  —  " + pname)
    fput(fh, "*==============================================================================*")
    fput(fh, "")
    standalone_block(fh, q, bt, ap, dol, "", pname, ssize, meta, tail_v, tstart, tend, nds, 1)
    fclose(fh)
    printf("  %s: written\n", st_global("directory_file"))


    p = dodir + "/00b_Local_Overrides.do"
    generate_local_overrides(p, q)

}

// ═══════════════════════════════════════════════════════════════════════════
//  PART 2 — generators for the pipeline modules, the HFC DO and Processing.do
//  (verbatim from Master_DO_File 10.1.0-rc1, Section 14)
// ═══════════════════════════════════════════════════════════════════════════

void write_find_root_fn(real scalar fh, string scalar q, string scalar bs, string scalar ind)
{
    fput(fh, ind + "cap mata: mata drop _hfc_find_root()")
    fput(fh, ind + "mata:")
    fput(fh, ind + "string scalar _hfc_find_root(string scalar start, real scalar maxup)")
    fput(fh, ind + "{")
    fput(fh, ind + "    string scalar p")
    fput(fh, ind + "    real scalar i, j")
    fput(fh, ind + "    p = subinstr(start, " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, ind + "    if (strlen(p) > 1 & substr(p, -1, 1) == " + q + "/" + q + ") p = substr(p, 1, strlen(p) - 1)")
    fput(fh, ind + "    for (i = 0; i <= maxup; i++) {")
    fput(fh, ind + "        if (fileexists(p + " + q + "/.hfc_root" + q + ")) return(p)")
    fput(fh, ind + "        j = strrpos(p, " + q + "/" + q + ")")
    fput(fh, ind + "        if (j <= 0) break")
    fput(fh, ind + "        p = substr(p, 1, j - 1)")
    fput(fh, ind + "        if (strlen(p) < 3) break")
    fput(fh, ind + "    }")
    fput(fh, ind + "    return(" + q + q + ")")
    fput(fh, ind + "}")
    fput(fh, ind + "end")
    fput(fh, "")
}

void write_root_resolution(real scalar fh, string scalar q, string scalar bt,
                           string scalar ap, string scalar dol, string scalar pname,
                           string scalar ind, real scalar abort_if_missing)
{
    string scalar bs
    bs = char(92)

    fput(fh, ind + "cap program drop _hfc_dirof")
    fput(fh, ind + "program define _hfc_dirof")
    fput(fh, ind + "    local _p = subinstr(" + bt + q + bt + "0" + ap + q + ap + ", " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, ind + "    local _len = length(" + bt + q + bt + "_p" + ap + q + ap + ")")
    fput(fh, ind + "    forvalues _j = " + bt + "_len" + ap + "(-1)1 {")
    fput(fh, ind + "        if substr(" + bt + q + bt + "_p" + ap + q + ap + ", " + bt + "_j" + ap + ", 1) == " + q + "/" + q + " {")
    fput(fh, ind + "            c_local _dirof = substr(" + bt + q + bt + "_p" + ap + q + ap + ", 1, " + bt + "_j" + ap + " - 1)")
    fput(fh, ind + "            continue, break")
    fput(fh, ind + "        }")
    fput(fh, ind + "    }")
    fput(fh, ind + "end")
    fput(fh, "")

    write_find_root_fn(fh, q, bs, ind)

    fput(fh, ind + "local _hfc_root " + q + q)
    fput(fh, "")
    fput(fh, ind + "*  1. Sentinel — this file's own folder, then the working directory.")
    fput(fh, ind + "if " + bt + q + bt + "c(do_current)" + ap + q + ap + " != " + q + q + " {")
    fput(fh, ind + "    local _dirof " + q + q)
    fput(fh, ind + "    _hfc_dirof " + bt + q + bt + "c(do_current)" + ap + q + ap)
    fput(fh, ind + "    if " + q + bt + "_dirof" + ap + q + " != " + q + q + " {")
    fput(fh, ind + "        mata: st_local(" + q + "_hfc_root" + q + ", _hfc_find_root(" + q + bt + "_dirof" + ap + q + ", 12))")
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, ind + "if " + q + bt + "_hfc_root" + ap + q + " == " + q + q + " & " + bt + q + bt + "c(filename)" + ap + q + ap + " != " + q + q + " {")
    fput(fh, ind + "    local _dirof " + q + q)
    fput(fh, ind + "    _hfc_dirof " + bt + q + bt + "c(filename)" + ap + q + ap)
    fput(fh, ind + "    if " + q + bt + "_dirof" + ap + q + " != " + q + q + " {")
    fput(fh, ind + "        mata: st_local(" + q + "_hfc_root" + q + ", _hfc_find_root(" + q + bt + "_dirof" + ap + q + ", 12))")
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, ind + "if " + q + bt + "_hfc_root" + ap + q + " == " + q + q + " {")
    fput(fh, ind + "    mata: st_local(" + q + "_hfc_root" + q + ", _hfc_find_root(" + q + bt + "c(pwd)" + ap + q + ", 12))")
    fput(fh, ind + "}")
    fput(fh, "")
    fput(fh, ind + "*  2. Tempdir cache written by the last Master run on this machine.")
    fput(fh, ind + "if " + q + bt + "_hfc_root" + ap + q + " == " + q + q + " {")
    fput(fh, ind + "    tempname _fhrc")
    fput(fh, ind + "    cap file open " + bt + "_fhrc" + ap + " using " + bt + q + bt + "c(tmpdir)" + ap + "hfc_root_cache_" + pname + ".txt" + q + ap + ", read text")
    fput(fh, ind + "    if !_rc {")
    fput(fh, ind + "        file read  " + bt + "_fhrc" + ap + " _hfc_root")
    fput(fh, ind + "        file close " + bt + "_fhrc" + ap)
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, "")

    if (abort_if_missing) {
        fput(fh, ind + "*  3. Nothing found — stop with instructions rather than guess a path.")
        fput(fh, ind + "if " + q + bt + "_hfc_root" + ap + q + " == " + q + q + " {")
        fput(fh, ind + "    di as error " + q + "ERROR: Could not locate the project root." + q)
        fput(fh, ind + "    di as error " + q + "       Searched upward from this file for a .hfc_root marker, then" + q)
        fput(fh, ind + "    di as error " + q + "       from the working directory, then for a cached path." + q)
        fput(fh, ind + "    di as error " + q + "  FIX: run Master_DO_File.do once from the project root, or open this" + q)
        fput(fh, ind + "    di as error " + q + "       file from inside the project folder and run it again." + q)
        fput(fh, ind + "    exit 198")
        fput(fh, ind + "}")
        fput(fh, "")
    }
}

void write_selection_guard(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar pname)
{
    fput(fh, "/* Secondary guard: reloads directory if globals were cleared mid-execution */")
    fput(fh, "/* Never in standalone mode: there is no 00_Directory.do to reload, and the")
    fput(fh, "   cache below names a project this file is no longer part of (ADR-056).   */")
    fput(fh, "if " + q + dol + "hfc_dofiles_dir" + q + " == " + q + q + " & " + q + dol + "mdf_standalone" + q + " != " + q + "1" + q + " {")
    fput(fh, "    local _sg_root " + bt + "c(pwd)" + ap)
    fput(fh, "    cap confirm file " + q + bt + "_sg_root" + ap + "/.hfc_root" + q)
    fput(fh, "    if _rc {")
    fput(fh, "        tempname _sgf")
    fput(fh, "        cap file open " + bt + "_sgf" + ap + " using " + bt + q + bt + "c(tmpdir)" + ap + "hfc_root_cache_" + dol + "{project_name}.txt" + q + ap + ", read text")
    fput(fh, "        if !_rc {")
    fput(fh, "            file read " + bt + "_sgf" + ap + " _sg_line")
    fput(fh, "            cap file close " + bt + "_sgf" + ap)
    fput(fh, "            if " + bt + q + bt + "_sg_line" + ap + q + ap + " != " + q + q + " local _sg_root " + bt + q + bt + "_sg_line" + ap + q + ap)
    fput(fh, "        }")
    fput(fh, "    }")
    //  mdf_bootstrap knows where each layout keeps its directory file (ADR-058).
    fput(fh, "    cap mdf_bootstrap " + bt + q + bt + "_sg_root" + ap + q + ap)
    fput(fh, "}")
}

void write_boxed_marker(real scalar fh, string scalar text)
{
    real scalar width, pad_len
    string scalar pad, line
    width = 76
    pad_len = trunc((width - strlen(text)) / 2)
    if (pad_len < 0) pad_len = 0
    pad = char(32) * pad_len
    line = "* " + pad + text + pad
    if (strlen(line) < 79) line = line + (char(32) * (79 - strlen(line)))
    line = line + "*"
    fput(fh, "")
    fput(fh, "*==============================================================================*")
    fput(fh, line)
    fput(fh, "*==============================================================================*")
    fput(fh, "")
}

void write_custom_check_slot(real scalar fh, string scalar ds_label)
{
    mdf_edit_section(fh, "Custom Checks - " + ds_label, "CUSTOM CHECKS  —  " + ds_label,
        ("Your own checks for this dataset. It is in memory; write results to" \
         "the report with the same commands the checks above use."))
    fput(fh, "")
    fput(fh, "")
    fput(fh, "")
}

string scalar slot_banner_line(string scalar text)
{
    real scalar pad_len
    string scalar pad, line
    pad_len = trunc((76 - strlen(text)) / 2)
    if (pad_len < 0) pad_len = 0
    pad = char(32) * pad_len
    line = "* " + pad + text + pad
    if (strlen(line) < 79) line = line + (char(32) * (79 - strlen(line)))
    return(line + "*")
}

string scalar tier2_marker(string scalar ver)
{
    return("*  __HFC_TEMPLATE__ " + ver + "   // do not edit this line")
}

string scalar read_template_version(string scalar path)
{
    real scalar fh_in, i
    string scalar ln, tag
    tag = "*  __HFC_TEMPLATE__ "
    if (!fileexists(path)) return("")
    fh_in = fopen(path, "r")
    i = 0
    while ((ln = fget(fh_in)) != J(0,0,"") & i < 40) {
        i++
        if (strpos(ln, tag) == 1) {
            fclose(fh_in)
            ln = substr(ln, strlen(tag) + 1, .)
            if (strpos(ln, "//") > 0) ln = substr(ln, 1, strpos(ln, "//") - 1)
            return(strtrim(ln))
        }
    }
    fclose(fh_in)
    return("")
}

string scalar tier2_target(string scalar path, string scalar ver, string scalar label)
{
    string scalar existing
    if (!fileexists(path)) {
        printf("  %s: created\n", label)
        return(path)
    }
    existing = read_template_version(path)
    if (existing == ver) {
        return("")                       // up to date — silence is correct here
    }
    printf("\n")
    printf("  {err}NOTE: %s was generated by an older framework template.\n", label)
    if (existing == "") printf("  {err}      Its template version could not be read (pre-v10 file).\n")
    else                printf("  {err}      Yours: %s   Current: %s\n", existing, ver)
    printf("  {err}      Your file has NOT been touched. A current version has been\n")
    printf("  {err}      written beside it as %s.new for you to compare and merge.\n", label)
    printf("\n")
    if (fileexists(path + ".new")) unlink(path + ".new")
    return(path + ".new")
}

//  A Deliverables package of a multi-dataset project carries ONE dataset and
//  its one form; the runtime points capi_override_k at that form only. The
//  detection loops below walk every dataset, so without this skip they looked
//  for the absent datasets' forms and aborted the rebuild ("No CAPI form for
//  DS2"). Same gate the Processing DO puts on each dataset block. Inside a
//  project mdf_package is never 1, so nothing changes there (ADR-059).
void _lab_skip_absent(real scalar fh, string scalar q, string scalar bt,
                      string scalar ap, string scalar dol)
{
    fput(fh, "            if " + q + dol + "mdf_package" + q + " == " + q + "1" + q + " & " + q + dol + "{mdf_ds_here_" + bt + "_i" + ap + "}" + q + " != " + q + "1" + q + " {")
    fput(fh, "                global capi_form_" + bt + "_i" + ap + " " + q + q)
    fput(fh, "                continue")
    fput(fh, "            }")
}

//  The odksplit sandbox trick is load-bearing. Do not simplify it.
void write_labeling_module(
    real scalar fh, string scalar q, string scalar bt, string scalar ap,
    string scalar dol, string scalar pname)
{
    //  ── Detect the CAPI form(s) ────────────────────────────────────────────────
    fput(fh, "*==============================================================================*")
    fput(fh, "*==============================================================================*")
    fput(fh, "")
    fput(fh, "*  ── Switch Protocol defaults (safe when run standalone) ────────────────────")
    //  Decide once per session, not once per call. Lines below default
    //  run_labeling to 1, so a Processing DO that calls this module for DS2
    //  would find the switch already set and conclude labeling had been asked
    //  for explicitly — aborting on a missing form where the DS1 call had
    //  warned and carried on. Master always sets run_labeling, so inside a
    //  project this resolves to 1 on the first call and stays there: unchanged
    //  (ADR-056).
    fput(fh, "if " + q + dol + "hfc_label_explicit" + q + " == " + q + q + " {")
    fput(fh, "    global hfc_label_explicit 1")
    fput(fh, "    if " + q + dol + "run_labeling" + q + " == " + q + q + " & " + q + dol + "run_label" + q + " == " + q + q + " global hfc_label_explicit 0")
    fput(fh, "}")
    fput(fh, "if " + q + dol + "run_labeling" + q + " == " + q + q + " global run_labeling " + dol + "run_label")
    fput(fh, "if " + q + dol + "run_labeling" + q + " == " + q + q + " global run_labeling 1")
    fput(fh, "global run_label " + q + dol + "run_labeling" + q)
    fput(fh, "")
    fput(fh, "di as result _n " + q + "--- Detecting CAPI form(s) ---" + q)
    fput(fh, "")
    fput(fh, "if " + dol + "actual_n_dta == 1 {")
    fput(fh, "")
    fput(fh, "    if " + q + dol + "capi_override" + q + " != " + q + q + " {")
    fput(fh, "        cap confirm file " + q + dol + "capi_dir/" + dol + "capi_override" + q)
    fput(fh, "        if _rc {")
    fput(fh, "            if " + q + dol + "run_label" + q + " == " + q + "1" + q + " & " + q + dol + "hfc_label_explicit" + q + " == " + q + "1" + q + " {")
    fput(fh, "                di as error " + q + "ERROR: run_label = 1 but forced CAPI form not found: " + dol + "capi_override" + q)
    fput(fh, "                _hfc_abort")
    fput(fh, "            }")
    fput(fh, "            else {")
    fput(fh, "                global capi_form " + q + q)
    fput(fh, "                di as result " + q + "WARNING: Forced CAPI form not found, but run_label=0. Continuing." + q)
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "        else {")
    fput(fh, "            global capi_form " + q + dol + "capi_dir/" + dol + "capi_override" + q)
    fput(fh, "            di as result " + q + "CAPI (forced override): " + dol + "capi_override" + q)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "    else {")
    fput(fh, "        local _latest_capi " + q + q)
    fput(fh, "        local _capi_all : dir " + q + dol + "capi_dir" + q + " files " + q + "*.xlsx" + q)
    fput(fh, "        foreach _f of local _capi_all {")
    fput(fh, "            if substr(" + bt + q + bt + "_f" + ap + q + ap + ", 1, 1) != " + q + "~" + q + " local _latest_capi " + q + bt + "_f" + ap + q)
    fput(fh, "        }")
    fput(fh, "")
    fput(fh, "        if " + q + bt + "_latest_capi" + ap + q + " == " + q + q + " {")
    fput(fh, "            if " + q + dol + "run_label" + q + " == " + q + "1" + q + " & " + q + dol + "hfc_label_explicit" + q + " == " + q + "1" + q + " {")
    fput(fh, "                di as error " + q + "ERROR: run_label = 1 but no .xlsx form found in 02_CAPI/." + q)
    fput(fh, "                di as error " + q + "       Place your SurveyCTO .xlsx form in 02_CAPI/ and re-run." + q)
    fput(fh, "                _hfc_abort")
    fput(fh, "            }")
    fput(fh, "            else {")
    fput(fh, "                global capi_form " + q + q)
    fput(fh, "                di as result " + q + "WARNING: No .xlsx in 02_CAPI/. Labels will be skipped (run_label = 0)." + q)
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "        else {")
    fput(fh, "            global capi_form " + q + dol + "capi_dir/" + bt + "_latest_capi" + ap + q)
    fput(fh, "            di as result " + q + "CAPI (auto-detected): " + bt + "_latest_capi" + ap + q)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "else {")
    fput(fh, "")
    fput(fh, "    if " + q + dol + "{ds1_capi}" + q + " != " + q + q + " {")
    fput(fh, "        *  ── Strategy A: name-based (ds{i}_capi defined in Section 0) ──────────")
    fput(fh, "        di as result " + q + "  CAPI detection: Strategy A (name-based)" + q)
    fput(fh, "        forvalues _i = 1/" + dol + "actual_n_dta {")
    _lab_skip_absent(fh, q, bt, ap, dol)
    fput(fh, "            if " + q + dol + "{ds" + bt + "_i" + ap + "_capi}" + q + " == " + q + q + " {")
    //  The single-dataset branch gates its abort on hfc_label_explicit too:
    //  it aborts when labeling was ASKED for, and degrades when the default
    //  merely switched it on. The multi-dataset branches did not, so the same
    //  project with two forms hard-stopped where one form warned. Inside a
    //  managed project Master always sets run_labeling, so hfc_label_explicit
    //  is 1 and the abort still fires exactly as before (ADR-056).
    fput(fh, "                if " + q + dol + "run_label" + q + " == " + q + "1" + q + " & " + q + dol + "hfc_label_explicit" + q + " == " + q + "1" + q + " {")
    fput(fh, "                    di as error " + q + "ERROR: ds" + bt + "_i" + ap + "_capi is empty. Define in Section 0." + q)
    fput(fh, "                    _hfc_abort")
    fput(fh, "                }")
    fput(fh, "                else {")
    fput(fh, "                    di as result " + q + "  WARNING: ds" + bt + "_i" + ap + "_capi is empty, but run_label=0. Continuing." + q)
    fput(fh, "                    global capi_form_" + bt + "_i" + ap + " " + q + q)
    fput(fh, "                    continue")
    fput(fh, "                }")
    fput(fh, "            }")
    fput(fh, "            cap confirm file " + q + dol + "capi_dir/" + dol + "{ds" + bt + "_i" + ap + "_capi}" + q)
    fput(fh, "            if _rc {")
    //  The single-dataset branch gates its abort on hfc_label_explicit too:
    //  it aborts when labeling was ASKED for, and degrades when the default
    //  merely switched it on. The multi-dataset branches did not, so the same
    //  project with two forms hard-stopped where one form warned. Inside a
    //  managed project Master always sets run_labeling, so hfc_label_explicit
    //  is 1 and the abort still fires exactly as before (ADR-056).
    fput(fh, "                if " + q + dol + "run_label" + q + " == " + q + "1" + q + " & " + q + dol + "hfc_label_explicit" + q + " == " + q + "1" + q + " {")
    fput(fh, "                    di as error " + q + "ERROR: CAPI file not found: " + dol + "capi_dir/" + dol + "{ds" + bt + "_i" + ap + "_capi}" + q)
    fput(fh, "                    _hfc_abort")
    fput(fh, "                }")
    fput(fh, "                else {")
    fput(fh, "                    di as result " + q + "  WARNING: CAPI file not found for DS" + bt + "_i" + ap + ", but run_label=0. Continuing." + q)
    fput(fh, "                    global capi_form_" + bt + "_i" + ap + " " + q + q)
    fput(fh, "                }")
    fput(fh, "            }")
    fput(fh, "            else {")
    fput(fh, "                global capi_form_" + bt + "_i" + ap + " " + q + dol + "capi_dir/" + dol + "{ds" + bt + "_i" + ap + "_capi}" + q)
    fput(fh, "                di as result " + q + "  DS" + bt + "_i" + ap + " (" + dol + "{ds" + bt + "_i" + ap + "_name}): CAPI → " + dol + "{ds" + bt + "_i" + ap + "_capi}" + q)
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "    else {")
    fput(fh, "        *  ── Strategy B: folder-based, with optional per-dataset override ──────")
    fput(fh, "        *  capi_override_N bypasses auto-detection for that index only. This")
    fput(fh, "        *  override is independent of Strategy A — it applies within Strategy B.")
    fput(fh, "        di as result " + q + "  CAPI detection: Strategy B (folder-based)" + q)
    fput(fh, "        forvalues _i = 1/" + dol + "actual_n_dta {")
    _lab_skip_absent(fh, q, bt, ap, dol)
    fput(fh, "            local _fnum : display %02.0f " + bt + "_i" + ap)
    fput(fh, "")
    fput(fh, "            if " + q + dol + "{capi_override_" + bt + "_i" + ap + "}" + q + " != " + q + q + " {")
    fput(fh, "                cap confirm file " + q + dol + "capi_dir/" + dol + "{capi_override_" + bt + "_i" + ap + "}" + q)
    fput(fh, "                if _rc {")
    fput(fh, "                    if " + q + dol + "run_label" + q + " == " + q + "1" + q + " {")
    fput(fh, "                        di as error " + q + "ERROR: capi_override_" + bt + "_i" + ap + " file not found." + q)
    fput(fh, "                        _hfc_abort")
    fput(fh, "                    }")
    fput(fh, "                    else {")
    fput(fh, "                        di as result " + q + "  WARNING: capi_override_" + bt + "_i" + ap + " not found, but run_label=0. Continuing." + q)
    fput(fh, "                        global capi_form_" + bt + "_i" + ap + " " + q + q)
    fput(fh, "                    }")
    fput(fh, "                }")
    fput(fh, "                else {")
    fput(fh, "                    global capi_form_" + bt + "_i" + ap + " " + q + dol + "capi_dir/" + dol + "{capi_override_" + bt + "_i" + ap + "}" + q)
    fput(fh, "                    di as result " + q + "  DS" + bt + "_i" + ap + " CAPI (per-dataset override): " + dol + "{capi_override_" + bt + "_i" + ap + "}" + q)
    fput(fh, "                }")
    fput(fh, "            }")
    fput(fh, "            else {")
    fput(fh, "                local _rdirs : dir " + q + dol + "capi_dir" + q + " dirs " + q + bt + "_fnum" + ap + "_SurveyCTO_*" + q)
    fput(fh, "                gettoken _rfolder : _rdirs")
    //  v11 names the per-dataset form folder NN_<dataset> (ADR-058).
    fput(fh, "                if " + q + bt + "_rfolder" + ap + q + " == " + q + q + " {")
    fput(fh, "                    local _rdirs : dir " + q + dol + "capi_dir" + q + " dirs " + q + bt + "_fnum" + ap + "_*" + q)
    fput(fh, "                    gettoken _rfolder : _rdirs")
    fput(fh, "                }")
    fput(fh, "                if " + q + bt + "_rfolder" + ap + q + " != " + q + q + " {")
    fput(fh, "                    local _folder " + q + bt + "_rfolder" + ap + q)
    fput(fh, "                }")
    fput(fh, "                else {")
    fput(fh, "                    local _folder " + q + "form_" + bt + "_fnum" + ap + q)
    fput(fh, "                }")
    //  -dir- on a folder that is not there raises r(601), which killed the whole
    //  run even with run_label = 0. Master always creates these CAPI subfolders,
    //  so this is only reachable standalone — where the "no CAPI form" branch
    //  below already says the right thing and already tells run_label 1 from 0.
    //  The blank first is load-bearing: without it a failed -dir- would leave the
    //  previous dataset's form list standing (ADR-056).
    fput(fh, "                local _xlsx " + q + q)
    fput(fh, "                cap local _xlsx : dir " + q + dol + "capi_dir/" + bt + "_folder" + ap + q + " files " + q + "*.xlsx" + q)
    fput(fh, "                local _c " + q + q)
    fput(fh, "                local _xlsx_clean " + q + q)
    fput(fh, "                foreach _xf of local _xlsx {")
    fput(fh, "                    if substr(" + bt + q + bt + "_xf" + ap + q + ap + ", 1, 1) != " + q + "~" + q + " local _xlsx_clean " + bt + q + bt + "_xlsx_clean" + ap + " " + bt + "_xf" + ap + q + ap)
    fput(fh, "                }")
    fput(fh, "                local _xlsx " + bt + q + bt + "_xlsx_clean" + ap + q + ap)
    fput(fh, "                gettoken _c : _xlsx")
    fput(fh, "                if " + q + bt + "_c" + ap + q + " == " + q + q + " {")
    fput(fh, "                    if " + q + dol + "run_label" + q + " == " + q + "1" + q + " & " + q + dol + "hfc_label_explicit" + q + " == " + q + "1" + q + " {")
    fput(fh, "                        di as error " + q + "ERROR: No CAPI form for DS" + bt + "_i" + ap + ". Place .xlsx in: " + dol + "capi_dir/" + bt + "_folder" + ap + "/" + q)
    fput(fh, "                        _hfc_abort")
    fput(fh, "                    }")
    fput(fh, "                    else {")
    fput(fh, "                        di as result " + q + "  WARNING: No CAPI form for DS" + bt + "_i" + ap + ", but run_label=0. Continuing." + q)
    fput(fh, "                        global capi_form_" + bt + "_i" + ap + " " + q + q)
    fput(fh, "                    }")
    fput(fh, "                }")
    fput(fh, "                else {")
    fput(fh, "                    global capi_form_" + bt + "_i" + ap + " " + q + dol + "capi_dir/" + bt + "_folder" + ap + "/" + bt + "_c" + ap + q)
    fput(fh, "                    di as result " + q + "  DS" + bt + "_i" + ap + " CAPI (folder " + bt + "_folder" + ap + "): " + bt + "_c" + ap + q)
    fput(fh, "                }")
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "")
    write_labeling_part2(fh, q, bt, ap, dol, pname)
}

void write_odksplit_call(real scalar fh, string scalar q, string scalar bt,
                         string scalar ap, string scalar dol,
                         string scalar sfx, string scalar form, string scalar ind)
{
    fput(fh, ind + "local _ods_t0 = clock(" + q + bt + "c(current_time)" + ap + q + ", " + q + "hms" + q + ")")
    fput(fh, ind + "local _odk_cap = cond(" + q + dol + "capi_verbose" + q + " == " + q + "1" + q + ", " + q + "cap noi" + q + ", " + q + "cap" + q + ")")
    fput(fh, "")
    fput(fh, ind + "*  SANDBOX TRICK — do not simplify.")
    fput(fh, ind + "*  odksplit fails on paths containing spaces and on some data filenames.")
    fput(fh, ind + "*  Copy form and data to short local names, run against those, then erase.")
    fput(fh, ind + "cd " + q + dol + "hfc_rawdata_dir" + q)
    fput(fh, ind + "cap copy " + q + form + q + " " + q + "temp_capi" + sfx + ".xlsx" + q + ", replace")
    fput(fh, ind + "cap copy " + q + bt + "_f" + ap + q + " " + q + "temp_data" + sfx + ".dta" + q + ", replace")
    fput(fh, "")
    fput(fh, ind + bt + "_odk_cap" + ap + " odksplit,                              ///")
    fput(fh, ind + "    survey(" + q + "temp_capi" + sfx + ".xlsx" + q + ")        ///")
    fput(fh, ind + "    data(" + q + "temp_data" + sfx + ".dta" + q + ")           ///")
    fput(fh, ind + "    label(" + q + dol + "capi_language" + q + ") multiple single varlabel clear")
    fput(fh, ind + "local _odksplit_rc = _rc")
    fput(fh, "")
    fput(fh, ind + "cap erase " + q + "temp_capi" + sfx + ".xlsx" + q)
    fput(fh, ind + "cap erase " + q + "temp_data" + sfx + ".dta" + q)
    fput(fh, ind + "cd " + q + dol + "{ROOT}" + q)
    fput(fh, "")
    fput(fh, ind + "di as result " + q + "  odksplit completed in " + q + " %5.1f (clock(" + q + bt + "c(current_time)" + ap + q + ", " + q + "hms" + q + ") - " + bt + "_ods_t0" + ap + ") / 1000 " + q + " seconds." + q)
    fput(fh, "")
    fput(fh, ind + "if " + bt + "_odksplit_rc" + ap + " {")
    fput(fh, ind + "    di as error " + q + "═══════════════════════════════════════════════" + q)
    fput(fh, ind + "    di as error " + q + "  WARNING: odksplit failed (rc=" + bt + "_odksplit_rc" + ap + ")." + q)
    fput(fh, ind + "    di as error " + q + "  Proceeding WITHOUT variable labels." + q)
    fput(fh, ind + "    di as error " + q + "  Check CAPI form compatibility." + q)
    fput(fh, ind + "    di as error " + q + "═══════════════════════════════════════════════" + q)
    fput(fh, ind + "    use " + q + dol + "hfc_raw_snapshot_dir/" + bt + "_f" + ap + q + ", clear")
    fput(fh, ind + "}")
}

void write_labeling_part2(
    real scalar fh, string scalar q, string scalar bt, string scalar ap,
    string scalar dol, string scalar pname)
{
    pragma unset pname

    fput(fh, "*==============================================================================*")
    fput(fh, "*==============================================================================*")
    fput(fh, "")
    fput(fh, "*  ── Which dataset? ─────────────────────────────────────────────────────────")
    fput(fh, "if " + bt + q + bt + "1" + ap + q + ap + " != " + q + q + " global hfc_label_ds " + bt + "1" + ap)
    fput(fh, "if " + q + dol + "hfc_label_ds" + q + " == " + q + q + " global hfc_label_ds 1")
    fput(fh, "global hfc_label_ok 0")
    fput(fh, "local _ds " + dol + "hfc_label_ds")
    fput(fh, "if " + bt + "_ds" + ap + " < 1 local _ds 1")
    fput(fh, "")
    fput(fh, "di as result _n " + q + "--- Labeling DS" + bt + "_ds" + ap + " ---" + q)
    fput(fh, "")
    fput(fh, "*  ── Resolve this dataset's archived raw file ───────────────────────────────")
    fput(fh, "local _f " + q + q)
    fput(fh, "local _base " + q + q)
    fput(fh, "")
    //  Standalone and package mode have already mapped each dataset to one
    //  file, by name. Sorted position cannot stand in for that in a package
    //  that carries a single dataset of several; inside a project this branch
    //  is never taken (ADR-059).
    fput(fh, "if " + q + dol + "mdf_standalone" + q + " == " + q + "1" + q + " & " + bt + q + dol + "{dta_labeled_" + bt + "_ds" + ap + "}" + q + ap + " != " + q + q + " {")
    fput(fh, "    local _f = ustrregexra(" + bt + q + dol + "{dta_labeled_" + bt + "_ds" + ap + "}" + q + ap + ", " + q + "^.*/" + q + ", " + q + q + ")")
    fput(fh, "}")
    fput(fh, "else if " + dol + "actual_n_dta == 1 {")
    fput(fh, "    local _arch : dir " + q + dol + "hfc_rawdata_dir" + q + " files " + q + "*_" + dol + "hfc_folder_date.dta" + q + ", respectcase")
    fput(fh, "    *  dir may return compound quotes when paths contain spaces; foreach")
    fput(fh, "    *  strips them. break exits after the first item.")
    fput(fh, "    foreach _file of local _arch {")
    fput(fh, "        local _f " + q + bt + "_file" + ap + q)
    fput(fh, "        continue, break")
    fput(fh, "    }")
    fput(fh, "    *  Fallback: nothing carries the folder date, so take the only dataset")
    fput(fh, "    *  archived in this snapshot folder. This is what kept the v9 cleaning")
    fput(fh, "    *  file runnable once fieldwork ended, and it is why a standalone run")
    fput(fh, "    *  never goes blank merely because the date stamp has moved on.")
    fput(fh, "    if " + q + bt + "_f" + ap + q + " == " + q + q + " {")
    fput(fh, "        local _any : dir " + q + dol + "hfc_rawdata_dir" + q + " files " + q + "*.dta" + q + ", respectcase")
    fput(fh, "        foreach _file of local _any {")
    fput(fh, "            local _f " + q + bt + "_file" + ap + q)
    fput(fh, "            continue, break")
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "else if " + q + dol + "{ds1_name}" + q + " != " + q + q + " {")
    fput(fh, "    *  Strategy A — name-based.")
    fput(fh, "    local _dsname " + q + dol + "{ds" + bt + "_ds" + ap + "_name}" + q)
    fput(fh, "    local _match : dir " + q + dol + "hfc_rawdata_dir" + q + " files " + q + "*" + bt + "_dsname" + ap + "*.dta" + q + ", respectcase")
    fput(fh, "    foreach _file of local _match {")
    fput(fh, "        local _f " + q + bt + "_file" + ap + q)
    fput(fh, "        continue, break")
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "else {")
    fput(fh, "    *  Strategy B — folder-based: sorted position on disk is the index.")
    fput(fh, "    local _all_raw : dir " + q + dol + "hfc_rawdata_dir" + q + " files " + q + "*.dta" + q + ", respectcase")
    fput(fh, "    local _all : list sort _all_raw")
    fput(fh, "    local _k 0")
    fput(fh, "    foreach _file of local _all {")
    fput(fh, "        local _k = " + bt + "_k" + ap + " + 1")
    fput(fh, "        if " + bt + "_k" + ap + " == " + bt + "_ds" + ap + " {")
    fput(fh, "            local _f " + q + bt + "_file" + ap + q)
    fput(fh, "            continue, break")
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "global hfc_label_ok 0")
    fput(fh, "if " + q + bt + "_f" + ap + q + " == " + q + q + " {")
    fput(fh, "    di as error " + q + "=======================================================================" + q)
    fput(fh, "    di as error " + q + "  DS" + bt + "_ds" + ap + ": NO DATASET FOUND — CLEANING WILL BE SKIPPED" + q)
    fput(fh, "    di as error " + q + "=======================================================================" + q)
    fput(fh, "    di as txt   " + q + "  Looked in: " + dol + "hfc_rawdata_dir" + q)
    fput(fh, "    di as txt   " + q + "  That folder holds no .dta at all, so there is nothing to clean and" + q)
    fput(fh, "    di as txt   " + q + "  the processing file will produce nothing. Either no data has been" + q)
    fput(fh, "    di as txt   " + q + "  archived yet, or every run folder under 03_HFC/ is empty." + q)
    fput(fh, "    clear")
    fput(fh, "    exit")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "local _base = subinstr(" + q + bt + "_f" + ap + q + ", " + q + "_" + dol + "hfc_folder_date.dta" + q + ", " + q + q + ", 1)")
    fput(fh, "local _base = subinstr(" + q + bt + "_base" + ap + q + ", " + q + ".dta" + q + ", " + q + q + ", 1)")
    fput(fh, "if " + q + dol + "{ds" + bt + "_ds" + ap + "_name}" + q + " != " + q + q + " local _base " + q + dol + "{ds" + bt + "_ds" + ap + "_name}" + q)
    //  The Processing DO saves under the context's dataset name; the pointer
    //  set below must name the same file or publishing finds nothing.
    fput(fh, "if " + q + dol + "mdf_standalone" + q + " == " + q + "1" + q + " & " + q + dol + "{auto_dsname_" + bt + "_ds" + ap + "}" + q + " != " + q + q + " local _base " + q + dol + "{auto_dsname_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "")
    fput(fh, "*  ── Apply CAPI value labels (or load raw when labeling is off) ─────────────")
    fput(fh, "local _capi " + q + dol + "{capi_form_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "if " + q + bt + "_capi" + ap + q + " == " + q + q + " local _capi " + q + dol + "capi_form" + q)
    fput(fh, "")
    fput(fh, "if " + q + dol + "run_label" + q + " == " + q + "1" + q + " & " + q + bt + "_capi" + ap + q + " != " + q + q + " {")
    fput(fh, "    di as result " + q + "  DS" + bt + "_ds" + ap + " (" + bt + "_base" + ap + "): running odksplit... please wait." + q)
    write_odksplit_call(fh, q, bt, ap, dol, "_" + bt + "_ds" + ap, bt + "_capi" + ap, "    ")
    fput(fh, "    if " + bt + "_odksplit_rc" + ap + " == 0 di as result " + q + "  DS" + bt + "_ds" + ap + ": labels applied (in memory)." + q)
    fput(fh, "}")
    fput(fh, "else {")
    fput(fh, "    use " + q + dol + "hfc_raw_snapshot_dir/" + bt + "_f" + ap + q + ", clear")
    fput(fh, "    if " + q + dol + "run_label" + q + " == " + q + "1" + q + " di as error " + q + "  DS" + bt + "_ds" + ap + ": no CAPI form resolved — loaded WITHOUT labels." + q)
    fput(fh, "    else di as result " + q + "  DS" + bt + "_ds" + ap + ": labeling off — loaded raw data." + q)
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "*  ── Pointers for the rest of the pipeline ──────────────────────────────────")
    fput(fh, "global dta_labeled_" + bt + "_ds" + ap + " " + q + dol + "hfc_raw_snapshot_dir/" + bt + "_f" + ap + q)
    fput(fh, "global dta_cleaned_" + bt + "_ds" + ap + " " + q + dol + "hfc_run_dir/" + bt + "_base" + ap + "_CLEANED_" + dol + "hfc_folder_date.dta" + q)
    fput(fh, "if " + q + dol + "{LAST_RUN_DATE}" + q + " != " + q + q + " global pre_keys_" + bt + "_ds" + ap + " " + q + dol + "hfc_keys_master_dir/" + bt + "_base" + ap + "_KEYS_" + dol + "{LAST_RUN_DATE}.dta" + q)
    fput(fh, "else global pre_keys_" + bt + "_ds" + ap + " " + q + q)
    fput(fh, "")
    fput(fh, "if " + bt + "_ds" + ap + " == 1 {")
    fput(fh, "    global dta_labeled " + q + dol + "dta_labeled_1" + q)
    fput(fh, "    global dta_cleaned " + q + dol + "dta_cleaned_1" + q)
    fput(fh, "    global pre_keys    " + q + dol + "pre_keys_1" + q)
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "qui count")
    fput(fh, "global hfc_label_ok 1")
    fput(fh, "di as result " + q + "  DS" + bt + "_ds" + ap + " ready in memory: " + q + " r(N) " + q + " observations." + q)
    fput(fh, "di as result " + q + "Labeling module complete (DS" + bt + "_ds" + ap + ")." + q)
}


// ═══════════════════════════════════════════════════════════════════════════
//  STANDALONE MODE  (ADR-056)
//
//  Every generated executable DO carries a small block that lets it run from
//  wherever it is sitting when there is no MDF project above it. The block is
//  reached only after the .hfc_root walk has failed, so a file inside a real
//  project can never take it.
//
//  Two shorthands keep the emitted quoting readable:
//    _cq("x")  ->  `"`x'"'      compound-quoted macro reference
//    _mq("x")  ->  `x'          plain macro reference
// ═══════════════════════════════════════════════════════════════════════════

string scalar _mq(string scalar nm)
{
    return(char(96) + nm + char(39))
}

string scalar _cq(string scalar nm)
{
    return(char(96) + char(34) + char(96) + nm + char(39) + char(34) + char(39))
}

//  Discover the datasets sitting beside this file.
//
//  Deterministic by construction: -dir- is asked for *.dta with respectcase,
//  the result is passed through `: list sort', and the framework's own output
//  is filtered out by name so a second run cannot read the first run's results
//  as input. The DO's own folder is searched first; only if it holds no
//  candidate are Data/, 02_Data/, 01_Data/ and 03_Data/ tried. 03_Data/ is the
//  v11 working-data folder and is tried last, so every folder v10.2.0 searched
//  keeps its precedence.
//
//  Leaves behind:  `_sa_cand'     sorted candidate filenames
//                  `_sa_k'        how many
//                  `_sa_datadir'  the folder they were found in
void standalone_discover(real scalar fh, string scalar q, string scalar bt,
                         string scalar ap, string scalar dol, string scalar ind)
{
    pragma unset dol
    fput(fh, ind + "*  ── Datasets sitting beside this file ──────────────────────────────")
    fput(fh, ind + "local _sa_datadir " + _cq("_selfdir"))
    fput(fh, ind + "local _sa_cand " + q + q)
    fput(fh, ind + "local _sa_k 0")
    fput(fh, ind + "foreach _sa_try in " + q + "." + q + " " + q + "Data" + q + " " + q + "02_Data" + q + " " + q + "01_Data" + q + " " + q + "03_Data" + q + " {")
    fput(fh, ind + "    if " + _mq("_sa_k") + " == 0 {")
    fput(fh, ind + "        local _sa_dir " + _cq("_selfdir"))
    fput(fh, ind + "        if " + q + _mq("_sa_try") + q + " != " + q + "." + q + " local _sa_dir " + bt + q + bt + "_selfdir" + ap + "/" + bt + "_sa_try" + ap + q + ap)
    fput(fh, ind + "        local _sa_raw " + q + q)
    fput(fh, ind + "        cap local _sa_raw : dir " + _cq("_sa_dir") + " files " + q + "*.dta" + q + ", respectcase")
    fput(fh, ind + "        local _sa_srt : list sort _sa_raw")
    fput(fh, ind + "        foreach _sa_f of local _sa_srt {")
    write_sa_filter(fh, q, bt, ap, ind + "            ")
    fput(fh, ind + "            if " + _mq("_sa_ok") + " == 1 {")
    fput(fh, ind + "                local _sa_cand " + bt + q + bt + "_sa_cand" + ap + " " + bt + q + bt + "_sa_f" + ap + q + ap + q + ap)
    fput(fh, ind + "            }")
    fput(fh, ind + "        }")
    fput(fh, ind + "        local _sa_k : list sizeof _sa_cand")
    fput(fh, ind + "        if " + _mq("_sa_k") + " > 0 local _sa_datadir " + _cq("_sa_dir"))
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
}

//  The framework's own output is never input: a second run must not read
//  the first run's results as data.
void write_sa_filter(real scalar fh, string scalar q, string scalar bt,
                     string scalar ap, string scalar ind)
{
    pragma unused bt
    pragma unused ap
    fput(fh, ind + "local _sa_ok 1")
    fput(fh, ind + "if strpos(" + _cq("_sa_f") + ", " + q + "_KEYS_" + q + ")    > 0 local _sa_ok 0")
    fput(fh, ind + "if strpos(" + _cq("_sa_f") + ", " + q + "_CLEANED" + q + ")  > 0 local _sa_ok 0")
    fput(fh, ind + "if strpos(" + _cq("_sa_f") + ", " + q + "_MERGED_" + q + ")  > 0 local _sa_ok 0")
    fput(fh, ind + "if strpos(" + _cq("_sa_f") + ", " + q + "_LABELED_" + q + ") > 0 local _sa_ok 0")
    fput(fh, ind + "if substr(" + _cq("_sa_f") + ", 1, 1) == " + q + "_" + q + " local _sa_ok 0")
}

//  Discover the raw data of a Deliverables package (ADR-059). One folder is
//  read — 02_Import & Raw files/ — with the same filters as above, so the
//  package's own cleaned output can never be read back as its input.
void package_discover(real scalar fh, string scalar q, string scalar bt,
                      string scalar ap, string scalar ind)
{
    fput(fh, ind + "*  ── The package's raw data: 02_Import & Raw files/ ─────────────────")
    fput(fh, ind + "local _sa_datadir " + bt + q + bt + "_sa_pkg" + ap + "/02_Import & Raw files" + q + ap)
    fput(fh, ind + "local _sa_cand " + q + q)
    fput(fh, ind + "local _sa_raw " + q + q)
    fput(fh, ind + "cap local _sa_raw : dir " + _cq("_sa_datadir") + " files " + q + "*.dta" + q + ", respectcase")
    fput(fh, ind + "local _sa_srt : list sort _sa_raw")
    fput(fh, ind + "foreach _sa_f of local _sa_srt {")
    write_sa_filter(fh, q, bt, ap, ind + "    ")
    fput(fh, ind + "    if " + _mq("_sa_ok") + " == 1 {")
    fput(fh, ind + "        local _sa_cand " + bt + q + bt + "_sa_cand" + ap + " " + bt + q + bt + "_sa_f" + ap + q + ap + q + ap)
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, ind + "local _sa_k : list sizeof _sa_cand")
}

//  The survey commands a package rebuild may need, and where Master installs
//  each from — the same sources as the DEPENDENCIES block of the Master DO
//  file. Kept in one place so the two cannot drift apart silently.
string colvector _mdf_dep_names()
{
    return(("odksplit" \ "inputcorrection" \ "mrtab" \ "exportopenended" \
            "recode_nrep" \ "recode_rep" \ "multisplit" \ "exporttabs" \
            "exportables" \ "exprep" \ "bias_expo" \ "export_hfc" \ "recode_oth"))
}

string scalar _mdf_dep_install(string scalar nm)
{
    string scalar gh, q
    q  = char(34)
    gh = "https://raw.githubusercontent.com/"
    if (nm == "odksplit")        return("ssc install odksplit")
    if (nm == "mrtab")           return("ssc install mrtab")
    if (nm == "inputcorrection") return("net install inputcorrection, from(" + q + gh + "RanaRedoan/inputcorrection/main" + q + ")")
    if (nm == "exportopenended") return("net install exportopenended, from(" + q + gh + "RanaRedoan/exportopenended/main" + q + ")")
    if (nm == "exporttabs")      return("net install exporttabs, from(" + q + gh + "RanaRedoan/exporttabs/main" + q + ")")
    if (nm == "recode_nrep")     return("net install recode_nrep, from(" + q + gh + "ashikpydev/recode_nrep/main/" + q + ")")
    if (nm == "recode_rep")      return("net install recode_rep, from(" + q + gh + "ashikpydev/recode_rep/main/" + q + ")")
    if (nm == "multisplit")      return("net install multisplit, from(" + q + gh + "ashikpydev/multisplit/main/" + q + ")")
    if (nm == "exportables")     return("net install exportables, from(" + q + gh + "ashikpydev/exportables/main/" + q + ") replace")
    if (nm == "exprep")          return("net install exprep, from(" + q + gh + "ashikpydev/exprep/main" + q + ")")
    if (nm == "recode_oth")      return("net install recode_oth, from(" + q + gh + "ashikpydev/recode_oth/main/" + q + ") replace")
    if (nm == "bias_expo")       return("net install bias_expo, from(" + q + gh + "adinkhan7/bias_expo/main/" + q + ")")
    if (nm == "export_hfc")      return("net install export_hfc, from(" + q + gh + "adinkhan7/export_hfc/main/" + q + ")")
    return("")
}

//  Build the standalone execution context.
//
//  Two shapes share it (ADR-056, ADR-059):
//    generic   a file carried off on its own, data beside it, output to
//              MDF_Output/ — exactly as in 10.2.0
//    package   a file inside a Deliverables package: raw data from
//              02_Import & Raw files/, datasets identified BY NAME against the
//              names this file was generated with, the cleaned dataset written
//              to 04_Cleaned Data/, working files to Stata's temp folder
//
//  `nds'   how many datasets this file was generated for
//  `needs' which package commands this particular file calls, so it carries a
//          fallback only for what it uses: "core", "finalise", or both.
void sa_part_checks(real scalar fh, string scalar q, string scalar bt,
                        string scalar ap, string scalar dol,
                        string scalar pname, string scalar nds,
                        string scalar needs, string scalar ind)
{
    real scalar _k, _nb
    string scalar bs, procfile
    string colvector deps

    bs = char(92)
    procfile = pname + "_Processing.do"
    pragma unused _nb
    pragma unused deps
    pragma unused procfile

    fput(fh, ind + "*  ══ STANDALONE MODE ═══════════════════════════════════════════════")
    fput(fh, ind + "*  No project above this file: either data beside it, or a Deliverables")
    fput(fh, ind + "*  package around it. Everything below is rooted in that folder; nothing")
    fput(fh, ind + "*  outside it is read or written, except Stata's own temp folder.")
    fput(fh, "")

    //  ── Fail loudly: nothing to work on ────────────────────────────────────
    fput(fh, ind + "if " + _mq("_sa_k") + " == 0 {")
    fput(fh, ind + "    di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "    if " + q + dol + "mdf_package" + q + " == " + q + "1" + q + " {")
    fput(fh, ind + "        di as error " + q + "  DELIVERABLES PACKAGE  —  NO RAW DATASET TO REBUILD FROM" + q)
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        di as txt   " + q + "  This file sits in a Deliverables package, but the package's raw-data" + q)
    fput(fh, ind + "        di as txt   " + q + "  folder holds no Stata dataset:" + q)
    fput(fh, ind + "        di as result " + q + "    " + q + " " + _cq("_sa_datadir"))
    fput(fh, ind + "        di as txt   " + q + "  Put the raw .dta that came with the package back in that folder, or" + q)
    fput(fh, ind + "        di as txt   " + q + "  run its import DO there to rebuild it from the CSV, then run again." + q)
    fput(fh, ind + "    }")
    fput(fh, ind + "    else {")
    fput(fh, ind + "        di as error " + q + "  STANDALONE MODE  —  NO DATASET FOUND BESIDE THIS FILE" + q)
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        di as txt   " + q + "  This file is not inside a Master DO File project, so it looked" + q)
    fput(fh, ind + "        di as txt   " + q + "  for Stata datasets in its own folder and found none:" + q)
    fput(fh, ind + "        di as result " + q + "    " + q + " " + _cq("_selfdir"))
    fput(fh, ind + "        di as txt   " + q + "  Stata does not tell a running DO file where it is saved, so that" + q)
    fput(fh, ind + "        di as txt   " + q + "  folder is Stata's WORKING DIRECTORY. If this file is somewhere else," + q)
    fput(fh, ind + "        di as txt   " + q + "  set the working directory to its folder (File > Change working" + q)
    fput(fh, ind + "        di as txt   " + q + "  directory, or double-click the DO to launch Stata there) and run it" + q)
    fput(fh, ind + "        di as txt   " + q + "  again. If it is there, put the .dta file(s) it should read in that" + q)
    fput(fh, ind + "        di as txt   " + q + "  folder (or in a Data/ subfolder) and run it again." + q)
    fput(fh, ind + "        di as txt   " + q + "  Framework output — *_CLEANED, *_KEYS_, *_MERGED_, *_LABELED_ — is" + q)
    fput(fh, ind + "        di as txt   " + q + "  never counted as input, so an earlier run's results cannot stand" + q)
    fput(fh, ind + "        di as txt   " + q + "  in for data." + q)
    fput(fh, ind + "    }")
    fput(fh, ind + "    di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "    exit 198")
    fput(fh, ind + "}")
    fput(fh, "")

    //  ── Fail loudly: a generic folder that does not match this file ────────
    //  A package is matched by NAME below instead: a per-dataset package
    //  legitimately carries fewer datasets than the file was built for.
    fput(fh, ind + "if " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " & " + _mq("_sa_k") + " != " + nds + " {")
    fput(fh, ind + "    di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "    di as error " + q + "  STANDALONE MODE  —  DATASET COUNT DOES NOT MATCH THIS FILE" + q)
    fput(fh, ind + "    di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "    di as txt   " + q + "  This file was generated for " + nds + " dataset(s); the folder holds " + _mq("_sa_k") + ":" + q)
    fput(fh, ind + "    foreach _sa_f of local _sa_cand {")
    fput(fh, ind + "        di as result " + q + "    " + q + " " + _cq("_sa_f"))
    fput(fh, ind + "    }")
    fput(fh, ind + "    di as txt   " + q + "  Looked in: " + q + " " + _cq("_sa_datadir"))
    fput(fh, ind + "    di as txt   " + q + "  Which dataset answers to which check cannot be decided from a" + q)
    fput(fh, ind + "    di as txt   " + q + "  count that does not match, and guessing would check the wrong" + q)
    fput(fh, ind + "    di as txt   " + q + "  data. Leave exactly " + nds + " dataset(s) in the folder, or take" + q)
    fput(fh, ind + "    di as txt   " + q + "  this file from a project built for " + _mq("_sa_k") + " dataset(s)." + q)
    fput(fh, ind + "    di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "    exit 198")
    fput(fh, ind + "}")
    fput(fh, "")
}

void sa_part_identity(real scalar fh, string scalar q, string scalar bt,
                        string scalar ap, string scalar dol,
                        string scalar pname, string scalar nds,
                        string scalar needs, string scalar ind)
{
    real scalar _k, _nb
    string scalar bs, procfile
    string colvector deps

    bs = char(92)
    procfile = pname + "_Processing.do"
    pragma unused _nb
    pragma unused deps
    pragma unused procfile

    //  ── Identity: the same DS1..DSn concepts a managed project uses ────────
    fput(fh, ind + "global mdf_standalone 1")
    fput(fh, ind + "global project_name " + q + pname + q)
    fput(fh, ind + "if " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " {")
    fput(fh, ind + "    global ROOT " + _cq("_selfdir"))
    fput(fh, ind + "    global actual_n_dta " + _mq("_sa_k"))
    fput(fh, ind + "    global n_datasets   " + _mq("_sa_k"))
    fput(fh, ind + "    forvalues _sa_i = 1/" + _mq("_sa_k") + " {")
    fput(fh, ind + "        local _sa_f : word " + _mq("_sa_i") + " of " + _mq("_sa_cand"))
    fput(fh, ind + "        global auto_dsname_" + _mq("_sa_i") + " = substr(" + _cq("_sa_f") + ", 1, strlen(" + _cq("_sa_f") + ") - 4)")
    fput(fh, ind + "        global target_dta_"  + _mq("_sa_i") + " " + bt + q + bt + "_sa_datadir" + ap + "/" + bt + "_sa_f" + ap + q + ap)
    fput(fh, ind + "        global dta_labeled_" + _mq("_sa_i") + " " + bt + q + bt + "_sa_datadir" + ap + "/" + bt + "_sa_f" + ap + q + ap)
    fput(fh, ind + "        global mdf_ds_here_" + _mq("_sa_i") + " 1")
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, ind + "else {")
    fput(fh, ind + "    *  ── Package: every raw dataset must be one this file was built for ──")
    fput(fh, ind + "    *  Identity is the dataset NAME, as Master derives it from the import:")
    fput(fh, ind + "    *  the .dta name, with SurveyCTO's _wide suffix dropped. A file that")
    fput(fh, ind + "    *  answers to no name, or to a name already taken, stops the run.")
    fput(fh, ind + "    global ROOT " + _cq("_sa_pkg"))
    _nb = strtoreal(nds)
    if (_nb >= . | _nb < 1) _nb = 1
    fput(fh, ind + "    local _pk_n " + strofreal(_nb))
    for (_k = 1; _k <= _nb; _k++) {
        fput(fh, ind + "    local _pk_nm" + strofreal(_k) + " " + q + st_global("auto_dsname_" + strofreal(_k)) + q)
    }
    fput(fh, ind + "    global actual_n_dta " + _mq("_pk_n"))
    fput(fh, ind + "    global n_datasets   " + _mq("_pk_n"))
    fput(fh, ind + "    forvalues _pk_i = 1/" + _mq("_pk_n") + " {")
    fput(fh, ind + "        global auto_dsname_" + _mq("_pk_i") + " " + bt + q + bt + "_pk_nm" + bt + "_pk_i" + ap + ap + q + ap)
    fput(fh, ind + "        global target_dta_"  + _mq("_pk_i") + " " + q + q)
    fput(fh, ind + "        global dta_labeled_" + _mq("_pk_i") + " " + q + q)
    fput(fh, ind + "        global mdf_ds_here_" + _mq("_pk_i") + " 0")
    fput(fh, ind + "        global capi_override_" + _mq("_pk_i") + " " + q + q)
    fput(fh, ind + "    }")
    fput(fh, ind + "    local _pk_bad " + q + q)
    fput(fh, ind + "    foreach _sa_f of local _sa_cand {")
    fput(fh, ind + "        local _pk_stem = substr(" + _cq("_sa_f") + ", 1, strlen(" + _cq("_sa_f") + ") - 4)")
    fput(fh, ind + "        if strlen(" + _cq("_pk_stem") + ") > 5 & lower(substr(" + _cq("_pk_stem") + ", -5, 5)) == " + q + "_wide" + q + " local _pk_stem = substr(" + _cq("_pk_stem") + ", 1, strlen(" + _cq("_pk_stem") + ") - 5)")
    fput(fh, ind + "        local _pk_hit 0")
    fput(fh, ind + "        *  A one-dataset package holding one file: nothing to tell apart.")
    fput(fh, ind + "        if " + _mq("_pk_n") + " == 1 & " + _mq("_sa_k") + " == 1 local _pk_hit 1")
    fput(fh, ind + "        forvalues _pk_i = 1/" + _mq("_pk_n") + " {")
    fput(fh, ind + "            if " + _mq("_pk_hit") + " == 0 & lower(" + _cq("_pk_stem") + ") == lower(" + bt + q + bt + "_pk_nm" + bt + "_pk_i" + ap + ap + q + ap + ") local _pk_hit " + _mq("_pk_i"))
    fput(fh, ind + "        }")
    fput(fh, ind + "        local _pk_dup 0")
    fput(fh, ind + "        if " + _mq("_pk_hit") + " > 0 {")
    fput(fh, ind + "            if " + q + dol + "{mdf_ds_here_" + _mq("_pk_hit") + "}" + q + " == " + q + "1" + q + " local _pk_dup 1")
    fput(fh, ind + "        }")
    fput(fh, ind + "        if " + _mq("_pk_hit") + " == 0 | " + _mq("_pk_dup") + " == 1 {")
    fput(fh, ind + "            local _pk_bad " + bt + q + bt + "_pk_bad" + ap + " " + bt + q + bt + "_sa_f" + ap + q + ap + q + ap)
    fput(fh, ind + "        }")
    fput(fh, ind + "        else {")
    fput(fh, ind + "            global mdf_ds_here_" + _mq("_pk_hit") + " 1")
    fput(fh, ind + "            global target_dta_"  + _mq("_pk_hit") + " " + bt + q + bt + "_sa_datadir" + ap + "/" + bt + "_sa_f" + ap + q + ap)
    fput(fh, ind + "            global dta_labeled_" + _mq("_pk_hit") + " " + bt + q + bt + "_sa_datadir" + ap + "/" + bt + "_sa_f" + ap + q + ap)
    fput(fh, ind + "        }")
    fput(fh, ind + "    }")
    fput(fh, ind + "    if " + _cq("_pk_bad") + " != " + q + q + " {")
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        di as error " + q + "  DELIVERABLES PACKAGE  —  A DATASET COULD NOT BE IDENTIFIED" + q)
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        di as txt   " + q + "  Every raw dataset in the package must be one this file was built" + q)
    fput(fh, ind + "        di as txt   " + q + "  for, named as it was in the project. These are not:" + q)
    fput(fh, ind + "        foreach _sa_f of local _pk_bad {")
    fput(fh, ind + "            di as result " + q + "    " + q + " " + _cq("_sa_f"))
    fput(fh, ind + "        }")
    fput(fh, ind + "        di as txt   " + q + "  Looked in: " + q + " " + _cq("_sa_datadir"))
    fput(fh, ind + "        di as txt   " + q + "  This file knows these datasets:" + q)
    fput(fh, ind + "        forvalues _pk_i = 1/" + _mq("_pk_n") + " {")
    fput(fh, ind + "            di as result " + q + "    " + q + " " + bt + q + bt + "_pk_nm" + bt + "_pk_i" + ap + ap + ".dta" + q + ap)
    fput(fh, ind + "        }")
    fput(fh, ind + "        di as txt   " + q + "  Which dataset a file is cannot be guessed, and guessing would clean" + q)
    fput(fh, ind + "        di as txt   " + q + "  the wrong data. Rename or remove the file(s) above and run again." + q)
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        exit 198")
    fput(fh, ind + "    }")
    fput(fh, ind + "    *  A dataset this package does not carry has no cleaned file to publish.")
    fput(fh, ind + "    *  Its pointer is cleared so a pointer left in this Stata session by")
    fput(fh, ind + "    *  another package cannot be published here in its place. A carried")
    fput(fh, ind + "    *  dataset's pointer is left alone: the Processing DO sets it before")
    fput(fh, ind + "    *  the modules it calls re-enter this block.")
    fput(fh, ind + "    forvalues _pk_i = 1/" + _mq("_pk_n") + " {")
    fput(fh, ind + "        if " + q + dol + "{mdf_ds_here_" + _mq("_pk_i") + "}" + q + " != " + q + "1" + q + " global dta_cleaned_" + _mq("_pk_i") + " " + q + q)
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, ind + "global target_dta  " + q + dol + "{target_dta_1}"  + q)
    fput(fh, ind + "global dta_labeled " + q + dol + "{dta_labeled_1}" + q)
    fput(fh, "")
}

void sa_part_folders(real scalar fh, string scalar q, string scalar bt,
                        string scalar ap, string scalar dol,
                        string scalar pname, string scalar nds,
                        string scalar needs, string scalar ind)
{
    real scalar _k, _nb
    string scalar bs, procfile
    string colvector deps

    bs = char(92)
    procfile = pname + "_Processing.do"
    pragma unused _nb
    pragma unused deps
    pragma unused procfile

    //  ── Dates ──────────────────────────────────────────────────────────────
    fput(fh, ind + "local _sa_dt = daily(" + q + bt + "c(current_date)" + ap + q + ", " + q + "DMY" + q + ")")
    fput(fh, ind + "local _sa_ds : display %tdCCYYNNDD " + _mq("_sa_dt"))
    fput(fh, ind + "global today = strtrim(" + q + _mq("_sa_ds") + q + ")")
    fput(fh, ind + "local _sa_dy = " + _mq("_sa_dt") + " - 1")
    fput(fh, ind + "local _sa_dys : display %tdCCYYNNDD " + _mq("_sa_dy"))
    fput(fh, ind + "global yesterday = strtrim(" + q + _mq("_sa_dys") + q + ")")
    fput(fh, ind + "global hfc_folder_date " + q + dol + "today" + q)
    fput(fh, ind + "global LAST_RUN_DATE   " + q + dol + "today" + q)
    fput(fh, "")

    //  ── Output ─────────────────────────────────────────────────────────────
    fput(fh, ind + "if " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " {")
    fput(fh, ind + "    *  One folder, always beside this file.")
    fput(fh, ind + "    global mdf_out " + bt + q + bt + "_selfdir" + ap + "/MDF_Output" + q + ap)
    fput(fh, ind + "    cap mkdir " + q + dol + "mdf_out" + q)
    fput(fh, ind + "    global clean_dir            " + q + dol + "mdf_out" + q)
    fput(fh, ind + "}")
    fput(fh, ind + "else {")
    fput(fh, ind + "    *  The package receives only the cleaned dataset, in 04_Cleaned Data/.")
    fput(fh, ind + "    *  The dated working copy the workflow saves on the way goes to Stata's")
    fput(fh, ind + "    *  temp folder.")
    fput(fh, ind + "    local _pk_tmp = subinstr(" + bt + q + bt + "c(tmpdir)" + ap + q + ap + ", " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, ind + "    if substr(" + _cq("_pk_tmp") + ", -1, 1) == " + q + "/" + q + " local _pk_tmp = substr(" + _cq("_pk_tmp") + ", 1, strlen(" + _cq("_pk_tmp") + ") - 1)")
    fput(fh, ind + "    global mdf_out " + bt + q + bt + "_pk_tmp" + ap + "/mdf_package_work" + q + ap)
    fput(fh, ind + "    cap mkdir " + q + dol + "mdf_out" + q)
    fput(fh, ind + "    global clean_dir " + bt + q + bt + "_sa_pkg" + ap + "/04_Cleaned Data" + q + ap)
    fput(fh, ind + "    cap mkdir " + q + dol + "clean_dir" + q)
    fput(fh, ind + "}")
    fput(fh, ind + "global hfc_run_dir          " + q + dol + "mdf_out" + q)
    fput(fh, ind + "global hfc_dir              " + q + dol + "mdf_out" + q)
    fput(fh, ind + "global hfc_keys_dir         " + q + dol + "mdf_out/KEYS" + q)
    fput(fh, ind + "global hfc_keys_hfc_dir     " + q + dol + "hfc_keys_dir/01_HFC_Keys" + q)
    fput(fh, ind + "global hfc_keys_audio_dir   " + q + dol + "hfc_keys_dir/02_Audio_Keys" + q)
    fput(fh, ind + "global hfc_keys_trans_dir   " + q + dol + "hfc_keys_dir/03_Translation_Keys" + q)
    fput(fh, ind + "global hfc_keys_master_dir  " + q + dol + "hfc_keys_hfc_dir" + q)
    fput(fh, ind + "global hfc_flag_dir         " + q + dol + "hfc_keys_dir/.flag_history" + q)
    fput(fh, ind + "cap mkdir " + q + dol + "hfc_keys_dir" + q)
    fput(fh, ind + "cap mkdir " + q + dol + "hfc_keys_hfc_dir" + q)
    fput(fh, ind + "cap mkdir " + q + dol + "hfc_keys_audio_dir" + q)
    fput(fh, ind + "cap mkdir " + q + dol + "hfc_keys_trans_dir" + q)
    fput(fh, ind + "cap mkdir " + q + dol + "hfc_flag_dir" + q)
    fput(fh, ind + "global hfc_report " + q + dol + "mdf_out/HFC_" + dol + "{project_name}_" + dol + "today.xlsx" + q)
    fput(fh, "")

    //  ── Input folders ──────────────────────────────────────────────────────
    fput(fh, ind + "global data_dir             " + _cq("_sa_datadir"))
    fput(fh, ind + "global raw_data_dir         " + _cq("_sa_datadir"))
    fput(fh, ind + "global hfc_rawdata_dir      " + _cq("_sa_datadir"))
    fput(fh, ind + "global hfc_raw_snapshot_dir " + _cq("_sa_datadir"))
    fput(fh, ind + "if " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " {")
    fput(fh, ind + "    global dofiles_dir          " + _cq("_selfdir"))
    fput(fh, ind + "    global processing_dir       " + _cq("_selfdir"))
    fput(fh, ind + "    global processing_data_dir  " + _cq("_sa_datadir"))
    fput(fh, ind + "    global surv_inst_dir        " + _cq("_selfdir"))
    fput(fh, ind + "}")
    fput(fh, ind + "else {")
    fput(fh, ind + "    global processing_dir       " + bt + q + bt + "_sa_pkg" + ap + "/03_Processing Files" + q + ap)
    fput(fh, ind + "    global processing_data_dir  " + q + dol + "processing_dir/03_Data" + q)
    fput(fh, ind + "    global dofiles_dir          " + q + dol + "processing_dir" + q)
    fput(fh, ind + "    global surv_inst_dir        " + _cq("_sa_pkg"))
    fput(fh, ind + "}")
    fput(fh, ind + "*  The modules sit beside the Processing DO, or in a 01_Do Files/")
    fput(fh, ind + "*  subfolder of it (the v11 arrangement).")
    fput(fh, ind + "local _sa_ok 0")
    fput(fh, ind + "mata: st_local(" + q + "_sa_ok" + q + ", strofreal(direxists(st_global(" + q + "dofiles_dir" + q + ") + " + q + "/01_Do Files" + q + ")))")
    fput(fh, ind + "if " + _mq("_sa_ok") + " == 1 global dofiles_dir " + q + dol + "dofiles_dir/01_Do Files" + q)
    fput(fh, ind + "*  The framework's own already-bootstrapped flag. Every module tests it,")
    fput(fh, ind + "*  and so does the secondary guard, which would otherwise reload another")
    fput(fh, ind + "*  project's directory file over the context just built here.")
    fput(fh, ind + "global hfc_dofiles_dir      " + q + dol + "dofiles_dir" + q)
    fput(fh, "")

    //  ── CAPI material ──────────────────────────────────────────────────────
    fput(fh, ind + "if " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " {")
    fput(fh, ind + "    global capi_dir " + _cq("_selfdir"))
    fput(fh, ind + "    foreach _sa_c in " + q + "02_CAPI" + q + " " + q + "CAPI" + q + " " + q + "01_Survey_Instruments/02_CAPI" + q + " {")
    fput(fh, ind + "        local _sa_ok 0")
    fput(fh, ind + "        mata: st_local(" + q + "_sa_ok" + q + ", strofreal(direxists(" + q + bt + "_selfdir" + ap + "/" + bt + "_sa_c" + ap + q + ")))")
    fput(fh, ind + "        if " + _mq("_sa_ok") + " == 1 {")
    fput(fh, ind + "            global capi_dir " + bt + q + bt + "_selfdir" + ap + "/" + bt + "_sa_c" + ap + q + ap)
    fput(fh, ind + "        }")
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, ind + "else {")
    fput(fh, ind + "    global capi_dir  " + bt + q + bt + "_sa_pkg" + ap + "/01_CAPI & Questionnaire" + q + ap)
    fput(fh, ind + "    global quest_dir " + q + dol + "capi_dir" + q)
    fput(fh, ind + "}")
    fput(fh, "")

    //  ── Translation material ───────────────────────────────────────────────
    fput(fh, ind + "if " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " {")
    fput(fh, ind + "    global translation_dir " + q + dol + "mdf_out/Translation" + q)
    fput(fh, ind + "    foreach _sa_c in " + q + "02_Translation" + q + " " + q + "05_Translation" + q + " " + q + "Translation" + q + " {")
    fput(fh, ind + "        local _sa_ok 0")
    fput(fh, ind + "        mata: st_local(" + q + "_sa_ok" + q + ", strofreal(direxists(" + q + bt + "_selfdir" + ap + "/" + bt + "_sa_c" + ap + q + ")))")
    fput(fh, ind + "        if " + _mq("_sa_ok") + " == 1 {")
    fput(fh, ind + "            global translation_dir " + bt + q + bt + "_selfdir" + ap + "/" + bt + "_sa_c" + ap + q + ap)
    fput(fh, ind + "        }")
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, ind + "else global translation_dir " + q + dol + "processing_dir/02_Translation" + q)
    fput(fh, ind + "global trans_exported_dir   " + q + dol + "translation_dir/01_Exported" + q)
    fput(fh, ind + "global trans_translated_dir " + q + dol + "translation_dir/02_Translated" + q)
    fput(fh, ind + "cap mkdir " + q + dol + "translation_dir" + q)
    fput(fh, ind + "cap mkdir " + q + dol + "trans_exported_dir" + q)
    fput(fh, ind + "cap mkdir " + q + dol + "trans_translated_dir" + q)
    fput(fh, "")
}

void sa_part_config(real scalar fh, string scalar q, string scalar bt,
                        string scalar ap, string scalar dol,
                        string scalar pname, string scalar nds,
                        string scalar needs, string scalar ind)
{
    real scalar _k, _nb
    string scalar bs, procfile
    string colvector deps

    bs = char(92)
    procfile = pname + "_Processing.do"
    pragma unused _nb
    pragma unused deps
    pragma unused procfile

    //  ── Survey configuration, as this file was generated with it ──────────
    fput(fh, ind + "global sample_size  " + st_global("sample_size"))
    fput(fh, ind + "global meta_front   " + q + st_global("meta_front")  + q)
    fput(fh, ind + "global meta_ids     " + q + st_global("meta_ids")    + q)
    fput(fh, ind + "global tail         " + q + st_global("tail")        + q)
    fput(fh, ind + "global timer_start  " + q + st_global("timer_start") + q)
    fput(fh, ind + "global timer_end    " + q + st_global("timer_end")   + q)
    for (_k = 1; _k <= 3; _k++) {
    fput(fh, ind + "global meta_front_" + strofreal(_k) + " " + q + st_global("meta_front_" + strofreal(_k)) + q)
    fput(fh, ind + "global meta_ids_"   + strofreal(_k) + " " + q + st_global("meta_ids_"   + strofreal(_k)) + q)
    fput(fh, ind + "global tail_"       + strofreal(_k) + " " + q + st_global("tail_"       + strofreal(_k)) + q)
    }
    fput(fh, ind + "global hfc_openended_vars   " + q + st_global("hfc_openended_vars")   + q)
    fput(fh, ind + "global hfc_openended_vars_1 " + q + st_global("hfc_openended_vars_1") + q)
    fput(fh, ind + "global hfc_openended_vars_2 " + q + st_global("hfc_openended_vars_2") + q)
    fput(fh, ind + "global hfc_openended_vars_3 " + q + st_global("hfc_openended_vars_3") + q)
    fput(fh, ind + "global oe_export_all   " + q + st_global("oe_export_all")   + q)
    fput(fh, "")
    fput(fh, ind + "*  Stage switches, unlike the survey constants above, are settings a")
    fput(fh, ind + "*  caller may legitimately want to change: a wrapper DO can set one")
    fput(fh, ind + "*  before running this file. Only fill in what the session has not.")
    fput(fh, ind + "if " + q + dol + "run_labeling" + q + "    == " + q + q + " global run_labeling    " + q + st_global("run_labeling")    + q)
    fput(fh, ind + "if " + q + dol + "exportopenended" + q + " == " + q + q + " global exportopenended " + q + st_global("exportopenended") + q)
    fput(fh, ind + "if " + q + dol + "inputcorrection" + q + " == " + q + q + " global inputcorrection " + q + st_global("inputcorrection") + q)
    fput(fh, ind + "global capi_language " + q + st_global("capi_language") + q)
    fput(fh, ind + "global capi_override " + q + st_global("capi_override") + q)
    fput(fh, ind + "global capi_verbose  " + q + st_global("capi_verbose")  + q)
    fput(fh, ind + "global code_dk    " + q + st_global("code_dk")    + q)
    fput(fh, ind + "global code_na    " + q + st_global("code_na")    + q)
    fput(fh, ind + "global code_other " + q + st_global("code_other") + q)
    fput(fh, ind + "global verbose    " + q + st_global("verbose")    + q)
    fput(fh, ind + "global audio_seed         " + q + st_global("audio_seed")         + q)
    fput(fh, ind + "global audio_sample_count " + q + st_global("audio_sample_count") + q)
    fput(fh, ind + "global audio_drop_before  " + q + st_global("audio_drop_before")  + q)
    fput(fh, ind + "global audio_keep_enums   " + q + st_global("audio_keep_enums")   + q)
    fput(fh, ind + "global merge_required  " + q + st_global("merge_required") + q)
    fput(fh, ind + "global merge_datasets  " + q + st_global("merge_datasets") + q)
    fput(fh, ind + "global merge_type      " + q + st_global("merge_type")     + q)
    fput(fh, ind + "global merge_key       " + q + st_global("merge_key")      + q)
    fput(fh, "")
    fput(fh, ind + "*  Stages that only mean anything inside a managed project.")
    fput(fh, ind + "global post_field           0")
    fput(fh, ind + "global run_import           0")
    fput(fh, ind + "global import_fingerprint   0")
    fput(fh, ind + "global hfc_postfield_active 0")
    fput(fh, "")
}

void sa_part_package(real scalar fh, string scalar q, string scalar bt,
                        string scalar ap, string scalar dol,
                        string scalar pname, string scalar nds,
                        string scalar needs, string scalar ind)
{
    real scalar _k, _nb
    string scalar bs, procfile
    string colvector deps

    bs = char(92)
    procfile = pname + "_Processing.do"
    pragma unused _nb
    pragma unused deps
    pragma unused procfile

    //  ── Package: what reproducing the cleaned dataset needs ────────────────
    fput(fh, ind + "if " + q + dol + "mdf_package" + q + " == " + q + "1" + q + " {")
    fput(fh, ind + "    *  Rebuilding never sends text to a translator, and a per-dataset")
    fput(fh, ind + "    *  package has no second dataset to merge with.")
    fput(fh, ind + "    global exportopenended 0")
    fput(fh, ind + "    global merge_required  0")
    fput(fh, "")
    fput(fh, ind + "    *  ── The SurveyCTO form: the one workbook with survey + choices sheets ─")
    fput(fh, ind + "    *  The questionnaire shares this folder, possibly as a spreadsheet too,")
    fput(fh, ind + "    *  so a form is recognised by its sheets rather than by being an .xlsx.")
    fput(fh, ind + "    local _pk_form " + q + q)
    fput(fh, ind + "    local _pk_nf 0")
    fput(fh, ind + "    local _pk_xl " + q + q)
    fput(fh, ind + "    cap local _pk_xl : dir " + q + dol + "capi_dir" + q + " files " + q + "*.xlsx" + q + ", respectcase")
    fput(fh, ind + "    local _pk_xl : list sort _pk_xl")
    fput(fh, ind + "    foreach _pk_f of local _pk_xl {")
    fput(fh, ind + "        if substr(" + _cq("_pk_f") + ", 1, 1) == " + q + "~" + q + " continue")
    fput(fh, ind + "        cap qui import excel using " + bt + q + dol + "capi_dir/" + bt + "_pk_f" + ap + q + ap + ", describe")
    fput(fh, ind + "        if _rc continue")
    fput(fh, ind + "        local _pk_s 0")
    fput(fh, ind + "        local _pk_c 0")
    fput(fh, ind + "        local _pk_nw = r(N_worksheet)")
    fput(fh, ind + "        forvalues _pk_w = 1/" + _mq("_pk_nw") + " {")
    fput(fh, ind + "            local _pk_wn = lower(strtrim(" + bt + q + bt + "r(worksheet_" + bt + "_pk_w" + ap + ")" + ap + q + ap + "))")
    fput(fh, ind + "            if " + _cq("_pk_wn") + " == " + q + "survey" + q + "  local _pk_s 1")
    fput(fh, ind + "            if " + _cq("_pk_wn") + " == " + q + "choices" + q + " local _pk_c 1")
    fput(fh, ind + "        }")
    fput(fh, ind + "        if " + _mq("_pk_s") + " == 1 & " + _mq("_pk_c") + " == 1 {")
    fput(fh, ind + "            local _pk_form " + _cq("_pk_f"))
    fput(fh, ind + "            local _pk_nf = " + _mq("_pk_nf") + " + 1")
    fput(fh, ind + "        }")
    fput(fh, ind + "    }")
    fput(fh, ind + "    if " + _mq("_pk_nf") + " > 1 {")
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        di as error " + q + "  DELIVERABLES PACKAGE  —  MORE THAN ONE SURVEYCTO FORM" + q)
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        di as txt   " + q + "  01_CAPI & Questionnaire/ holds " + q + " " + _mq("_pk_nf") + " " + q + " SurveyCTO forms. The package" + q)
    fput(fh, ind + "        di as txt   " + q + "  carries exactly one, and which one labelled the data cannot be" + q)
    fput(fh, ind + "        di as txt   " + q + "  guessed. Remove the extra form(s) and run again:" + q)
    fput(fh, ind + "        di as result " + q + "    " + q + " " + q + dol + "capi_dir" + q)
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        exit 198")
    fput(fh, ind + "    }")
    fput(fh, ind + "    if " + _mq("_pk_nf") + " == 0 & " + q + dol + "run_labeling" + q + " == " + q + "1" + q + " {")
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        di as error " + q + "  DELIVERABLES PACKAGE  —  THE SURVEYCTO FORM IS MISSING" + q)
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        di as txt   " + q + "  The cleaned dataset was labelled from a SurveyCTO form, and none is" + q)
    fput(fh, ind + "        di as txt   " + q + "  in 01_CAPI & Questionnaire/. Without it the rebuild would carry no" + q)
    fput(fh, ind + "        di as txt   " + q + "  value labels and would not match. Nothing has been written." + q)
    fput(fh, ind + "        di as result " + q + "    " + q + " " + q + dol + "capi_dir" + q)
    fput(fh, ind + "        di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "        exit 198")
    fput(fh, ind + "    }")
    fput(fh, ind + "    if " + _mq("_pk_nf") + " == 1 {")
    fput(fh, ind + "        global capi_override " + _cq("_pk_form"))
    fput(fh, ind + "        forvalues _pk_i = 1/" + dol + "actual_n_dta {")
    fput(fh, ind + "            if " + q + dol + "{mdf_ds_here_" + _mq("_pk_i") + "}" + q + " == " + q + "1" + q + " global capi_override_" + _mq("_pk_i") + " " + _cq("_pk_form"))
    fput(fh, ind + "        }")
    fput(fh, ind + "    }")
    fput(fh, "")

    //  ── Package: the survey commands the rebuild uses ───────────────────
    //  A client machine has no reason to carry them. Without odksplit the
    //  labels are missing, without inputcorrection the translations are, and
    //  the rebuild would differ from the original with nothing said. So each
    //  is installed from the source Master uses when it is absent, and if that
    //  cannot be done the run stops before a dataset is written. Other survey
    //  commands the cleaning code names are installed when absent too; they
    //  are not fatal here, because a missing one stops the run by itself.
    //  Done once per package per session.
    deps = _mdf_dep_names()
    fput(fh, ind + "    if " + q + dol + "mdf_pkg_deps_ok" + q + " != " + _cq("_sa_pkg") + " {")
    fput(fh, ind + "        local _pk_need " + q + q)
    fput(fh, ind + "        if " + q + dol + "run_labeling" + q + " == " + q + "1" + q + " local _pk_need " + q + "odksplit" + q)
    fput(fh, ind + "        if " + q + dol + "inputcorrection" + q + " == " + q + "1" + q + " {")
    fput(fh, ind + "            local _pk_tx " + q + q)
    fput(fh, ind + "            cap local _pk_tx : dir " + q + dol + "trans_translated_dir" + q + " files " + q + "*.xlsx" + q)
    fput(fh, ind + "            local _pk_td " + q + q)
    fput(fh, ind + "            cap local _pk_td : dir " + q + dol + "trans_translated_dir" + q + " dirs " + q + "*" + q)
    fput(fh, ind + "            foreach _pk_d of local _pk_td {")
    fput(fh, ind + "                local _pk_t2 " + q + q)
    fput(fh, ind + "                cap local _pk_t2 : dir " + bt + q + dol + "trans_translated_dir/" + bt + "_pk_d" + ap + q + ap + " files " + q + "*.xlsx" + q)
    fput(fh, ind + "                local _pk_tx " + bt + q + bt + "_pk_tx" + ap + " " + bt + "_pk_t2" + ap + q + ap)
    fput(fh, ind + "            }")
    //  Counted, not compared with "": the list is built by concatenation and
    //  is a lone space when there is nothing in it.
    fput(fh, ind + "            local _pk_ntx : word count " + _mq("_pk_tx"))
    fput(fh, ind + "            if " + _mq("_pk_ntx") + " > 0 local _pk_need " + q + bt + "_pk_need" + ap + " inputcorrection" + q)
    fput(fh, ind + "        }")
    fput(fh, ind + "        foreach _pk_c of local _pk_need {")
    fput(fh, ind + "            cap which " + _mq("_pk_c"))
    fput(fh, ind + "            if _rc {")
    fput(fh, ind + "                di as txt " + q + "  " + _mq("_pk_c") + " is not installed on this machine; installing it..." + q)
    fput(fh, ind + "                if " + q + _mq("_pk_c") + q + " == " + q + "odksplit" + q + " cap noi " + _mdf_dep_install("odksplit"))
    fput(fh, ind + "                if " + q + _mq("_pk_c") + q + " == " + q + "inputcorrection" + q + " cap noi " + _mdf_dep_install("inputcorrection"))
    fput(fh, ind + "                cap which " + _mq("_pk_c"))
    fput(fh, ind + "                if _rc {")
    fput(fh, ind + "                    di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "                    di as error " + q + "  DELIVERABLES PACKAGE  —  " + _mq("_pk_c") + " IS NOT AVAILABLE" + q)
    fput(fh, ind + "                    di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "                    di as txt   " + q + "  The cleaned dataset was produced with the Stata command " + _mq("_pk_c") + "," + q)
    fput(fh, ind + "                    di as txt   " + q + "  which is not installed here and could not be installed (no" + q)
    fput(fh, ind + "                    di as txt   " + q + "  connection?). Without it the rebuild would not match, so nothing" + q)
    fput(fh, ind + "                    di as txt   " + q + "  has been written. Install it, then run this file again:" + q)
    fput(fh, ind + "                    if " + q + _mq("_pk_c") + q + " == " + q + "odksplit" + q + " di as result " + q + "    " + _mdf_dep_install("odksplit") + q)
    fput(fh, ind + "                    if " + q + _mq("_pk_c") + q + " == " + q + "inputcorrection" + q + " di as result " + bt + q + "    " + _mdf_dep_install("inputcorrection") + q + ap)
    fput(fh, ind + "                    di as error " + q + "=====================================================================" + q)
    fput(fh, ind + "                    exit 199")
    fput(fh, ind + "                }")
    fput(fh, ind + "            }")
    fput(fh, ind + "        }")
    fput(fh, ind + "        *  The rest: only what the Processing DO actually names.")
    fput(fh, ind + "        local _pk_src " + bt + q + dol + "processing_dir/" + procfile + q + ap)
    fput(fh, ind + "        local _pk_want " + q + q)
    //  Read in Mata: a line held in a Stata macro would have the macro
    //  references in the analyst's own code expanded on use, and one stray
    //  quote there would stop the rebuild with a syntax error.
    fput(fh, ind + "        cap confirm file " + _cq("_pk_src"))
    fput(fh, ind + "        if !_rc {")
    fput(fh, ind + "            mata: _mdf_pk_L = strtrim(cat(st_local(" + q + "_pk_src" + q + ")))")
    //  Comments do not count, and nor does this preflight's own code, which
    //  names every command it can install (its locals all start _pk_).
    fput(fh, ind + "            mata: _mdf_pk_L = select(_mdf_pk_L, (substr(_mdf_pk_L, 1, 1) :!= " + q + "*" + q + ") :& (strpos(_mdf_pk_L, " + q + "_pk_" + q + ") :== 0))")
    //  exportopenended is left out: it is also the name of a Section 0 switch
    //  every Processing DO reads, and exporting is off in a package anyway.
    _dl = ""
    for (_k = 3; _k <= rows(deps); _k++) {
        if (deps[_k] != "exportopenended") _dl = _dl + " " + deps[_k]
    }
    fput(fh, ind + "            foreach _pk_c in" + _dl + " {")
    fput(fh, ind + "                local _pk_h 0")
    fput(fh, ind + "                mata: st_local(" + q + "_pk_h" + q + ", strofreal(sum(strpos(_mdf_pk_L, st_local(" + q + "_pk_c" + q + ")) :> 0) > 0))")
    fput(fh, ind + "                if " + _mq("_pk_h") + " == 1 local _pk_want " + q + bt + "_pk_want" + ap + " " + bt + "_pk_c" + ap + q)
    fput(fh, ind + "            }")
    fput(fh, ind + "            cap mata: mata drop _mdf_pk_L")
    fput(fh, ind + "        }")
    fput(fh, ind + "        foreach _pk_c of local _pk_want {")
    fput(fh, ind + "            cap which " + _mq("_pk_c"))
    fput(fh, ind + "            if _rc {")
    fput(fh, ind + "                di as txt " + q + "  " + _mq("_pk_c") + " is used by the cleaning code and is not installed; installing it..." + q)
    for (_k = 3; _k <= rows(deps); _k++) {
        fput(fh, ind + "                if " + q + _mq("_pk_c") + q + " == " + q + deps[_k] + q + " cap noi " + _mdf_dep_install(deps[_k]))
    }
    fput(fh, ind + "                cap which " + _mq("_pk_c"))
    fput(fh, ind + "                if _rc di as error " + q + "  WARNING: " + _mq("_pk_c") + " could not be installed. If the cleaning needs it, the run will stop there." + q)
    fput(fh, ind + "            }")
    fput(fh, ind + "        }")
    fput(fh, ind + "        global mdf_pkg_deps_ok " + _cq("_sa_pkg"))
    fput(fh, ind + "    }")
    fput(fh, ind + "}")
    fput(fh, "")

    fput(fh, ind + "forvalues _sa_i = 1/" + dol + "actual_n_dta {")
    fput(fh, ind + "    global pre_keys_" + _mq("_sa_i") + " " + bt + q + dol + "hfc_keys_master_dir/" + dol + "{auto_dsname_" + bt + "_sa_i" + ap + "}_KEYS_" + dol + "LAST_RUN_DATE.dta" + q + ap)
    fput(fh, ind + "}")
    fput(fh, "")
}

void sa_part_tail(real scalar fh, string scalar q, string scalar bt,
                        string scalar ap, string scalar dol,
                        string scalar pname, string scalar nds,
                        string scalar needs, string scalar ind)
{
    real scalar _k, _nb
    string scalar bs, procfile
    string colvector deps

    bs = char(92)
    procfile = pname + "_Processing.do"
    pragma unused _nb
    pragma unused deps
    pragma unused procfile

    //  ── Helper programs, in case the package is not installed ─────────────
    fput(fh, ind + "*  ── Helpers, for a machine with no framework installed ─────────────")
    write_module_helpers(fh, q, bt, ap, dol)
    fput(fh, "")

    if (strpos(needs, "core") > 0) {
        fput(fh, "cap which mdf_core_vars")
        fput(fh, "if _rc {")
        fput(fh, "    cap program drop mdf_core_vars")
        fput(fh, "    program define mdf_core_vars")
        fput(fh, "        cap confirm variable fielddate")
        fput(fh, "        if _rc {")
        fput(fh, "            cap confirm variable starttime")
        fput(fh, "            if !_rc {")
        fput(fh, "                cap gen double fielddate = dofc(starttime)")
        fput(fh, "                cap format fielddate %td")
        fput(fh, "            }")
        fput(fh, "        }")
        fput(fh, "        cap confirm variable total_duration")
        fput(fh, "        if _rc {")
        fput(fh, "            cap confirm variable duration")
        fput(fh, "            if !_rc {")
        fput(fh, "                cap destring duration, replace force")
        fput(fh, "                cap gen total_duration = duration / 60")
        fput(fh, "            }")
        fput(fh, "        }")
        fput(fh, "    end")
        fput(fh, "}")
        fput(fh, "")
    }

    if (strpos(needs, "finalise") > 0) {
        fput(fh, "cap which mdf_finalise")
        fput(fh, "if _rc {")
        fput(fh, "    cap program drop mdf_finalise")
        fput(fh, "    program define mdf_finalise")
        fput(fh, "        args _mode")
        fput(fh, "        if " + q + bt + "_mode" + ap + q + " == " + q + q + " local _mode " + q + "all" + q)
        fput(fh, "        if " + q + bt + "_mode" + ap + q + " == " + q + "merge" + q + " | " + q + bt + "_mode" + ap + q + " == " + q + "all" + q + " {")
        fput(fh, "            if " + q + dol + "merge_required" + q + " == " + q + "1" + q + " {")
        fput(fh, "                local _ds1 : word 1 of " + dol + "merge_datasets")
        fput(fh, "                local _ds2 : word 2 of " + dol + "merge_datasets")
        fput(fh, "                local _cln1 " + q + dol + "{dta_cleaned_" + bt + "_ds1" + ap + "}" + q)
        fput(fh, "                local _cln2 " + q + dol + "{dta_cleaned_" + bt + "_ds2" + ap + "}" + q)
        fput(fh, "                if " + q + bt + "_cln1" + ap + q + " != " + q + q + " & " + q + bt + "_cln2" + ap + q + " != " + q + q + " {")
        fput(fh, "                    use " + q + bt + "_cln2" + ap + q + ", clear")
        fput(fh, "                    rename * u_*")
        fput(fh, "                    rename u_" + dol + "merge_key " + dol + "merge_key")
        fput(fh, "                    cap tostring " + dol + "merge_key, replace force format(%20.0g)")
        fput(fh, "                    tempfile _using_tmp")
        fput(fh, "                    save " + q + bt + "_using_tmp" + ap + q + ", replace")
        fput(fh, "                    use " + q + bt + "_cln1" + ap + q + ", clear")
        fput(fh, "                    rename * m_*")
        fput(fh, "                    rename m_" + dol + "merge_key " + dol + "merge_key")
        fput(fh, "                    cap rename m_key key")
        fput(fh, "                    cap tostring " + dol + "merge_key, replace force format(%20.0g)")
        fput(fh, "                    merge " + dol + "merge_type " + dol + "merge_key using " + q + bt + "_using_tmp" + ap + q + ", gen(_merge_post) force")
        fput(fh, "                    local _sfx = subinstr(" + q + dol + "merge_datasets" + q + ", " + q + " " + q + ", " + q + "_" + q + ", .)")
        fput(fh, "                    save " + q + dol + "hfc_run_dir/" + dol + "{project_name}_" + bt + "_sfx" + ap + "_MERGED_" + dol + "hfc_folder_date.dta" + q + ", replace")
        fput(fh, "                    di as result " + q + "  Merged dataset saved." + q)
        fput(fh, "                }")
        fput(fh, "            }")
        fput(fh, "        }")
        fput(fh, "        if " + q + bt + "_mode" + ap + q + " == " + q + "publish" + q + " | " + q + bt + "_mode" + ap + q + " == " + q + "all" + q + " {")
        fput(fh, "            forvalues _ds = 1/" + dol + "actual_n_dta {")
        fput(fh, "                local _src " + q + dol + "{dta_cleaned_" + bt + "_ds" + ap + "}" + q)
        fput(fh, "                cap confirm file " + q + bt + "_src" + ap + q)
        fput(fh, "                if _rc {")
        fput(fh, "                    di as txt " + q + "  DS" + bt + "_ds" + ap + ": no cleaned dataset produced — nothing to publish." + q)
        fput(fh, "                    continue")
        fput(fh, "                }")
        fput(fh, "                local _nm " + q + dol + "{auto_dsname_" + bt + "_ds" + ap + "}" + q)
        fput(fh, "                if " + q + bt + "_nm" + ap + q + " == " + q + q + " local _nm " + q + "DS" + bt + "_ds" + ap + q)
        fput(fh, "                cap copy " + q + bt + "_src" + ap + q + " " + q + dol + "clean_dir/" + bt + "_nm" + ap + "_CLEANED.dta" + q + ", replace")
        fput(fh, "                if !_rc di as result " + q + "  Published → " + bt + "_nm" + ap + "_CLEANED.dta" + q)
        fput(fh, "            }")
        fput(fh, "        }")
        fput(fh, "    end")
        fput(fh, "}")
        fput(fh, "")
    }

    //  ── Announce, loudly and specifically ─────────────────────────────────
    fput(fh, ind + "if " + q + dol + "mdf_package" + q + " == " + q + "1" + q + " {")
    fput(fh, ind + "    di as result " + q + "=====================================================================" + q)
    fput(fh, ind + "    di as result " + q + "  DELIVERABLES PACKAGE  —  rebuilding the cleaned dataset here" + q)
    fput(fh, ind + "    di as result " + q + "=====================================================================" + q)
    fput(fh, ind + "    di as txt    " + q + "    package  : " + q + " " + _cq("_sa_pkg"))
    fput(fh, ind + "    di as txt    " + q + "    raw data : " + q + " " + _cq("_sa_datadir"))
    fput(fh, ind + "    forvalues _sa_i = 1/" + dol + "actual_n_dta {")
    fput(fh, ind + "        if " + q + dol + "{mdf_ds_here_" + _mq("_sa_i") + "}" + q + " == " + q + "1" + q + " di as result " + q + "    DS" + bt + "_sa_i" + ap + "      : " + q + " " + bt + q + dol + "{auto_dsname_" + bt + "_sa_i" + ap + "}" + q + ap)
    fput(fh, ind + "    }")
    fput(fh, ind + "    di as txt    " + q + "    form     : " + q + " " + _cq("_pk_form"))
    fput(fh, ind + "    di as txt    " + q + "    output   : " + q + " " + q + dol + "clean_dir" + q)
    fput(fh, ind + "    di as result " + q + "=====================================================================" + q)
    fput(fh, ind + "}")
    fput(fh, ind + "else {")
    fput(fh, ind + "    di as result " + q + "=====================================================================" + q)
    fput(fh, ind + "    di as result " + q + "  STANDALONE MODE  —  running from this file's own folder" + q)
    fput(fh, ind + "    di as result " + q + "=====================================================================" + q)
    fput(fh, ind + "    di as txt    " + q + "  No Master DO File project was found above this file, so it is" + q)
    fput(fh, ind + "    di as txt    " + q + "  running on what sits beside it. CONFIRM this is the data you" + q)
    fput(fh, ind + "    di as txt    " + q + "  meant:" + q)
    fput(fh, ind + "    di as txt    " + q + "    root   : " + q + " " + _cq("_selfdir"))
    fput(fh, ind + "    di as txt    " + q + "    data   : " + q + " " + _cq("_sa_datadir"))
    fput(fh, ind + "    forvalues _sa_i = 1/" + _mq("_sa_k") + " {")
    fput(fh, ind + "        di as result " + q + "    DS" + bt + "_sa_i" + ap + "    : " + q + " " + q + dol + "{target_dta_" + bt + "_sa_i" + ap + "}" + q)
    fput(fh, ind + "    }")
    fput(fh, ind + "    di as txt    " + q + "    output : " + q + " " + q + dol + "mdf_out" + q)
    fput(fh, ind + "    if " + _mq("_sel_run") + " == 1 {")
    fput(fh, ind + "        di as error " + q + "  Ctrl+A / Ctrl+D gives Stata no path for this file, so the folder" + q)
    fput(fh, ind + "        di as error " + q + "  above is Stata's WORKING DIRECTORY, not necessarily this file's." + q)
    fput(fh, ind + "        di as error " + q + "  If it is wrong: File > Change working directory, or launch Stata" + q)
    fput(fh, ind + "        di as error " + q + "  by double-clicking this file." + q)
    fput(fh, ind + "    }")
    fput(fh, ind + "    di as result " + q + "=====================================================================" + q)
    fput(fh, ind + "}")
    fput(fh, ind + "local _boot " + _cq("_selfdir"))
}

void standalone_context(real scalar fh, string scalar q, string scalar bt,
                        string scalar ap, string scalar dol,
                        string scalar pname, string scalar nds,
                        string scalar needs, string scalar ind)
{
    sa_part_checks(fh, q, bt, ap, dol, pname, nds, needs, ind)
    sa_part_identity(fh, q, bt, ap, dol, pname, nds, needs, ind)
    sa_part_folders(fh, q, bt, ap, dol, pname, nds, needs, ind)
    sa_part_config(fh, q, bt, ap, dol, pname, nds, needs, ind)
    sa_part_package(fh, q, bt, ap, dol, pname, nds, needs, ind)
    sa_part_tail(fh, q, bt, ap, dol, pname, nds, needs, ind)
}

//  `nds'   datasets this file was generated for; standalone mode refuses to
//          run against a folder holding a different number (ADR-056).
//  `needs' package commands this file calls, so its standalone fallback
//          carries only what it uses: "core", "finalise", or both.
void module_header(
    real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar pname,
    string scalar nds, string scalar needs)
{
    string scalar bs
    bs = char(92)

    fput(fh, "*  ── Bootstrap: locate the project, then load its paths and helpers ─────────")
    fput(fh, "local _boot " + q + dol + "hfc_dofiles_dir" + q)
    fput(fh, "*  A standalone context belongs to the folder that established it. Stata's")
    fput(fh, "*  globals outlive `clear all', so a second stranded file run in the same")
    fput(fh, "*  session must resolve itself afresh rather than inherit the first one's.")
    fput(fh, "if " + q + dol + "mdf_standalone" + q + " == " + q + "1" + q + " local _boot " + q + q)
    //  Anything else left in the session may be another project's (ADR-061).
    fput(fh, "*  Only a running Master hands its context on; anything else left in this")
    fput(fh, "*  session may belong to another project, so the file resolves its own.")
    fput(fh, "if " + q + dol + "mdf_pipeline_root" + q + " == " + q + q + " local _boot " + q + q)
    fput(fh, "global mdf_standalone 0")
    fput(fh, "global mdf_package 0")
    fput(fh, "if " + bt + q + bt + "_boot" + ap + q + ap + " == " + q + q + " {")
    fput(fh, "")
    fput(fh, "    local _p " + bt + q + bt + "c(do_current)" + ap + q + ap)
    fput(fh, "    *  c(filename) is the last file -use-d or -save-d, which is a DATASET as")
    fput(fh, "    *  soon as anything has loaded one — and a sibling module called after")
    fput(fh, "    *  that would anchor itself in the data folder instead of its own. Take")
    fput(fh, "    *  this rung only when it really is a do-file (ADR-056).")
    fput(fh, "    if " + bt + q + bt + "_p" + ap + q + ap + " == " + q + q + " {")
    fput(fh, "        local _cf " + bt + q + bt + "c(filename)" + ap + q + ap)
    fput(fh, "        if lower(substr(" + bt + q + bt + "_cf" + ap + q + ap + ", -3, 3)) == " + q + ".do" + q + " local _p " + bt + q + bt + "_cf" + ap + q + ap)
    fput(fh, "    }")
    fput(fh, "    *  Measured in Stata 17: c(do_current) is empty for every run, from the")
    fput(fh, "    *  Do button, from Ctrl+A / Ctrl+D and from a nested -do-. The working")
    fput(fh, "    *  directory is therefore where this file starts looking (ADR-059).")
    fput(fh, "    if " + bt + q + bt + "_p" + ap + q + ap + " == " + q + q + " local _p " + bt + q + bt + "c(pwd)" + ap + "/." + q + ap)
    fput(fh, "    local _p = subinstr(" + bt + q + bt + "_p" + ap + q + ap + ", " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, "")
    fput(fh, "    local _sel_run 0")
    fput(fh, "    local _sel_base = ustrregexra(" + bt + q + bt + "_p" + ap + q + ap + ", " + q + "^.*/" + q + ", " + q + q + ")")
    fput(fh, "    if substr(" + bt + q + bt + "_sel_base" + ap + q + ap + ", 1, 3) == " + q + "STD" + q + " & strpos(" + bt + q + bt + "_sel_base" + ap + q + ap + ", " + q + ".tmp" + q + ") > 0 {")
    fput(fh, "        *  Selection run (Ctrl+A / Ctrl+D). Stata executed an anonymous temp")
    fput(fh, "        *  file, so this file has no path of its own to search upward from.")
    fput(fh, "        *  Recover ROOT from the working-directory sentinel, then from the")
    fput(fh, "        *  cache the last Master run wrote. Recovery is announced below.")
    fput(fh, "        local _sel_run 1")
    fput(fh, "        local _p " + bt + q + bt + "c(pwd)" + ap + "/." + q + ap)
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "    *  The folder this file is sitting in. It is the standalone root if no")
    fput(fh, "    *  project turns up above it. Captured before the walk below consumes")
    fput(fh, "    *  `_p'.")
    fput(fh, "    local _selfdir = substr(" + bt + q + bt + "_p" + ap + q + ap + ", 1, strrpos(" + bt + q + bt + "_p" + ap + q + ap + ", " + q + "/" + q + ") - 1)")
    fput(fh, "")
    //  ── Package probe (ADR-059) ────────────────────────────────────────────
    fput(fh, "    *  ── A Deliverables package around this file? ──────────────────────")
    fput(fh, "    *  A package holds 02_Import & Raw files/; this file sits in its")
    fput(fh, "    *  03_Processing Files/ or 03_Processing Files/01_Do Files/. Looked for")
    fput(fh, "    *  BEFORE the project walk, so a package built inside a project")
    fput(fh, "    *  rebuilds inside the package instead of re-running the project.")
    fput(fh, "    local _sa_pkg " + q + q)
    fput(fh, "    local _pk_try " + _cq("_selfdir"))
    fput(fh, "    forvalues _pk_i = 1/3 {")
    fput(fh, "        if " + _cq("_sa_pkg") + " == " + q + q + " & " + _cq("_pk_try") + " != " + q + q + " {")
    fput(fh, "            local _pk_ok 0")
    fput(fh, "            mata: st_local(" + q + "_pk_ok" + q + ", strofreal(direxists(" + q + bt + "_pk_try" + ap + "/02_Import & Raw files" + q + ")))")
    fput(fh, "            if " + _mq("_pk_ok") + " == 1 local _sa_pkg " + _cq("_pk_try"))
    fput(fh, "            local _pk_cut = strrpos(" + _cq("_pk_try") + ", " + q + "/" + q + ")")
    fput(fh, "            if " + _mq("_pk_cut") + " > 1 local _pk_try = substr(" + _cq("_pk_try") + ", 1, " + _mq("_pk_cut") + " - 1)")
    fput(fh, "            else local _pk_try " + q + q)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "    local _root " + q + q)
    fput(fh, "    if " + _cq("_sa_pkg") + " == " + q + q + " {")
    fput(fh, "        forvalues _i = 1/12 {")
    fput(fh, "            local _p = substr(" + bt + q + bt + "_p" + ap + q + ap + ", 1, strrpos(" + bt + q + bt + "_p" + ap + q + ap + ", " + q + "/" + q + ") - 1)")
    fput(fh, "            if " + bt + q + bt + "_p" + ap + q + ap + " == " + q + q + " continue, break")
    fput(fh, "            cap confirm file " + bt + q + bt + "_p" + ap + "/.hfc_root" + q + ap)
    fput(fh, "            if !_rc {")
    fput(fh, "                local _root " + bt + q + bt + "_p" + ap + q + ap)
    fput(fh, "                continue, break")
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "    *  ── No project above this file ──────────────────────────────────────")
    fput(fh, "    *  Before falling back to the cache an earlier Master run left behind —")
    fput(fh, "    *  which would bind this file to a project it is no longer part of, and")
    fput(fh, "    *  write results there — see whether it can stand on its own where it")
    fput(fh, "    *  sits. Discovery runs only on this branch, so a file inside a real")
    fput(fh, "    *  project never reaches it.")
    fput(fh, "    if " + bt + q + bt + "_root" + ap + q + ap + " == " + q + q + " {")
    fput(fh, "        if " + _cq("_sa_pkg") + " != " + q + q + " {")
    package_discover(fh, q, bt, ap, "            ")
    fput(fh, "            global mdf_standalone 1")
    fput(fh, "            global mdf_package 1")
    fput(fh, "        }")
    fput(fh, "        else {")
    standalone_discover(fh, q, bt, ap, dol, "            ");
    fput(fh, "            *  No project above this file, so run it where it stands. An empty")
    fput(fh, "            *  folder then has to SAY so rather than quietly adopt the cached")
    fput(fh, "            *  root of a project this file is no longer part of.")
    fput(fh, "            if " + bt + "_sel_run" + ap + " == 0 global mdf_standalone 1")
    fput(fh, "            *  Where a selection run IS reported by a temp-file name, the")
    fput(fh, "            *  working directory is weaker evidence — take it only when it")
    fput(fh, "            *  actually holds data, and leave the cache its chance.")
    fput(fh, "            if " + bt + "_sel_run" + ap + " == 1 & " + bt + "_sa_k" + ap + " > 0 global mdf_standalone 1")
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "    if " + bt + q + bt + "_root" + ap + q + ap + " == " + q + q + " & " + q + dol + "mdf_standalone" + q + " != " + q + "1" + q + " {")
    fput(fh, "        tempname _fhb")
    fput(fh, "        cap file open " + bt + "_fhb" + ap + " using " + bt + q + bt + "c(tmpdir)" + ap + "hfc_root_cache_" + pname + ".txt" + q + ap + ", read text")
    fput(fh, "        if !_rc {")
    fput(fh, "            file read  " + bt + "_fhb" + ap + " _root")
    fput(fh, "            file close " + bt + "_fhb" + ap)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "if " + q + dol + "mdf_standalone" + q + " == " + q + "1" + q + " {")
    standalone_context(fh, q, bt, ap, dol, pname, nds, needs, "    ");
    fput(fh, "}")
    fput(fh, "else {")
    fput(fh, "")
    fput(fh, "    if " + bt + q + bt + "_root" + ap + q + ap + " == " + q + q + " {")
    fput(fh, "        di as error " + q + "ERROR: could not locate the project root from this file." + q)
    fput(fh, "        di as txt   " + q + "  Run the Master DO file once from the project root, then try again," + q)
    fput(fh, "        di as txt   " + q + "  or open this file from inside the project folder." + q)
    fput(fh, "        di as txt   " + q + "  To run it on its own instead, put the .dta file(s) it should read" + q)
    fput(fh, "        di as txt   " + q + "  in its own folder — see STANDALONE MODE in the project README." + q)
    fput(fh, "        exit 198")
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "    if " + bt + "_sel_run" + ap + " == 1 {")
    fput(fh, "        di as error " + q + "=======================================================================" + q)
    fput(fh, "        di as error " + q + "  SELECTION RUN — PROJECT ROOT RECOVERED, NOT READ FROM THIS FILE" + q)
    fput(fh, "        di as error " + q + "=======================================================================" + q)
    fput(fh, "        di as txt   " + q + "  Ctrl+A / Ctrl+D gives Stata no path for this file, so the project" + q)
    fput(fh, "        di as txt   " + q + "  below was recovered from the working directory, or from the cache" + q)
    fput(fh, "        di as txt   " + q + "  left by the last Master run. CONFIRM it is the one you intended:" + q)
    fput(fh, "        di as result " + q + "    " + q + " " + bt + q + bt + "_root" + ap + q + ap)
    fput(fh, "        di as txt   " + q + "  If that is the wrong project, run its Master once, then retry." + q)
    fput(fh, "        di as error " + q + "=======================================================================" + q)
    fput(fh, "    }")
    fput(fh, "    di as result " + q + "Project root → " + q + " " + bt + q + bt + "_root" + ap + q + ap)
    fput(fh, "    local _boot " + _cq("_root"))
    fput(fh, "")
    fput(fh, "    *  A managed project's globals live in its directory file, which the")
    fput(fh, "    *  package knows how to find in either layout. Standalone mode never")
    fput(fh, "    *  gets here: it built its own context above and must not need the")
    fput(fh, "    *  package installed.")
    fput(fh, "    cap which mdf_bootstrap")
    fput(fh, "    if _rc {")
    fput(fh, "        di as error " + q + "The Master DO File framework is not installed on this machine." + q)
    fput(fh, "        di as error " + bt + q + "Run:  net install mdf, from(" + q + "https://raw.githubusercontent.com/adinkhan7/master-do-file/main" + q + ") replace" + q + ap)
    fput(fh, "        exit 601")
    fput(fh, "    }")
    fput(fh, "    mdf_bootstrap " + bt + q + bt + "_root" + ap + q + ap)
    fput(fh, "}")
    fput(fh, "}")
    fput(fh, "")
}

//  APPLY — operates on the dataset already in memory; never loads or saves.
void write_mod_oe_apply(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar dsname, string scalar indent)
{
    fput(fh, indent + "* ── Apply returned translations (inputcorrection) ──────────────────────────")
    fput(fh, indent + "")
    fput(fh, indent + "* ── Step 1: Apply existing translations (inputcorrection) ──────────────────")
    fput(fh, indent + "if " + q + dol + "inputcorrection" + q + " == " + q + "1" + q + " {")
    fput(fh, indent + "    *  ONE DATASET, MANY RETURNED FILES. Translation comes back in chunks over")
    fput(fh, indent + "    *  the life of a survey, under whatever names the translator chose, so this")
    fput(fh, indent + "    *  applies EVERY .xlsx in the dataset's own return folder, in sorted order.")
    fput(fh, indent + "    *  Applying one and stopping would silently drop the rest.")
    fput(fh, indent + "    *")
    fput(fh, indent + "    *  Two locations are read, in this order:")
    fput(fh, indent + "    *    1. 02_Translated/NN_<dataset>/   the per-dataset folder — the convention")
    fput(fh, indent + "    *    2. 02_Translated/                loose files sitting in the parent")
    fput(fh, indent + "    *  The second is not legacy tolerance for its own sake: projects that ran an")
    fput(fh, indent + "    *  earlier v10 build have real returned translations sitting there, and")
    fput(fh, indent + "    *  ignoring them would quietly discard work already paid for.")
    fput(fh, indent + "    local _ds_folder " + q + bt + "_tfold" + ap + q)
    fput(fh, indent + "    local _ds_dir    " + q + dol + "trans_translated_dir/" + bt + "_ds_folder" + ap + q)
    //  A Deliverables package carries one dataset, so its returned files sit
    //  directly in 02_Translated/: the dataset's name twice on the path pushed
    //  real files past Windows' 260-character limit (ADR-059).
    fput(fh, indent + "    if " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " cap mkdir " + q + bt + "_ds_dir" + ap + q)
    fput(fh, indent + "")
    fput(fh, indent + "    local _trans_files " + q + q)
    fput(fh, indent + "    cap local _trans_files : dir " + q + bt + "_ds_dir" + ap + q + " files " + q + "*.xlsx" + q + ", respectcase")
    fput(fh, indent + "    local _trans_files : list sort _trans_files")
    fput(fh, indent + "    local _trans_root " + q + bt + "_ds_dir" + ap + q)
    fput(fh, indent + "")
    fput(fh, indent + "    *  Nothing filed under the dataset folder — look in the parent.")
    fput(fh, indent + "    if " + bt + ": word count " + bt + "_trans_files" + ap + ap + " == 0 {")
    fput(fh, indent + "        local _search_pat " + q + "*" + dsname + "*.xlsx" + q)
    fput(fh, indent + "        if " + q + dol + "mdf_package" + q + " == " + q + "1" + q + " local _search_pat " + q + "*.xlsx" + q)
    fput(fh, indent + "        local _trans_files : dir " + q + dol + "trans_translated_dir" + q + " files " + q + bt + "_search_pat" + ap + q + ", respectcase")
    fput(fh, indent + "        if " + bt + ": word count " + bt + "_trans_files" + ap + ap + " == 0 {")
    fput(fh, indent + "            *  A single-dataset project has no reason to carry the dataset name.")
    fput(fh, indent + "            if " + dol + "actual_n_dta == 1 local _trans_files : dir " + q + dol + "trans_translated_dir" + q + " files " + q + "*.xlsx" + q + ", respectcase")
    fput(fh, indent + "        }")
    fput(fh, indent + "        local _trans_files : list sort _trans_files")
    fput(fh, indent + "        local _trans_root " + q + dol + "trans_translated_dir" + q)
    fput(fh, indent + "        if " + bt + ": word count " + bt + "_trans_files" + ap + ap + " > 0 & " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " {")
    fput(fh, indent + "            di as txt " + q + "  NOTE: reading loose files from 02_Translated/. Move them into" + q)
    fput(fh, indent + "            di as txt " + q + "        " + bt + "_ds_folder" + ap + "/ so each dataset stays separate." + q)
    fput(fh, indent + "        }")
    fput(fh, indent + "    }")
    fput(fh, indent + "    local _ti 0")
    fput(fh, indent + "    local _tapplied 0")
    fput(fh, indent + "    local _tskipped 0")
    fput(fh, indent + "    local _tfailed 0")
    fput(fh, indent + "    foreach _tf of local _trans_files {")
    fput(fh, indent + "        local _ti = " + bt + "_ti" + ap + " + 1")
    fput(fh, indent + "        di as result " + q + "  Translation file (" + bt + "_ti" + ap + "): " + bt + "_tf" + ap + q)
    fput(fh, indent + "        cd " + q + bt + "_trans_root" + ap + q)
    fput(fh, indent + "        local _safe_tf " + q + "_temp_trans_" + bt + "_ti" + ap + ".xlsx" + q)
    fput(fh, indent + "        cap copy " + q + bt + "_tf" + ap + q + " " + q + bt + "_safe_tf" + ap + q + ", replace")
    fput(fh, indent + "")
    fput(fh, indent + "        local _skip 0")
    fput(fh, indent + "        local _nfill 0")
    fput(fh, indent + "        preserve")
    fput(fh, indent + "        cap import excel using " + q + bt + "_safe_tf" + ap + q + ", firstrow clear")
    fput(fh, indent + "        if _rc {")
    fput(fh, indent + "            di as error " + q + "    SKIPPED — file could not be read as Excel." + q)
    fput(fh, indent + "            local _skip 1")
    fput(fh, indent + "        }")
    fput(fh, indent + "        if " + bt + "_skip" + ap + " == 0 {")
    fput(fh, indent + "            cap confirm variable translated")
    fput(fh, indent + "            if _rc {")
    fput(fh, indent + "                di as error " + q + "    SKIPPED — no 'translated' column. Return the exported file, not a copy" + q)
    fput(fh, indent + "                di as error " + q + "              with renamed columns." + q)
    fput(fh, indent + "                local _skip 1")
    fput(fh, indent + "            }")
    fput(fh, indent + "        }")
    fput(fh, indent + "        if " + bt + "_skip" + ap + " == 0 {")
    fput(fh, indent + "            cap confirm string variable translated")
    fput(fh, indent + "            if _rc {")
    fput(fh, indent + "                di as error " + q + "    SKIPPED — the 'translated' column is entirely empty." + q)
    fput(fh, indent + "                di as error " + q + "              Nothing has been translated in this file yet." + q)
    fput(fh, indent + "                local _skip 1")
    fput(fh, indent + "            }")
    fput(fh, indent + "            else {")
    fput(fh, indent + "                qui count if strtrim(translated) != " + q + q)
    fput(fh, indent + "                local _nfill = r(N)")
    fput(fh, indent + "                if " + bt + "_nfill" + ap + " == 0 {")
    fput(fh, indent + "                    di as txt " + q + "    SKIPPED — no filled rows in the 'translated' column." + q)
    fput(fh, indent + "                    local _skip 1")
    fput(fh, indent + "                }")
    fput(fh, indent + "            }")
    fput(fh, indent + "        }")
    fput(fh, indent + "        restore")
    fput(fh, indent + "")
    fput(fh, indent + "        if " + bt + "_skip" + ap + " == 0 {")
    fput(fh, indent + "            cap drop corrected")
    fput(fh, indent + "            cap noi inputcorrection using " + q + bt + "_safe_tf" + ap + q + ", idvar(key) varnamecol(variable) correction(translated)")
    fput(fh, indent + "            local _ic_rc = _rc")
    fput(fh, indent + "            if " + bt + "_ic_rc" + ap + " == 0 {")
    fput(fh, indent + "                local _tapplied = " + bt + "_tapplied" + ap + " + 1")
    fput(fh, indent + "                di as result " + q + "    applied — " + bt + "_nfill" + ap + " translated row(s) in this file." + q)
    fput(fh, indent + "            }")
    fput(fh, indent + "            else {")
    fput(fh, indent + "                local _tfailed = " + bt + "_tfailed" + ap + " + 1")
    fput(fh, indent + "                di as error " + q + "    FAILED — inputcorrection returned rc=" + q + " " + bt + "_ic_rc" + ap + " " + q + ". Nothing from this file was applied." + q)
    fput(fh, indent + "                di as error " + q + "             The file was NOT modified. Check that 'key' and 'variable'" + q)
    fput(fh, indent + "                di as error " + q + "             are unchanged from the export." + q)
    fput(fh, indent + "            }")
    fput(fh, indent + "        }")
    fput(fh, indent + "        else local _tskipped = " + bt + "_tskipped" + ap + " + 1")
    fput(fh, indent + "        cap erase " + q + bt + "_safe_tf" + ap + q)
    fput(fh, indent + "        cd " + q + dol + "ROOT" + q)
    fput(fh, indent + "    }")
    fput(fh, indent + "    if " + bt + "_ti" + ap + " > 0 {")
    fput(fh, indent + "        di as result " + q + "  Translation summary for " + dsname + ": " + bt + "_tapplied" + ap + " applied, " + bt + "_tskipped" + ap + " skipped, " + bt + "_tfailed" + ap + " failed." + q)
    fput(fh, indent + "        if " + bt + "_tfailed" + ap + " > 0 di as error " + q + "  One or more translation files could not be applied — see above." + q)
    fput(fh, indent + "        if " + bt + "_tapplied" + ap + " == 0 di as error " + q + "  NOTHING was applied for " + dsname + "." + q)
    fput(fh, indent + "    }")
    fput(fh, indent + "    if " + bt + "_ti" + ap + " == 0 di as txt " + q + "  No translation files found for " + dsname + " — skipping inputcorrection." + q)
    fput(fh, indent + "}")
    fput(fh, indent + "")
}

//  EXPORT — sends untranslated open-ended responses out, after cleaning.
void write_mod_oe_export(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar dsname, string scalar indent, string scalar ds_idx)
{
    fput(fh, indent + "* ── Step 2: Export open-ended responses for translation ─────────────────────")
    fput(fh, indent + "if " + q + dol + "exportopenended" + q + " == " + q + "1" + q + " {")
    fput(fh, indent + "    di as result " + q + "  Exporting open-ended responses for translation..." + q)
    fput(fh, indent + "    preserve")
    fput(fh, indent + "    local _run_export 0")
    fput(fh, indent + "    cap confirm variable key")
    fput(fh, indent + "    if _rc {")
    fput(fh, indent + "        di as error " + q + "  ERROR: variable 'key' not found. Cannot export open-ended responses." + q)
    fput(fh, indent + "    }")
    fput(fh, indent + "    else {")
    fput(fh, indent + "        local _oe_vars " + dol + "{hfc_openended_vars_" + ds_idx + "}")
    fput(fh, indent + "        if " + q + bt + "_oe_vars" + ap + q + " == " + q + q + " local _oe_vars " + dol + "hfc_openended_vars")
    fput(fh, indent + "        if " + q + bt + "_oe_vars" + ap + q + " != " + q + q + " {")
    fput(fh, indent + "            local _keep_vars key")
    fput(fh, indent + "            foreach _v in " + bt + "_oe_vars" + ap + " {")
    fput(fh, indent + "                *  Expand wildcard patterns (e.g. mainvar_*) before confirming")
    fput(fh, indent + "                if strpos(" + q + bt + "_v" + ap + q + ", " + q + "*" + q + ") > 0 | strpos(" + q + bt + "_v" + ap + q + ", " + q + "?" + q + ") > 0 {")
    fput(fh, indent + "                    cap ds " + bt + "_v" + ap + ", has(type string)")
    fput(fh, indent + "                    if !_rc {")
    fput(fh, indent + "                        foreach _exp of varlist " + bt + "r(varlist)" + ap + " {")
    fput(fh, indent + "                            local _keep_vars " + q + bt + "_keep_vars" + ap + " " + bt + "_exp" + ap + q)
    fput(fh, indent + "                        }")
    fput(fh, indent + "                    }")
    fput(fh, indent + "                    else {")
    fput(fh, indent + "                        *  ds with has(type string) failed — try unfiltered expand")
    fput(fh, indent + "                        cap unab _expanded : " + bt + "_v" + ap)
    fput(fh, indent + "                        if !_rc {")
    fput(fh, indent + "                            foreach _exp of local _expanded {")
    fput(fh, indent + "                                cap confirm string variable " + bt + "_exp" + ap)
    fput(fh, indent + "                                if !_rc local _keep_vars " + q + bt + "_keep_vars" + ap + " " + bt + "_exp" + ap + q)
    fput(fh, indent + "                            }")
    fput(fh, indent + "                        }")
    fput(fh, indent + "                        else di as txt " + q + "    Note: no variables matched pattern " + bt + "_v" + ap + " — skipping." + q)
    fput(fh, indent + "                    }")
    fput(fh, indent + "                }")
    fput(fh, indent + "                else {")
    fput(fh, indent + "                    *  No wildcard — confirm directly")
    fput(fh, indent + "                    cap confirm string variable " + bt + "_v" + ap)
    fput(fh, indent + "                    if !_rc local _keep_vars " + q + bt + "_keep_vars" + ap + " " + bt + "_v" + ap + q)
    fput(fh, indent + "                    else {")
    fput(fh, indent + "                        *  Not string — may be numeric with value labels; include anyway")
    fput(fh, indent + "                        cap confirm variable " + bt + "_v" + ap)
    fput(fh, indent + "                        if !_rc local _keep_vars " + q + bt + "_keep_vars" + ap + " " + bt + "_v" + ap + q)
    fput(fh, indent + "                        else di as txt " + q + "    Note: " + bt + "_v" + ap + " not found in dataset — skipping." + q)
    fput(fh, indent + "                    }")
    fput(fh, indent + "                }")
    fput(fh, indent + "            }")
    fput(fh, indent + "            cap keep " + bt + "_keep_vars" + ap)
    fput(fh, indent + "            local _n_keep : word count " + bt + "_keep_vars" + ap)
    fput(fh, indent + "            if " + bt + "_n_keep" + ap + " > 1 local _run_export 1")
    fput(fh, indent + "            else di as txt " + q + "  No valid open-ended variables found. Skipping export." + q)
    fput(fh, indent + "        }")
    fput(fh, indent + "        else {")
    fput(fh, indent + "            cap ds, has(type string)")
    fput(fh, indent + "            if !_rc {")
    fput(fh, indent + "                local _str_vars " + bt + "r(varlist)" + ap)
    fput(fh, indent + "                local _keep_vars key")
    fput(fh, indent + "                foreach _v of local _str_vars {")
    fput(fh, indent + "                    if " + q + bt + "_v" + ap + q + " != " + q + "key" + q + " local _keep_vars " + q + bt + "_keep_vars" + ap + " " + bt + "_v" + ap + q)
    fput(fh, indent + "                }")
    fput(fh, indent + "                cap keep " + bt + "_keep_vars" + ap)
    fput(fh, indent + "                local _n_keep : word count " + bt + "_keep_vars" + ap)
    fput(fh, indent + "                if " + bt + "_n_keep" + ap + " > 1 local _run_export 1")
    fput(fh, indent + "                else di as txt " + q + "  No string variables found beyond key. Skipping export." + q)
    fput(fh, indent + "            }")
    fput(fh, indent + "            else di as txt " + q + "  No string variables detected. Skipping export." + q)
    fput(fh, indent + "        }")
    fput(fh, indent + "    }")
    fput(fh, indent + "")
    fput(fh, indent + "    if " + bt + "_run_export" + ap + " == 1 {")
    fput(fh, indent + "        local _safe_name " + q + dsname + q)
    fput(fh, indent + "        local _safe_name : subinstr local _safe_name " + q + " " + q + " " + q + "_" + q + ", all")
    fput(fh, indent + "")
    fput(fh, indent + "        * ── Export scope: NEW ONLY (default) or EVERYTHING ($oe_export_all) ───────")
    fput(fh, indent + "        *  Both are first-class, and both are meant to be used mid-survey:")
    fput(fh, indent + "        *    new-only  sends the next chunk without re-sending translated work")
    fput(fh, indent + "        *    all       sends every open-ended row, whatever was sent before")
    fput(fh, indent + "        *  ALL mode skips the filter entirely rather than merging and un-dropping,")
    fput(fh, indent + "        *  so there is no path where a filter bug can silently shrink a full export.")
    fput(fh, indent + "        *  It still archives the sent keys, so a later new-only export stays correct.")
    fput(fh, indent + "        local _scope " + q + "NEW" + q)
    fput(fh, indent + "        if " + q + dol + "oe_export_all" + q + " == " + q + "1" + q + " local _scope " + q + "ALL" + q)
    fput(fh, indent + "")
    fput(fh, indent + "        local _oe_keys_pat " + q + bt + "_safe_name" + ap + "_OE_KEYS_*.dta" + q)
    fput(fh, indent + "        local _oe_keys_all : dir " + q + dol + "hfc_keys_trans_dir" + q + " files " + q + bt + "_oe_keys_pat" + ap + q + ", respectcase")
    fput(fh, indent + "        local _oe_keys_sorted : list sort _oe_keys_all")
    fput(fh, indent + "        local _latest_oe_keys " + q + q)
    fput(fh, indent + "        foreach _kf of local _oe_keys_sorted {")
    fput(fh, indent + "            local _latest_oe_keys " + q + bt + "_kf" + ap + q)
    fput(fh, indent + "        }")
    fput(fh, indent + "")
    fput(fh, indent + "        if " + q + bt + "_scope" + ap + q + " == " + q + "ALL" + q + " {")
    fput(fh, indent + "            qui count")
    fput(fh, indent + "            di as result " + q + "    EXPORT ALL requested (oe_export_all = 1) — sending all " + bt + "r(N)" + ap + " row(s)," + q)
    fput(fh, indent + "            di as result " + q + "    including any already exported." + q)
    fput(fh, indent + "        }")
    fput(fh, indent + "        else if " + q + bt + "_latest_oe_keys" + ap + q + " != " + q + q + " {")
    fput(fh, indent + "            di as txt " + q + "    Found prior OE export keys: " + bt + "_latest_oe_keys" + ap + " — filtering to new-only." + q)
    fput(fh, indent + "            cap merge 1:1 key using " + q + dol + "hfc_keys_trans_dir/" + bt + "_latest_oe_keys" + ap + q + ", keep(master match) gen(_oe_merge)")
    fput(fh, indent + "            local _oe_merge_rc = _rc")
    fput(fh, indent + "            if " + bt + "_oe_merge_rc" + ap + " == 0 {")
    fput(fh, indent + "                cap drop if _oe_merge == 3")
    fput(fh, indent + "                cap drop _oe_merge")
    fput(fh, indent + "            }")
    fput(fh, indent + "            else {")
    fput(fh, indent + "                di as error " + q + "    ERROR: merge against prior OE keys failed (rc=" + q + " " + bt + "_oe_merge_rc" + ap + " " + q + "). Aborting export to avoid re-sending old data." + q)
    fput(fh, indent + "                local _run_export 0")
    fput(fh, indent + "            }")
    fput(fh, indent + "        }")
    fput(fh, indent + "        else di as txt " + q + "    No prior OE export keys found — treating all rows as new." + q)
    fput(fh, indent + "")
    fput(fh, indent + "        qui count")
    fput(fh, indent + "        if r(N) == 0 {")
    fput(fh, indent + "            di as result " + q + "    No new open-ended responses since last export. Skipping." + q)
    fput(fh, indent + "        }")
    fput(fh, indent + "        else {")
    fput(fh, indent + "            * ── Destination: this dataset's own export folder ──────────────")
    fput(fh, indent + "            local _exp_dir " + q + dol + "trans_exported_dir/" + bt + "_tfold" + ap + q)
    fput(fh, indent + "            cap mkdir " + q + bt + "_exp_dir" + ap + q)
    fput(fh, indent + "")
    fput(fh, indent + "            * ── Never overwrite a previous export ──────────────────────────────")
    fput(fh, indent + "            *  Exports happen repeatedly, including more than once in a day. The")
    fput(fh, indent + "            *  file name carries the date and the scope; if that name is already")
    fput(fh, indent + "            *  taken, a _02, _03 ... suffix is added rather than replacing a file")
    fput(fh, indent + "            *  that may already be out with a translator. Capped at 99: past that")
    fput(fh, indent + "            *  something is wrong with the workflow, and silently looping forever")
    fput(fh, indent + "            *  would hide it.")
    fput(fh, indent + "            local _stem " + q + bt + "_safe_name" + ap + "_Openended_" + q)
    fput(fh, indent + "            if " + q + bt + "_scope" + ap + q + " == " + q + "ALL" + q + " local _stem " + q + bt + "_safe_name" + ap + "_Openended_ALL_" + q)
    fput(fh, indent + "            local _out_name " + q + bt + "_stem" + ap + dol + "hfc_folder_date.xlsx" + q)
    fput(fh, indent + "            local _seq 1")
    fput(fh, indent + "            cap confirm file " + q + bt + "_exp_dir" + ap + "/" + bt + "_out_name" + ap + q)
    fput(fh, indent + "            while _rc == 0 & " + bt + "_seq" + ap + " < 99 {")
    fput(fh, indent + "                local _seq = " + bt + "_seq" + ap + " + 1")
    fput(fh, indent + "                local _sq : display %02.0f " + bt + "_seq" + ap)
    fput(fh, indent + "                local _out_name " + q + bt + "_stem" + ap + dol + "{hfc_folder_date}_" + bt + "_sq" + ap + ".xlsx" + q)
    fput(fh, indent + "                cap confirm file " + q + bt + "_exp_dir" + ap + "/" + bt + "_out_name" + ap + q)
    fput(fh, indent + "            }")
    fput(fh, indent + "")
    fput(fh, indent + "            cd " + q + bt + "_exp_dir" + ap + q)
    fput(fh, indent + "            cap noi exportopenended using " + q + bt + "_out_name" + ap + q + ", id(key) replace")
    fput(fh, indent + "            local _export_rc = _rc")
    fput(fh, indent + "            cd " + q + dol + "ROOT" + q)
    fput(fh, indent + "")
    fput(fh, indent + "            * ── Archive keys on successful export ──────────────────────────────")
    fput(fh, indent + "            if " + bt + "_export_rc" + ap + " == 0 {")
    fput(fh, indent + "                *  The key store is CUMULATIVE. Each archive appends this export's")
    fput(fh, indent + "                *  keys to whatever was already sent, so new-only stays correct")
    fput(fh, indent + "                *  across many exports in one day and across an ALL export. Writing")
    fput(fh, indent + "                *  only this export's keys would make the next new-only run re-send")
    fput(fh, indent + "                *  everything sent before today.")
    fput(fh, indent + "                cap keep key")
    fput(fh, indent + "                if " + q + bt + "_latest_oe_keys" + ap + q + " != " + q + q + " {")
    fput(fh, indent + "                    cap append using " + q + dol + "hfc_keys_trans_dir/" + bt + "_latest_oe_keys" + ap + q)
    fput(fh, indent + "                    cap duplicates drop key, force")
    fput(fh, indent + "                }")
    fput(fh, indent + "                cap save " + q + dol + "hfc_keys_trans_dir/" + bt + "_safe_name" + ap + "_OE_KEYS_" + dol + "hfc_folder_date.dta" + q + ", replace")
    fput(fh, indent + "                qui count")
    fput(fh, indent + "                di as result " + q + "    OE export keys archived (" + bt + "r(N)" + ap + " sent to date) → " + bt + "_safe_name" + ap + "_OE_KEYS_" + dol + "hfc_folder_date.dta" + q)
    fput(fh, indent + "                di as result " + q + q)
    fput(fh, indent + "                di as result " + q + "    ┌─ TRANSLATION ROUND TRIP ─────────────────────────────────────" + q)
    fput(fh, indent + "                di as result " + q + "    │ 1. SEND OUT:  05_Translation/01_Exported/" + bt + "_tfold" + ap + "/" + q)
    fput(fh, indent + "                di as result " + q + "    │               " + bt + "_out_name" + ap + q)
    fput(fh, indent + "                di as result " + q + "    │ 2. TRANSLATE: fill the 'translated' column, leave 'key' and" + q)
    fput(fh, indent + "                di as result " + q + "    │               'variable' untouched." + q)
    fput(fh, indent + "                di as result " + q + "    │ 3. RETURN TO: 05_Translation/02_Translated/" + bt + "_tfold" + ap + "/" + q)
    fput(fh, indent + "                di as result " + q + "    │               (any filename; every .xlsx there is applied)" + q)
    fput(fh, indent + "                di as result " + q + "    │ 4. RE-RUN Master. Every .xlsx in that folder is applied, and" + q)
    fput(fh, indent + "                di as result " + q + "    │               these rows are not re-sent by a new-only export." + q)
    fput(fh, indent + "                di as result " + q + "    │               Set oe_export_all 1 to export everything again." + q)
    fput(fh, indent + "                di as result " + q + "    └──────────────────────────────────────────────────────────────" + q)
    fput(fh, indent + "            }")
    fput(fh, indent + "            else di as error " + q + "    ERROR: exportopenended failed (rc=" + q + " " + bt + "_export_rc" + ap + " " + q + "). Nothing exported for " + dsname + "." + q)
    fput(fh, indent + "        }")
    fput(fh, indent + "    }")
    fput(fh, indent + "    restore")
    fput(fh, indent + "}")
    fput(fh, indent + "")
}

void write_mod_openended(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar dsname, string scalar indent, string scalar ds_idx)
{
    write_mod_oe_apply(fh, q, bt, ap, dol, dsname, indent)
    write_mod_oe_export(fh, q, bt, ap, dol, dsname, indent, ds_idx)
}
void write_mod_cover_page(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar pname, string scalar dsname, string scalar sheetname, string scalar ds_idx)
{
    fput(fh, "di as result _n " + q + "--- Generating Cover Page (" + dsname + ") ---" + q)
    write_selection_guard(fh, q, bt, ap, dol, pname)
    fput(fh, "preserve")
    fput(fh, "cap confirm variable fielddate")
    fput(fh, "if !_rc {")
    fput(fh, "    keep fielddate")
    fput(fh, "    drop if missing(fielddate)")
    fput(fh, "    gen one = 1")
    fput(fh, "    cap collapse (sum) n=one, by(fielddate)")
    fput(fh, "    qui sum n")
    fput(fh, "    local avg_daily = round(r(mean), 1)")
    fput(fh, "}")
    fput(fh, "restore")
    fput(fh, "if " + q + bt + "avg_daily" + ap + q + " == " + q + q + " local avg_daily 0")
    fput(fh, "")
    fput(fh, "qui count")
    fput(fh, "local total_obs = r(N)")
    fput(fh, "qui describe")
    fput(fh, "local total_vars = r(k)")
    fput(fh, "")
    fput(fh, "*  ── Raw vs cleaned observation delta ( guard) ──────────────────────────────")
    fput(fh, "local raw_n " + q + "N/A" + q)
    fput(fh, "local clean_delta " + q + "N/A" + q)
    fput(fh, "local delta_flag " + q + q)
    fput(fh, "local _rawf " + q + dol + "raw_data_dir/" + dol + "{auto_dsname_" + ds_idx + "}.dta" + q)
    fput(fh, "cap confirm file " + q + bt + "_rawf" + ap + q)
    fput(fh, "if !_rc {")
    fput(fh, "    preserve")
    fput(fh, "    qui use " + q + bt + "_rawf" + ap + q + ", clear")
    fput(fh, "    qui count")
    fput(fh, "    local raw_n = r(N)")
    fput(fh, "    restore")
    fput(fh, "    local clean_delta = " + bt + "raw_n" + ap + " - " + bt + "total_obs" + ap)
    fput(fh, "    local _thr " + dol + "hfcsys_clean_delta_pct_max")
    fput(fh, "    if " + q + bt + "_thr" + ap + q + " == " + q + q + " local _thr 5")
    fput(fh, "    if " + bt + "raw_n" + ap + " > 0 & " + bt + "clean_delta" + ap + " > 0 {")
    fput(fh, "        local _pct = 100 * " + bt + "clean_delta" + ap + " / " + bt + "raw_n" + ap)
    fput(fh, "        if " + bt + "_pct" + ap + " > " + bt + "_thr" + ap + " {")
    fput(fh, "            local delta_flag " + q + "  <-- CHECK" + q)
    fput(fh, "            di as error " + q + "  WARNING: cleaning removed " + bt + "clean_delta" + ap + " of " + bt + "raw_n" + ap + " rows (>" + bt + "_thr" + ap + "%)." + q)
    fput(fh, "            di as error " + q + "           HFC below is computed on the CLEANED dataset. Confirm this is intended." + q)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "local excel_start_date " + q + "N/A" + q)
    fput(fh, "local excel_last_date " + q + "N/A" + q)
    fput(fh, "cap confirm variable fielddate")
    fput(fh, "if !_rc {")
    fput(fh, "    qui sum fielddate, meanonly")
    fput(fh, "    if r(N) > 0 {")
    fput(fh, "        local min_date = r(min)")
    fput(fh, "        local max_date = r(max)")
    fput(fh, "        local excel_base = td(30dec1899)")
    fput(fh, "        local excel_start_date = " + bt + "min_date" + ap + " - " + bt + "excel_base" + ap)
    fput(fh, "        local excel_last_date = " + bt + "max_date" + ap + " - " + bt + "excel_base" + ap)
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "local avg_duration " + q + "N/A" + q)
    fput(fh, "cap confirm variable duration")
    fput(fh, "if !_rc {")
    fput(fh, "    cap destring duration, replace force")
    fput(fh, "    qui sum duration")
    fput(fh, "    if r(N) > 0 local avg_duration = round(r(mean)/60, 0.1)")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "local current_ss " + dol + "sample_size")
    fput(fh, "if " + q + dol + "sample_size_" + ds_idx + q + " != " + q + q + " local current_ss " + dol + "sample_size_" + ds_idx)
    fput(fh, "")
    fput(fh, "local est_days " + q + "N/A" + q)
    fput(fh, "local est_end_date " + q + "N/A" + q)
    fput(fh, "if " + bt + "avg_daily" + ap + " > 0 & " + q + bt + "excel_last_date" + ap + q + " != " + q + "N/A" + q + " {")
    fput(fh, "    local est_days = ceil(" + bt + "current_ss" + ap + " / " + bt + "avg_daily" + ap + ")")
    fput(fh, "    if " + bt + "total_obs" + ap + " >= " + bt + "current_ss" + ap + " {")
    fput(fh, "        local est_end_date = " + bt + "excel_last_date" + ap)
    fput(fh, "    }")
    fput(fh, "    else {")
    fput(fh, "        local rem_days = ceil((" + bt + "current_ss" + ap + " - " + bt + "total_obs" + ap + ") / " + bt + "avg_daily" + ap + ")")
    fput(fh, "        local est_end_date = " + bt + "excel_last_date" + ap + " + " + bt + "rem_days" + ap)
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "cap putexcel set " + q + dol + "excel_file" + q + ", sheet(" + q + sheetname + q + ") modify open")
    fput(fh, "putexcel D5:M5 = (" + q + dol + "project_name - " + dsname + q + "), bold border(bottom) merge")
    fput(fh, "putexcel D7:M7 = (" + q + "Total Observations: " + bt + "total_obs" + ap + " | Total Variables: " + bt + "total_vars" + ap + q + "), merge")
    fput(fh, "putexcel D9:M9 = (" + q + "--- Project Timeline ---" + q + "), bold underline merge")
    fput(fh, "putexcel D10 = (" + q + "Start Date:" + q + "), bold")
    fput(fh, "if " + q + bt + "excel_start_date" + ap + q + " != " + q + "N/A" + q + " putexcel F10 = (" + bt + "excel_start_date" + ap + "), nformat(" + q + "mm/dd/yyyy" + q + ")")
    fput(fh, "else putexcel F10 = (" + q + "N/A" + q + ")")
    fput(fh, "putexcel D11:E11 = (" + q + "Sample Size:" + q + "), bold merge")
    fput(fh, "putexcel F11 = (" + bt + "current_ss" + ap + ")")
    fput(fh, "putexcel D12 = (" + q + "Average Daily Collection:" + q + "), bold")
    fput(fh, "putexcel F12 = (" + bt + "avg_daily" + ap + ")")
    fput(fh, "putexcel D13 = (" + q + "Estimated Days:" + q + "), bold")
    fput(fh, "if " + q + bt + "est_days" + ap + q + " != " + q + "N/A" + q + " putexcel F13 = (" + bt + "est_days" + ap + ")")
    fput(fh, "else putexcel F13 = (" + q + "N/A" + q + ")")
    fput(fh, "putexcel D14 = (" + q + "Estimated End Date:" + q + "), bold")
    fput(fh, "if " + q + bt + "est_end_date" + ap + q + " != " + q + "N/A" + q + " {")
    fput(fh, "    putexcel F14 = formula(" + q + "F10+F13" + q + "), nformat(" + q + "mm/dd/yyyy" + q + ")")
    fput(fh, "}")
    fput(fh, "else putexcel F14 = (" + q + "N/A" + q + ")")
    fput(fh, "putexcel D15 = (" + q + "Average Interview Duration (mins):" + q + "), bold")
    fput(fh, "if " + q + bt + "avg_duration" + ap + q + " == " + q + "N/A" + q + " putexcel F15 = (" + q + "N/A" + q + ")")
    fput(fh, "else putexcel F15 = (" + bt + "avg_duration" + ap + ")")
    fput(fh, "putexcel D17:M17 = (" + q + "--- Data Lineage ---" + q + "), bold underline merge")
    fput(fh, "putexcel D18 = (" + q + "Raw Observations:" + q + "), bold")
    fput(fh, "putexcel F18 = (" + q + bt + "raw_n" + ap + q + ")")
    fput(fh, "putexcel D19 = (" + q + "Cleaned Observations (used by HFC):" + q + "), bold")
    fput(fh, "putexcel F19 = (" + bt + "total_obs" + ap + ")")
    fput(fh, "putexcel D20 = (" + q + "Rows Removed by Cleaning:" + q + "), bold")
    fput(fh, "putexcel F20 = (" + q + bt + "clean_delta" + ap + bt + "delta_flag" + ap + q + ")")
    fput(fh, "putexcel close")
    fput(fh, "di as result " + q + "-> Cover Page exported successfully." + q)
    fput(fh, "")
}

void write_mod_enum_success(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar pname, string scalar sheet_suffix)
{
    fput(fh, "* SUCCESS RATE BY ENUMERATOR")
    fput(fh, "di as result _n " + q + "--- Running Enumerator Success Rate ---" + q)
    write_selection_guard(fh, q, bt, ap, dol, pname)
    fput(fh, "preserve")
    fput(fh, "")
    fput(fh, "foreach v in sup enum {")
    fput(fh, "    cap confirm variable " + bt + "v" + ap)
    fput(fh, "    if !_rc {")
    fput(fh, "        cap confirm numeric variable " + bt + "v" + ap)
    fput(fh, "        if !_rc {")
    fput(fh, "            cap decode " + bt + "v" + ap + ", gen(" + bt + "v" + ap + "_str)")
    fput(fh, "            if !_rc {")
    fput(fh, "                cap tostring " + bt + "v" + ap + ", gen(" + bt + "v" + ap + "_num) force")
    fput(fh, "                cap replace " + bt + "v" + ap + "_str = " + bt + "v" + ap + "_num if missing(" + bt + "v" + ap + "_str)")
    fput(fh, "                cap drop " + bt + "v" + ap + " " + bt + "v" + ap + "_num")
    fput(fh, "                cap rename " + bt + "v" + ap + "_str " + bt + "v" + ap)
    fput(fh, "            }")
    fput(fh, "            else cap tostring " + bt + "v" + ap + ", replace force")
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "cap confirm variable consent")
    fput(fh, "if !_rc {")
    fput(fh, "    gen consented_survey = 1 if (consent==1)")
    fput(fh, "    replace consented_survey = 0 if missing(consented_survey)")
    fput(fh, "    gen not_success_survey = 1 if (consent!=1)")
    fput(fh, "    replace not_success_survey = 0 if (consent==1)")
    fput(fh, "    local grp_vars " + q + "enum" + q)
    fput(fh, "    cap confirm variable sup")
    fput(fh, "    if !_rc local grp_vars " + q + "sup enum" + q)
    fput(fh, "    cap keep " + bt + "grp_vars" + ap + " consented_survey not_success_survey")
    fput(fh, "    cap collapse (sum) consented_survey not_success_survey, by(" + bt + "grp_vars" + ap + ")")
    fput(fh, "    gen consent_percent = consented_survey / (consented_survey + not_success_survey) * 100")
    fput(fh, "    gen not_success_percent = not_success_survey / (consented_survey + not_success_survey) * 100")
    fput(fh, "    di as result " + q + "-> Exporting Enum Success Page..." + q)
    fput(fh, "    cap export excel using " + q + dol + "excel_file" + q + ", sheet(" + q + "Enum_Success_" + sheet_suffix + q + ") sheetreplace firstrow(variables) cell(A1)")
    fput(fh, "}")
    fput(fh, "else di as txt " + q + "-> 'consent' variable not found. Skipping Success Rate export." + q)
    fput(fh, "restore")
    fput(fh, "")
    fput(fh, "di as result _n " + q + "--- Running Daily Progress ---" + q)
    write_selection_guard(fh, q, bt, ap, dol, pname)
    fput(fh, "preserve")
    fput(fh, "local req_ok 1")
    fput(fh, "foreach v in enum fielddate {")
    fput(fh, "    cap confirm variable " + bt + "v" + ap)
    fput(fh, "    if _rc local req_ok 0")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "if " + bt + "req_ok" + ap + " {")
    fput(fh, "    foreach v in sup enum {")
    fput(fh, "        cap confirm variable " + bt + "v" + ap)
    fput(fh, "        if !_rc {")
    fput(fh, "            cap confirm numeric variable " + bt + "v" + ap)
    fput(fh, "            if !_rc {")
    fput(fh, "                cap decode " + bt + "v" + ap + ", gen(" + bt + "v" + ap + "_str)")
    fput(fh, "                if !_rc {")
    fput(fh, "                    cap tostring " + bt + "v" + ap + ", gen(" + bt + "v" + ap + "_num) force")
    fput(fh, "                    cap replace " + bt + "v" + ap + "_str = " + bt + "v" + ap + "_num if missing(" + bt + "v" + ap + "_str)")
    fput(fh, "                    cap drop " + bt + "v" + ap + " " + bt + "v" + ap + "_num")
    fput(fh, "                    cap rename " + bt + "v" + ap + "_str " + bt + "v" + ap)
    fput(fh, "                }")
    fput(fh, "                else cap tostring " + bt + "v" + ap + ", replace force")
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "    cap confirm variable consent")
    fput(fh, "    if !_rc keep if consent == 1")
    fput(fh, "    cap confirm variable screening")
    fput(fh, "    if !_rc keep if screening == 1")
    fput(fh, "")
    fput(fh, "    drop if missing(enum) | missing(fielddate)")
    fput(fh, "    qui count")
    fput(fh, "    if r(N) > 0 {")
    fput(fh, "        cap confirm numeric variable fielddate")
    fput(fh, "        if !_rc {")
    fput(fh, "            format fielddate %td")
    fput(fh, "            gen surv_count = 1")
    fput(fh, "            local collapse_by " + q + "enum" + q)
    fput(fh, "            cap confirm variable sup")
    fput(fh, "            if !_rc local collapse_by " + q + "sup enum" + q)
    fput(fh, "")
    fput(fh, "            collapse (count) daily_count=surv_count, by(" + bt + "collapse_by" + ap + " fielddate)")
    fput(fh, "            qui reshape wide daily_count, i(" + bt + "collapse_by" + ap + ") j(fielddate)")
    fput(fh, "")
    fput(fh, "            cap unab daily_vars : daily_count*")
    fput(fh, "            if !_rc {")
    fput(fh, "                foreach v of local daily_vars {")
    fput(fh, "                    local d = subinstr(" + q + bt + "v" + ap + q + ", " + q + "daily_count" + q + ", " + q + q + ", 1)")
    fput(fh, "                    if " + q + bt + "d" + ap + q + " != " + q + q + " {")
    fput(fh, "                        local dlabel : display %tdDDmonCCYY real(" + q + bt + "d" + ap + q + ")")
    fput(fh, "                        local clean = subinstr(" + q + bt + "dlabel" + ap + q + ", " + q + " " + q + ", " + q + q + ", .)")
    fput(fh, "                        local newname = " + q + "d_" + bt + "clean" + ap + q)
    fput(fh, "                        rename " + bt + "v" + ap + " " + bt + "newname" + ap)
    fput(fh, "                        label var " + bt + "newname" + ap + " " + q + bt + "dlabel" + ap + q)
    fput(fh, "                    }")
    fput(fh, "                }")
    fput(fh, "            }")
    fput(fh, "            cap egen Total = rowtotal(d_*)")
    fput(fh, "            di as result " + q + "-> Exporting Daily Progress Page..." + q)
    fput(fh, "            cap export excel using " + q + dol + "excel_file" + q + ", sheet(" + q + "Daily_Surveys_" + sheet_suffix + q + ") sheetreplace firstrow(varlabels)")
    fput(fh, "        }")
    fput(fh, "        else di as err " + q + "-> fielddate must be numeric Stata date. Skipping Daily Progress export." + q)
    fput(fh, "    }")
    fput(fh, "    else di as txt " + q + "-> No valid observations after filtering. Skipping Daily Progress export." + q)
    fput(fh, "}")
    fput(fh, "else di as txt " + q + "-> Skipping Daily Progress: core variables missing (enum, fielddate)" + q)
    fput(fh, "restore")
    fput(fh, "")
}

void write_flag_lifecycle(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar ind)
{
    fput(fh, ind + "*  -- Issue-flag lifecycle ---------------------------------------------------")
    fput(fh, ind + "cap confirm variable key")
    fput(fh, ind + "if _rc {")
    fput(fh, ind + "    di as txt " + q + "   -> no key variable; lifecycle columns unavailable for this sheet." + q)
    fput(fh, ind + "}")
    fput(fh, ind + "else {")
    fput(fh, ind + "    local _lc_today " + q + dol + "today" + q)
    fput(fh, ind + "    if " + q + bt + "_lc_today" + ap + q + " == " + q + q + " local _lc_today = string(date(c(current_date), " + q + "DMY" + q + "), " + q + "%tdCCYYNNDD" + q + ")")
    fput(fh, ind + "    cap confirm file " + q + bt + "_flagstore" + ap + q)
    fput(fh, ind + "    if !_rc {")
    fput(fh, ind + "        cap merge 1:1 key using " + q + bt + "_flagstore" + ap + q + ", keepusing(first_flagged) keep(master match) gen(_fl_m)")
    fput(fh, ind + "        cap drop _fl_m")
    fput(fh, ind + "    }")
    fput(fh, ind + "    cap confirm variable first_flagged")
    fput(fh, ind + "    if _rc gen str8 first_flagged = " + q + q)
    fput(fh, ind + "    qui replace first_flagged = " + q + bt + "_lc_today" + ap + q + " if first_flagged == " + q + q)
    fput(fh, ind + "    gen byte is_new = (first_flagged == " + q + bt + "_lc_today" + ap + q + ")")
    fput(fh, ind + "    gen int days_open = date(" + q + bt + "_lc_today" + ap + q + ", " + q + "YMD" + q + ") - date(first_flagged, " + q + "YMD" + q + ")")
    fput(fh, ind + "    cap replace days_open = 0 if missing(days_open)")
    fput(fh, ind + "    label var is_new " + q + "1 = first flagged today" + q)
    fput(fh, ind + "    label var first_flagged " + q + "First flagged (YYYYMMDD)" + q)
    fput(fh, ind + "    label var days_open " + q + "Days open since first flagged" + q)
    fput(fh, ind + "    *  NEW first, then the longest-outstanding issues — triage order.")
    fput(fh, ind + "    gsort -is_new -days_open")
    fput(fh, ind + "    *  Persist only what is flagged NOW. Resolved rows leave the store here.")
    fput(fh, ind + "    *  NOTE: tempfile round-trip, NOT preserve/restore. Every caller is")
    fput(fh, ind + "    *  already inside its own preserve, and Stata rejects a nested one.")
    fput(fh, ind + "    tempfile _lc_all")
    fput(fh, ind + "    qui save " + q + bt + "_lc_all" + ap + q + ", replace emptyok")
    fput(fh, ind + "    keep key first_flagged")
    fput(fh, ind + "    qui save " + q + bt + "_flagstore" + ap + q + ", replace emptyok")
    fput(fh, ind + "    qui use " + q + bt + "_lc_all" + ap + q + ", clear")
    fput(fh, ind + "}")
    fput(fh, "")
}

void write_mod_duration_audit(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar pname, string scalar sheet_suffix, string scalar ds_idx)
{
    fput(fh, "di as result _n " + q + "--- Running Duration Audit ---" + q)
    write_selection_guard(fh, q, bt, ap, dol, pname)
    fput(fh, "preserve")
    fput(fh, "")
    fput(fh, "cap keep if consent == 1")
    fput(fh, "cap confirm variable screening")
    fput(fh, "if !_rc cap keep if screening == 1")
    fput(fh, "")
    fput(fh, "cap confirm variable duration")
    fput(fh, "if !_rc {")
    fput(fh, "    cap destring duration, replace force")
    fput(fh, "    gen du_min = duration / 60")
    fput(fh, "    gen du_hr = du_min / 60")
    fput(fh, "    cap keep if (du_min < " + dol + "dur_low & !missing(du_min)) | (du_min > " + dol + "dur_high & !missing(du_min))")
    fput(fh, "    qui count")
    fput(fh, "    if r(N) > 0 {")
    fput(fh, "        di as result " + q + "-> Found " + q + " r(N) " + q + " duration outliers. Exporting..." + q)
    fput(fh, "        cap confirm variable fielddate")
    fput(fh, "        if !_rc sort du_min fielddate")
    fput(fh, "        else sort du_min")
    fput(fh, "        local _flagstore " + q + dol + "hfc_flag_dir/" + dol + "{auto_dsname_" + ds_idx + "}_FLAGS_DURATION.dta" + q)
    write_flag_lifecycle(fh, q, bt, ap, dol, "        ")
    fput(fh, "        local _mf_ds " + dol + "meta_front_" + ds_idx)
    fput(fh, "        if " + q + bt + "_mf_ds" + ap + q + " == " + q + q + " local _mf_ds " + dol + "meta_front")
    fput(fh, "        local _mi_ds " + dol + "meta_ids_" + ds_idx)
    fput(fh, "        if " + q + bt + "_mi_ds" + ap + q + " == " + q + q + " local _mi_ds " + dol + "meta_ids")
    fput(fh, "        local _tl_ds " + dol + "tail_" + ds_idx)
    fput(fh, "        if " + q + bt + "_tl_ds" + ap + q + " == " + q + q + " local _tl_ds " + dol + "tail")
    fput(fh, "        local keep_vars " + q + q)
    fput(fh, "        foreach v in is_new days_open first_flagged " + bt + "_mf_ds" + ap + " " + bt + "_mi_ds" + ap + " " + bt + "_tl_ds" + ap + " total_duration du_min {")
    fput(fh, "            cap confirm variable " + bt + "v" + ap)
    fput(fh, "            if !_rc local keep_vars " + bt + "keep_vars" + ap + " " + bt + "v" + ap)
    fput(fh, "        }")
    fput(fh, "        keep " + bt + "keep_vars" + ap)
    fput(fh, "        order " + bt + "keep_vars" + ap)
    fput(fh, "        cap export excel using " + q + dol + "excel_file" + q + ", sheet(" + q + "Duration_Flags_" + sheet_suffix + q + ") sheetreplace firstrow(variables)")
    fput(fh, "    }")
    fput(fh, "    else di as result " + q + "-> No duration outliers found. Skipping export." + q)
    fput(fh, "}")
    fput(fh, "else di as txt " + q + "-> Variable 'duration' not found. Skipping module." + q)
    fput(fh, "restore")
    fput(fh, "")
}

void write_mod_gatekeeper_skip(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar pname, string scalar sheet_suffix, string scalar ds_idx)
{
    fput(fh, "di as result _n " + q + "--- Running Gatekeeper Skip Trends ---" + q)
    write_selection_guard(fh, q, bt, ap, dol, pname)
    fput(fh, "preserve")
    fput(fh, "")
    fput(fh, "if " + q + dol + "gate_vars_" + ds_idx + q + " != " + q + q + " {")
    fput(fh, "    cap keep if consent == 1")
    fput(fh, "    local gate_run " + q + q)
    fput(fh, "    foreach v in " + dol + "gate_vars_" + ds_idx + " {")
    fput(fh, "        cap confirm variable " + bt + "v" + ap)
    fput(fh, "        if !_rc {")
    fput(fh, "            local lbl_" + bt + "v" + ap + " : variable label " + bt + "v" + ap)
    fput(fh, "            if " + q + bt + "lbl_" + bt + "v" + ap + ap + q + " == " + q + q + " local lbl_" + bt + "v" + ap + " " + q + bt + "v" + ap + q)
    fput(fh, "            cap confirm numeric variable " + bt + "v" + ap)
    fput(fh, "            if !_rc gen skip_" + bt + "v" + ap + " = (" + bt + "v" + ap + " == 0) if !missing(" + bt + "v" + ap + ")")
    fput(fh, "            else        gen skip_" + bt + "v" + ap + " = (" + bt + "v" + ap + " == " + q + "0" + q + ") if !missing(" + bt + "v" + ap + ")")
    fput(fh, "            local gate_run " + bt + "gate_run" + ap + " " + bt + "v" + ap)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "    if " + q + bt + "gate_run" + ap + q + " != " + q + q + " {")
    fput(fh, "        gen n_surv = 1")
    fput(fh, "        collapse (mean) skip_* (sum) n_surv, by(enum)")
    fput(fh, "        foreach v in " + bt + "gate_run" + ap + " {")
    fput(fh, "            cap confirm variable skip_" + bt + "v" + ap)
    fput(fh, "            if !_rc {")
    fput(fh, "                qui replace skip_" + bt + "v" + ap + " = skip_" + bt + "v" + ap + " * 100")
    fput(fh, "                local clean_lbl = substr(" + q + bt + "lbl_" + bt + "v" + ap + ap + q + ", 1, 55)")
    fput(fh, "                label var skip_" + bt + "v" + ap + " " + q + "[" + bt + "v" + ap + "] % No: " + bt + "clean_lbl" + ap + q)
    fput(fh, "            }")
    fput(fh, "        }")
    fput(fh, "        label var enum " + q + "Enumerator Name" + q)
    fput(fh, "        label var n_surv " + q + "Total Surveys Evaluated" + q)
    fput(fh, "        qui count")
    fput(fh, "        if r(N) > 0 {")
    fput(fh, "            di as result " + q + "-> Exporting Gatekeeper Skips..." + q)
    fput(fh, "            local first_gv : word 1 of " + bt + "gate_run" + ap)
    fput(fh, "            cap gsort -skip_" + bt + "first_gv" + ap)
    fput(fh, "            cap export excel using " + q + dol + "excel_file" + q + ", sheet(" + q + "Skip_Trends_" + sheet_suffix + q + ") sheetreplace firstrow(variables)")
    fput(fh, "        }")
    fput(fh, "        else di as result " + q + "-> No data to export for gatekeeper skips." + q)
    fput(fh, "    }")
    fput(fh, "    else di as txt " + q + "-> Gatekeeper variables configured but not found in dataset." + q)
    fput(fh, "}")
    fput(fh, "else di as txt " + q + "-> No gatekeeper variables configured. Skipping module." + q)
    fput(fh, "restore")
    fput(fh, "")
}

void write_mod_response_bias(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar pname, string scalar sheet_suffix)
{
    fput(fh, "di as result _n " + q + "--- Running Response Bias (DK/NA/Other) Monitor ---" + q)
    write_selection_guard(fh, q, bt, ap, dol, pname)
    fput(fh, "preserve")
    fput(fh, "")
    fput(fh, "qui count")
    fput(fh, "if r(N) > 0 {")
    fput(fh, "    cap confirm variable enum")
    fput(fh, "    if !_rc {")
    fput(fh, "        gen row_dk = 0")
    fput(fh, "        gen row_na = 0")
    fput(fh, "        gen row_other = 0")
    fput(fh, "        gen int var_count_v = 0")
    fput(fh, "        qui ds, has(type numeric)")
    fput(fh, "        local num_vars " + bt + "r(varlist)" + ap)
    fput(fh, "        *  Exclude admin/ID/timing vars from the bias denominator so")
    fput(fh, "        *  percentages reflect question-domain variables only.")
    fput(fh, "        local _mf_ds " + dol + "meta_front_" + sheet_suffix)
    fput(fh, "        if " + q + bt + "_mf_ds" + ap + q + " == " + q + q + " local _mf_ds " + dol + "meta_front")
    fput(fh, "        local _mi_ds " + dol + "meta_ids_" + sheet_suffix)
    fput(fh, "        if " + q + bt + "_mi_ds" + ap + q + " == " + q + q + " local _mi_ds " + dol + "meta_ids")
    fput(fh, "        local _tl_ds " + dol + "tail_" + sheet_suffix)
    fput(fh, "        if " + q + bt + "_tl_ds" + ap + q + " == " + q + q + " local _tl_ds " + dol + "tail")
    fput(fh, "        local _excl_vars " + q + q)
    fput(fh, "        foreach _xv in " + bt + "_mf_ds" + ap + " " + bt + "_mi_ds" + ap + " " + bt + "_tl_ds" + ap + " " + dol + "timer_start " + dol + "timer_end {")
    fput(fh, "            local _excl_vars " + bt + "_excl_vars" + ap + " " + bt + "_xv" + ap)
    fput(fh, "        }")
    fput(fh, "        foreach var of local num_vars {")
    fput(fh, "            if inlist(" + q + bt + "var" + ap + q + ", " + q + "enum" + q + ", " + q + "consent" + q + ", " + q + "fielddate" + q + ") continue")
    fput(fh, "            local _in_excl 0")
    fput(fh, "            foreach _xv of local _excl_vars {")
    fput(fh, "                if " + q + bt + "var" + ap + q + " == " + q + bt + "_xv" + ap + q + " local _in_excl 1")
    fput(fh, "            }")
    fput(fh, "            if " + bt + "_in_excl" + ap + " continue")
    fput(fh, "            qui replace row_dk    = row_dk    + (" + bt + "var" + ap + " == " + dol + "code_dk)")
    fput(fh, "            qui replace row_na    = row_na    + (" + bt + "var" + ap + " == " + dol + "code_na)")
    fput(fh, "            qui replace row_other = row_other + (" + bt + "var" + ap + " == " + dol + "code_other)")
    fput(fh, "            qui replace var_count_v = var_count_v + (!missing(" + bt + "var" + ap + "))")
    fput(fh, "        }")
    fput(fh, "        qui count if row_dk > 0 | row_na > 0 | row_other > 0")
    fput(fh, "        if r(N) > 0 {")
    fput(fh, "            gen dk_percent    = (row_dk / var_count_v) * 100")
    fput(fh, "            gen na_percent    = (row_na / var_count_v) * 100")
    fput(fh, "            gen other_percent = (row_other / var_count_v) * 100")
    fput(fh, "            cap confirm numeric variable enum")
    fput(fh, "            if !_rc {")
    fput(fh, "                cap decode enum, gen(enum_name)")
    fput(fh, "                if !_rc {")
    fput(fh, "                    drop enum")
    fput(fh, "                    rename enum_name enum")
    fput(fh, "                }")
    fput(fh, "            }")
    fput(fh, "            collapse (count) surveys = row_dk (sum) total_dk = row_dk (sum) total_na = row_na (sum) total_other = row_other (mean) avg_dk = row_dk (mean) avg_na = row_na (mean) avg_other = row_other (mean) avg_dk_percent = dk_percent (mean) avg_na_percent = na_percent (mean) avg_other_percent = other_percent, by(enum)")
    fput(fh, "            format avg_dk_percent avg_na_percent avg_other_percent %6.2f")
    fput(fh, "            gen dk_flag = avg_dk_percent > 20")
    fput(fh, "            label define dkflag 0 " + q + "Normal" + q + " 1 " + q + "High DK" + q)
    fput(fh, "            cap label values dk_flag dkflag")
    fput(fh, "            order enum surveys total_dk total_na total_other avg_dk avg_na avg_other avg_dk_percent avg_na_percent avg_other_percent dk_flag")
    fput(fh, "            gsort -avg_dk_percent")
    fput(fh, "            qui count")
    fput(fh, "            if r(N) > 0 {")
    fput(fh, "                di as result " + q + "-> Found " + q + " r(N) " + q + " enumerators in response bias check. Exporting..." + q)
    fput(fh, "                cap export excel using " + q + dol + "excel_file" + q + ", sheet(" + q + "Response_Bias_" + sheet_suffix + q + ") sheetreplace firstrow(variables)")
    fput(fh, "            }")
    fput(fh, "            else di as result " + q + "-> No valid responses found for bias check. Skipping export." + q)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "    else di as txt " + q + "-> Variable 'enum' missing. Skipping Response Bias module." + q)
    fput(fh, "}")
    fput(fh, "else di as txt " + q + "-> No new surveys found for response bias check. Skipping." + q)
    fput(fh, "restore")
    fput(fh, "")
}

void write_mod_duplicates_check(real scalar fh, string scalar q, string scalar bt, string scalar ap, string scalar dol, string scalar pname, string scalar sheet_suffix, string scalar ds_idx)
{
    fput(fh, "di as result _n " + q + "--- Running Core Identity Duplicates Check ---" + q)
    write_selection_guard(fh, q, bt, ap, dol, pname)
    fput(fh, "preserve")
    fput(fh, "")
    fput(fh, "cap keep if consent == 1")
    fput(fh, "*  ── Build list of ID variables to check independently ──────────────────────")
    fput(fh, "local _dup_vars " + q + q)
    fput(fh, "foreach _chk_v in resp_id hhid resp_phone_1 {")
    fput(fh, "    cap confirm variable " + bt + "_chk_v" + ap)
    fput(fh, "    if !_rc local _dup_vars " + q + bt + "_dup_vars" + ap + " " + bt + "_chk_v" + ap + q)
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "if " + q + bt + "_dup_vars" + ap + q + " == " + q + q + " {")
    fput(fh, "    di as txt " + q + "-> No valid ID variable (resp_id/hhid/resp_phone_1) found. Skipping duplicates check." + q)
    fput(fh, "}")
    fput(fh, "else {")
    fput(fh, "    local _mf_ds " + dol + "meta_front_" + sheet_suffix)
    fput(fh, "    if " + q + bt + "_mf_ds" + ap + q + " == " + q + q + " local _mf_ds " + dol + "meta_front")
    fput(fh, "    local _mi_ds " + dol + "meta_ids_" + sheet_suffix)
    fput(fh, "    if " + q + bt + "_mi_ds" + ap + q + " == " + q + q + " local _mi_ds " + dol + "meta_ids")
    fput(fh, "    local _tl_ds " + dol + "tail_" + sheet_suffix)
    fput(fh, "    if " + q + bt + "_tl_ds" + ap + q + " == " + q + q + " local _tl_ds " + dol + "tail")
    fput(fh, "")
    fput(fh, "    *  Save a working copy once — reload per ID variable instead of nested preserve")
    fput(fh, "    tempfile _dup_base")
    fput(fh, "    qui save " + q + bt + "_dup_base" + ap + q + ", replace emptyok")
    fput(fh, "")
    fput(fh, "    local _any_dups_found 0")
    fput(fh, "    foreach _dup_id of local _dup_vars {")
    fput(fh, "        use " + q + bt + "_dup_base" + ap + q + ", clear")
    fput(fh, "        cap destring " + bt + "_dup_id" + ap + ", replace force")
    fput(fh, "        cap drop if missing(" + bt + "_dup_id" + ap + ")")
    fput(fh, "        cap drop if " + bt + "_dup_id" + ap + " == " + q + q)
    fput(fh, "        cap duplicates tag " + bt + "_dup_id" + ap + ", gen(dup)")
    fput(fh, "        cap confirm variable dup")
    fput(fh, "        if !_rc {")
    fput(fh, "            cap keep if dup >= 1")
    fput(fh, "            qui count")
    fput(fh, "            if r(N) > 0 {")
    fput(fh, "                local _any_dups_found 1")
    fput(fh, "                local _sheet_lbl " + q + "Duplicates_" + sheet_suffix + "_" + bt + "_dup_id" + ap + q)
    fput(fh, "                di as error " + q + "-> WARNING: Found " + q + " r(N) " + q + " duplicate(s) on " + bt + "_dup_id" + ap + "! Exporting to sheet: " + bt + "_sheet_lbl" + ap + q)
    fput(fh, "                cap confirm variable fielddate")
    fput(fh, "                if !_rc sort " + bt + "_dup_id" + ap + " fielddate")
    fput(fh, "                else sort " + bt + "_dup_id" + ap)
    fput(fh, "                local _flagstore " + q + dol + "hfc_flag_dir/" + dol + "{auto_dsname_" + ds_idx + "}_FLAGS_DUP_" + bt + "_dup_id" + ap + ".dta" + q)
                    write_flag_lifecycle(fh, q, bt, ap, dol, "                ")
    fput(fh, "                local keep_vars " + q + q)
    fput(fh, "                foreach v in is_new days_open first_flagged " + bt + "_mf_ds" + ap + " " + bt + "_mi_ds" + ap + " " + bt + "_tl_ds" + ap + " dup {")
    fput(fh, "                    cap confirm variable " + bt + "v" + ap)
    fput(fh, "                    if !_rc local keep_vars " + bt + "keep_vars" + ap + " " + bt + "v" + ap)
    fput(fh, "                }")
    fput(fh, "                keep " + bt + "keep_vars" + ap)
    fput(fh, "                order " + bt + "keep_vars" + ap)
    fput(fh, "                cap export excel using " + q + dol + "excel_file" + q + ", sheet(" + q + bt + "_sheet_lbl" + ap + q + ") sheetreplace firstrow(variables)")
    fput(fh, "            }")
    fput(fh, "            else di as result " + q + "-> No duplicates on " + bt + "_dup_id" + ap + "." + q)
    fput(fh, "        }")
    fput(fh, "    }")
    fput(fh, "    use " + q + bt + "_dup_base" + ap + q + ", clear")
    fput(fh, "    if !" + bt + "_any_dups_found" + ap + " di as result " + q + "-> Excellent! No duplicates found on any ID variable." + q)
    fput(fh, "}")
    fput(fh, "restore")
    fput(fh, "")
}

//  Call a sibling generated module, if it is there.
//
//  Inside a project it always is, so the guard never fires and behaviour is
//  unchanged. A Processing DO carried off on its own may arrive without its
//  siblings; the fallback says so and carries on rather than erroring out on a
//  missing file (ADR-056).
// ═══════════════════════════════════════════════════════════════════════════
//  PART 4 — the analyst-facing files and the framework runtime  (ADR-061)
//
//  An analyst-facing DO file is a readable orchestration layer: a header, one
//  INITIALISE block, the stages in the order they run, and the sections the
//  analyst owns, marked SAFE TO EDIT. The machinery behind them lives in
//  framework files the analyst never edits:
//
//    in a project   the mdf package, plus _mdf/mdf_labeling.do and
//                   _mdf/mdf_translation.do beside the modules — Tier 1,
//                   rewritten on every Master run
//    in a package   the same two engine files, byte for byte, plus
//                   _mdf/mdf_runtime.do (static, shipped with this package as
//                   _mdf_rt_package.ado) and _mdf/mdf_package.do (the package's
//                   identity and settings, written when the package is built)
// ═══════════════════════════════════════════════════════════════════════════

string scalar _rule(string scalar ch)
{
    return("*" + ch * 78 + "*")
}

//  "* Label                : value" — values line up at column 26.
string scalar _hdr(string scalar lab, string scalar val)
{
    return("* " + lab + " " * (21 - strlen(lab)) + ": " + val)
}

string scalar _hdrc(string scalar val)
{
    return("*" + " " * 24 + val)
}

//  Title on the left, tag on the right, 80 columns wide.
string scalar _titled(string scalar title, string scalar tag)
{
    real scalar gap
    gap = 80 - ustrlen("* " + title) - ustrlen(tag)
    //  Too long for one line: the tag goes right-aligned on the next.
    if (gap < 2) return("* " + title + char(10) + "*" + " " * (79 - ustrlen(tag)) + tag)
    return("* " + title + " " * gap + tag)
}

//  Words of s, in lines of at most w characters.
string colvector _wrap(string scalar s, real scalar w)
{
    string rowvector T
    string colvector R
    string scalar cur
    real scalar i
    T = tokens(s)
    R = J(0, 1, "")
    cur = ""
    for (i = 1; i <= cols(T); i++) {
        if (cur != "" & ustrlen(cur + " " + T[i]) > w) {
            R = R \ cur
            cur = T[i]
        }
        else cur = (cur == "" ? T[i] : cur + " " + T[i])
    }
    if (cur != "" | rows(R) == 0) R = R \ cur
    return(R)
}

//  The header every analyst-facing file opens with. Personal details come from
//  Section 0 and a field that is not set is left out — nothing is invented.
void mdf_file_header(real scalar fh, string scalar purpose,
                     string colvector about, string colvector howto)
{
    string scalar v
    real scalar i

    fput(fh, _rule("="))
    fput(fh, _hdr("Project", st_global("project_name")))
    fput(fh, _hdr("Purpose", purpose))
    v = st_global("project_lead")
    if (v != "") fput(fh, _hdr("Author", v))
    v = st_global("organisation")
    if (v != "") fput(fh, _hdr("Organisation", v))
    v = st_global("project_email")
    if (v != "") fput(fh, _hdr("Email", v))
    fput(fh, _hdr("Last Modified", c("current_date") + "   (generated by Master DO File " + st_global("hfc_version") + ")"))
    fput(fh, _rule("="))
    v = st_global("project_description")
    if (v != "") {
        W = _wrap(v, 54)
        fput(fh, _hdr("Description", W[1]))
        for (i = 2; i <= rows(W); i++) fput(fh, _hdrc(W[i]))
        for (i = 1; i <= rows(about); i++) fput(fh, _hdrc(about[i]))
    }
    else {
        fput(fh, _hdr("Description", about[1]))
        for (i = 2; i <= rows(about); i++) fput(fh, _hdrc(about[i]))
    }
    fput(fh, _rule("-"))
    fput(fh, _hdr("How to run", howto[1]))
    for (i = 2; i <= rows(howto); i++) fput(fh, _hdrc(howto[i]))
    fput(fh, _hdr("What to edit", "Only the sections marked [SAFE TO EDIT]. Those"))
    fput(fh, _hdrc("marked [MDF GENERATED - DO NOT EDIT] are the"))
    fput(fh, _hdrc("framework's. Master never overwrites this file"))
    fput(fh, _hdrc("once it exists."))
    fput(fh, _rule("="))
}

//  How every analyst-facing file is run, said the same way in each.
string colvector _howto_run()
{
    return(("Open it in Stata and run it (Ctrl+A, then Ctrl+D)." \
            "It finds its project, or its Deliverables package," \
            "from Stata's working directory, and stops if that is" \
            "not where it belongs."))
}

void mdf_gen_section(real scalar fh, string scalar title, string colvector notes)
{
    real scalar i
    fput(fh, "")
    fput(fh, _rule("-"))
    fput(fh, _titled(title, "[MDF GENERATED - DO NOT EDIT]"))
    for (i = 1; i <= rows(notes); i++) fput(fh, "*    " + notes[i])
    fput(fh, _rule("-"))
}

void mdf_edit_section(real scalar fh, string scalar bookmark, string scalar title,
                      string colvector notes)
{
    real scalar i
    fput(fh, "")
    if (bookmark != "") fput(fh, "**# Bookmark: " + bookmark)
    fput(fh, _rule("="))
    fput(fh, _titled(title, "[SAFE TO EDIT]"))
    for (i = 1; i <= rows(notes); i++) fput(fh, "*    " + notes[i])
    fput(fh, _rule("="))
}

//  The one block of machinery an analyst-facing file keeps. Stata gives a
//  running DO file no way to learn its own path (c(do_current) and c(filename)
//  are empty in Stata 17 — measured), so the search starts at the working
//  directory and walks up. A Deliverables package is recognised by its runtime
//  file and a project by .hfc_root; either one is then made to prove it is THIS
//  file's project before anything runs (mdf_runtime.do, mdf_bootstrap).
void write_init_block(real scalar fh, string scalar q, string scalar bt,
                      string scalar ap, string scalar dol, string scalar pname,
                      string scalar role, real scalar clearall)
{
    string scalar bs, rt

    bs = char(92)
    rt = "/03_Processing Files/01_Do Files/_mdf/mdf_runtime.do"
    mdf_gen_section(fh, "0. INITIALISE",
        ("Finds the project, or the Deliverables package, this file belongs to" \
         "and loads its settings. The search starts at Stata's working" \
         "directory and goes upward; a folder is used only if it identifies" \
         "itself as this file's project, and nothing is inherited from"  \
         "anything else run earlier in this Stata session."))
    if (clearall) fput(fh, "clear all")
    fput(fh, "set more off")
    fput(fh, "version 16")
    fput(fh, "global mdf_want_id   " + q + pname + q)
    fput(fh, "global mdf_want_role " + q + role + q)
    fput(fh, "global mdf_want_at   " + q + q)
    fput(fh, "local _mdf_p = subinstr(" + _cq("c(pwd)") + ", " + q + bs + q + ", " + q + "/" + q + ", .)")
    fput(fh, "local _mdf_kind " + q + q)
    fput(fh, "while " + _cq("_mdf_p") + " != " + q + q + " & " + q + _mq("_mdf_kind") + q + " == " + q + q + " {")
    fput(fh, "    cap confirm file " + bt + q + _mq("_mdf_p") + rt + q + ap)
    fput(fh, "    if !_rc local _mdf_kind " + q + "package" + q)
    fput(fh, "    cap confirm file " + bt + q + _mq("_mdf_p") + "/.hfc_root" + q + ap)
    fput(fh, "    if !_rc & " + q + _mq("_mdf_kind") + q + " == " + q + q + " local _mdf_kind " + q + "project" + q)
    fput(fh, "    if " + q + _mq("_mdf_kind") + q + " != " + q + q + " global mdf_want_at " + _cq("_mdf_p"))
    fput(fh, "    local _mdf_c = strrpos(" + _cq("_mdf_p") + ", " + q + "/" + q + ")")
    fput(fh, "    local _mdf_p = substr(" + _cq("_mdf_p") + ", 1, max(" + _mq("_mdf_c") + " - 1, 0))")
    fput(fh, "}")
    fput(fh, "if " + q + _mq("_mdf_kind") + q + " == " + q + "package" + q + " do " + bt + q + dol + "mdf_want_at" + rt + q + ap)
    fput(fh, "else {")
    fput(fh, "    cap which mdf_bootstrap")
    fput(fh, "    if _rc {")
    fput(fh, "        di as error " + q + "  This file is not inside its project or its Deliverables package," + q)
    fput(fh, "        di as error " + q + "  and the Master DO File framework is not installed. Searched upward" + q)
    fput(fh, "        di as error " + q + "  from Stata's working directory:" + q)
    fput(fh, "        di as result " + bt + q + "    " + bt + "c(pwd)" + ap + q + ap)
    fput(fh, "        di as txt   " + q + "  Set the working directory to this file's folder (File > Change" + q)
    fput(fh, "        di as txt   " + q + "  Working Directory) and run it again. A folder path over ~200" + q)
    fput(fh, "        di as txt   " + q + "  characters can also hide it: Windows cannot open longer paths." + q)
    fput(fh, "        exit 601")
    fput(fh, "    }")
    fput(fh, "    mdf_bootstrap " + bt + q + dol + "mdf_want_at" + q + ap)
    fput(fh, "}")
}

//  ── Carrying an analyst's cleaning into a newer template ──────────────────
//  A Processing DO is Tier 2: when the template moves, Master writes the new
//  one beside it as .new and touches nothing. Since 11.1.0 the .new also
//  carries the analyst's own cleaning over, so adopting it is a rename rather
//  than a hand merge. The cleaning is whatever sits between a dataset's
//  "Field Cleaning" bookmark and the generated save, minus the banners.
string colvector _mdf_lines(string scalar path)
{
    string colvector L
    real scalar i
    L = cat(path)
    for (i = 1; i <= rows(L); i++) {
        if (strlen(L[i]) > 0 & substr(L[i], -1, 1) == char(13)) L[i] = substr(L[i], 1, strlen(L[i]) - 1)
    }
    return(L)
}

//  First line after a banner that opens right below line b.
real scalar _after_banner(string colvector L, real scalar b)
{
    real scalar m, n
    string scalar pre
    n = rows(L)
    if (b + 1 > n) return(b + 1)
    pre = substr(L[b + 1], 1, 2)
    if (pre != "*=" & pre != "*-") return(b + 1)
    for (m = b + 2; m <= min((b + 10, n)); m++) {
        if (substr(L[m], 1, 2) == pre) return(m + 1)
    }
    return(b + 1)
}

string colvector _trim_blank(string colvector X)
{
    real scalar a, z
    if (rows(X) == 0) return(X)
    //  Mata evaluates both sides of & and && (measured), so no condition here
    //  may index X past its end.
    z = rows(X)
    for (a = 1; a <= z; a++) {
        if (strtrim(X[a]) != "") break
    }
    if (a > z) return(J(0, 1, ""))
    for (; z > a; z--) {
        if (strtrim(X[z]) != "") break
    }
    return(X[|a \ z|])
}

//  part 1 = field cleaning, part 2 = post-field cleaning, of dataset block k.
//  Returns a 1-row "__MDF_NONE__" when the block cannot be found.
string colvector carry_region(string colvector L, real scalar k, real scalar part)
{
    real scalar i, n, seen, fi, pi, si, a
    n = rows(L)
    seen = 0
    fi = 0
    for (i = 1; i <= n; i++) {
        if (strpos(L[i], "**# Bookmark: Field Cleaning - ") == 1) {
            seen++
            if (seen == k) {
                fi = i
                break
            }
        }
    }
    if (fi == 0) return("__MDF_NONE__")
    pi = 0
    for (i = fi + 1; i <= n; i++) {
        if (strpos(L[i], "**# Bookmark: Field Cleaning - ") == 1) break
        if (strpos(L[i], "**# Bookmark: Post-Field Cleaning - ") == 1) {
            pi = i
            break
        }
    }
    if (pi == 0) return("__MDF_NONE__")
    si = 0
    for (i = pi + 1; i <= n; i++) {
        if (strpos(L[i], "**# Bookmark: Field Cleaning - ") == 1) break
        if (strpos(L[i], "── Save Data ──") > 0) {
            si = i
            break
        }
        if (strpos(L[i], "* 4. SAVE") == 1) {
            si = i - 1
            break
        }
    }
    if (si == 0) return("__MDF_NONE__")
    if (part == 1) {
        a = _after_banner(L, fi)
        if (a > pi - 1) return(J(0, 1, ""))
        return(_trim_blank(L[|a \ pi - 1|]))
    }
    a = _after_banner(L, pi)
    if (a > si - 1) return(J(0, 1, ""))
    return(_trim_blank(L[|a \ si - 1|]))
}

void _put_lines(real scalar fh, string colvector X)
{
    real scalar i
    if (rows(X) == 0) {
        fput(fh, "")
        fput(fh, "")
        fput(fh, "")
        return
    }
    fput(fh, "")
    for (i = 1; i <= rows(X); i++) fput(fh, X[i])
    fput(fh, "")
    fput(fh, "")
}

//  The cleaning slots of one dataset: the analyst's two sections, empty in a
//  new file, carried over (A, B) when a newer template replaces an older one.
void write_cleaning_slots(real scalar fh, string scalar ds_label,
                          string colvector A, string colvector B)
{
    mdf_edit_section(fh, "Field Cleaning - " + ds_label, "2. FIELD CLEANING  —  " + ds_label,
        ("Runs every day, before the HFC. ID corrections, enumerator typos," \
         "duplicate resolution: fixes that must reach the same-day checks."))
    _put_lines(fh, A)
    mdf_edit_section(fh, "Post-Field Cleaning - " + ds_label, "3. POST-FIELD CLEANING  —  " + ds_label,
        ("Final recodes, labels, derived variables, harmonisation, and any" \
         "final validation of the cleaned dataset."))
    _put_lines(fh, B)
}

void write_processing_do(string scalar procdir, string scalar procfile,
                         string scalar tver,
                         string scalar pname, string scalar q, string scalar bt,
                         string scalar ap, string scalar dol, string scalar nds)
{
    string scalar p, dsname, full_lbl, ks, old
    real scalar fh, _k, nb, carried
    string colvector L, A, B, names

    old = procdir + "/" + procfile
    p = tier2_target(old, tver, procfile)
    if (p == "") return

    //  ── Carry the analyst's cleaning into a .new ────────────────────────────
    nb = strtoreal(nds)
    if (nb >= . | nb < 1) nb = 1
    carried = 0
    L = J(0, 1, "")
    if (p != old & fileexists(old)) {
        L = _mdf_lines(old)
        carried = 1
        for (_k = 1; _k <= nb; _k++) {
            if (carry_region(L, _k, 1) == "__MDF_NONE__") carried = 0
            if (carry_region(L, _k, 2) == "__MDF_NONE__") carried = 0
        }
    }

    names = J(nb, 1, "")
    for (_k = 1; _k <= nb; _k++) {
        dsname = st_global("ds" + strofreal(_k) + "_name")
        if (dsname == "") dsname = st_global("auto_dsname_" + strofreal(_k))
        if (dsname == "") dsname = (nb == 1 ? pname : "Dataset " + strofreal(_k))
        names[_k] = dsname
    }

    fh = fopen(p, "w")
    mdf_file_header(fh, "Data cleaning and processing",
        ("Loads the raw survey data, applies the CAPI labels" \
         "and the returned translations, runs this project's" \
         "cleaning and saves the cleaned dataset." \
         "Dataset(s): " + invtokens(names', "; ")),
        _howto_run())
    fput(fh, tier2_marker(tver))
    write_init_block(fh, q, bt, ap, dol, pname, "processing", 1)
    fput(fh, "di as result " + q + "--- Processing ---" + q)
    fput(fh, "di as result " + q + "--- Cleaning ---" + q)

    for (_k = 1; _k <= nb; _k++) {
        ks = strofreal(_k)
        dsname = names[_k]
        full_lbl = (nb == 1 ? dsname : "DS" + ks + ": " + dsname)
        A = J(0, 1, "")
        B = J(0, 1, "")
        if (carried) {
            A = carry_region(L, _k, 1)
            B = carry_region(L, _k, 2)
        }

        mdf_gen_section(fh, "1. LOAD, LABEL AND TRANSLATE  —  " + full_lbl,
            ("Loads the raw data and applies the CAPI labels and your manual labels" \
             "(01_Do Files/01_Labeling.do), then the returned translations and your" \
             "manual overrides (01_Do Files/02_Translation.do)."))
        if (nb > 1) {
            fput(fh, "*  Runs unless this is a Deliverables package that does not carry DS" + ks + ".")
            fput(fh, "if " + q + dol + "mdf_package" + q + " != " + q + "1" + q + " | " + q + dol + "{mdf_ds_here_" + ks + "}" + q + " == " + q + "1" + q + " {")
        }
        fput(fh, "local _ds_name " + q + dsname + q)
        fput(fh, "if " + q + dol + "mdf_package" + q + " == " + q + "1" + q + " local _ds_name " + q + dol + "{auto_dsname_" + ks + "}" + q)
        fput(fh, "local _cln_file " + q + dol + "hfc_run_dir/" + bt + "_ds_name" + ap + "_CLEANED_" + dol + "hfc_folder_date.dta" + q)
        fput(fh, "global dta_cleaned_" + ks + " " + q + bt + "_cln_file" + ap + q)
        //  Sort ties are broken by a random stream that every earlier sort in
        //  the session advances; fixed per dataset, the cleaning is the same in
        //  the project, in the package and on any machine (ADR-059).
        fput(fh, "set sortseed 11235813")
        fput(fh, "do " + q + dol + "dofiles_dir/01_Labeling.do" + q + " " + ks)
        fput(fh, "if " + q + dol + "hfc_label_ok" + q + " == " + q + "1" + q + " {    // clean only when data were loaded")
        fput(fh, "if " + q + dol + "inputcorrection" + q + " == " + q + "1" + q + " do " + q + dol + "dofiles_dir/02_Translation.do" + q + " apply " + ks)
        fput(fh, "mdf_core_vars")

        write_cleaning_slots(fh, dsname, A, B)

        mdf_gen_section(fh, "4. SAVE  —  " + full_lbl, J(0, 1, ""))
        fput(fh, "save " + q + bt + "_cln_file" + ap + q + ", replace")
        fput(fh, "}")
        fput(fh, "else di as error " + q + "  DS" + ks + ": no data available — cleaning skipped." + q)
        if (nb > 1) {
            fput(fh, "}")
            fput(fh, "else di as txt " + q + "  DS" + ks + " (" + dsname + "): not in this package — skipped." + q)
        }
    }

    mdf_gen_section(fh, "5. FINALISE",
        ("Merges the cleaned datasets (if configured), exports untranslated" \
         "open-ended text for the translators (if switched on), and publishes" \
         "the cleaned dataset(s)."))
    fput(fh, "mdf_finalise merge")
    fput(fh, "di as result " + q + "Cleaning complete." + q)
    fput(fh, "if " + q + dol + "exportopenended" + q + " == " + q + "1" + q + " do " + q + dol + "dofiles_dir/02_Translation.do" + q + " export")
    fput(fh, "else di as txt " + q + "Open-ended export skipped (exportopenended = 0)." + q)
    fput(fh, "mdf_finalise publish")
    fput(fh, "di as result " + q + "Processing complete." + q)
    fclose(fh)

    if (p != old) {
        if (carried) {
            printf("  {txt}      Your cleaning code has been carried into the .new file, in the\n")
            printf("  {txt}      sections marked SAFE TO EDIT. Review it, then replace your file\n")
            printf("  {txt}      with it.\n")
        }
        else {
            printf("  {err}      Your cleaning code could not be located in the old file, so the\n")
            printf("  {err}      .new file has empty cleaning sections: copy your code across.\n")
        }
    }
}

//  _mdf/mdf_labeling.do and _mdf/mdf_translation.do — Tier 1. Nothing in them
//  names this project, so the copy a Deliverables package carries is the same
//  file the project ran (ADR-061).
void write_engine_file(string scalar path, string scalar which, string scalar q,
                       string scalar bt, string scalar ap, string scalar dol)
{
    real scalar fh
    if (fileexists(path)) unlink(path)
    fh = fopen(path, "w")
    fput(fh, _rule("="))
    fput(fh, "*  MDF RUNTIME  —  " + which + " engine   (Master DO File " + st_global("hfc_version") + ")")
    fput(fh, _rule("="))
    fput(fh, "*  Framework code. Master rewrites this file on every run and the")
    fput(fh, "*  Deliverables package carries it unchanged, so the project and the")
    fput(fh, "*  package run the same code. Do not edit it: changes are overwritten.")
    fput(fh, "*  Your own labels belong in 01_Labeling.do and your own translation")
    fput(fh, "*  overrides in 02_Translation.do, in the sections marked SAFE TO EDIT.")
    fput(fh, _rule("="))
    fput(fh, "")
    fput(fh, "version 16")
    if (which == "labeling") write_labeling_module(fh, q, bt, ap, dol, "")
    else                     write_translation_body(fh, q, bt, ap, dol)
    fclose(fh)
}

//  One empty SAFE TO EDIT slot per dataset, or a plain one for a single dataset.
void _per_ds_slots(real scalar fh, string scalar test, string scalar nds)
{
    real scalar _k, nb
    string scalar ks, nm
    nb = strtoreal(nds)
    if (nb >= . | nb <= 1) {
        fput(fh, "")
        fput(fh, "")
        fput(fh, "")
        return
    }
    for (_k = 1; _k <= nb; _k++) {
        ks = strofreal(_k)
        nm = st_global("auto_dsname_" + ks)
        fput(fh, "")
        fput(fh, "if " + test + " == " + char(34) + ks + char(34) + " {    // DS" + ks + (nm != "" ? ": " + nm : ""))
        fput(fh, "")
        fput(fh, "}")
    }
    fput(fh, "")
}

void write_labeling_do(string scalar dodir, string scalar tver, string scalar pname,
                       string scalar q, string scalar bt, string scalar ap,
                       string scalar dol, string scalar nds)
{
    string scalar p
    real scalar fh
    p = tier2_target(dodir + "/01_Labeling.do", tver, "01_Labeling.do")
    if (p == "") return
    fh = fopen(p, "w")
    mdf_file_header(fh, "Variable and value labels",
        ("Applies the labels of the SurveyCTO (CAPI) form to" \
         "one dataset, then the labels you add by hand below." \
         "The Processing DO calls it for each dataset; run on" \
         "its own it labels DS1."),
        _howto_run())
    fput(fh, tier2_marker(tver))
    fput(fh, "")
    fput(fh, "args _mdf_ds")
    fput(fh, "if " + q + bt + "_mdf_ds" + ap + q + " == " + q + q + " local _mdf_ds 1")
    write_init_block(fh, q, bt, ap, dol, pname, "labeling", 0)
    mdf_gen_section(fh, "1. CAPI LABELS",
        ("Loads the dataset and applies the form's value and variable labels" \
         "with odksplit (framework code: 01_Do Files/_mdf/mdf_labeling.do)."))
    fput(fh, "do " + q + dol + "mdf_rt_dir/mdf_labeling.do" + q + " " + bt + "_mdf_ds" + ap)
    fput(fh, "if " + q + dol + "hfc_label_ok" + q + " != " + q + "1" + q + " exit    // no data loaded: nothing to label")
    mdf_edit_section(fh, "Manual Labeling", "2. MANUAL LABELING",
        ("Labels the CAPI form cannot supply: variables made in the field," \
         "other-specify and repeat-group variables, clearer wording. Applied" \
         "after the CAPI labels, every time the data are processed, in the" \
         "project and in the Deliverables package. For example:" \
         "    label variable myvar " + q + "My variable label" + q \
         "    label define yesno 1 " + q + "Yes" + q + " 0 " + q + "No" + q + ", replace"))
    _per_ds_slots(fh, q + bt + "_mdf_ds" + ap + q, nds)
    fclose(fh)
}

void write_translation_do(string scalar dodir, string scalar tver, string scalar pname,
                          string scalar q, string scalar bt, string scalar ap,
                          string scalar dol, string scalar nds)
{
    string scalar p
    real scalar fh
    p = tier2_target(dodir + "/02_Translation.do", tver, "02_Translation.do")
    if (p == "") return
    fh = fopen(p, "w")
    mdf_file_header(fh, "Open-ended translation",
        ("apply  : applies the translators' returned files to" \
         "         the dataset in memory, then your overrides" \
         "         below. The Processing DO calls this before" \
         "         cleaning." \
         "export : exports untranslated open-ended text for" \
         "         translation." \
         "Run on its own it does both, for every dataset."),
        _howto_run())
    fput(fh, tier2_marker(tver))
    fput(fh, "")
    fput(fh, "args _mdf_mode _mdf_ds")
    write_init_block(fh, q, bt, ap, dol, pname, "translation", 0)
    mdf_gen_section(fh, "1. RETURNED TRANSLATIONS",
        ("Every returned .xlsx in 02_Translation/02_Translated/ is applied, in" \
         "name order (framework code: 01_Do Files/_mdf/mdf_translation.do)."))
    fput(fh, "do " + q + dol + "mdf_rt_dir/mdf_translation.do" + q + " " + bt + "_mdf_mode" + ap + " " + bt + "_mdf_ds" + ap)
    fput(fh, "if " + q + bt + "_mdf_mode" + ap + q + " != " + q + "apply" + q + " exit    // overrides apply while the data are processed")
    mdf_edit_section(fh, "Manual Translation Overrides", "2. MANUAL TRANSLATION OVERRIDES",
        ("Corrections the returned files do not carry. Applied after them, to" \
         "the dataset being processed, in the project and in the Deliverables" \
         "package. For example:" \
         "    replace q12_other = " + q + "Tuition fees" + q + " if key == " + q + "uuid:..." + q))
    _per_ds_slots(fh, q + bt + "_mdf_ds" + ap + q, nds)
    fclose(fh)
}

void write_audio_do(string scalar dodir, string scalar tver, string scalar pname,
                    string scalar q, string scalar bt, string scalar ap,
                    string scalar dol, string scalar nds)
{
    string scalar p
    real scalar fh
    p = tier2_target(dodir + "/03_Audio.do", tver, "03_Audio.do")
    if (p == "") return
    fh = fopen(p, "w")
    mdf_file_header(fh, "Audio audit sample",
        ("Draws the interviews whose recordings are to be" \
         "audited, per enumerator, using the audio_* settings" \
         "of Master Section 0, and writes the list to today's" \
         "HFC run folder."),
        _howto_run())
    fput(fh, tier2_marker(tver))
    write_init_block(fh, q, bt, ap, dol, pname, "audio", 1)
    mdf_gen_section(fh, "1. AUDIO SAMPLE", J(0, 1, ""))
    write_audio_body(fh, q, bt, ap, dol, nds)
    fclose(fh)
}

//  _mdf/mdf_package.do — what a Deliverables package is and how it was built.
//  Written by mdf_deliverables for the package that carries dataset k. Every
//  value is the one this Master run used, assigned unconditionally: the
//  package never takes a setting from the Stata session it runs in (ADR-061).
string scalar _cg(string scalar name, string scalar val)
{
    return("global " + name + " " * max((1, 22 - strlen(name))) + char(96) + char(34) + val + char(34) + char(39))
}

void _pk_settings_id(real scalar fh, real scalar k, real scalar nb,
                     string scalar form, string scalar sig, string scalar obs,
                     string scalar shortnm)
{
    real scalar i
    string scalar is
    fput(fh, _rule("="))
    fput(fh, "*  DELIVERABLES PACKAGE  —  identity and settings")
    fput(fh, _rule("="))
    fput(fh, "*  Written by Master DO File " + st_global("hfc_version") + " on " + c("current_date") + ", when this package was")
    fput(fh, "*  built. Its DO files load it every time they run, so a rebuild never")
    fput(fh, "*  depends on anything left in the Stata session. Do not edit, except as")
    fput(fh, "*  the note on the raw-data signature below says.")
    fput(fh, _rule("="))
    fput(fh, "")
    fput(fh, "*  ── Identity ────────────────────────────────────────────────────────────")
    fput(fh, _cg("mdf_pk_project",  st_global("project_name")))
    fput(fh, _cg("mdf_pk_version",  st_global("hfc_version")))
    fput(fh, _cg("mdf_pk_built",    st_global("today")))
    fput(fh, _cg("mdf_pk_procfile", st_global("processing_file")))
    fput(fh, _cg("mdf_pk_form",     form))
    fput(fh, _cg("mdf_pk_short",    shortnm))
    fput(fh, "global mdf_pk_maxpath        259")
    fput(fh, "global mdf_pk_nds            " + strofreal(nb))
    for (i = 1; i <= nb; i++) {
        is = strofreal(i)
        fput(fh, _cg("mdf_pk_name_" + is, st_global("auto_dsname_" + is)))
        fput(fh, _cg("mdf_pk_here_" + is, (i == k ? "1" : "0")))
    }
    fput(fh, "")
    fput(fh, "*  The raw data this package was built from (-datasignature-). A rebuild")
    fput(fh, "*  stops if the raw dataset no longer matches. If you replace it on")
    fput(fh, "*  purpose, delete this line: the result will then not match the cleaned")
    fput(fh, "*  dataset the package was shipped with.")
    fput(fh, _cg("mdf_pk_sig_" + strofreal(k), sig))
    fput(fh, _cg("mdf_pk_obs_" + strofreal(k), obs))
}

void _pk_settings_cfg(real scalar fh, real scalar nb)
{
    real scalar i
    string colvector G
    string scalar is
    fput(fh, "")
    fput(fh, "*  ── Settings, as the project ran when the package was built ───────────────")
    G = ("project_name" \ "sample_size" \ "meta_front" \ "meta_ids" \ "tail" \
         "timer_start" \ "timer_end" \ "hfc_openended_vars" \ "oe_export_all" \
         "run_labeling" \ "inputcorrection" \ "capi_language" \ "capi_verbose" \
         "code_dk" \ "code_na" \ "code_other" \ "verbose" \
         "merge_datasets" \ "merge_type" \ "merge_key")
    for (i = 1; i <= rows(G); i++) fput(fh, _cg(G[i], st_global(G[i])))
    for (i = 1; i <= max((nb, 3)); i++) {
        is = strofreal(i)
        fput(fh, _cg("meta_front_" + is, st_global("meta_front_" + is)))
        fput(fh, _cg("meta_ids_" + is,   st_global("meta_ids_" + is)))
        fput(fh, _cg("tail_" + is,       st_global("tail_" + is)))
        fput(fh, _cg("hfc_openended_vars_" + is, st_global("hfc_openended_vars_" + is)))
        if (st_global("ds" + is + "_name") != "") fput(fh, _cg("ds" + is + "_name", st_global("ds" + is + "_name")))
    }
    fput(fh, "*  A rebuild never sends text to translators or merges across datasets.")
    fput(fh, _cg("exportopenended", "0"))
    fput(fh, _cg("merge_required", "0"))
}

void write_package_settings()
{
    real scalar fh, k, nb
    string scalar path
    path = st_local("_setf")
    k    = strtoreal(st_local("_k"))
    nb   = strtoreal(st_local("_nds"))
    if (fileexists(path)) unlink(path)
    fh = fopen(path, "w")
    _pk_settings_id(fh, k, nb, st_local("_cfleaf"), st_local("_rsig"), st_local("_robs"), st_local("_short"))
    _pk_settings_cfg(fh, nb)
    fclose(fh)
}

//  The translation engine: mode apply | export | full (ADR-034). Moved here
//  verbatim from the 11.0.0 module; it now runs from _mdf/mdf_translation.do.
void write_translation_body(real scalar fh, string scalar q, string scalar bt,
                            string scalar ap, string scalar dol)
{
    fput(fh, "*  ── MODE ───────────────────────────────────────────────────────────────────")
    fput(fh, "if " + bt + q + bt + "1" + ap + q + ap + " != " + q + q + " global hfc_trans_mode " + bt + q + bt + "1" + ap + q + ap)
    fput(fh, "if " + bt + q + bt + "2" + ap + q + ap + " != " + q + q + " global hfc_trans_ds " + bt + "2" + ap)
    fput(fh, "if " + q + dol + "hfc_trans_mode" + q + " == " + q + q + " global hfc_trans_mode " + q + "full" + q)
    fput(fh, "if " + q + dol + "hfc_trans_ds" + q + " == " + q + q + " global hfc_trans_ds 0")
    fput(fh, "")
    fput(fh, "if " + q + dol + "hfc_trans_mode" + q + " == " + q + "apply" + q + " {")
    fput(fh, "    *  ── APPLY, IN MEMORY ───────────────────────────────────────────────────")
    fput(fh, "    local _ds " + dol + "hfc_trans_ds")
    fput(fh, "    if " + bt + "_ds" + ap + " < 1 local _ds 1")
    fput(fh, "    local _base " + q + dol + "{auto_dsname_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "    local _tfold " + q + bt + "_base" + ap + q)
    fput(fh, "    if " + q + bt + "_base" + ap + q + " == " + q + q + " {")
    fput(fh, "        di as error " + q + "  DS" + bt + "_ds" + ap + ": dataset name unresolved — cannot locate its translation folder." + q)
    fput(fh, "    }")
    fput(fh, "    else {")
    fput(fh, "        di as result _n " + q + "--- Applying translations: " + bt + "_base" + ap + " ---" + q)
    write_mod_oe_apply(fh, q, bt, ap, dol, dol + "{auto_dsname_" + bt + "_ds" + ap + "}", "        ")
    fput(fh, "    }")
    fput(fh, "}")
    fput(fh, "else {")
    fput(fh, "")
    fput(fh, "forvalues _ds = 1/" + dol + "actual_n_dta {")
    fput(fh, "    local _base " + q + dol + "{auto_dsname_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "    local _target " + q + q)
    fput(fh, "")
    fput(fh, "    *  Per-dataset translation folder. The dataset name verbatim —")
    fput(fh, "    *  must match what Master creates in Section 11d, or the module writes")
    fput(fh, "    *  somewhere the analyst is not looking.")
    fput(fh, "    local _tfold " + q + bt + "_base" + ap + q)
    fput(fh, "")
    fput(fh, "    cap confirm file " + q + dol + "{target_dta_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "    if !_rc local _target " + q + dol + "{target_dta_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "    if " + q + bt + "_target" + ap + q + " == " + q + q + " {")
    fput(fh, "        cap confirm file " + q + dol + "{dta_cleaned_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "        if !_rc local _target " + q + dol + "{dta_cleaned_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "    }")
    fput(fh, "    if " + q + bt + "_target" + ap + q + " == " + q + q + " {")
    fput(fh, "        cap confirm file " + q + dol + "clean_dir/" + bt + "_base" + ap + "_CLEANED.dta" + q)
    fput(fh, "        if !_rc local _target " + q + dol + "clean_dir/" + bt + "_base" + ap + "_CLEANED.dta" + q)
    fput(fh, "    }")
    fput(fh, "    if " + q + bt + "_target" + ap + q + " == " + q + q + " {")
    fput(fh, "        cap confirm file " + q + dol + "{dta_labeled_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "        if !_rc local _target " + q + dol + "{dta_labeled_" + bt + "_ds" + ap + "}" + q)
    fput(fh, "    }")
    fput(fh, "    if " + q + bt + "_target" + ap + q + " == " + q + q + " {")
    fput(fh, "        cap confirm file " + q + dol + "raw_data_dir/" + bt + "_base" + ap + ".dta" + q)
    fput(fh, "        if !_rc local _target " + q + dol + "raw_data_dir/" + bt + "_base" + ap + ".dta" + q)
    fput(fh, "    }")
    fput(fh, "")
    fput(fh, "    if " + q + bt + "_target" + ap + q + " == " + q + q + " {")
    fput(fh, "        di as error " + q + "  DS" + bt + "_ds" + ap + ": no dataset found (cleaned, labeled or raw) — skipping translation." + q)
    fput(fh, "        continue")
    fput(fh, "    }")
    fput(fh, "    di as result _n " + q + "--- Translation: DS" + bt + "_ds" + ap + " ---" + q)
    fput(fh, "    use " + q + bt + "_target" + ap + q + ", clear")
    fput(fh, "")
    fput(fh, "    if " + q + dol + "hfc_trans_mode" + q + " != " + q + "export" + q + " {")
    write_mod_oe_apply(fh, q, bt, ap, dol, dol + "{auto_dsname_" + bt + "_ds" + ap + "}", "        ")
    fput(fh, "    }")
    fput(fh, "")
    write_mod_oe_export(fh, q, bt, ap, dol, dol + "{auto_dsname_" + bt + "_ds" + ap + "}", "    ", bt + "_ds" + ap)
    fput(fh, "")
    fput(fh, "    cap save " + q + bt + "_target" + ap + q + ", replace")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "}")
    fput(fh, "")
    fput(fh, "global hfc_trans_mode " + q + q)
    fput(fh, "global hfc_trans_ds 0")
    fput(fh, "di as result " + q + "Translation module complete." + q)
}

//  The audio sample, verbatim from the 11.0.0 module.
void write_audio_body(real scalar fh, string scalar q, string scalar bt,
                      string scalar ap, string scalar dol, string scalar nds)
{
    real scalar _k

    fput(fh, "di as result " + q + "--- Audio Audit ---" + q)
    fput(fh, "global date " + q + dol + "today" + q)
    if (nds == "1") {
        fput(fh, "use " + q + dol + "target_dta" + q + ", clear")
        fput(fh, "cap lab drop enum")
        fput(fh, "destring duration, replace force")
        fput(fh, "gen dur_min = duration / 60")
        fput(fh, "cap confirm variable int_date")
        fput(fh, "if _rc {")
        fput(fh, "    cap confirm variable fielddate")
        fput(fh, "    if !_rc gen int_date = fielddate")
        fput(fh, "    else cap gen int_date = dofc(starttime)")
        fput(fh, "}")
        fput(fh, "format int_date %td")
        fput(fh, "*  ── Audio Date Filter ──────────────────────────────────────────────────────")
        fput(fh, "if " + q + dol + "audio_drop_before" + q + " != " + q + q + " {")
        fput(fh, "    cap drop if int_date < daily(" + q + dol + "audio_drop_before" + q + ", " + q + "YMD" + q + ")")
        fput(fh, "}")
        fput(fh, "else {")
        fput(fh, "    cap drop if int_date < (daily(" + q + dol + "today" + q + ", " + q + "YMD" + q + ") - 1)  // Default: drop before yesterday")
        fput(fh, "}")
        fput(fh, "")
        fput(fh, "cap keep if consent == 1")
        fput(fh, "keep enum int_date dur_min key")
        fput(fh, "")
        fput(fh, "*  ── Enum Filter (keep only specified enumerators if configured) ────────────")
        fput(fh, "if " + q + dol + "audio_keep_enums" + q + " != " + q + q + " {")
        fput(fh, "    tempvar _eflag")
        fput(fh, "    gen " + bt + "_eflag" + ap + " = 0")
        fput(fh, "    cap confirm numeric variable enum")
        fput(fh, "    if !_rc {")
        fput(fh, "        foreach _eid in " + dol + "audio_keep_enums {")
        fput(fh, "            cap replace " + bt + "_eflag" + ap + " = 1 if enum == " + bt + "_eid" + ap)
        fput(fh, "        }")
        fput(fh, "    }")
        fput(fh, "    else {")
        fput(fh, "        foreach _eid in " + dol + "audio_keep_enums {")
        fput(fh, "            cap replace " + bt + "_eflag" + ap + " = 1 if enum == " + q + bt + "_eid" + ap + q)
        fput(fh, "        }")
        fput(fh, "    }")
        fput(fh, "    keep if " + bt + "_eflag" + ap + " == 1")
        fput(fh, "    drop " + bt + "_eflag" + ap)
        fput(fh, "}")
        fput(fh, "")
        fput(fh, "qui count")
        fput(fh, "if r(N) == 0 {")
        fput(fh, "    di as error " + q + "WARNING: No observations after filters. Audio list empty — skipping export." + q)
        fput(fh, "    exit")
        fput(fh, "}")
        fput(fh, "set seed " + dol + "audio_seed")
        fput(fh, "bys enum: sample " + dol + "audio_sample_count, count")
        fput(fh, "preserve")
        fput(fh, "keep key")
        fput(fh, "save " + q + dol + "hfc_keys_audio_dir/" + dol + "{project_name}_Audio_KEY_" + dol + "date" + q + ", replace")
        fput(fh, "restore")
        fput(fh, "gen verifier = .")
        fput(fh, "gen verified_date = .")
        fput(fh, "order verifier verified_date enum int_date key dur_min")
        fput(fh, "export excel using " + q + dol + "hfc_run_dir/Audio_List_" + dol + "{project_name}_" + dol + "date.xlsx" + q + ", sheet(" + q + "Audio Audit" + q + ") sheetreplace firstrow(variables) cell(A1)")

    }
    else {
        for (_k = 1; _k <= strtoreal(nds); _k++) {
            fput(fh, "clear")
            fput(fh, "use " + q + dol + "{target_dta_" + strofreal(_k) + "}" + q)
            fput(fh, "cap lab drop enum")
            fput(fh, "cap tostring enum, replace force")
            fput(fh, "cap confirm variable starttime")
            fput(fh, "if _rc gen double starttime = .")
            fput(fh, "cap confirm variable duration")
            fput(fh, "if _rc gen duration = .")
            fput(fh, "cap keep if consent == 1")
            fput(fh, "keep enum starttime duration key")
            fput(fh, "tempfile tf_" + strofreal(_k))
            fput(fh, "save " + q + bt + "tf_" + strofreal(_k) + ap + q + ", replace")
        }
        fput(fh, "use " + q + bt + "tf_1" + ap + q + ", clear")
        for (_k = 2; _k <= strtoreal(nds); _k++) {
            fput(fh, "append using " + q + bt + "tf_" + strofreal(_k) + ap + q)
        }
        fput(fh, "destring duration, replace force")
        fput(fh, "gen dur_min = duration / 60")
        fput(fh, "cap gen int_date = dofc(starttime)")
        fput(fh, "cap confirm variable fielddate")
        fput(fh, "if !_rc replace int_date = fielddate")
        fput(fh, "format int_date %td")
        fput(fh, "*  ── Audio Date Filter ──────────────────────────────────────────────────────")
        fput(fh, "if " + q + dol + "audio_drop_before" + q + " != " + q + q + " {")
        fput(fh, "    cap drop if int_date < daily(" + q + dol + "audio_drop_before" + q + ", " + q + "YMD" + q + ")")
        fput(fh, "}")
        fput(fh, "else {")
        fput(fh, "    cap drop if int_date < (daily(" + q + dol + "today" + q + ", " + q + "YMD" + q + ") - 1)  // Default: drop before yesterday")
        fput(fh, "}")
        fput(fh, "")
        fput(fh, "keep enum int_date dur_min key")
        fput(fh, "")
        fput(fh, "*  ── Enum Filter (keep only specified enumerators if configured) ────────────")
        fput(fh, "if " + q + dol + "audio_keep_enums" + q + " != " + q + q + " {")
        fput(fh, "    tempvar _eflag")
        fput(fh, "    gen " + bt + "_eflag" + ap + " = 0")
        fput(fh, "    cap confirm numeric variable enum")
        fput(fh, "    if !_rc {")
        fput(fh, "        foreach _eid in " + dol + "audio_keep_enums {")
        fput(fh, "            cap replace " + bt + "_eflag" + ap + " = 1 if enum == " + bt + "_eid" + ap)
        fput(fh, "        }")
        fput(fh, "    }")
        fput(fh, "    else {")
        fput(fh, "        foreach _eid in " + dol + "audio_keep_enums {")
        fput(fh, "            cap replace " + bt + "_eflag" + ap + " = 1 if enum == " + q + bt + "_eid" + ap + q)
        fput(fh, "        }")
        fput(fh, "    }")
        fput(fh, "    keep if " + bt + "_eflag" + ap + " == 1")
        fput(fh, "    drop " + bt + "_eflag" + ap)
        fput(fh, "}")
        fput(fh, "")
        fput(fh, "qui count")
        fput(fh, "if r(N) == 0 {")
        fput(fh, "    di as error " + q + "WARNING: No observations after filters. Audio list empty — skipping export." + q)
        fput(fh, "    exit")
        fput(fh, "}")
        fput(fh, "set seed " + dol + "audio_seed")
        fput(fh, "bys enum: sample " + dol + "audio_sample_count, count")
        fput(fh, "preserve")
        fput(fh, "keep key")
        fput(fh, "save " + q + dol + "hfc_keys_audio_dir/" + dol + "{project_name}_Audio_KEY_" + dol + "date" + q + ", replace")
        fput(fh, "restore")
        fput(fh, "gen verifier = .")
        fput(fh, "gen verified_date = .")
        fput(fh, "order verifier verified_date enum int_date key dur_min")
        fput(fh, "export excel using " + q + dol + "hfc_run_dir/Audio_List_" + dol + "{project_name}_" + dol + "date.xlsx" + q + ", sheet(" + q + "Combined Audio Audit" + q + ") sheetreplace firstrow(variables) cell(A1)")
    }
}

//  entry point: was the driver at the tail of Section 14's mata block
void mdf_modules_main()
{
    string scalar q, bt, ap, dol, bs
    string scalar pname, ssize, meta, tail_v, tstart, tend, nds
    string scalar dodir, hfcdir, tver, procdir, procfile
    string scalar p, rtdir
    real   scalar fh

    q   = char(34)
    bt  = char(96)
    ap  = char(39)
    dol = "$"
    bs  = char(92)

    pname  = st_local("_pname")
    ssize  = st_local("_ssize")
    meta   = st_local("_meta")
    tail_v = st_local("_tail")
    tstart = st_local("_tstart")
    tend   = st_local("_tend")
    nds    = st_local("_nds")
    dodir  = st_local("_dodir")
    hfcdir = st_local("_hfcdir")
    tver   = st_local("_tver")
    procdir = st_local("_procdir")
    procfile = st_local("_procfile")

    p = tier2_target(hfcdir + "/02_" + pname + "_HFC.do", tver, "02_" + pname + "_HFC.do")
    if (p != "") {
        fh = fopen(p, "w")
        mdf_file_header(fh, "High-frequency checks",
            ("Runs the data-quality checks on the latest cleaned" \
             "data and writes one Excel report per run: a README" \
             "sheet and a sheet per check that found something." \
             "Your own checks go in the CUSTOM CHECKS sections."),
            ("Master runs it (run_hfc = 1). You can also run it" \
             "yourself (Ctrl+A, Ctrl+D) from inside the project," \
             "or carry it off beside its dataset(s) to check" \
             "those (STANDALONE MODE in the project README)."))
        fput(fh, tier2_marker(tver))
        mdf_gen_section(fh, "0. INITIALISE",
            ("Finds the project (or the dataset(s) beside this file) and loads its" \
             "settings."))
        fput(fh, "clear all")
        fput(fh, "set more off")
        fput(fh, "version 16")
        fput(fh, "")
        module_header(fh, q, bt, ap, dol, pname, nds, "core")
        mdf_gen_section(fh, "1. RUN SETTINGS", J(0, 1, ""))
        fput(fh, "*  ── System dates ───────────────────────────────────────────────────────────")
        fput(fh, "local sys_today = daily(" + q + bt + "c(current_date)" + ap + q + ", " + q + "DMY" + q + ")")
        fput(fh, "local sys_today_str   : display %tdCCYYNNDD " + bt + "sys_today" + ap)
        fput(fh, "local sys_yesterday_str : display %tdCCYYNNDD (" + bt + "sys_today" + ap + " - 1)")
        fput(fh, "global today     " + q + bt + "sys_today_str" + ap + q)
        fput(fh, "global yesterday " + q + bt + "sys_yesterday_str" + ap + q)
        fput(fh, "")
        fput(fh, "*  ── Project config ─────────────────────────────────────────────────────────")
        fput(fh, "global dta_name    " + q + pname + q)
        fput(fh, "global sample_size " + ssize)
        fput(fh, "")
        mdf_edit_section(fh, "Check Settings", "2. CHECK SETTINGS",
            ("Sample sizes, duration thresholds and gatekeeper variables. Adjust" \
             "them to the survey; the checks below read them."))
        fput(fh, "*  ── Dataset-Specific Sample Sizes ──────────────────────────────────────────")
        for (_k = 1; _k <= strtoreal(nds); _k++) {
            _dsname_ss = st_global("auto_dsname_" + strofreal(_k))
            if (_dsname_ss == "") _dsname_ss = "Dataset " + strofreal(_k)
            fput(fh, "global sample_size_" + strofreal(_k) + " " + q + q + "  // " + _dsname_ss)
        }
        if (strtoreal(nds) > 1) fput(fh, "global sample_size_merged " + q + q + "  // Merged Dataset (Conditional)")
        fput(fh, "")
        fput(fh, "*  ── Core Quality Check Thresholds ──────────────────────────────────────────")
        fput(fh, "global dur_low  30  // UPDATE on need basis: flag interviews shorter than N minutes")
        fput(fh, "global dur_high 120  // UPDATE on need basis: flag interviews longer than N minutes")
        fput(fh, "")
        fput(fh, "*  ── Sentinel / Response Codes ──────────────────────────────────────────────")
        fput(fh, "global code_dk = " + dol + "code_dk")
        fput(fh, "global code_na = " + dol + "code_na")
        fput(fh, "global code_other = " + dol + "code_other")
        fput(fh, "")
        fput(fh, "*  ── Gatekeeper Skip Toggles ────────────────────────────────────────────────")
        for (_k = 1; _k <= strtoreal(nds); _k++) {
            _dsname_gate = st_global("auto_dsname_" + strofreal(_k))
            if (_dsname_gate == "") _dsname_gate = "Dataset " + strofreal(_k)
            fput(fh, "global gate_vars_" + strofreal(_k) + " " + q + q + "  // " + _dsname_gate)
        }
        if (strtoreal(nds) > 1) fput(fh, "global gate_vars_merged " + q + q + "  // Merged Dataset (Conditional)")
        fput(fh, "")
        mdf_gen_section(fh, "3. THE CHECKS",
            ("The framework's checks, then a CUSTOM CHECKS section per dataset."))
        fput(fh, "*  ── HFC output workbook ────────────────────────────────────────────────────")
        fput(fh, "global excel_file   " + q + dol + "hfc_report" + q)
        fput(fh, "")
        fput(fh, "cap confirm file " + q + dol + "excel_file" + q)
        fput(fh, "if !_rc cap erase " + q + dol + "excel_file" + q)
        fput(fh, "")
        if (nds == "1") {
            fput(fh, "use " + q + dol + "target_dta" + q + ", clear")
            fput(fh, "quietly count")
            fput(fh, "di as result " + q + "HFC dataset loaded. N = " + q + " r(N)")
            fput(fh, "")
            write_boxed_marker(fh, "[START HFC]")
            fput(fh, "global pre_keys " + q + dol + "pre_keys_1" + q)
            fput(fh, "use " + q + dol + "target_dta" + q + ", clear")
            fput(fh, "")
            fput(fh, "mdf_core_vars")

            write_mod_cover_page(fh, q, bt, ap, dol, pname, pname, "Cover_Page", "1")
            write_mod_enum_success(fh, q, bt, ap, dol, pname, "Page")
            write_mod_duration_audit(fh, q, bt, ap, dol, pname, "Page", "1")
            write_mod_gatekeeper_skip(fh, q, bt, ap, dol, pname, "Page", "1")
            write_mod_response_bias(fh, q, bt, ap, dol, pname, "Page")
            write_mod_duplicates_check(fh, q, bt, ap, dol, pname, "Page", "1")
            write_custom_check_slot(fh, pname)
            write_boxed_marker(fh, "[END HFC]")
            }
    else {
            fput(fh, "forvalues _i = 1/" + dol + "actual_n_dta {")
            fput(fh, "")
            fput(fh, "    local _tgt " + q + dol + "{target_dta_" + bt + "_i" + ap + "}" + q)
            fput(fh, "    if " + q + bt + "_tgt" + ap + q + " == " + q + q + " {")
            fput(fh, "        di as txt " + q + "DS" + bt + "_i" + ap + ": target dataset not found — skipping." + q)
            fput(fh, "        continue")
            fput(fh, "    }")
            fput(fh, "")
            fput(fh, "    use " + q + bt + "_tgt" + ap + q + ", clear")
            fput(fh, "    quietly count")
            fput(fh, "    di as result " + q + "DS" + bt + "_i" + ap + " loaded. N = " + q + " r(N)")
            fput(fh, "")

            for (_k = 1; _k <= strtoreal(nds); _k++) {
                dsname = st_global("ds" + strofreal(_k) + "_name")
                if (dsname == "") dsname = st_global("auto_dsname_" + strofreal(_k))
                if (dsname == "") dsname = "Dataset " + strofreal(_k)

                full_lbl = "Dataset " + strofreal(_k) + " - " + dsname
                cond = (_k == 1 ? "if " : "else if ")

                fput(fh, "    " + cond + bt + "_i" + ap + " == " + strofreal(_k) + " {")
                fput(fh, "")
                write_boxed_marker(fh, "[START HFC " + full_lbl + "]")
                fput(fh, "        global pre_keys " + q + dol + "pre_keys_" + strofreal(_k) + q)
                fput(fh, "        use " + q + dol + "{target_dta_" + strofreal(_k) + "}" + q + ", clear")
                fput(fh, "")
                fput(fh, "mdf_core_vars")
                write_mod_cover_page(fh, q, bt, ap, dol, pname, full_lbl, "Cover_" + strofreal(_k), strofreal(_k))
                write_mod_enum_success(fh, q, bt, ap, dol, pname, strofreal(_k))
                write_mod_duration_audit(fh, q, bt, ap, dol, pname, strofreal(_k), strofreal(_k))
                write_mod_gatekeeper_skip(fh, q, bt, ap, dol, pname, strofreal(_k), strofreal(_k))
                write_mod_response_bias(fh, q, bt, ap, dol, pname, strofreal(_k))
                write_mod_duplicates_check(fh, q, bt, ap, dol, pname, strofreal(_k), strofreal(_k))
                write_custom_check_slot(fh, full_lbl)
                write_boxed_marker(fh, "[END HFC " + full_lbl + "]")
                fput(fh, "    }")
                fput(fh, "")
            }
            fput(fh, "}")
            fput(fh, "")
            fput(fh, "    *──────────────────────────────────────────────────────────────────────────────")
            fput(fh, "    *  MERGED DATASET (Conditional)")
            fput(fh, "    *──────────────────────────────────────────────────────────────────────────────")
            fput(fh, "    if " + dol + "merge_required == 1 {")
            fput(fh, "        local _sfx = subinstr(" + q + dol + "merge_datasets" + q + ", " + q + " " + q + ", " + q + "_" + q + ", .)")
            fput(fh, "        local _merged_file " + q + dol + "hfc_run_dir/" + dol + "{project_name}_" + bt + "_sfx" + ap + "_MERGED_" + dol + "hfc_folder_date.dta" + q)
            fput(fh, "        cap confirm file " + q + bt + "_merged_file" + ap + q)
            fput(fh, "        if !_rc {")
            fput(fh, "            global target_dta_merged " + q + bt + "_merged_file" + ap + q)
            fput(fh, "            global pre_keys_merged " + q + dol + "hfc_keys_master_dir/" + dol + "{project_name}_" + bt + "_sfx" + ap + "_MERGED_KEYS_" + dol + "LAST_RUN_DATE.dta" + q)
            fput(fh, "")
            fput(fh, "            use " + q + dol + "target_dta_merged" + q + ", clear")
            fput(fh, "            quietly count")
            fput(fh, "            di as result _n " + q + "Merged Dataset loaded. N = " + q + " r(N)")
            fput(fh, "")
            write_boxed_marker(fh, "[START HFC Merged Dataset]")
            fput(fh, "            global pre_keys " + q + dol + "pre_keys_merged" + q)
            fput(fh, "            use " + q + dol + "target_dta_merged" + q + ", clear")
            fput(fh, "")
            write_custom_check_slot(fh, "Merged Dataset")
            write_boxed_marker(fh, "[END HFC Merged Dataset]")
            fput(fh, "        }")
            fput(fh, "        else di as txt _n " + q + "Merged dataset not found — skipping." + q)
            fput(fh, "    }")
        }
        fput(fh, "")
        fput(fh, "di as result " + q + "─────────────────────────────────────────" + q)
        fput(fh, "di as result " + q + "  HFC checks complete." + q)
        fput(fh, "di as result " + q + "  Report → " + dol + "hfc_report" + q)
        fput(fh, "di as result " + q + "─────────────────────────────────────────" + q)
        fclose(fh)
    }

    //  ── The framework runtime beside the modules: Tier 1, every run ────────
    rtdir = dodir + "/_mdf"
    if (!direxists(rtdir)) (void) _mkdir(rtdir)
    write_engine_file(rtdir + "/mdf_labeling.do", "labeling", q, bt, ap, dol)
    write_engine_file(rtdir + "/mdf_translation.do", "translation", q, bt, ap, dol)

    write_labeling_do(dodir, tver, pname, q, bt, ap, dol, nds)
    write_translation_do(dodir, tver, pname, q, bt, ap, dol, nds)
    write_audio_do(dodir, tver, pname, q, bt, ap, dol, nds)

    write_processing_do(procdir, procfile, tver, pname, q, bt, ap, dol, nds)
}


end

mata: mata set matastrict `_mdf_ms'
