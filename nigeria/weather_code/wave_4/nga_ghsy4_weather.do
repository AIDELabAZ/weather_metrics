* Project: WB Weather
* Created on: April 2020
* Created by: jdm
* edited on: 20 May 2024
* edited by: jdm
* Stata v.18

* does
	* reads in Nigeria, wave 4 .dta files with daily values
	* runs wxsum .ado file
	* outputs .dta file of the relevant weather variables
	* does the above for both rainfall and temperature data
	/* 	-the growing season that we care about is defined on the FAO website:
			http://www.fao.org/giews/countrybrief/country.jsp?code=NGA
		-we measure rainfall during the months that the FAO defines as sowing and growing
		-Nigeria has a bi-modal distribution so we generate variables for both north and south
		-we define the relevant months for the north as Aprol 1 - October 1
		-we define the relevant months for the south as June 1 - October 1 */

* assumes
	* daily data converted to .dta
	* wxsum.ado

* TO DO:
	* completed


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	loc			shared_daily = "$wraw/nigeria/wave_4/daily/ghsy4_up"
	capture local shared_files : dir "`shared_daily'" files "*_daily.dta"
	if _rc local shared_files
	if `"`shared_files'"' == "" loc shared_daily = ///
				"$wraw/nigeria/wave_4/daily 2/ghsy4_up"
	loc			root = "$wout/nigeria/wave_4/daily/ghsy4_up"
	capture local available : dir "`root'" files "*_daily.dta"
	if _rc local available
	if `"`available'"' == "" loc root = "`shared_daily'"
	loc			export = "$wout/nigeria/wave_4/refined/ghsy4_up"
	loc			logout = "$wout/nigeria/logs"

* open log
	cap log close
	log			using "`logout'/nga_ghsy4_weather", append


**********************************************************************
* 1.A - run command for rainfall - north
**********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'" files "*rf_daily.dta"
	if `"`fileList'"' == "" error 601
	if `"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* drop weather variables beyond 2018
		keep		hhid rf_19830101-rf_20181231

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* run the user written weather command - this takes a while
		do			"$code/analysis/reg_code/wxsum_metrics.do" rf_ rain 6 10 hhid

	* save file
		compress
		save		"`export'/`dat'_n.dta", replace
	}


**********************************************************************
* 1.B - run command for rainfall - south
**********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'" files "*rf_daily.dta"
	if `"`fileList'"' == "" error 601
	if `"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* drop weather variables beyond 2018
		keep		hhid rf_19830101-rf_20181231

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* run the user written weather command - this takes a while
		do			"$code/analysis/reg_code/wxsum_metrics.do" rf_ rain 4 10 hhid

	* save file
		compress
		save		"`export'/`dat'_s.dta", replace
	}


**********************************************************************
* 2.A - run command for temperature - north
**********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'" files "*tp_daily.dta"
	if `"`fileList'"' == "" error 601
	if `"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* drop weather variables beyond 2018
		keep		hhid tmp_19830101-tmp_20181231

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* run the user written weather command - this takes a while
		do			"$code/analysis/reg_code/wxsum_metrics.do" tmp_ temp 6 10 hhid

	* save file
		compress
		save		"`export'/`dat'_n.dta", replace
	}


**********************************************************************
* 2.B - run command for temperature - south
**********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'" files "*tp_daily.dta"
	if `"`fileList'"' == "" error 601
	if `"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* drop weather variables beyond 2018
		keep		hhid tmp_19830101-tmp_20181231

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* run the user written weather command - this takes a while
		do			"$code/analysis/reg_code/wxsum_metrics.do" tmp_ temp 4 10 hhid

	* save file
		compress
		save		"`export'/`dat'_s.dta", replace
	}

* close the log
	log			close

/* END */
