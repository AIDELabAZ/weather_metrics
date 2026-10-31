* Project: WB Weather - metric
* Created on: 31 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 31 Oct 2026
* Stata v.18

* does
	* recovers household, wave, and geographic keys for validation
	* records rainfall missingness before the panel's zero replacement

* assumes
	* projectdo.do has established the code, raw, and data globals
	* the existing country append and panel build files have run

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths and open the log
	loc			out "$data/results_data/additional_evidence/exhibit2"
	capture mkdir "$data/results_data/additional_evidence"
	capture mkdir "`out'"
	capture mkdir "`out'/logs"
	cap log close
	log using	"`out'/logs/metric_keys.log", text replace
	tempfile	eth mwi ngr nga tza uga keys places lookup geo


**********************************************************************
**# 1 - ethiopia
**********************************************************************

* recover wave-specific EAs from the merged household files
	forvalues w = 1/5 {
		use			household_id year region zone woreda ea using ///
					"$data/merged_data/ethiopia/wave_`w'/essy`w'_merged", clear
		gen byte	wave = `w'
		egen		ea_key = concat(region zone woreda ea), punct("/")
		egen		stratum = concat(region)
		keep		household_id year wave ea_key stratum
		if `w' > 1 append using "`places'"
		save		"`places'", replace
	}
	keep if		household_id != ""
	isid		household_id year
	save		"`places'", replace
	use			"$data/regression_data/ethiopia/eth_complete", clear
	merge		1:1 household_id year using "`places'", ///
				keep(master match) keepusing(wave ea_key stratum) nogen
	rename		eth_id country_id
	drop		country
	gen byte	country = 1
	save		"`eth'"


**********************************************************************
**# 2 - malawi
**********************************************************************

* use each household's baseline EA for the geographically grouped split
	use			case_id ea_id region using ///
				"$data/merged_data/malawi/wave_1/lp1_merged", clear
	append		using "$data/merged_data/malawi/wave_1/sp1_merged", ///
				keep(case_id ea_id region)
	keep		case_id ea_id region
	drop if		case_id == ""
	duplicates drop
	isid		case_id
	rename		ea_id ea_key
	capture confirm string variable ea_key
	if _rc tostring ea_key, replace
	tostring	region, gen(stratum)
	save		"`places'", replace
	use			"$data/regression_data/malawi/mwi_complete", clear
	merge		m:1 case_id using "`places'", ///
				keep(master match) keepusing(ea_key stratum) nogen
	gen byte	survey_wave = 1 if year == 2009
	replace		survey_wave = 2 if year == 2012
	replace		survey_wave = 4 if year == 2015
	replace		survey_wave = 6 if year == 2018
	drop		wave
	rename		survey_wave wave
	rename		mwi_id country_id
	drop		country
	gen byte	country = 2
	save		"`mwi'"


**********************************************************************
**# 3 - niger
**********************************************************************

	forvalues w = 1/2 {
		loc			extra = cond(`w' == 2, "extension", "")
		use			hid year region enumeration clusterid `extra' using ///
					"$data/merged_data/niger/wave_`w'/ecvmay`w'_merged", clear
		if `w' == 2 {
			drop if		inlist(extension, "1", "2")
			drop		extension
		}
		gen byte	wave = `w'
		if `w' > 1 append using "`places'"
		save		"`places'", replace
	}
	egen		ea_key = concat(region enumeration clusterid), punct("/")
	tostring	region, gen(stratum)
	isid		hid year
	save		"`places'", replace
	use			"$data/regression_data/niger/ngr_complete", clear
	merge		1:1 hid year using "`places'", ///
				keep(master match) keepusing(wave ea_key stratum) nogen
	rename		ngr_id country_id
	drop		country
	gen byte	country = 4
	save		"`ngr'"


**********************************************************************
**# 4 - nigeria
**********************************************************************

	forvalues w = 1/4 {
		use			hhid year zone state lga sector ea using ///
					"$data/merged_data/nigeria/wave_`w'/ghsy`w'_merged", clear
		gen byte	wave = `w'
		if `w' > 1 append using "`places'"
		save		"`places'", replace
	}
	egen		ea_key = concat(state lga sector ea), punct("/")
	tostring	zone, gen(stratum)
	isid		hhid year
	save		"`places'", replace
	use			"$data/regression_data/nigeria/nga_complete", clear
	merge		1:1 hhid year using "`places'", ///
				keep(master match) keepusing(wave ea_key stratum) nogen
	rename		nga_id country_id
	drop		country
	gen byte	country = 5
	save		"`nga'"


**********************************************************************
**# 5 - tanzania
**********************************************************************

* recover each wave's own EA identifier; the appended panel drops these keys
	loc			ids y1_hhid y2_hhid y3_hhid y4_hhid y4_hhid sdd_hhid y5_hhid
	loc			files npsy1 npsy2 npsy3 npsy4 npsy4xp npsy5sdd npsy5
	loc			years 2008 2010 2012 2014 2014 2018 2020
	loc			clusters clusterid2008 clusterid2010 clusterid2012 clusterid ///
				clusterid2014 clusterid2018 clusterid
	forvalues w = 1/7 {
		loc			id : word `w' of `ids'
		loc			file : word `w' of `files'
		loc			year : word `w' of `years'
		loc			cluster : word `w' of `clusters'
		use			`id' region district `cluster' using ///
					"$data/merged_data/tanzania/wave_`w'/`file'_merged", clear
		egen		ea_key = concat(region district `cluster'), punct("/")
		egen		stratum = concat(region)
		keep		`id' ea_key stratum
		isid		`id'
		save		"`lookup'", replace
		use			"$data/regression_data/tanzania/tza_complete", clear
		keep if		year == `year'
		if `w' == 4 keep if dtype == "sp"
		if `w' == 5 keep if dtype == "lp"
		merge		m:1 `id' using "`lookup'", ///
					keep(master match) keepusing(ea_key stratum) generate(geo_match)
		assert		geo_match == 3
		gen byte	wave = `w'
		keep		tza_id year wave ea_key stratum
		if `w' > 1 append using "`places'"
		save		"`places'", replace
	}
	isid		tza_id year
	use			"$data/regression_data/tanzania/tza_complete", clear
	merge		1:1 tza_id year using "`places'", ///
				keep(master match) keepusing(wave ea_key stratum) nogen
	rename		tza_id country_id
	drop		country
	gen byte	country = 6
	save		"`tza'"


**********************************************************************
**# 6 - uganda
**********************************************************************

* retain parish keys before string/numeric differences are forced on append
	foreach w in 1 2 3 4 5 8 {
		use			"$data/merged_data/uganda/wave_`w'/unps`w'_merged", clear
		loc			id = cond(`w' == 5, "hh", cond(`w' == 4, "HHID", "hhid"))
		egen		raw_key = concat(`id')
		egen		ea_key = concat(district subcounty parish), punct("/")
		egen		stratum = concat(region)
		keep		raw_key year ea_key stratum
		if `w' > 1 append using "`geo'"
		save		"`geo'", replace
	}
	isid		raw_key year

* reconstruct the existing panel-ID links before the append file drops them
	use			"$data/merged_data/uganda/wave_1/unps1_merged", clear
	gen byte	wave = 1
	foreach w in 2 3 4 {
		append		using "$data/merged_data/uganda/wave_`w'/unps`w'_merged", force
		replace		wave = `w' if missing(wave)
	}
	rename		hhid hh_1_4
	append		using "$data/merged_data/uganda/wave_5/unps5_merged", force
	replace		wave = 5 if missing(wave)
	append		using "$data/refined_data/uganda/wave_7/2018_gsec1", force
	rename		HHID hh_4_7
	append		using "$data/merged_data/uganda/wave_8/unps8_merged", force
	replace		wave = 8 if missing(wave) & year == 2019
	egen		hh47 = group(hh_4_7)
	xtset		hh47
	xfill		hh_1_4 if hh_1_4 == "" & hh47 != ., i(hh47)
	egen		hh78 = group(hh_7_8)
	xtset		hh78
	xfill		hh_4_7 if hh_4_7 == "" & hh78 != ., i(hh78)
	xfill		hh47 if hh47 == . & hh78 != ., i(hh78)
	xtset		hh47
	xfill		hh_1_4 if hh_1_4 == "" & hh47 != ., i(hh47)
	egen		pnl_hhid = group(hh_1_4)
	drop		hh47
	egen		hh47 = group(hh_4_7) if pnl_hhid == .
	quietly summarize pnl_hhid
	replace		pnl_hhid = hh47 + r(max) if pnl_hhid == .
	drop		hh78
	egen		hh78 = group(hh_7_8) if pnl_hhid == .
	quietly summarize pnl_hhid
	replace		pnl_hhid = hh78 + r(max) if pnl_hhid == .
	egen		hh8 = group(hhid) if pnl_hhid == .
	quietly summarize pnl_hhid
	replace		pnl_hhid = hh8 + r(max) if pnl_hhid == .
	drop if		data == ""
	egen		uga_id = group(pnl_hhid)

* parish blocks are coarser than EAs; retain their original administrative keys
	egen		raw_key = concat(hh_1_4)
	egen		raw5 = concat(hh)
	egen		raw8 = concat(hhid)
	replace		raw_key = hh_4_7 if wave == 4
	replace		raw_key = raw5 if wave == 5
	replace		raw_key = raw8 if wave == 8
	merge		1:1 raw_key year using "`geo'", ///
				keep(master match) keepusing(ea_key stratum) nogen
	keep		uga_id year wave ea_key stratum hh_1_4 hh_4_7 hh_7_8 hhid
	rename		hhid raw_hhid
	isid		uga_id year
	save		"`places'", replace
	use			"$data/regression_data/uganda/uga_complete", clear
	merge		1:1 uga_id year using "`places'", ///
				keep(master match) keepusing(wave ea_key stratum ///
				hh_1_4 hh_4_7 hh_7_8 raw_hhid) nogen
	rename		uga_id country_id
	drop		country
	gen byte	country = 7
	save		"`uga'"


**********************************************************************
**# 7 - recover the harmonized household IDs and missingness
**********************************************************************

* retain cross sections here because their IDs were assigned before deletion
	use			"`eth'", clear
	append		using "`mwi'" "`ngr'" "`nga'" "`tza'" "`uga'", force
	gen str3	prefix = "eth" if country == 1
	replace		prefix = "mwi" if country == 2
	replace		prefix = "ngr" if country == 4
	replace		prefix = "nga" if country == 5
	replace		prefix = "tza" if country == 6
	replace		prefix = "uga" if country == 7
	gen str20	panel_key = prefix + strtrim(string(country_id, "%12.0g"))
	capture drop hhid
	egen		hhid = group(panel_key)
	loc			rain
	forvalues m = 1/14 {
		loc			metric : display %02.0f `m'
		forvalues p = 1/6 {
			loc			rain `rain' v`metric'_rf`p'
		}
	}
	egen		rain_missing = rowmiss(`rain')
	keep		country country_id hhid year wave ea_key stratum rain_missing ///
				household_id case_id hid hh_1_4 hh_4_7 hh_7_8 raw_hhid ///
				y1_hhid y2_hhid y3_hhid y4_hhid sdd_hhid y5_hhid
	isid		country hhid year
	save		"`keys'"

* keep only observations in the actual analysis panel
	use			country hhid year using "$data/regression_data/lsms_panel", clear
	merge		1:1 country hhid year using "`keys'", ///
				keep(master match) generate(key_match)
	assert		key_match == 3
	assert		!missing(wave) & ea_key != "" & stratum != ""
	drop		key_match
	label var	rain_missing "Missing rainfall candidates before zero replacement"
	label var	ea_key "Released EA/admin block key within country and survey wave"
	save		"`out'/panel_keys", replace
	log close

/* END */
