* Project: WB Weather - metric
* Created on: 31 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 31 Oct 2026
* Stata v.18

* does
	* estimates geographically held-out rainfall selection frontiers
	* saves candidate scores, choices, sample counts, and recorded folds

* assumes
	* projectdo.do has established the code, raw, and data globals
	* metric_keys.do has recovered the panel's geographic keys

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* use five allocations for the pilot, then twenty for the full analysis
*	do "$code/analysis/reg_code/metric_front.do" 5 20
	args reps orders
	if "`reps'" == "" loc reps = 20
	if "`orders'" == "" loc orders = 20
	loc			suffix = cond(`reps' == 20, "", "_pilot")
	loc			out "$data/results_data/additional_evidence/exhibit2"
	cap log close
	log using	"`out'/logs/metric_front`suffix'.log", text replace
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
**# 1 - candidate dictionary and geographically grouped folds
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
**# 2 - common samples and cached candidate scores
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
**# 3 - save results and compare the common sample with the existing fits
**********************************************************************

	foreach f in candidates selected baseline {
		frame `f' {
			merge		m:1 candidate using "`out'/candidates", ///
						assert(match) nogen
			gen str9	outcome_var = cond(outcome == 1, "lntf_yld", "lncp_yld")
			gen str4	spec_id = "reg" + string(spec)
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
	log close

/* END */
