* project: wb weather - metric
* created on: 31 oct 2026
* created by: codex
* edited on: 12 nov 2026
* edited by: chatgpt
* Stata v.18

* does
	* reconstruct household and geographic keys and original rainfall missingness
	* estimate candidate instrument scores in training and held-out samples
	* simulate instrument search and produce frontier figures and summaries

* assumes
	* projectdo.do has set the code, raw, and data globals
	* country append and panel build files have produced their inputs
	* supporting metric_fe.mata, metric_front.mata, and metric_palette.do exist

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* accept optional keys-only mode and define output paths
	args		reps orders
	loc			out "$data/results_data/additional_evidence/exhibit2"
	capture mkdir "$data/results_data/additional_evidence"
	capture mkdir "`out'"
	capture mkdir "`out'/logs"
	cap		log close
	log		using "`out'/logs/metric_front.log", text append
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

* stop after rebuilding keys when called for spatial analysis
	if "`reps'" == "keys" {
		log		close
		exit
	}


**********************************************************************
**# 8 - configure instrument search
**********************************************************************

* use 20 allocations and 20 orderings by default; five allocations for the pilot

	if "`reps'" == "" loc reps = 20
	if "`orders'" == "" loc orders = 20
	loc			suffix = cond(`reps' == 20, "", "_pilot")
	loc			out "$data/results_data/additional_evidence/exhibit2"

	timer clear 1
	timer on 1
	tempfile	panel assignments common

* load the fixed-effects and selection calculations
	capture mata: mata drop metric_sums() metric_demean() metric_resid() metric_stats()
	capture mata: mata drop metric_root() metric_blocks() metric_folds()
	capture mata: mata drop metric_choices() metric_add() metric_front()
	do			"$code/analysis/reg_code/metric_fe.mata"
	do			"$code/analysis/reg_code/metric_front.mata"


**********************************************************************
**# 9 - candidate dictionary and geographically grouped folds
**********************************************************************

* verify the suffix mapping against the current country append files
	clear
	set obs		84
	gen byte	candidate = _n
	gen byte	metric = ceil(candidate / 6)
	gen byte	product = mod(candidate - 1, 6) + 1
	gen str8	weather_var = "v" + string(metric, "%02.0f") + ///
				"_rf" + string(product)
	gen str8	product_name = ""
	loc			products ARC2 CHIRPS CPC ERA5 MERRA-2 TAMSAT
	forvalues p = 1/6 {
		loc			name : word `p' of `products'
		replace		product_name = "`name'" if product == `p'
	}
	isid		weather_var
	save		"`out'/candidates", replace
	export delimited using "`out'/candidates.csv", replace
	loc			rain
	forvalues j = 1/84 {
		loc			x = weather_var[`j']
		loc			rain `rain' `x'
	}

* connect households that share any observed EA-wave or parish-wave block
	use			"`out'/panel_keys", clear
	egen		ea_wave_id = group(country wave ea_key)
	gen long	block = .
	mata: metric_blocks()
	egen		stratum_id = group(country stratum)
	sort		block hhid year
	by block: replace stratum_id = stratum_id[1]
	keep		country hhid block stratum_id
	duplicates drop
	isid		hhid
	save		"`assignments'"
	contract	country block stratum_id, freq(nhh)
	forvalues r = 1/20 {
		set seed	`=20261031 + `r''
		gen byte	fold`r' = .
		mata: metric_folds("fold`r'")
	}
	merge		1:m country block stratum_id using "`assignments'", nogen
	isid		country hhid
	char _dta[fold_seed] "Allocation r uses seed 20261031+r; 20 allocations"
	char _dta[grouping] "Connected household/EA-wave groups; Uganda parish-wave blocks"
	save		"`out'/folds", replace
	keep		country hhid block fold*
	save		"`assignments'", replace

* retain the existing outcome transformations and weather values
	use			country hhid year lntf_yld lncp_yld `rain' using ///
				"$data/regression_data/lsms_panel", clear
	isid		country hhid year
	merge		1:1 country hhid year using "`out'/panel_keys", ///
				keepusing(wave ea_key rain_missing) assert(match) nogen
	merge		m:1 country hhid using "`assignments'", assert(match) nogen
	egen		missing_now = rowmiss(`rain')
	gen byte	weather_ok = rain_missing == 0 & missing_now == 0
	save		"`panel'"


**********************************************************************
**# 10 - common samples and cached candidate scores
**********************************************************************

* keep score and selection records separate from the observation-level panel
	foreach f in candidates selected split_audit baseline {
		capture frame drop `f'
	}
	frame create candidates double(country outcome spec rep fold candidate ///
		beta_train se_train t_train r_train xx_train beta_valid se_valid ///
		t_valid r_valid n_train n_valid hh_train hh_valid xx_valid)
	frame create selected double(country outcome spec rep fold ordering rule k ///
		candidate beta_train se_train t_train r_train beta_valid se_valid ///
		t_valid r_valid strength_train strength_valid gap reversal pass196 ///
		pass481 rank direction estimable_prefix n_train n_valid hh_train hh_valid)
	frame create split_audit double(country outcome spec rep fold n_train n_valid ///
		hh_train hh_valid years_train years_valid accepted)
	frame create baseline double(country outcome spec candidate beta se t corr n hh years)
	tempname	samples
	postfile	`samples' byte(country outcome) long(n_panel n_outcome ///
				n_weather n_single n_common households eas years) using ///
				"`out'/sample_audit`suffix'", replace
	loc			foldvars
	forvalues r = 1/`reps' {
		loc			foldvars `foldvars' fold`r'
	}
	foreach c in 1 2 4 5 6 7 {
		forvalues o = 1/2 {
			use			"`panel'", clear
			keep if		country == `c'
			loc			n_panel = _N
			loc			y = cond(`o' == 1, "lntf_yld", "lncp_yld")
			drop if		missing(`y')
			loc			n_outcome = _N
			keep if		weather_ok
			loc			n_weather = _N
			bysort hhid: gen int waves = _N
			quietly count if waves == 1
			loc			n_single = r(N)
			keep if		waves >= 2
			loc			n_common = _N
			egen		hh_tag = tag(hhid)
			quietly count if hh_tag
			loc			hh = r(N)
			egen		ea_tag = tag(wave ea_key)
			quietly count if ea_tag
			loc			eas = r(N)
			quietly levelsof year, local(years)
			loc			nyears : word count `years'
			post		`samples' (`c') (`o') (`n_panel') (`n_outcome') ///
						(`n_weather') (`n_single') (`n_common') (`hh') ///
						(`eas') (`nyears')
			mata: metric_front(`c', `o', `reps', `orders')
		}
	}
	postclose	`samples'


**********************************************************************
**# 11 - save results and compare the common sample with the existing fits
**********************************************************************

	foreach f in candidates selected baseline {
		frame `f' {
			merge		m:1 candidate using "`out'/candidates", ///
						assert(match) nogen
			gen str9	outcome_var = cond(outcome == 1, "lntf_yld", "lncp_yld")
			gen str4	spec_id = "reg" + string(spec)
			if "`f'" == "candidates" {
				isid		country outcome_var weather_var spec_id rep fold
				count if	missing(se_train, r_train, se_valid, r_valid)
			}
			if "`f'" == "selected" {
				isid		country outcome_var spec_id rep fold ordering rule k
				count if	missing(strength_train, strength_valid, t_valid)
			}
			if "`f'" == "baseline" isid country outcome_var weather_var spec_id
			compress
			loc			name = cond("`f'" == "candidates", ///
						"candidate_scores", cond("`f'" == "selected", ///
						"selected_instruments", "baseline_common"))
			save		"`out'/`name'`suffix'", replace
		}
	}
	frame split_audit {
		list		country outcome spec rep fold if !accepted, noobs
		save		"`out'/split_audit`suffix'", replace
		export delimited using "`out'/split_audit`suffix'.csv", replace
	}

* compare every common-sample fit with its original regression-result row
	use			"$data/results_data/reg_results", clear
	keep if		inlist(regname, "reg2", "reg7") & ///
				regexm(weather_var, "^v(0[1-9]|1[0-4])_rf[1-6]$")
	gen str9	outcome_var = cond(depvar == "tf", "lntf_yld", "lncp_yld")
	rename		regname spec_id
	rename		(betarain serain obs nclusters) (beta_original se_original n_original hh_original)
	keep		country outcome_var weather_var spec_id *_original
	merge		1:1 country outcome_var weather_var spec_id using ///
				"`out'/baseline_common`suffix'", assert(match) nogen
	gen double	beta_change = beta - beta_original
	gen double	se_change = se - se_original
	gen long	n_excluded = n_original - n
	save		"`out'/baseline_comparison`suffix'", replace
	export delimited using "`out'/baseline_comparison`suffix'.csv", replace
	use			"`out'/sample_audit`suffix'", clear
	list, noobs
	export delimited using "`out'/sample_audit`suffix'.csv", replace
	timer off 1
	timer list 1


* pilot runs save separate results and do not regenerate the full figures
	if `reps' != 20 | `orders' != 20 {
		log		close
		exit
	}


**********************************************************************
**# 12 - configure frontier figures
**********************************************************************

	loc			root "$data/results_data/additional_evidence/exhibit2"
	loc			xfig "$data/results_data/figures/metric_paper"

	include		"$code/analysis/viz_code/metric_palette.do"
	tempfile	selected splits front
	loc			frame scheme(stcolor) graphregion(color(white)) ///
				plotregion(color(white) lstyle(none))
	loc			ticks labsize(2.5) labcolor("38 43 47") tlcolor("38 43 47")
	loc			grid grid glcolor("231 234 237") glpattern(solid) glwidth(vthin)


**********************************************************************
**# 13 - split summaries and descriptive denominators
**********************************************************************

	use			"`root'/selected_instruments", clear
	gen byte	attempts = 1
	gen byte	valid = !missing(strength_train, strength_valid, t_valid)
	count if	!valid
	list		country outcome_var spec_id rep fold k weather_var if !valid, noobs
	foreach v in reversal pass196 pass481 {
		replace		`v' = . if !valid
	}
	save		"`selected'"

* first summarize the candidate orderings within each held-out fold
	collapse	(median) strength_train strength_valid gap ///
				(mean) reversal pass196 pass481 ///
				(sum) attempts valid, by(country outcome spec rule rep fold k)
	save		"`splits'"
	collapse	(p10) lo_train = strength_train lo_valid = strength_valid ///
				(p50) train = strength_train valid_corr = strength_valid gap ///
				(p90) hi_train = strength_train hi_valid = strength_valid ///
				(mean) reversal pass196 pass481 ///
				(sum) attempts valid, by(country outcome spec rule k)
	foreach v in reversal pass196 pass481 {
		replace		`v' = 100 * `v'
	}
	gen long	invalid = attempts - valid
	gen str9	outcome_var = cond(outcome == 1, "lntf_yld", "lncp_yld")
	gen str4	spec_id = "reg" + string(spec)
	gen str20	selection_rule = cond(rule == 1, "Partial Correlation", "Household-Clustered T")
	label define country 1 "{bf:Ethiopia}" 2 "{bf:Malawi}" ///
				4 "{bf:Niger}" 5 "{bf:Nigeria}" 6 "{bf:Tanzania}" 7 "{bf:Uganda}"
	label values country country
	decode		country, gen(country_name)
	replace		country_name = subinstr(country_name, "{bf:", "", .)
	replace		country_name = subinstr(country_name, "}", "", .)
	char _dta[bands] "10th-90th percentiles across held-out folds; descriptive dispersion"
	char _dta[shares] "Equal weight to folds; denominator is valid selected records in each fold"
	save		"`root'/selection_frontier", replace
	save		"`front'"
	keep if		inlist(k, 1, 10, 84)
	export delimited using "`root'/front_table.csv", nolabel replace

* distinguish the search increment from the gap for a prespecified candidate
	use			"`selected'", clear
	keep if		inlist(k, 1, 84)
	keep		country outcome spec rule rep fold ordering k gap
	reshape wide gap, i(country outcome spec rule rep fold ordering) j(k)
	gen double	increment = gap84 - gap1
	gen byte	valid = !missing(increment)
	collapse	(median) increment (sum) valid, by(country outcome spec rule)
	export delimited using "`root'/front_increment.csv", replace


**********************************************************************
**# 14 - selection frontiers with descriptive dispersion bands
**********************************************************************

* both outcomes and all countries use the same vertical scale
	use			"`front'", clear
	loc			ymin = -.1
	loc			ymax = .4
	foreach view in main year {
		loc			spec = cond("`view'" == "year", 7, 2)
		loc			prefix = cond("`view'" == "main", "front", "front_`view'")
		forvalues o = 1/2 {
			loc			outcome = cond(`o' == 1, "value", "maize")
			preserve
			keep if		spec == `spec' & outcome == `o' & rule == 1
			* clip the displayed band; saved percentile values remain unchanged
			replace		lo_valid = max(lo_valid, `ymin') if !missing(lo_valid)
			twoway		(rarea lo_train hi_train k, sort color("`arc2'%18")) ///
						(rarea lo_valid hi_valid k, sort color("`era5'%18")) ///
						(line train k, sort lcolor("`arc2'") lwidth(medium)) ///
						(line valid_corr k, sort lcolor("`era5'") ///
						lpattern(dash) lwidth(medium)), ///
						`frame' xscale(log) ///
						xlabel(1 2 3 5 10 20 40 60 84, nogrid labsize(2.2) ///
						labcolor("38 43 47") tlcolor("38 43 47")) ///
						ylabel(`ymin'(.1)`ymax', format(%4.1f) `grid' `ticks') ///
						xtitle("Number Of Candidate Instruments Considered", size(3)) ///
						ytitle("Selected First-Stage Partial Correlation", size(3)) ///
						yline(0, lcolor("140 140 140") lwidth(vthin)) ///
						legend(order(3 "Selected In Training" ///
						4 "Same Instrument In Held-Out Data") ///
						rows(1) size(2.8) region(lstyle(none))) ///
						subtitle(, size(2.8) nobox fcolor(white)) ///
						by(country, cols(3) iscale(1) legend(pos(6)) ///
						note("") graphregion(color(white)) imargin(small)) ///
						xsize(9) ysize(5.5)
			graph export "`xfig'/`prefix'_`outcome'.pdf", replace
			graph export "`xfig'/`prefix'_`outcome'.png", width(3200) replace
			restore
		}
	}


**********************************************************************
**# 15 - selection frequencies among all eighty-four candidates
**********************************************************************

	use			"`selected'", clear
	keep if		k == 84 & spec == 2 & rule == 1 & valid

* count all orderings so exact ties do not give extra weight to a fold
	contract	country outcome candidate, freq(selected)
	tempfile	frequency
	save		"`frequency'"
	keep		country outcome
	duplicates drop
	cross using	"`root'/candidates"
	merge		1:1 country outcome candidate using "`frequency'", nogen
	replace		selected = 0 if missing(selected)
	bysort country outcome: egen total = total(selected)
	gen double	share = 100 * selected / total
	gen byte	shade = ceil(share / 10)
	label define country 1 "{bf:Ethiopia}" 2 "{bf:Malawi}" ///
				4 "{bf:Niger}" 5 "{bf:Nigeria}" 6 "{bf:Tanzania}" 7 "{bf:Uganda}", replace
	label values country country
	save		"`root'/choice_frequency", replace
	export delimited using "`root'/choice_frequency.csv", replace


**********************************************************************
**# 16 - end matter
**********************************************************************

* close the log
	log		close

/* END */

