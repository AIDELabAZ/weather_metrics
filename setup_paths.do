* Shared inputs and project-specific outputs. Called by projectdo.do.
* Optional arguments: repository root, shared weather_and_agriculture root.
version 18
args code_root data_root
if `"`code_root'"' == "" local code_root `"`c(pwd)'"'
if `"`data_root'"' == "" local data_root : environment WEATHER_AGRICULTURE_DATA
if `"`data_root'"' == "" {
    local userprofile : environment USERPROFILE
    local data_root `"`userprofile'/OneDrive - University of Arizona/weather_and_agriculture"'
}
global code = subinstr(`"`code_root'"', char(92), "/", .)
global datahome = subinstr(`"`data_root'"', char(92), "/", .)
global rawlsms "$datahome/raw_lsms_data"
global weatherdata "$datahome/weather_data"
global data "$datahome/weather_metrics_data"
global weatherwork "$data/refined_data/weather"

confirm file "$code/projectdo.do"
foreach input in rawlsms weatherdata {
    local folders : dir "${`input'}" dirs "*"
    if `"`folders'"' == "" {
        display as error "Input root is empty: ${`input'}"
        error 601
    }
}

* Create output directories only; raw inputs keep their original structure.
capture mkdir "$data"
foreach folder in refined_data merged_data regression_data results_data {
    capture mkdir "$data/`folder'"
    capture mkdir "$data/`folder'/logs"
}
foreach country in ethiopia malawi niger nigeria tanzania uganda {
    foreach folder in refined_data merged_data regression_data results_data {
        capture mkdir "$data/`folder'/`country'"
        capture mkdir "$data/`folder'/`country'/logs"
    }
    local waves : dir "$code/`country'/household_code" dirs "wave_*"
    foreach wave of local waves {
        capture mkdir "$data/refined_data/`country'/`wave'"
        capture mkdir "$data/refined_data/`country'/`wave'/tmp"
        capture mkdir "$data/merged_data/`country'/`wave'"
    }
}
capture mkdir "$data/refined_data/nigeria/conversion_files"
capture mkdir "$data/refined_data/malawi/trackingfiles"
capture mkdir "$weatherwork"
foreach country in ethiopia malawi niger nigeria tanzania uganda {
    capture mkdir "$weatherwork/`country'"
    capture mkdir "$weatherwork/`country'/logs"
    local waves : dir "$code/`country'/weather_code" dirs "wave_*"
    foreach wave of local waves {
        capture mkdir "$weatherwork/`country'/`wave'"
        capture mkdir "$weatherwork/`country'/`wave'/daily"
        capture mkdir "$weatherwork/`country'/`wave'/refined"
        capture local surveys : dir "$weatherdata/`country'/`wave'/daily" dirs "*"
        if _rc local surveys
        foreach survey of local surveys {
            capture mkdir "$weatherwork/`country'/`wave'/daily/`survey'"
            capture mkdir "$weatherwork/`country'/`wave'/refined/`survey'"
        }
    }
}
foreach folder in tables figures {
    capture mkdir "$data/results_data/`folder'"
    foreach paper in paper metric_paper mismeasure_paper privacy_paper {
        capture mkdir "$data/results_data/`folder'/`paper'"
    }
}
capture mkdir "$data/results_data/figures/presentations"
capture mkdir "$data/results_data/figures/presentations/PacDev"
display as text "Code: $code"
display as text "Raw LSMS: $rawlsms"
display as text "Weather: $weatherdata"
display as text "Project data: $data"
display as text "Derived weather: $weatherwork"
