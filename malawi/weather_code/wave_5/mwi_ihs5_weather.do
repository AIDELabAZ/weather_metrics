* Project: WB Weather
* Created on: May 2024
* Created by: jdm
* edited by: jdm
* edited on: 20 May 2024
* Stata v.18

* does
* reads in Malawi IHS5, which we term wave 5, .dta files with daily values
* runs wxsum .ado file
* outputs .dta file of the relevant weather variables
* does the above for both rainfall and temperature data
	/* 	-the growing season that we care about is defined on the FAO website:
			http://www.fao.org/giews/countrybrief/country.jsp?code=MWI
		-we measure rainfall during the months that the FAO defines as sowing and growing
		-we define the relevant months as November 1 - April 30
		-but in code below we keep the Jan 1 to Jul 1 since these are "rename" months */

* assumes
* daily data converted to .dta
* wxsum.ado

* TO DO:
* completed


* **********************************************************************
**# 0 - setup
* **********************************************************************

* define paths
	loc			shared_daily = "$weatherdata/malawi/wave_5/daily/ihs5_up"
	loc			root = "$weatherwork/malawi/wave_5/daily/ihs5_up"
	capture		local		available : dir "`root'" files "*_daily.dta"
	if			_rc local available
	if			`"`available'"' == "" loc root = "`shared_daily'"
	loc			export 	= 	"$weatherwork/malawi/wave_5/refined/ihs5_up"
	loc			logout 	= 	"$weatherwork/malawi/logs"

* open log
	cap			log			close
	log			using 		"`logout'/mwi_ihs5_weather", append


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

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* run the user written weather command - this takes a while
		do			"$code/analysis/reg_code/wxsum_metrics.do" rf_ rain 1 7 case_id

	* save file
		compress
		save		"`export'/`dat'.dta", replace
	}

* **********************************************************************
**# 2 - run command for temperature
* **********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'" files "*tp_daily.dta"
	if			`"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach		file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* run the user written weather command - this takes a while
		do			"$code/analysis/reg_code/wxsum_metrics.do" tmp_ temp 1 7 case_id

	* save file
		compress
		save		"`export'/`dat'.dta", replace
	}

* close the log
	log			close

/* END */
