* Project: WB Weather - metric
* Created on: 31 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 31 Oct 2026
* Stata v.18

* does
	* inventories released coordinates and recovers the original household keys
	* creates a separate georeferenced panel and coverage audit

* assumes
	* project globals and the panel_keys output from metric_keys.do
	* released geovariables mappings in metric_geo.csv

* TO DO:
	* add usable Tanzania late-wave and Uganda wave-8 coordinates if released


**********************************************************************
**# 0 - setup
**********************************************************************

	loc			out "$data/results_data/additional_evidence/exhibit3"
	capture mkdir "`out'"
	capture mkdir "`out'/logs"
	capture mkdir "`out'/scores"
	capture mkdir "`out'/neighbors"
	cap log close
	log using	"`out'/logs/metric_geo.log", text replace
	tempfile	map keys eth mwi ngr nga tza bridge found one coverage lpmap spmap


**********************************************************************
**# 1 - recover the household identifiers removed by the append scripts
**********************************************************************

* ethiopia's second and third waves use the wave-2 household identifier
	foreach w in 2 3 {
		use			household_id household_id2 year using ///
					"$data/merged_data/ethiopia/wave_`w'/essy`w'_merged", clear
		if `w' == 3 append using "`bridge'"
		save		"`bridge'", replace
	}
	keep if		household_id != ""
	rename		household_id2 eth_hh2
	isid		household_id year
	save		"`bridge'", replace
	use			"$data/results_data/additional_evidence/exhibit2/panel_keys", clear
	keep if		country == 1
	merge		1:1 household_id year using "`bridge'", ///
				keep(master match) keepusing(eth_hh2) nogen
	save		"`eth'"

* malawi's append IDs distinguish tracked units sharing a baseline case ID
	use			lp_id year y2_hhid y3_hhid y4_hhid using ///
				"$data/regression_data/malawi/mwi_lp", clear
	rename		(y2_hhid y3_hhid y4_hhid) (lp_y2 lp_y3 lp_y4)
	isid		lp_id year
	save		"`lpmap'"
	use			sp_id year y2_hhid y3_hhid y4_hhid using ///
				"$data/regression_data/malawi/mwi_sp", clear
	rename		(y2_hhid y3_hhid y4_hhid) (sp_y2 sp_y3 sp_y4)
	isid		sp_id year
	save		"`spmap'"
	use			mwi_id year dtype lp_id sp_id using ///
				"$data/regression_data/malawi/mwi_complete", clear
	merge		m:1 lp_id year using "`lpmap'", keep(master match) nogen
	merge		m:1 sp_id year using "`spmap'", keep(master match) nogen
	foreach w in 2 3 4 {
		gen str80	mwi_y`w' = cond(dtype == "lp", lp_y`w', sp_y`w')
	}
	rename		mwi_id country_id
	keep		country_id year mwi_y2 mwi_y3 mwi_y4
	isid		country_id year
	save		"`bridge'", replace
	use			"$data/results_data/additional_evidence/exhibit2/panel_keys", clear
	keep if		country == 2
	merge		1:1 country_id year using "`bridge'", ///
				keep(master match) keepusing(mwi_y2 mwi_y3 mwi_y4) nogen
	save		"`mwi'"

* niger retains the same grappe across waves; the user confirmed the EA linkage
	forvalues w = 1/2 {
		loc			extra = cond(`w' == 2, "extension", "")
		use			hid year clusterid `extra' using ///
					"$data/merged_data/niger/wave_`w'/ecvmay`w'_merged", clear
		if `w' == 2 drop if inlist(extension, "1", "2")
		rename		clusterid ngr_grappe
		keep		hid year ngr_grappe
		if `w' > 1 append using "`bridge'"
		save		"`bridge'", replace
	}
	isid		hid year
	use			"$data/results_data/additional_evidence/exhibit2/panel_keys", clear
	keep if		country == 4
	merge		1:1 hid year using "`bridge'", ///
				keep(master match) keepusing(ngr_grappe) nogen
	save		"`ngr'"

* nigeria's raw household identifier differs from the harmonized panel ID
	use			nga_id hhid year using ///
				"$data/regression_data/nigeria/nga_complete", clear
	rename		(nga_id hhid) (country_id nga_hhid)
	isid		country_id year
	save		"`bridge'", replace
	use			"$data/results_data/additional_evidence/exhibit2/panel_keys", clear
	keep if		country == 5
	merge		1:1 country_id year using "`bridge'", ///
				keep(master match) keepusing(nga_hhid) nogen
	save		"`nga'"

* recover the 2014 cluster identifiers separately for each tanzania panel
	loc			files npsy4 npsy4xp
	loc			clusters clusterid clusterid2014
	forvalues w = 4/5 {
		loc			j = `w' - 3
		loc			file : word `j' of `files'
		loc			cluster : word `j' of `clusters'
		use			y4_hhid `cluster' using ///
					"$data/merged_data/tanzania/wave_`w'/`file'_merged", clear
		rename		`cluster' tza_cluster
		keep		y4_hhid tza_cluster
		isid		y4_hhid
		save		"`one'", replace
		use			"$data/results_data/additional_evidence/exhibit2/panel_keys", clear
		keep if		country == 6 & wave == `w'
		merge		m:1 y4_hhid using "`one'", keep(master match) nogen
		if `w' > 4 append using "`bridge'"
		save		"`bridge'", replace
	}
	use			"$data/results_data/additional_evidence/exhibit2/panel_keys", clear
	keep if		country == 6 & !inlist(wave, 4, 5)
	append		using "`bridge'"
	isid		country hhid year
	save		"`tza'"

* uganda's 2013 geofile uses hh, while the panel key retains HHID
	use			HHID hh using ///
				"$data/merged_data/uganda/wave_4/unps4_merged", clear
	rename		(HHID hh) (hh_4_7 uga_hh4)
	isid		hh_4_7
	save		"`bridge'", replace
	use			"$data/results_data/additional_evidence/exhibit2/panel_keys", clear
	keep if		country == 7
	merge		m:1 hh_4_7 using "`bridge'", ///
				keep(master match) keepusing(uga_hh4) nogen
	append		using "`eth'" "`mwi'" "`ngr'" "`nga'" "`tza'"
	isid		country hhid year
	save		"`keys'"


**********************************************************************
**# 2 - read the released coordinate sources and join the recovered keys
**********************************************************************

* the map records real country-wave differences, not machine-specific paths
	import delimited using "$code/analysis/reg_code/metric_geo.csv", ///
				varnames(1) stringcols(3/9) clear
	gen int		map_id = _n
	gen byte	coordinates_available = lat_var != "" & lon_var != ""
	loc			nfiles = _N
	save		"`map'"

* initialize a crosswalk with the original key types
	use			"`keys'", clear
	keep		country hhid year wave
	keep if		0
	gen double	latitude = .
	gen double	longitude = .
	gen str80	source_ea = ""
	gen str200	raw_geofile = ""
	gen str80	geo_key = ""
	save		"`found'"
	forvalues i = 1/`nfiles' {
		use			"`map'", clear
		if !coordinates_available[`i'] continue
		loc			c = country[`i']
		loc			w = wave[`i']
		loc			file = raw_geofile[`i']
		loc			lat = lat_var[`i']
		loc			lon = lon_var[`i']
		loc			ea = ea_var[`i']
		loc			rawkey = raw_key[`i']
		loc			panelkey = panel_key[`i']
		use			"`keys'", clear
		keep if		country == `c' & wave == `w'
		egen		geo_key = concat(`panelkey'), format(%21.0g)
		replace		geo_key = strtrim(geo_key)
		keep		country hhid year wave geo_key
		save		"`one'", replace
		use			`rawkey' `lat' `lon' `ea' using "$raw/`file'", clear
		egen		geo_key = concat(`rawkey'), format(%21.0g)
		replace		geo_key = strtrim(geo_key)
		gen double	latitude = `lat'
		gen double	longitude = `lon'
		gen str80	source_ea = ""
		if "`ea'" != "" {
			drop		source_ea
			egen		source_ea = concat(`ea'), format(%21.0g)
			replace		source_ea = strtrim(source_ea)
		}
		keep		geo_key latitude longitude source_ea
		drop if		geo_key == "" | geo_key == "."
		isid		geo_key
		merge		1:m geo_key using "`one'", keep(match) nogen
		gen str200	raw_geofile = "`file'"
		append		using "`found'"
		save		"`found'", replace
	}

* overlapping source files must agree on a household's released coordinates
	use			"`found'", clear
	bysort country hhid year: assert latitude == latitude[1] & ///
				longitude == longitude[1]
	bysort country hhid year: keep if _n == 1
	merge		1:1 country hhid year using "`keys'", ///
				assert(match using) generate(geo_merge)
	gen byte	key_matched = geo_merge == 3
	drop		geo_merge


**********************************************************************
**# 3 - validate geography and preserve the wave-specific locations
**********************************************************************

	gen byte	coordinate_range = inrange(latitude, -90, 90) & ///
				inrange(longitude, -180, 180)
	gen byte	country_range = 0
	replace		country_range = inrange(latitude, 2, 16) & ///
				inrange(longitude, 31, 50) if country == 1
	replace		country_range = inrange(latitude, -19, -8) & ///
				inrange(longitude, 31, 37) if country == 2
	replace		country_range = inrange(latitude, 11, 24) & ///
				inrange(longitude, -1, 17) if country == 4
	replace		country_range = inrange(latitude, 3, 15) & ///
				inrange(longitude, 2, 16) if country == 5
	replace		country_range = inrange(latitude, -13, 1) & ///
				inrange(longitude, 28, 42) if country == 6
	replace		country_range = inrange(latitude, -2, 5) & ///
				inrange(longitude, 28, 36) if country == 7
	gen byte	geo_available = coordinate_range & country_range
	count if	!missing(latitude, longitude) & !geo_available
	list		country wave hhid latitude longitude if ///
				!missing(latitude, longitude) & !geo_available, noobs

* identical released positions can be aggregated without changing the kernel
* preserve source EA codes; use coordinate groups where EA codes are unreleased
	egen long	ea_wave_id = group(country wave source_ea latitude longitude) ///
				if geo_available, missing
	label var	ea_wave_id "Country-wave released EA/location group"
	label var	latitude "Publicly released modified latitude"
	label var	longitude "Publicly released modified longitude"
	bysort ea_wave_id: assert latitude == latitude[1] & ///
				longitude == longitude[1] if geo_available

* retain observed wave locations; Niger's shared grappe source is explicit in the map
	bysort country hhid (year): gen byte location_changed = ///
				(latitude != latitude[_n-1] | longitude != longitude[_n-1]) ///
				if _n > 1 & geo_available & geo_available[_n-1]
	compress
	save		"`out'/geovariables_crosswalk", replace
	merge		1:1 country hhid year using "$data/regression_data/lsms_panel", ///
				assert(match) nogen
	char _dta[geography] "Released modified coordinates; Niger uses stable grappe and the 2011 EA source in both waves"
	save		"`out'/lsms_panel_geo", replace


**********************************************************************
**# 4 - export the inventory and actual estimation-sample coverage
**********************************************************************

	egen byte	ea_tag = tag(country wave ea_wave_id) if geo_available
	gen byte	panel_obs = 1
	preserve
	collapse	(sum) households_matched = key_matched n_georef = geo_available ///
				distinct_eas = ea_tag panel_obs, by(country wave year)
	gen double	share_matched = households_matched / panel_obs
	gen double	share_georef = n_georef / panel_obs
	save		"`coverage'"
	restore

* the outcome-specific denominator is the existing first-stage sample
	keep		country hhid wave year geo_available lntf_yld lncp_yld
	rename		(lntf_yld lncp_yld) (yield1 yield2)
	reshape long yield, i(country hhid year) j(outcome)
	keep if		!missing(yield)
	gen byte	n_reg = 1
	egen byte	hh = tag(country wave outcome hhid)
	gen byte	geo_hh = hh * geo_available
	collapse	(sum) n_reg n_geo = geo_available hh geo_hh, ///
				by(country wave year outcome)
	gen double	share_georef = n_geo / n_reg
	gen str9	outcome_var = cond(outcome == 1, "lntf_yld", "lncp_yld")
	export delimited using "`out'/geo_merge_audit.csv", replace
	save		"`out'/geo_merge_audit", replace

* retain all active input folders, including files still being located
	use			"`map'", clear
	gen str80	coordinate_variable_names = lat_var + " " + lon_var
	gen str80	ea_id_variable = cond(ea_var == "", "Released Coordinate Group", ea_var)
	gen str80	household_join_key = raw_key + " -> " + panel_key
	bysort country wave (map_id): gen str2045 files = raw_geofile
	by country wave: replace files = files[_n-1] + "; " + raw_geofile if _n > 1
	by country wave: keep if _n == _N
	drop		raw_geofile map_id lat_var lon_var ea_var raw_key panel_key
	rename		files raw_geofile
	merge		1:1 country wave using "`coverage'", assert(match) nogen
	order		country wave year raw_geofile coordinate_variable_names ///
				ea_id_variable household_join_key coordinates_available ///
				distinct_eas households_matched share_matched n_georef share_georef
	export delimited using "`out'/geo_inventory.csv", replace
	save		"`out'/geo_inventory", replace
	list		country wave panel_obs n_georef share_georef, noobs
	log close

/* END */
