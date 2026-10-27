* project: wb weather - metric
* created on: 26 oct 2026
* created by: codex
* edited on: 27 Oct 2026
* edited by: codex
* stata v.18
* does
	* checks shared input roots and project outputs using synthetic folders

* assumes
	* run from the repository root with a new scratch directory argument


**********************************************************************
**# 0 - setup
**********************************************************************

* define independent input and output roots for the test
	version		18
	args		scratch
	if `"`scratch'"' == "" error 198
	local		repo `"`c(pwd)'"'
	global		code	`"`repo'"'
	global		raw		"`scratch'/household_inputs"
	global		wraw	"`scratch'/weather_inputs"
	global		data	"`scratch'/project_outputs"
	capture mkdir "`scratch'"
	capture mkdir "$raw"
	capture mkdir "$raw/ethiopia"
	capture mkdir "$wraw"
	capture mkdir "$wraw/ethiopia"
	capture mkdir "$wraw/ethiopia/wave_1"
	capture mkdir "$wraw/ethiopia/wave_1/raw"
	foreach source in source_a source_b {
		capture mkdir "$wraw/ethiopia/wave_1/raw/`source'"
	}
* record the path test without closing the calling log
	tempname	test_log
	log			using "`scratch'/project_paths.log", text append name(`test_log')


**********************************************************************
**# 1 - check input and output separation
**********************************************************************

* seed an input whose value must survive setup
	confirm		new file "$raw/input_sentinel.dta"
	clear
	set			obs 1
	gen byte	input_sentinel = 73
	save		"$raw/input_sentinel.dta"
	do			"`repo'/setup_paths.do"
	assert		`"$code"' == `"`repo'"'
	assert		`"$raw"' == `"`scratch'/household_inputs"'
	assert		`"$wraw"' == `"`scratch'/weather_inputs"'
	assert		`"$data"' == `"`scratch'/project_outputs"'

* create shared weather outputs for sources discovered in the raw tree
	foreach source in source_a source_b {
		foreach stage in daily refined {
			save		"$wraw/ethiopia/wave_1/`stage'/`source'/output_sentinel.dta"
			confirm		file ///
				"$wraw/ethiopia/wave_1/`stage'/`source'/output_sentinel.dta"
		}
	}
	local		copies : dir "$data/refined_data" dirs "weather"
	assert		`"`copies'"' == ""

* keep household and analysis outputs in the project tree
	foreach destination in refined_data/ethiopia/wave_1 merged_data/ethiopia/wave_1 ///
				regression_data results_data {
		save		"$data/`destination'/output_sentinel.dta"
		confirm		file "$data/`destination'/output_sentinel.dta"
	}
	use			"$raw/input_sentinel.dta", clear
	assert		_N == 1 & input_sentinel == 73
	display		as result ///
				"PASS: shared weather outputs, project outputs, and unchanged inputs."


**********************************************************************
**# 2 - end matter
**********************************************************************

* close the test log
	log			close `test_log'

/* END */
