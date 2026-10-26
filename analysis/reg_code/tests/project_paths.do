* project: wb weather - metric
* created on: 26 oct 2026
* created by: codex
* edited on: 26 oct 2026
* edited by: codex
* stata v.18
* does
* checks shared input roots and project outputs using synthetic folders

* assumes
* run from the repository root with a new scratch directory argument

**********************************************************************
**# 0 - setup
**********************************************************************

* define the test location
	version		18
	args		scratch
	if			`"`scratch'"' == "" error 198
	local		repo `"`c(pwd)'"'
	capture		mkdir		"`scratch'"
	capture		mkdir		"`scratch'/raw_lsms_data"
	capture		mkdir		"`scratch'/raw_lsms_data/ethiopia"
	capture		mkdir		"`scratch'/weather_data"
	capture		mkdir		"`scratch'/weather_data/ethiopia"
* record the path test without closing the calling log
	tempname	test_log
	log			using "`scratch'/project_paths.log", text append name(`test_log')

**********************************************************************
**# 1 - check input and output separation
**********************************************************************

* seed an input whose value must survive setup
	confirm		new file "`scratch'/raw_lsms_data/input_sentinel.dta"
	clear
	set			obs 1
	gen byte	input_sentinel = 73
	save		"`scratch'/raw_lsms_data/input_sentinel.dta"
	do			"`repo'/setup_paths.do" "`repo'" "`scratch'"
	assert		`"$code"' == `"`repo'"'
	assert		`"$rawlsms"' == `"`scratch'/raw_lsms_data"'
	assert		`"$weatherdata"' == `"`scratch'/weather_data"'
	assert		`"$data"' == `"`scratch'/weather_metrics_data"'
	assert		`"$weatherwork"' == ///
				`"`scratch'/weather_metrics_data/refined_data/weather"'
	foreach		destination in refined_data/ethiopia/wave_1 merged_data/ethiopia/wave_1 ///
				regression_data results_data {
		save		"$data/`destination'/output_sentinel.dta"
		confirm		file "$data/`destination'/output_sentinel.dta"
	}
	use			"$rawlsms/input_sentinel.dta", clear
	assert		_N == 1 & input_sentinel == 73
	display		as result ///
				"PASS: shared input roots, isolated project outputs, directory creation, input preservation."

**********************************************************************
**# 2 - end matter
**********************************************************************

* close the test log
	log			close `test_log'

/* END */
