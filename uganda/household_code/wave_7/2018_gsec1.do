* Project: WB Weather
* Created on: Aug 2020
* Created by: themacfreezie
* Edited on: 3 June 24
* Edited by: jdm
* Stata v.18

* does
	* household Location data (2018_GSEC1) for the 1st season

* assumes
	* access to raw data
	* mdesc.ado

* TO DO:
	* currently written just to allow me to merge waves 7 and 8 together
	* needs to be adapted for use in cleaning wave 7


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	global		root 	"$raw/uganda/wave_7/raw"
	global		export 	"$data/refined_data/uganda/wave_7"
	global		logout 	"$data/refined_data/uganda/logs"

* open log
	cap log close
	log 			using 	"$logout/2018_GSEC1", append


**********************************************************************
**# 1 - unps 2011 (wave 3) - general(?) section 1
**********************************************************************

* import wave 7 season 1
	use				"$root/hh/GSEC1", clear

* rename variables
	isid 			hhid
	rename			hhid hh_7_8
	rename			t0_hhid HHID

	rename 			distirct_name district
	rename 			county_name county
	rename 			subcounty_name subcounty
	rename 			parish_name parish
	rename 			hwgt_wc wgt18

	tab 			region, missing

* drop if missing
	drop if			district == ""
	*** dropped 0 observations

	replace				year = 2018


**********************************************************************
**# 2 - end matter, clean up to save
**********************************************************************

	keep 			hh_7_8 HHID year region district county subcounty parish ///
						wgt18 subreg

	compress
	describe
	summarize

* save file
	save		"$export/2018_gsec1.dta", replace

* close the log
	log	close

/* END */
