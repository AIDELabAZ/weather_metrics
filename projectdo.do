* project: wb weather - metric
* created on: jan 2024
* created by: cda
* edited on: 26 oct 2026
* edited by: codex
* stata v.18.0

* does
* take 8.5 hours to run, most (8 hrs) cleaning weather data
* establishes an identical workspace between users
* sets globals that define absolute paths
* serves as the starting point to find any do-file, dataset or output
* runs all do-files needed for data work
* loads any user written packages needed for analysis

* assumes
* access to all data and code

* TO DO:
* done


* **********************************************************************
**# 0 - setup
* **********************************************************************

* set $pack to 0 to skip package installation
	global		pack 	0

* specify the stata version in use
	global		stataVersion	18.0
	version		$stataVersion

* **********************************************************************
**## 0.1 - create user-specific paths
* **********************************************************************

* define the shared inputs and project outputs from the repository root
	loc			userprofile : environment USERPROFILE
	loc			data_root : environment WEATHER_AGRICULTURE_DATA
	if			`"`data_root'"' == "" {
		loc			data_root ///
					`"`userprofile'/OneDrive - University of Arizona/weather_and_agriculture"'
	}
	global		code		`"`c(pwd)'"'
	global		datahome	`"`data_root'"'
	global		rawlsms		"$datahome/raw_lsms_data"
	global		weatherdata	"$datahome/weather_data"
	global		data		"$datahome/weather_metrics_data"
	global		weatherwork	"$data/refined_data/weather"

* create the project output folders
	do			"$code/setup_paths.do" "$code" "$datahome"

* **********************************************************************
**## 0.2 - check required packages
* **********************************************************************

* install packages if global is set to 1
	if			$pack == 1 {

	* for packages/commands, make a local containing any required packages
	* temporarily set delimiter to ; so can break the line
		#delimit	;
		loc			userpack = "blindschemes mdesc estout distinct winsor2 unique
                    palettes catplot colrspace carryforward missings
                    coefplot" ;
		#delimit	cr

	* install packages that are on ssc
		foreach		package in `userpack' {
			capture		:			which `package', all
			if			(_rc) {
				capture		window		stopbox rusure "You are missing some packages." ///
							"Do you want to install `package'?"
				if			_rc == 0 {
					capture		ssc			install `package', replace
					if			(_rc) {
						window		stopbox rusure ///
									`"This package is not on SSC. Do you want to proceed without it?"'
					}
				}
				else		{
					exit		199
				}
			}
		}
	* install -wxsum- package
		net			install wxsum, ///
					from(https://raw.githubusercontent.com/jdavidm/wxsum/main/) replace

	* install -xfill and nwcommands packages
		net			install xfill, 	replace from(https://www.sealedenvelope.com/)
		net			from "https://raw.githubusercontent.com/ThomasGrund/nwcommands/master"

	* update all ado files
		ado			update, update

	* set graph and Stata preferences
		set			scheme plotplain, perm
		set			more off
	}

* **********************************************************************
**# 1 - run weather data cleaning .do file
* **********************************************************************

/*	this code requires access to the weather data sets, which are confidential
	and held by the World Bank. They are not publically available

	do			"$code/ethiopia/weather_code/eth_ess_masterdo.do"
	do			"$code/malawi/weather_code/mwi_ihs_masterdo.do"
	do			"$code/niger/weather_code/ngr_ecvma_masterdo.do"
	do			"$code/nigeria/weather_code/nga_ghs_masterdo.do"
	do			"$code/tanzania/weather_code/tza_nps_masterdo.do"
	do			"$code/uganda/weather_code/uga_unps_masterdo.do"
*/

* **********************************************************************
**# 2 - run household data cleaning .do files and merge with weather data
* **********************************************************************

/*	this code requires a user to have downloaded the publically available
	household data sets and placed them into the folder structure detailed
	in the readme file accompanying this repo.

	do			"$code/ethiopia/household_code/eth_hh_masterdo.do"
	do			"$code/malawi/household_code/mwi_hh_masterdo.do"
	do			"$code/niger/household_code/ngr_hh_masterdo.do"
	do			"$code/nigeria/household_code/nga_hh_masterdo.do"
	do			"$code/tanzania/household_code/tza_hh_masterdo.do"
	do			"$code/uganda/household_code/uga_hh_masterdo.do"
*/

* **********************************************************************
**# 3 - build panel and run regressions .do files
* **********************************************************************
/*
	do			"$code/analysis/reg_code/panel_build.do"
	do			"$code/analysis/reg_code/regressions.do"
*/
* **********************************************************************
**# 4 - run analysis .do files
* **********************************************************************

	do			"$code/analysis/viz_code/metric_sum.do"
	do			"$code/analysis/viz_code/metric_pval.do"
	do			"$code/analysis/viz_code/metric_coeff_vis.do"

/* END */
