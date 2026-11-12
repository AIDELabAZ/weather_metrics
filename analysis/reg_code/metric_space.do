* Project: WB Weather - metric
* Created on: 31 Oct 2026
* Created by: codex
* Last updated: 12 Nov 2026
* Last updated by: codex
* Stata v.18

* does
	* estimates household and spatial precision on identical observations
	* saves first-stage scores and prespecified distance diagnostics

* assumes
	* project globals, metric_geo.do, and the original regression results

* TO DO:
	* rerun when the pending coordinate files are available


**********************************************************************
**# 0 - setup
**********************************************************************

* pilot: total rainfall and rainy days, all six products and both outcomes
	args mode
	if "`mode'" == "" loc mode full
	if !inlist("`mode'", "full", "pilot") error 198
	loc			suffix = cond("`mode'" == "pilot", "_pilot", "")
	loc			out "$data/results_data/additional_evidence/exhibit3"
	cap log close
	log using	"`out'/logs/metric_space`suffix'.log", text replace
	timer clear 1
	timer on 1
	tempfile	country dictionary
	capture mata: mata drop metric_distance() metric_neighbors() metric_save_neighbors() metric_spatial()
	do			"$code/analysis/reg_code/metric_front.do" routines
	do			"$code/analysis/reg_code/metric_space.mata"


**********************************************************************
**# 1 - candidate dictionary and long-format output files
**********************************************************************

	use			"$data/results_data/additional_evidence/exhibit2/candidates", clear
	if "`mode'" == "pilot" keep if inlist(metric, 5, 8)
	sort		candidate
	loc			nweather = _N
	loc			rain
	forvalues j = 1/`nweather' {
		loc			x = weather_var[`j']
		loc			rain `rain' `x'
	}
	save		"`dictionary'"
	tempname	fits diagnostics
	postfile	`fits' byte(country outcome spec metric product) str8 weather_var ///
				str24 status double(beta se_hh se_sp50 se_sp100 se_sp200 se_sp100_lag1 ///
				var_sp50 var_sp100 var_sp200 var_sp100_lag1 omega_hh omega_within_ea ///
				omega_pair50 omega_pair100 omega_pair200 omega_lag100 xx correction) ///
				long(n_geo households ea_years years) double rank_k long n_panel ///
				using "`out'/spatial_first_stage`suffix'", replace
	postfile	`diagnostics' byte(country outcome spec metric product band lag) ///
				str8 weather_var double(score_crossproduct pairs) using ///
				"`out'/score_correlogram`suffix'", replace


**********************************************************************
**# 2 - cache geographic neighbors and fit the matched models
**********************************************************************

	foreach c in 1 2 4 5 6 7 {
		use			"`out'/lsms_panel_geo", clear
		keep if		country == `c'
		quietly levelsof year, local(years)
		save		"`country'", replace
		keep if		geo_available
		capture frame drop neighbors
		frame create neighbors double(ea1 ea2 distance lag year1 year2)
		if _N > 0 {
			mata: metric_points = uniqrows(sort(st_data(., ///
				("ea_wave_id", "year", "latitude", "longitude")), (1, 2, 3, 4)))
			mata: metric_years = strtoreal(tokens(st_local("years")))
			mata: metric_pairs = metric_neighbors(metric_points, metric_years)
			mata: metric_save_neighbors(metric_points, metric_pairs)
		}
		frame neighbors {
			gen byte	country = `c'
			foreach b in 50 100 200 {
				gen double	weight`b' = max(1 - distance / `b', 0)
			}
			compress
			save		"`out'/neighbors/neighbors_`c'", replace
		}
		forvalues o = 1/2 {
			use			"`country'", clear
			loc			y = cond(`o' == 1, "lntf_yld", "lncp_yld")
			loc			name = cond(`o' == 1, "tf", "cp")
			keep if		!missing(`y')
			loc			n_panel = _N
			keep if		geo_available
			loc			n_geo = _N
			foreach s in 2 7 {
				if `n_geo' > 0 {
					capture drop q_*
					mata: metric_spatial(`s', metric_points, metric_pairs, metric_years)
				}
				forvalues j = 1/`nweather' {
					loc			x : word `j' of `rain'
					loc			m = real(substr("`x'", 2, 2))
					loc			p = real(substr("`x'", -1, 1))
					loc			status "no_coordinates"
					if `n_geo' > 0 {
						loc			status = cond(missing(sp_fit[`j', 1]), ///
								"no_within_variation", "ok")
					}
					loc			values
					forvalues col = 1/23 {
						if `n_geo' > 0 loc values `values' (sp_fit[`j', `col'])
						else if `col' >= 19 loc values `values' (0)
						else loc values `values' (.)
					}
					post		`fits' (`c') (`o') (`s') (`m') (`p') ///
							("`x'") ("`status'") `values' (`n_panel')
					if `n_geo' == 0 & inlist(`m', 5, 8) {
						forvalues lag = 0/1 {
							forvalues band = 1/5 {
								post `diagnostics' (`c') (`o') (`s') (`m') (`p') ///
									(`band') (`lag') ("`x'") (.) (0)
							}
						}
					}
				}
				if `n_geo' > 0 {
					forvalues d = 1/`=rowsof(sp_diag)' {
						loc			j = sp_diag[`d', 1]
						loc			x : word `j' of `rain'
						loc			m = real(substr("`x'", 2, 2))
						loc			p = real(substr("`x'", -1, 1))
						post		`diagnostics' (`c') (`o') (`s') (`m') (`p') ///
								(sp_diag[`d', 2]) (sp_diag[`d', 3]) ("`x'") ///
								(sp_diag[`d', 4]) (sp_diag[`d', 5])
					}
					if `s' == 2 {
						preserve
						keep		country hhid year wave ea_wave_id latitude longitude q_*
						gen str9	outcome_var = "`y'"
						gen str4	spec_id = "reg2"
						char _dta[scores] "q_<weather_var> is residualized rainfall times full regression residual"
						compress
						save		"`out'/scores/scores_`c'_`name'`suffix'", replace
						restore
					}
				}
				display		"Country `c', `y', reg`s': `n_geo' georeferenced observations."
			}
		}
	}
	postclose	`fits'
	postclose	`diagnostics'


**********************************************************************
**# 3 - retain calculation warnings and the original-sample comparison
**********************************************************************

	use			"`out'/spatial_first_stage`suffix'", clear
	gen str9	outcome_var = cond(outcome == 1, "lntf_yld", "lncp_yld")
	gen str4	spec_id = "reg" + string(spec)
	foreach v in hh sp50 sp100 sp200 sp100_lag1 {
		gen double	t_`v' = beta / se_`v' if se_`v' > 0 & se_`v' < .
	}
	foreach b in sp50 sp100 sp200 sp100_lag1 {
		gen byte	bad_`b' = var_`b' <= 0 & var_`b' < .
		count if	bad_`b'
	}
	count if	status != "ok"
	isid		country outcome_var weather_var spec_id
	label var	omega_within_ea "Contemporaneous within-location cross-household score covariance"
	label var	omega_lag100 "Adjacent-interval cross-household addition; temporal weight 0.5"
	label var	correction "Household-cluster finite-sample factor applied to all covariance components"
	save		"`out'/spatial_first_stage`suffix'", replace
	export delimited using "`out'/spatial_first_stage`suffix'.csv", replace
	tempfile	spatial
	save		"`spatial'"
	use			"$data/results_data/reg_results", clear
	keep if		inlist(regname, "reg2", "reg7") & ///
				regexm(weather_var, "^v(0[1-9]|1[0-4])_rf[1-6]$")
	if "`mode'" == "pilot" keep if inlist(varname, "v05", "v08")
	gen str9	outcome_var = cond(depvar == "tf", "lntf_yld", "lncp_yld")
	rename		regname spec_id
	rename		(betarain serain obs) (beta_original se_original n_original)
	keep		country outcome_var weather_var spec_id *_original
	merge		1:1 country outcome_var weather_var spec_id using "`spatial'", ///
				assert(match) nogen
	gen double	beta_geo_change = beta - beta_original
	gen double	se_geo_change = se_hh - se_original
	gen long	n_geo_excluded = n_original - n_geo
	export delimited using "`out'/geo_model_comparison`suffix'.csv", replace
	timer off 1
	timer list 1
	log close

/* END */
