* Project: WB Weather
* Created on: April 2020
* Created by: alj
* edited on: 20 May 2024
* edited by: jdm
* Stata v.18

* does
	* reads in Nigeria, wave 4 .csv files
	* outputs .dta file ready for processing by the weather program
	* does the above for both rainfall and temperature data

* assumes
	* raw updated weather data

* TO DO:
	* completed


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	loc			root = "$wraw/nigeria/wave_4/raw/ghsy4_up"
	loc			export = "$wout/nigeria/wave_4/daily/ghsy4_up"
	loc			logout = "$wout/nigeria/logs"

* open log
	cap log close
	log using 	"`logout'/nga_ghsy4_converter", append


**********************************************************************
**# 1 - converts weather data
**********************************************************************

* define local with all files in each sub-folder
	capture local fileList : dir "`root'" files "*.csv"
	if _rc local fileList
	if `"`fileList'"' == "" {
	* Some shared archives store this wave in OneDrive's duplicate folder.
		loc			root = "$wraw/nigeria/wave_4/raw 2/ghsy4_up"
		loc			fileList : dir "`root'" files "*.csv"
		display		as text "Using wave 4 weather archive: `root'"
	}
	if `"`fileList'"' == "" {
		display		as error "No wave 4 weather CSV files found in `root'."
		error		601
	}

* loop through each file in the above local
	foreach file in `fileList' {

	* import the .csv files - this takes time
		import delimited "`root'/`file'", varnames (1) clear

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 4)

	* save file
		compress
		save			"`export'/`dat'_daily.dta", replace
	}

* close the log
	log	close

/* END */
