* Run from the repository root: do analysis/reg_code/tests/project_paths.do <new-scratch-directory>
* Verifies the path contract using synthetic input folders, without private data.
version 18
args scratch
if `"`scratch'"' == "" error 198
local repo = subinstr(`"`c(pwd)'"', char(92), "/", .)
local scratch = subinstr(`"`scratch'"', char(92), "/", .)
capture mkdir "`scratch'"
capture mkdir "`scratch'/raw_lsms_data"
capture mkdir "`scratch'/raw_lsms_data/ethiopia"
capture mkdir "`scratch'/weather_data"
capture mkdir "`scratch'/weather_data/ethiopia"
confirm new file "`scratch'/raw_lsms_data/input_sentinel.dta"
clear
set obs 1
gen byte input_sentinel = 73
save "`scratch'/raw_lsms_data/input_sentinel.dta"
do "`repo'/projectdo.do" "`repo'" "`scratch'" "setup"
assert `"$code"' == `"`repo'"'
assert `"$rawlsms"' == `"`scratch'/raw_lsms_data"'
assert `"$weatherdata"' == `"`scratch'/weather_data"'
assert `"$data"' == `"`scratch'/weather_metrics_data"'
assert `"$weatherwork"' == `"`scratch'/weather_metrics_data/refined_data/weather"'
foreach destination in refined_data/ethiopia/wave_1 merged_data/ethiopia/wave_1 regression_data results_data {
    save "$data/`destination'/output_sentinel.dta"
    confirm file "$data/`destination'/output_sentinel.dta"
}
use "$rawlsms/input_sentinel.dta", clear
assert _N == 1 & input_sentinel == 73
capture do "`repo'/projectdo.do" "`repo'" "`scratch'" "invalid-stage"
assert _rc == 198
display as result "PASS: shared input roots, isolated project outputs, directory creation, input preservation, stage validation."
