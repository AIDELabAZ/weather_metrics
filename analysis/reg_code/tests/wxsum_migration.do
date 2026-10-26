* Run from the repository root: do analysis/reg_code/tests/wxsum_migration.do
* Synthetic daily series; verifies corrected metrics and the legacy merge contract.
version 18
clear all
set more off
global code = subinstr(`"`c(pwd)'"', char(92), "/", .)
set obs 3
gen byte hhid = _n
forvalues year = 1983/1985 {
    forvalues date = `=mdy(1,1,`year')'/`=mdy(12,31,`year')' {
        local suffix : display %tdCCYYNNDD `date'
        gen double rf_`suffix' = mod(`date', 5) + (`year'-1983)/10
        gen double tmp_`suffix' = 5 + mod(`date', 40)
        replace rf_`suffix' = . if hhid == 3 & `year' == 1984
        replace tmp_`suffix' = . if hhid == 3 & `year' == 1984
    }
}
tempfile input native_rain native_temp
save `input'

wxsum rf_, type(rain) ini_month(1) fin_month(2) ini_day(1) fin_day(1) ///
    baseline(1983 1985) ref_min(2) shape(wide) keep(hhid)
keep hhid mean_* median_* sd_* skew_* total_* raindays_* norain_* pct_raindays_* dry_* dev_total_* z_total_*
save `native_rain'
use `input', clear
do "$code/analysis/reg_code/wxsum_metrics.do" rf_ rain 1 2 hhid
isid hhid
assert _N == 3
assert missing(total_season_1984) & missing(raindays_1984) if hhid == 3
unab range : mean_season_1983-dry_1983
assert `"`range'"' == "mean_season_1983 median_season_1983 sd_season_1983 total_season_1983 skew_season_1983 norain_1983 raindays_1983 percent_raindays_1983 dry_1983"
merge 1:1 hhid using `native_rain', assert(match) nogen
foreach year in 1983 1984 1985 {
    assert reldif(total_season_`year', total_`year') < 1e-7
    assert reldif(mean_season_`year', mean_`year') < 1e-7
    assert reldif(skew_season_`year', skew_`year') < 1e-7
    assert reldif(percent_raindays_`year', pct_raindays_`year') < 1e-7
    assert reldif(dev_total_season_`year', dev_total_`year') < 1e-7
    assert reldif(z_total_season_`year', z_total_`year') < 1e-7
}

use `input', clear
* Independent check of degree-day units: capped degrees above 10, not days in range.
gen double expected_gdd = 0
gen double old_day_count = 0
forvalues date = `=mdy(1,1,1983)'/`=mdy(2,1,1983)' {
    local suffix : display %tdCCYYNNDD `date'
    replace expected_gdd = expected_gdd + min(20, max(0, tmp_`suffix' - 10))
    replace old_day_count = old_day_count + inrange(tmp_`suffix', 10, 30)
}
tempfile expected
preserve
    keep hhid expected_gdd old_day_count
    save `expected'
restore
wxsum tmp_, type(temp) ini_month(1) fin_month(2) ini_day(1) fin_day(1) ///
    gdd_lo(10) gdd_hi(30) heat_threshold(30) baseline(1983 1985) ref_min(2) shape(wide) keep(hhid)
keep hhid gdd_* dev_gdd_* z_gdd_*
save `native_temp'
use `input', clear
do "$code/analysis/reg_code/wxsum_metrics.do" tmp_ temp 1 2 hhid
isid hhid
assert _N == 3
unab range : mean_season_1983-tempbin1001983
local nrange : word count `range'
assert `nrange' == 11
assert missing(gdd_1984) & missing(tempbin201984) if hhid == 3
foreach year in 1983 1984 1985 {
    assert abs(tempbin20`year' + tempbin40`year' + tempbin60`year' + tempbin80`year' + tempbin100`year' - 1) < 1e-7 if !missing(gdd_`year')
}
merge 1:1 hhid using `expected', assert(match) nogen
assert reldif(gdd_1983, expected_gdd) < 1e-7
assert gdd_1983 != old_day_count
* Rename before merging so Stata cannot hide a disagreement in overlapping names.
rename (gdd_* dev_gdd_* z_gdd_*) (bridge_gdd_* bridge_dev_gdd_* bridge_z_gdd_*)
merge 1:1 hhid using `native_temp', assert(match) nogen
foreach year in 1983 1984 1985 {
    assert reldif(bridge_gdd_`year', gdd_`year') < 1e-7
    assert reldif(bridge_dev_gdd_`year', dev_gdd_`year') < 1e-7
    assert reldif(bridge_z_gdd_`year', z_gdd_`year') < 1e-7
}
display as result "PASS: wxsum metrics, GDD units, missing seasons, percentile shares, fixed reference, legacy names/order."

* A calendar year with no daily variables still needs the complete merge schema.
foreach type in rain temp {
    use `input', clear
    drop rf_1984* tmp_1984*
    local stub = cond("`type'" == "rain", "rf_", "tmp_")
    do "$code/analysis/reg_code/wxsum_metrics.do" `stub' `type' 1 2 hhid
    assert missing(mean_season_1984)
    if "`type'" == "temp" assert missing(tempbin201984) & missing(gdd_1984)
}
display as result "PASS: absent daily-variable year retains missing statistics and schema."
