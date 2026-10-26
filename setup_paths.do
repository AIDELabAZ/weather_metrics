* project: wb weather - metric
* created on: 26 oct 2026
* created by: codex
* edited on: 26 oct 2026
* edited by: codex
* stata v.18
* does
	* creates project output folders using the calling script's paths

* assumes
	* code, raw, wraw, data, and wout globals are defined
	* setup is recorded in the calling master or test log


**********************************************************************
**# 0 - setup
**********************************************************************

* check the roots defined by the calling master or test
	version		18
	foreach root in code raw wraw data wout {
		if `"${`root'}"' == "" {
			display		as error "Define `root' before running setup_paths.do."
			error		198
		}
	}

	confirm		file "$code/projectdo.do"
	foreach input in raw wraw {
		local		folders : dir "${`input'}" dirs "*"
		if `"`folders'"' == "" {
			display		as error "Input root is empty: ${`input'}"
			error		601
		}
	}


**********************************************************************
**# 1 - create project output directories
**********************************************************************

* keep generated data within the project output root
	capture mkdir "$data"
	foreach folder in refined_data merged_data regression_data results_data {
		capture mkdir "$data/`folder'"
		capture mkdir "$data/`folder'/logs"
	}
* create country and wave output folders
	foreach country in ethiopia malawi niger nigeria tanzania uganda {
		foreach folder in refined_data merged_data regression_data results_data {
			capture mkdir "$data/`folder'/`country'"
			capture mkdir "$data/`folder'/`country'/logs"
		}
		local		waves : dir "$code/`country'/household_code" dirs "wave_*"
		foreach wave of local waves {
			capture mkdir "$data/refined_data/`country'/`wave'"
			capture mkdir "$data/refined_data/`country'/`wave'/tmp"
			capture mkdir "$data/merged_data/`country'/`wave'"
		}
	}
	capture mkdir "$data/refined_data/nigeria/conversion_files"
	capture mkdir "$data/refined_data/malawi/trackingfiles"
	capture mkdir "$wout"
* create country and wave output folders
	foreach country in ethiopia malawi niger nigeria tanzania uganda {
		capture mkdir "$wout/`country'"
		capture mkdir "$wout/`country'/logs"
		local		waves : dir "$code/`country'/weather_code" dirs "wave_*"
		foreach wave of local waves {
			capture mkdir "$wout/`country'/`wave'"
			capture mkdir "$wout/`country'/`wave'/daily"
			capture mkdir "$wout/`country'/`wave'/refined"
			capture local surveys : dir ///
						"$wraw/`country'/`wave'/daily" dirs ///
						"*"
			if _rc local surveys
			foreach survey of local surveys {
				capture mkdir "$wout/`country'/`wave'/daily/`survey'"
				capture mkdir "$wout/`country'/`wave'/refined/`survey'"
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


**********************************************************************
**# 2 - end matter
**********************************************************************

* report the configured roots
	display		as text "Code: $code"
	display		as text "Raw LSMS: $raw"
	display		as text "Weather: $wraw"
	display		as text "Project data: $data"
	display		as text "Derived weather: $wout"

/* END */
