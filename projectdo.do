* Project: WB Weather - metric; Stata 18
* Run from the repository root, or supply its path as the first argument.
* Arguments: code_root shared_data_root stage
* Stages: setup, packages, weather, metrics, households, panel, regressions, figures, all.
* all rebuilds the core pipeline through regressions; figures are a separate stage.
version 18
set more off
args code_root data_root stage
if `"`code_root'"' == "" local code_root `"`c(pwd)'"'
if `"`stage'"' == "" local stage "all"
if !inlist("`stage'", "setup", "packages", "weather", "metrics", "households", "panel", "regressions", "figures", "all") {
    display as error "Unknown stage: `stage'"
    error 198
}
do "`code_root'/setup_paths.do" `"`code_root'"' `"`data_root'"'
if "`stage'" == "setup" exit

* The daily wide files exceed Stata's default 5,000-variable limit.
if inlist("`stage'", "weather", "metrics", "all") & c(maxvar) < 20000 {
    clear all
    set maxvar 20000
}

* Install existing dependencies only when explicitly selecting packages.
* Normal runs never update installed ado files or change permanent preferences.
if "`stage'" == "packages" {
    local failed_packages
    foreach package in distinct winsor2 mdesc unique missings carryforward estout palettes catplot colrspace coefplot blindschemes {
        local command "`package'"
        if "`package'" == "palettes" local command "colorpalette"
        if "`package'" == "blindschemes" capture findfile scheme-plotplain.scheme
        else capture which `command'
        if _rc {
            local initial = substr("`package'", 1, 1)
            capture noisily ssc install `package'
            if _rc capture noisily net install `package', from("https://fmwww.bc.edu/repec/bocode/`initial'")
            if _rc local failed_packages `failed_packages' `package'
        }
    }
    capture which wxsum
    if _rc {
        capture noisily net install wxsum, from("https://raw.githubusercontent.com/jdavidm/wxsum/main/")
        if _rc local failed_packages `failed_packages' wxsum
    }
    capture which xfill
    if _rc {
        capture noisily net install xfill, from("https://www.sealedenvelope.com/")
        if _rc local failed_packages `failed_packages' xfill
    }
    if `"`failed_packages'"' != "" {
        display as error "Dependency installation failed: `failed_packages'"
        error 499
    }
    exit
}

* Weather converters and metric construction (the longest stage).
if inlist("`stage'", "weather", "all") {
    do "$code/ethiopia/weather_code/eth_ess_masterdo.do"
    do "$code/malawi/weather_code/mwi_ihs_masterdo.do"
    do "$code/niger/weather_code/ngr_ecvma_masterdo.do"
    do "$code/nigeria/weather_code/nga_ghs_masterdo.do"
    do "$code/tanzania/weather_code/tza_nps_masterdo.do"
    do "$code/uganda/weather_code/uga_unps_masterdo.do"
}

* Recompute metrics from existing daily files without repeating CSV conversion.
if "`stage'" == "metrics" {
    foreach country in ethiopia malawi niger nigeria tanzania uganda {
        local waves : dir "$code/`country'/weather_code" dirs "wave_*"
        foreach wave of local waves {
            local scripts : dir "$code/`country'/weather_code/`wave'" files "*_weather.do"
            foreach script of local scripts {
                do "$code/`country'/weather_code/`wave'/`script'"
            }
        }
    }
}

* Clean household sections, assemble waves, merge weather, append countries.
if inlist("`stage'", "households", "all") {
    do "$code/ethiopia/household_code/eth_hh_masterdo.do"
    do "$code/malawi/household_code/mwi_hh_masterdo.do"
    do "$code/niger/household_code/ngr_hh_masterdo.do"
    do "$code/nigeria/household_code/nga_hh_masterdo.do"
    do "$code/tanzania/household_code/tza_hh_masterdo.do"
    do "$code/uganda/household_code/uga_hh_masterdo.do"
}
if inlist("`stage'", "panel", "all") do "$code/analysis/reg_code/panel_build.do"
if inlist("`stage'", "regressions", "all") do "$code/analysis/reg_code/regressions.do"
if "`stage'" == "figures" {
    do "$code/analysis/viz_code/metric_sum.do"
    do "$code/analysis/viz_code/metric_pval.do"
    do "$code/analysis/viz_code/metric_coeff_vis.do"
}
display as result "Completed stage: `stage'"
