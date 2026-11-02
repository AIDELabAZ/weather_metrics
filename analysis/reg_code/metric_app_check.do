* Project: WB Weather - metric
* Created on: 2 Nov 2026
* Created by: codex
* edited by: codex
* edited on: 2 Nov 2026
* Stata v.18

* does
	* checks the saved appendix quantities and their estimation samples
	* runs direct first-stage fits and the prescribed small covariance example

* assumes
	* project globals and completed metric_app.do tables

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

	loc			front "$data/results_data/additional_evidence/exhibit2"
	loc			space "$data/results_data/additional_evidence/exhibit3"
	loc			out "$data/results_data/additional_evidence/appendix"
	cap log close
	log using	"`out'/metric_app_check.log", text replace
	tempfile	medians panel source chosen
	capture mata: mata drop metric_sums() metric_demean() metric_resid() metric_stats()
	capture mata: mata drop metric_root() metric_blocks() metric_folds()
	capture mata: mata drop metric_choices() metric_add() metric_front()
	capture mata: mata drop metric_distance() metric_neighbors() metric_save_neighbors() metric_spatial()
	do			"$code/analysis/reg_code/metric_fe.mata"
	do			"$code/analysis/reg_code/metric_front.mata"
	do			"$code/analysis/reg_code/metric_space.mata"


**********************************************************************
**# 1 - recorded candidate grids, nested searches, and plotted medians
**********************************************************************

	use			"`front'/candidates", clear
	isid		candidate
	isid		weather_var
	assert		_N == 84
	assert		weather_var == "v" + string(metric, "%02.0f") + "_rf" + string(product)
	sort		candidate
	loc			rain
	forvalues j = 1/84 {
		loc			x = weather_var[`j']
		loc			rain `rain' `x'
	}
	use			"`front'/candidate_scores", clear
	isid		country outcome spec rep fold candidate
	assert		_N == 201600
	bysort country outcome spec rep fold: assert _N == 84
	count if	missing(r_train, r_valid, se_train, se_valid)
	display		"Candidate records with undefined estimates: " r(N)
	use			"`front'/selected_instruments", clear
	isid		country outcome spec rep fold ordering rule k
	assert		_N == 864000
	assert		inrange(rep, 1, 20) & inrange(fold, 1, 5) & inrange(ordering, 1, 20)
	assert		inlist(k, 1, 2, 3, 5, 10, 20, 40, 60, 84)
	count if	missing(strength_train, strength_valid, t_valid)
	display		"Selected records with undefined validation statistics: " r(N)
	bysort country outcome spec rep fold ordering rule (k): ///
				assert strength_train >= strength_train[_n-1] - 1e-12 if ///
				rule == 1 & _n > 1 & !missing(strength_train, strength_train[_n-1])
	gen double	train_abs_t = abs(t_train)
	by country outcome spec rep fold ordering rule: ///
				assert train_abs_t >= train_abs_t[_n-1] - 1e-10 if ///
				rule == 2 & _n > 1 & !missing(train_abs_t, train_abs_t[_n-1])
	keep if		rule == 1
	collapse	(median) strength_train strength_valid, ///
				by(country outcome spec rep fold k)
	collapse	(median) train_check = strength_train valid_check = strength_valid, ///
				by(country outcome spec k)
	save		"`medians'"
	use			"`front'/selection_frontier", clear
	keep if		rule == 1
	merge		1:1 country outcome spec k using "`medians'", assert(match) nogen
	assert		reldif(train, train_check) < 1e-12
	assert		reldif(valid_corr, valid_check) < 1e-12
	display		"All 216 primary frontier medians reproduce the saved plotting data."


**********************************************************************
**# 2 - household/EA-wave leakage and unchanged outcome columns
**********************************************************************

	use			"`front'/panel_keys", clear
	isid		country hhid year
	merge		m:1 country hhid using "`front'/folds", assert(match) nogen
	forvalues r = 1/20 {
		bysort country hhid: assert fold`r' == fold`r'[1]
		bysort country wave ea_key: assert fold`r' == fold`r'[1]
		bysort country block: assert fold`r' == fold`r'[1]
	}
	display		"All 20 allocations keep households and connected EA-wave groups together."
	use			country hhid year lntf_yld lncp_yld using ///
				"$data/regression_data/lsms_panel", clear
	rename		(lntf_yld lncp_yld) (value_original maize_original)
	merge		1:1 country hhid year using "`space'/lsms_panel_geo", ///
				assert(match) nogen
	assert		lntf_yld == value_original
	assert		lncp_yld == maize_original
	display		"All 54,237 panel keys and both outcome columns are unchanged."


**********************************************************************
**# 3 - saved paired percentages and variance decomposition
**********************************************************************

	use			"`out'/spatial_variance_components", clear
	isid		country outcome_var weather_var spec_id
	assert		_N == 2016
	assert		reldif(v_sp100, v_hh + v_add_ea + v_add_between) < 1e-10
	count if	v_add_ea < 0
	display		"Negative within-EA additions retained: " r(N)
	count if	v_add_between < 0
	display		"Negative between-EA additions retained: " r(N)
	use			"`out'/spatial_bandwidth_audit", clear
	keep if		outcome == 0
	rename		(share_hh share_sp n_matched) (hh_check spatial_check matched_check)
	keep		country spec bandwidth threshold hh_check spatial_check matched_check
	save		"`source'", replace
	use			"`space'/spatial_shares", clear
	merge		1:1 country spec bandwidth threshold using "`source'", assert(match) nogen
	assert		reldif(share_hh, hh_check) < 1e-12
	assert		reldif(share_sp, spatial_check) < 1e-12
	assert		n_matched == matched_check
	assert		n_matched == 168 if bandwidth == "100"
	display		"All saved shares reproduce; primary matched denominators are 168."


**********************************************************************
**# 4 - verify the SDD source vintage and current EA link
**********************************************************************

	use			"`space'/geovariables_crosswalk", clear
	keep if		country == 6 & wave == 6 & geo_available
	isid		sdd_hhid
	assert		_N == 168
	quietly count if raw_geofile == "tanzania/wave_3/raw/HouseholdGeovars_Y3.dta"
	assert		r(N) == 120
	quietly count if raw_geofile == "tanzania/wave_1/raw/HH.Geovariables_Y1.dta"
	assert		r(N) == 48
	save		"`panel'", replace
	use			sdd_hhid region district ward ea using ///
				"$data/refined_data/tanzania/wave_6/hhfinal_npsy5sdd", clear
	replace		district = district - 10 * region
	rename		(region district ward ea) (current_region current_district current_ward current_ea)
	save		"`source'", replace
	foreach w in 3 1 {
		loc			id = cond(`w' == 1, "hhid", "y3_hhid")
		use			`id' region district ward ea using ///
					"$data/refined_data/tanzania/wave_`w'/HH_SECA", clear
		rename		`id' sdd_y`w'
		save		"`chosen'", replace
		use			"`panel'", clear
		keep if		sdd_y`w' != ""
		merge		m:1 sdd_y`w' using "`chosen'", keep(master match) assert(match using) nogen
		merge		1:1 sdd_hhid using "`source'", keep(master match) assert(match using) nogen
		foreach v in region district ward ea {
			assert		`v' == current_`v' & !missing(`v')
		}
	}
	display		"SDD: 168 unique matches, 120 from 2012 and 48 from 2008; current EA agrees."


**********************************************************************
**# 5 - prespecified direct first-stage fits on the actual common sample
**********************************************************************

	capture frame drop app_ref
	frame create app_ref
	frame app_ref: use "`space'/spatial_first_stage", clear
	use			"`space'/lsms_panel_geo", clear
	tempname	fits
	postfile	`fits' byte(country outcome spec) str8 weather_var ///
				double(beta_stata beta_saved se_stata se_saved repeat_relative_error) long n ///
				using "`out'/direct_stata_audit", replace
	loc			checked = 0
	foreach c in 1 4 6 {
		forvalues o = 1/2 {
			preserve
			loc			y = cond(`o' == 1, "lntf_yld", "lncp_yld")
			keep if		country == `c' & geo_available & !missing(`y')
			xtset		hhid
			foreach x in v05_rf2 v08_rf2 {
				foreach s in 2 7 {
					if `s' == 2 quietly xtreg `y' `x' i.year, fe vce(cluster hhid)
					if `s' == 7 quietly regress `y' `x' i.year, vce(cluster hhid)
					loc			b = _b[`x']
					loc			se = _se[`x']
					loc			n = e(N)
					mata: app_a = st_data(., tokens(st_local("y") + " " + st_local("x")))
					mata: app_repeat = metric_stats(app_a, st_data(., "hhid"), st_data(., "year"), strtoreal(st_local("s")))
					mata: st_numscalar("app_repeat_error", mreldif(app_repeat, metric_stats(app_a, st_data(., "hhid"), st_data(., "year"), strtoreal(st_local("s")))))
					assert		app_repeat_error < 1e-12
					frame app_ref: quietly summarize beta if country == `c' & ///
							outcome == `o' & spec == `s' & weather_var == "`x'"
					loc			b_saved = r(mean)
					assert		abs(`b' - `b_saved') < 1e-8 * max(1e-8, abs(`b'))
					frame app_ref: quietly summarize se_hh if country == `c' & ///
							outcome == `o' & spec == `s' & weather_var == "`x'"
					loc			se_saved = r(mean)
					assert		abs(`se' - `se_saved') < 1e-8 * abs(`se')
					frame app_ref: quietly summarize n_geo if country == `c' & ///
							outcome == `o' & spec == `s' & weather_var == "`x'"
					assert		`n' == r(mean)
					post		`fits' (`c') (`o') (`s') ("`x'") ///
							(`b') (`b_saved') (`se') (`se_saved') (app_repeat_error) (`n')
					loc			checked = `checked' + 1
				}
			}
			restore
		}
	}
	postclose	`fits'
	use			"`out'/direct_stata_audit", clear
	export delimited using "`out'/direct_stata_audit.csv", replace
	display		"Direct Stata coefficients, clustered SEs and N agree in `checked' fits."


**********************************************************************
**# 6 - replay recorded candidate orderings deterministically
**********************************************************************

	use			"`front'/selected_instruments", clear
	keep if		country == 4 & outcome == 1 & rep == 1 & fold == 1
	save		"`chosen'", replace
	foreach s in 2 7 {
		use			"`front'/candidate_scores", clear
		keep if		country == 4 & outcome == 1 & rep == 1 & fold == 1 & spec == `s'
		sort		candidate
		mata: app_train = st_data(., tokens("beta_train se_train t_train r_train xx_train"))
		mata: app_valid = st_data(., tokens("beta_valid se_valid t_valid r_valid xx_valid"))
		mata: rseed(20261031 + 4 * 10000 + 100 + 1)
		mata: app_choice1 = metric_choices(app_train, app_valid, 20)
		mata: rseed(20261031 + 4 * 10000 + 100 + 1)
		mata: app_choice2 = metric_choices(app_train, app_valid, 20)
		mata: assert(sum(vec(app_choice1 :!= app_choice2)) == 0)
		use			"`chosen'", clear
		keep if		spec == `s'
		sort		ordering rule k
		loc			cols ordering rule k candidate beta_train se_train t_train r_train ///
					beta_valid se_valid t_valid r_valid strength_train strength_valid ///
					gap reversal pass196 pass481 rank direction estimable_prefix
		mata: assert(mreldif(app_choice1, st_data(., tokens(st_local("cols")))) < 1e-12)
	}
	display		"Recorded seed reproduces all 720 choices in both models; repeated run identical."


**********************************************************************
**# 7 - hand-checkable covariance example with a mover and serial dependence
**********************************************************************

	clear
	input hhid year v05_rf2 v08_rf2 lntf_yld latitude longitude ea_wave_id
	1 1 1 4 3 0 0 1
	1 2 3 1 7 0 0 4
	2 1 2 3 6 0 0 1
	2 2 5 6 9 0 .2 5
	3 1 3 2 4 0 .2 2
	3 2 4 5 8 0 .2 5
	4 1 2 5 8 0 .2 2
	4 2 6 3 7 0 .2 5
	5 1 4 6 9 0 1 3
	5 2 3 5 6 0 1 6
	6 1 6 1 7 0 1 3
	6 2 2 4 5 0 1 6
	end
	loc			rain v05_rf2 v08_rf2
	loc			y lntf_yld
	mata: app_points = uniqrows(sort(st_data(., ("ea_wave_id", "year", "latitude", "longitude")), (1, 2, 3, 4)))
	mata: app_years = (1, 2)
	mata: app_pairs = metric_neighbors(app_points, app_years)
	mata: metric_spatial(2, app_points, app_pairs, app_years)
	xtset		hhid
	foreach x in v05_rf2 v08_rf2 {
		quietly xtreg lntf_yld `x' i.year, fe vce(cluster hhid)
		predict double app_u, e
		quietly xtreg `x' i.year, fe
		predict double app_z, e
		gen double	check_`x' = app_u * app_z
		clonevar	check_z_`x' = app_z
		assert		abs(check_`x' - q_`x') < 1e-10
		drop		app_u app_z
	}

* independent ordered observation pairs; equatorial distances are exact arc lengths
mata:
	app_q = st_data(., ("check_v05_rf2", "check_v08_rf2"))
	app_fit = st_matrix("sp_fit")
	app_xx = colsum(st_data(., ("check_z_v05_rf2", "check_z_v08_rf2")):^2)'
	app_scale = ((6 / 5) * (11 / 9)) :/ (app_xx:^2)
	app_h = st_data(., "hhid")
	app_t = st_data(., "year")
	app_lon = st_data(., "longitude")
	app_loc = st_data(., "ea_wave_id")
	app_raw = J(2, 6, 0)
	app_bw = (50, 100, 200)
	for (app_i = 1; app_i <= rows(app_q); app_i++) {
		for (app_j = 1; app_j <= rows(app_q); app_j++) {
			app_product = (app_q[app_i, .] :* app_q[app_j, .])'
			app_d = abs(app_lon[app_i] - app_lon[app_j]) * pi() / 180 * 6371.0088
			if (app_h[app_i] == app_h[app_j]) app_raw[, 1] = app_raw[, 1] + app_product
			if (app_t[app_i] == app_t[app_j] & app_h[app_i] != app_h[app_j]) {
				if (app_loc[app_i] == app_loc[app_j]) app_raw[, 2] = app_raw[, 2] + app_product
				else {
					for (app_b = 1; app_b <= 3; app_b++) {
						app_raw[, app_b+2] = app_raw[, app_b+2] +
							max((0, 1-app_d/app_bw[app_b])) * app_product
					}
				}
			}
			if (abs(app_t[app_i]-app_t[app_j]) == 1 & app_h[app_i] != app_h[app_j]) {
				app_raw[, 6] = app_raw[, 6] + .5 * max((0, 1-app_d/100)) * app_product
			}
		}
	}
	app_expected = (app_raw, (app_raw[, 1] + app_raw[, 2] :+ app_raw[, 3..5]) :*
		app_scale)
	app_expected = (app_expected, (app_raw[, 1] + app_raw[, 2] + app_raw[, 4] +
		app_raw[, 6]) :* app_scale)
	app_actual = app_fit[, (11, 12, 13, 14, 15, 16, 7, 8, 9, 10)]
	assert(mreldif(app_expected, app_actual) < 1e-10)
	st_matrix("app_toy", (app_expected, app_actual))
end
	clear
	svmat double app_toy
	gen byte	metric = cond(_n == 1, 5, 8)
	export delimited using "`out'/spatial_toy_audit.csv", replace
	display		"Independent ordered-pair covariance sums agree to relative tolerance 1e-10."
	log close

/* END */
