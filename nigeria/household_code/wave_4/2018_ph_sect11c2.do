* Project: WB Weather
* Created on: Feb 2024
* Created by: jet
* Edited on: 19 March 2024
* Edited by: jet
* Stata v.18

* does
	* reads in Nigeria, WAVE 4 (2018-2019), POST HARVEST, AG SECT11C2
	* creates binaries for pesticide and herbicide use
	* outputs clean data file ready for combination with wave 4 plot data

* assumes
	* customsave.ado
	* mdesc.ado
	
* TO DO:
	* file save

* **********************************************************************
* 0 - setup
* **********************************************************************
	
* define paths	
	global root			"$data/household_data/nigeria/wave_4/raw"
	global export		"$data/household_data/nigeria/wave_4/refined"
	global logout		"$data/household_data/nigeria/logs"

* close log (in case still open)
	*log close
	
* open log	
	*cap log close
	*log using "`logout'/ph_sect11c2", append

* **********************************************************************
* 1 - determine pesticide, herbicide, etc.
* **********************************************************************
		
* import the first relevant data file
		use "$root/secta11c2_harvestw4", clear 	

describe
sort hhid plotid 
isid hhid plotid

*binary for pesticide use since the new year
	rename s11c2q1 pest_any
	lab var			pest_any "=1 if any pesticide was used"

	*binary for herbicide use since the new year
	rename s11c2q10 herb_any
	lab var			herb_any "=1 if any herbicide was used"

* check if any missing values
	mdesc			pest_any herb_any
	*** 1 pest and 1 herb missing, change these to "no"
	
* convert missing values to "no"
	replace			pest_any = 2 if pest_any == .
	replace			herb_any = 2 if herb_any == .

* **********************************************************************
* 2 - end matter, clean up to save
* **********************************************************************

	keep 			hhid zone state lga sector hhid ea plotid ///
					pest_any herb_any 
	
* create unique household-plot identifier
	isid			hhid plotid
	sort			hhid plotid
	egen			plot_id = group(hhid plotid)
	lab var			plot_id "unique plot identifier"

compress
describe
summarize 

* save file
		customsave , idvar(hhid) filename("ph_sect11c2.dta") ///
			path("$export/`folder'") dofile(ph_sect11c2) user($user)

* close the log
	log	close

/* END */