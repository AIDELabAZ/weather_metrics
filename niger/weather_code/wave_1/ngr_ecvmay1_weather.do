* Project: WB Weather
* Created on: April 2020
* Created by: jdm
* Edited on: 7 June 2024
* Edited by: jdm
* Stata v.18

* does
* reads in Niger, wave 1 .dta files with daily values
* runs wxsum .ado file
* outputs .dta file of the relevant weather variables
* does the above for both rainfall and temperature data
	/* 	-the growing season that we care about is defined on the FAO website:
			http://www.fao.org/giews/countrybrief/country.jsp?code=NER
		-we measure rainfall during the months that the FAO defines as sowing and growing
		-we define the relevant months as 1 June - 31 October */

* assumes
* NGR_ECVMAY1_converter.do
* wxsum.ado

* TO DO:
* completed


* **********************************************************************
**# 0 - setup
* **********************************************************************

* define paths
	loc			shared_daily = "$weatherdata/niger/wave_1/daily/ecvmay1_up"
	loc			root = "$weatherwork/niger/wave_1/daily/ecvmay1_up"
	capture		local		available : dir "`root'" files "*_daily.dta"
	if			_rc local available
	if			`"`available'"' == "" loc root = "`shared_daily'"
	loc			export = "$weatherwork/niger/wave_1/refined/ecvmay1_up"
	loc			logout = "$weatherwork/niger/logs"

* open log
	cap			log			close
	log			using "`logout'/ngr_ecvmay1_weather", replace


* **********************************************************************
**# 1 - run command for rainfall
* **********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'" files "*rf_daily.dta"
	if			`"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach		file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* drop weather variables beyond 2011
		keep		hid rf_19830101-rf_20111231

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* run the user written weather command - this takes a while
		do			"$code/analysis/reg_code/wxsum_metrics.do" rf_ rain 6 10 hid

	* save file
		compress
		save		"`export'/`dat'.dta", replace
	}


* **********************************************************************
**# 2 - run command for temperature
* **********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'/`folder'" files "*tp_daily.dta"
	if			`"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach		file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* drop weather variables beyond 2011
		keep		hid tmp_19830101-tmp_20111231

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* run the user written weather command - this takes a while
		do			"$code/analysis/reg_code/wxsum_metrics.do" tmp_ temp 6 10 hid

	* save file
		compress
		save		"`export'/`dat'.dta", replace
	}

* close the log
	log			close

/* END */
