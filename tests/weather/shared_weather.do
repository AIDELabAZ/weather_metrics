* project: wb weather - metric
* created on: 27 oct 2026
* created by: codex
* edited on: 27 Oct 2026
* edited by: codex
* stata v.18

* does
	* checks CSV conversion and wxsum outputs in the shared weather tree
	* checks that another project can reuse the same refined files

* assumes
	* run from the repository root with a new scratch directory argument
	* wxsum is installed


**********************************************************************
**# 0 - setup
**********************************************************************

* isolate synthetic inputs and outputs from research data
	version		18
	clear all
	set			more off
	args		scratch
	if `"`scratch'"' == "" error 198
	global		code	`"`c(pwd)'"'
	global		raw		"`scratch'/households"
	global		wraw	"`scratch'/shared_weather"
	global		data	"`scratch'/project_a"
	capture mkdir "`scratch'"
	capture mkdir "$raw"
	capture mkdir "$raw/niger"
	capture mkdir "$wraw"
	capture mkdir "$wraw/niger"
	capture mkdir "$wraw/niger/wave_1"
	capture mkdir "$wraw/niger/wave_1/raw"
	capture mkdir "$wraw/niger/wave_1/raw/ecvmay1_up"
	tempname	check
	log using "`scratch'/shared_weather.log", text append name(`check')
	do			"$code/setup_paths.do"


**********************************************************************
**# 1 - create synthetic CSV inputs
**********************************************************************

* use constant daily values with known seasonal totals
	confirm		new file "$wraw/niger/wave_1/raw/ecvmay1_up/test_rf.csv"
	confirm		new file "$wraw/niger/wave_1/raw/ecvmay1_up/test_tp.csv"
	clear
	set			obs 3
	gen byte	hid = _n
	forvalues year = 1983/1985 {
		forvalues date = `=mdy(1,1,`year')'/`=mdy(12,31,`year')' {
			local		suffix : display %tdCCYYNNDD `date'
			gen double	rf_`suffix' = hid
			replace		rf_`suffix' = . if hid == 3 & `year' == 1984
		}
	}
	gen double	rf_20111231 = .
	export delimited using "$wraw/niger/wave_1/raw/ecvmay1_up/test_rf.csv", replace

* retain the daily variable range expected by the existing wave script
	forvalues year = 1983/1985 {
		forvalues date = `=mdy(1,1,`year')'/`=mdy(12,31,`year')' {
			local		suffix : display %tdCCYYNNDD `date'
			rename		rf_`suffix' tmp_`suffix'
			replace		tmp_`suffix' = 20 + hid
			replace		tmp_`suffix' = . if hid == 3 & `year' == 1984
		}
	}
	rename		rf_20111231 tmp_20111231
	export delimited using "$wraw/niger/wave_1/raw/ecvmay1_up/test_tp.csv", replace


**********************************************************************
**# 2 - run the converter and weather script
**********************************************************************

* run the production scripts against the synthetic shared tree
	do			"$code/niger/weather_code/wave_1/ngr_ecvmay1_converter.do"
	confirm		file "$wraw/niger/wave_1/daily/ecvmay1_up/test_rf_daily.dta"
	confirm		file "$wraw/niger/wave_1/daily/ecvmay1_up/test_tp_daily.dta"
	do			"$code/niger/weather_code/wave_1/ngr_ecvmay1_weather.do"

* check the historical June 1 to October 1 season in shared refined outputs
	tempfile	rain temp
	use			"$wraw/niger/wave_1/refined/ecvmay1_up/test_rf.dta", clear
	isid		hid
	assert		_N == 3
	assert		total_season_1983 == hid * (mdy(10,1,1983) - mdy(6,1,1983) + 1)
	assert		missing(total_season_1984) if hid == 3
	unab		annual : mean_season_1983-dry_1983
	local		n : word count `annual'
	assert		`n' == 9
	save		`rain'
	use			"$wraw/niger/wave_1/refined/ecvmay1_up/test_tp.dta", clear
	isid		hid
	assert		_N == 3
	assert		gdd_1983 == (10 + hid) * (mdy(10,1,1983) - mdy(6,1,1983) + 1)
	assert		missing(gdd_1984) & missing(tempbin201984) if hid == 3
	assert		abs(tempbin201983 + tempbin401983 + tempbin601983 + ///
			tempbin801983 + tempbin1001983 - 1) < 1e-7
	unab		annual : mean_season_1983-tempbin1001983
	local		n : word count `annual'
	assert		`n' == 11
	save		`temp'


**********************************************************************
**# 3 - reuse the weather files from another project
**********************************************************************

* change only the project output root and reuse the same refined weather
	global		data	"`scratch'/project_b"
	do			"$code/setup_paths.do"
	use			"$wraw/niger/wave_1/refined/ecvmay1_up/test_rf.dta", clear
	cf			_all using `rain', all
	use			"$wraw/niger/wave_1/refined/ecvmay1_up/test_tp.dta", clear
	cf			_all using `temp', all
	foreach project in project_a project_b {
		local		copies : dir "`scratch'/`project'/refined_data" dirs "weather"
		assert		`"`copies'"' == ""
	}
	display		as result "PASS: shared CSV, daily, and wxsum files; reuse across projects."


**********************************************************************
**# 4 - end matter
**********************************************************************

* close the test log
	log close `check'

/* END */
