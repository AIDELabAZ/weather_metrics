* Project: WB Weather - metric
* Created on: 27 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 27 Oct 2026
* Stata v.18.0

* does
	* bootstraps paired, signed reg2 minus reg7 rainfall coefficients
	* saves raw and standardized percentile intervals with restart checkpoints

* assumes
	* projectdo.do has established code and data
	* the panel and completed regression results describe the same sample

* TO DO:
	* select full mode explicitly for the production run


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths and open the log
	global		root	"$data/results_data"
	global		xfig	"$data/results_data/figures/metric_paper"
	global		logout	"$data/results_data/logs"
	cap log close
	log using	"$logout/cloudy_rainfall_fe_bootstrap", append

* arguments: mode, replications, countries, outcomes, weather variables
*	do metric_boot.do pilot 30 "1" "lncp_yld" "v01_rf1"
*	do metric_boot.do pilot 99 "1" "lncp_yld lntf_yld" "v01_rf*"
*	do metric_boot.do full 1000
	args mode reps countries outcomes weather
	if "`mode'" == "" loc mode pilot
	if !inlist("`mode'", "pilot", "full") error 198
	if "`reps'" == "" loc reps = cond("`mode'" == "pilot", 30, 1000)
	if "`countries'" == "" {
		loc			countries = cond("`mode'" == "pilot", "1", "1 2 4 5 6 7")
	}
	if "`outcomes'" == "" {
		loc			outcomes = cond("`mode'" == "pilot", ///
					"lncp_yld", "lncp_yld lntf_yld")
	}
	if "`weather'" == "" {
		loc			weather = cond("`mode'" == "pilot", "v01_rf1", "v*_rf*")
	}

* keep settings separate; increment revision after any estimation-code change
*	input changes stop reuse: remove that settings checkpoint to start afresh
	loc			base_seed = 20261027
	loc			revision = 1
	loc			min_success = .95
	loc			checkpoint ///
				"$root/rainfall_FE_bootstrap_`mode'_r`reps'_s`base_seed'_v`revision'.dta"
	loc			suffix = cond("`mode'" == "pilot", "_pilot", "")
	loc			backup = subinstr("`checkpoint'", ".dta", "_previous.dta", .)
	tempfile	cache draws pending


**********************************************************************
**# 1 - paired household bootstrap statistic
**********************************************************************

* the prefix assigns a fresh panel ID to each copy of a drawn household
	capture program drop cloudy_fe_difference
	program define cloudy_fe_difference, rclass
		args y x
		quietly xtset boot_hhid
		capture quietly xtreg `y' `x' i.year, fe
		if _rc {
			return scalar delta = .
			exit
		}
		if _se[`x'] == 0 {
			return scalar delta = .
			exit
		}
		loc			b2 = _b[`x']
		capture quietly reg `y' `x' i.year
		if _rc {
			return scalar delta = .
			exit
		}
		if _se[`x'] == 0 {
			return scalar delta = .
			exit
		}
		return scalar delta = `b2' - _b[`x']
	end


**********************************************************************
**# 2 - inventory and compatible checkpoints
**********************************************************************

* identify the actual estimation inputs, rather than relying on filenames
	use			hhid year country lncp_yld lntf_yld v*_rf* using ///
				"$data/regression_data/lsms_panel", clear
	datasignature
	loc			panel_signature "`r(datasignature)'"

* retain the full rainfall inventory before selecting the requested subset
	use			"$root/lsms_complete_results", clear
	keep if		paired_sample == 1 & inlist(spec_id, "reg2", "reg7") & ///
				inlist(outcome_var, "lncp_yld", "lntf_yld") & ///
				regexm(weather_var, "^v(0[1-9]|1[0-4])_rf[1-6]$")
	keep		country outcome_var weather_var spec_id beta obs nclusters estimable
	isid		country outcome_var weather_var spec_id
	datasignature
	loc			results_signature "`r(datasignature)'"
	rename		(beta obs nclusters estimable) (ref_beta ref_n ref_hh ref_ok)
	reshape wide ref_beta ref_n ref_hh ref_ok, ///
				i(country outcome_var weather_var) j(spec_id) string

* use the regression suffix mapping, verified in country append files
	gen byte	metric = real(substr(weather_var, 2, 2))
	gen byte	product = real(substr(weather_var, -1, 1))
	gen str8	product_name = ""
	loc			products ARC2 CHIRPS CPC ERA5 MERRA-2 TAMSAT
	forvalues p = 1/6 {
		loc			name : word `p' of `products'
		replace		product_name = "`name'" if product == `p'
	}

* select countries, outcomes and weather patterns without changing pair keys
	gen byte	selected = 0
	foreach c of numlist `countries' {
		foreach y of local outcomes {
			foreach x of local weather {
				replace		selected = 1 if country == `c' & ///
							outcome_var == "`y'" & strmatch(weather_var, "`x'")
			}
		}
	}
	keep if		selected
	drop		selected
	isid		country outcome_var weather_var
	loc			pairs = _N
	display		"Selected paired specifications: `pairs'"

* store point estimates, interval endpoints and the settings with every pair
	foreach v in beta_reg2 beta_reg7 delta_raw delta_std sd_weather sd_outcome ///
			scale ci_lo_raw ci_hi_raw ci_lo_std ci_hi_std boot_se_raw boot_se_std ///
			N N_clusters successful_reps failed_reps return_code seconds {
		gen double	`v' = .
	}
	gen int		requested_reps = `reps'
	gen long	seed = `base_seed' + country * 10000 + ///
				(outcome_var == "lntf_yld") * 1000 + metric * 10 + product
	gen str5	run_mode = "`mode'"
	gen str10	ci_method = "percentile"
	gen str24	status = ""
	gen str80	panel_signature = "`panel_signature'"
	gen str80	results_signature = "`results_signature'"

* rerun the same command to skip completed pairs with identical inputs
* recover the previous checkpoint if a crash interrupts the latest save
	capture confirm file "`checkpoint'"
	loc			resume = (_rc == 0)
	if !`resume' {
		capture confirm file "`backup'"
		loc			resume = (_rc == 0)
	}
	if `resume' {
		preserve
			capture use "`checkpoint'", clear
			if _rc {
				use			"`backup'", clear
				copy		"`backup'" "`checkpoint'", replace
				display		"Recovered the previous completed checkpoint."
			}
			assert		panel_signature == "`panel_signature'" & ///
						results_signature == "`results_signature'"
			keep if		status == "ok"
			save		"`cache'", replace
		restore
		merge 1:1 country outcome_var weather_var using "`cache'", ///
				update keep(1 3 4 5) nogen
	}
	count if	status == "ok"
	display		"Completed specifications reused: " r(N)


**********************************************************************
**# 3 - original paired estimates and standardization
**********************************************************************

	forvalues i = 1/`pairs' {
		if status[`i'] == "ok" continue
		loc			c = country[`i']
		loc			y = outcome_var[`i']
		loc			x = weather_var[`i']
		loc			ok2 = ref_okreg2[`i']
		loc			ok7 = ref_okreg7[`i']
		if `ok2' != 1 | `ok7' != 1 {
			replace		status = "non_estimable_reference" in `i'
			continue
		}
		preserve
			use			hhid year country `y' `x' using ///
						"$data/regression_data/lsms_panel", clear
			keep if		country == `c'
			quietly xtset hhid
			quietly xtreg `y' `x' i.year, fe vce(cluster hhid)
			keep if		e(sample)
			loc			b2 = _b[`x']
			loc			n2 = e(N)
			loc			h2 = e(N_clust)
			quietly reg `y' `x' i.year, vce(cluster hhid)
			loc			b7 = _b[`x']
			quietly summarize `x'
			loc			sdx = r(sd)
			quietly summarize `y'
			loc			sdy = r(sd)
		restore
		replace		beta_reg2 = `b2' in `i'
		replace		beta_reg7 = `b7' in `i'
		replace		N = `n2' in `i'
		replace		N_clusters = `h2' in `i'
		replace		sd_weather = `sdx' in `i'
		replace		sd_outcome = `sdy' in `i'
		replace		scale = sd_weather / sd_outcome in `i'
		replace		delta_raw = beta_reg2 - beta_reg7 in `i'
		replace		delta_std = delta_raw * scale in `i'
		replace		status = "ready" in `i'

		if missing(scale[`i']) | sd_weather[`i'] <= 0 | sd_outcome[`i'] <= 0 {
			replace		status = "invalid_standardization" in `i'
		}
	}


**********************************************************************
**# 4 - paired household resamples and percentile intervals
**********************************************************************

	forvalues i = 1/`pairs' {
		if status[`i'] != "ready" continue
		loc			c = country[`i']
		loc			y = outcome_var[`i']
		loc			x = weather_var[`i']
		loc			s = seed[`i']
		display		"Bootstrap `i'/`pairs': country `c', `y', `x'"
		preserve
			use			hhid year country `y' `x' using ///
						"$data/regression_data/lsms_panel", clear
			keep if		country == `c'
			quietly xtset hhid
			quietly xtreg `y' `x' i.year, fe
			keep if		e(sample)

		* initialize the ID for the observed-sample invocation of the prefix
			gen long	boot_hhid = hhid
			quietly xtset boot_hhid
			timer clear 91
			timer on 91
			capture noisily bootstrap delta = r(delta), reps(`reps') seed(`s') ///
				cluster(hhid) idcluster(boot_hhid) nodots nowarn notable ///
				saving("`draws'", double replace): cloudy_fe_difference `y' `x'
			loc			rc = _rc
			timer off 91
			quietly timer list 91
			loc			elapsed = r(t91)
			loc			nsuccess = 0
			loc			lo = .
			loc			hi = .
			loc			se = .
			if !`rc' {
				use			"`draws'", clear
				quietly summarize delta
				loc			nsuccess = r(N)
				loc			se = r(sd)
				quietly _pctile delta, p(2.5 97.5)
				loc			lo = r(r1)
				loc			hi = r(r2)
			}
		restore
		replace		return_code = `rc' in `i'
		replace		seconds = `elapsed' in `i'
		replace		successful_reps = `nsuccess' in `i'
		replace		failed_reps = requested_reps - successful_reps in `i'
		replace		boot_se_raw = `se' in `i'
		replace		ci_lo_raw = `lo' in `i'
		replace		ci_hi_raw = `hi' in `i'
		replace		boot_se_std = boot_se_raw * scale in `i'
		replace		ci_lo_std = ci_lo_raw * scale in `i'
		replace		ci_hi_std = ci_hi_raw * scale in `i'
		replace		status = cond(`rc', "bootstrap_error", ///
					cond(`nsuccess' >= `min_success' * `reps', "ok", "low_success")) in `i'

	* save every completed pair before starting the next one
	* keep the previous file intact while preparing its replacement
		preserve
			keep if		status != "" & status != "ready"
			capture confirm file "`checkpoint'"
			if !_rc append using "`checkpoint'"
			duplicates drop country outcome_var weather_var, force
			save		"`pending'", replace
			capture confirm file "`checkpoint'"
			if !_rc copy "`checkpoint'" "`backup'", replace
			copy		"`pending'" "`checkpoint'", replace
		restore
	}


**********************************************************************
**# 5 - results and runtime
**********************************************************************

* keep pilot outputs distinct from production results
	isid		country outcome_var weather_var
	save		"$root/rainfall_FE_bootstrap_differences`suffix'", replace
	tabulate	status, missing
	list		country outcome_var weather_var successful_reps failed_reps ///
				status if status != "ok", noobs
	quietly summarize seconds
	display		"Projected hours for 1,008 pairs at 1,000 reps: " ///
				%8.2f (r(mean) * 1008 * 1000 / `reps' / 3600)
	log close

* run the specification-chart file separately after estimation finishes

/* END */
