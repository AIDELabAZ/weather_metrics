* Project: WB Weather - metric
* Created on: 2 Nov 2026
* Created by: codex
* edited by: codex
* edited on: 2 Nov 2026
* Stata v.18

* does
	* prepares appendix selection and first-stage spatial-inference exhibits
	* reuses saved estimates and exports supporting descriptive audits

* assumes
	* project globals and completed selection-frontier/spatial results

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

	loc			front "$data/results_data/additional_evidence/exhibit2"
	loc			space "$data/results_data/additional_evidence/exhibit3"
	loc			out "$data/results_data/additional_evidence/appendix"
	loc			xfig "$data/results_data/figures/metric_paper"
	capture mkdir "`out'"
	capture mkdir "`out'/components"
	cap log close
	log using	"`out'/metric_app.log", text replace
	include		"$code/analysis/viz_code/metric_palette.do"
	tempfile	orderings contrast components bands table originals
	loc			countries Ethiopia Malawi Niger Nigeria Tanzania Uganda
	loc			frame scheme(stcolor) graphregion(color(white)) ///
				plotregion(color(white) lstyle(none)) ///
				xscale(lcolor("38 43 47")) yscale(lcolor("38 43 47"))
	loc			ticks labsize(8pt) labcolor("38 43 47") tlcolor("38 43 47")
	loc			grid grid glcolor("242 244 246") glpattern(solid) glwidth(vthin)
	label define country 1 "Ethiopia" 2 "Malawi" 4 "Niger" ///
				5 "Nigeria" 6 "Tanzania" 7 "Uganda", replace


**********************************************************************
**# 1 - incremental selection optimism and paired FE contrasts
**********************************************************************

	use			"`front'/selected_instruments", clear
	keep if		inlist(k, 1, 84)
	gen double	raw_gap = abs(r_train) - sign(r_train) * r_valid
	assert		abs(raw_gap - gap) < 1e-12 if !missing(raw_gap, gap)
	keep		country outcome spec rep fold ordering rule k candidate gap
	reshape wide candidate gap, ///
				i(country outcome spec rep fold ordering rule) j(k)
	gen double	increment = gap84 - gap1
	gen byte	valid = !missing(increment)
	gen byte	attempts = 1
	save		"`orderings'"
	preserve
	keep		country outcome spec rep fold ordering rule candidate1 increment valid
	reshape wide candidate1 increment valid, ///
				i(country outcome rep fold ordering rule) j(spec)
	assert		candidate12 == candidate17 if valid2 & valid7
	gen double	fe_contrast = increment2 - increment7 if valid2 & valid7
	gen byte	fe_pairs = !missing(fe_contrast)
* candidate orderings share a split; summarize them before across-split percentiles
	collapse	(median) fe_contrast (sum) fe_pairs, ///
				by(country outcome rule rep fold)
	collapse	(p50) fe_contrast (p10) fe_p10 = fe_contrast ///
				(p90) fe_p90 = fe_contrast (sum) fe_pairs ///
				(count) fe_splits = fe_contrast, by(country outcome rule)
	save		"`contrast'"
	restore
	collapse	(median) increment gap1 gap84 (sum) valid_comparisons = valid ///
				ordering_attempts = attempts, by(country outcome spec rule rep fold)
	collapse	(p50) increment gap1 gap84 (p10) increment_p10 = increment ///
				(p90) increment_p90 = increment (sum) valid_comparisons ///
				ordering_attempts (count) valid_splits = increment, ///
				by(country outcome spec rule)
	merge		m:1 country outcome rule using "`contrast'", assert(match) nogen
	gen byte	increment_sign = sign(increment)
	gen byte	fe_contrast_sign = sign(fe_contrast)
	gen str9	outcome_var = cond(outcome == 1, "lntf_yld", "lncp_yld")
	gen str4	spec_id = "reg" + string(spec)
	label var	fe_contrast "Increment(reg2) minus Increment(reg7); paired orderings"
	char _dta[dispersion] "Percentiles of fold/allocation medians; descriptive, not independent draws"
	sort		country outcome rule spec
	save		"`out'/front_increment_comparison", replace
	export delimited using "`front'/front_increment_comparison.csv", nolabel replace

* refresh the existing descriptive outputs without remaking standalone figures
	use			"`front'/selection_frontier", clear
	keep if		inlist(k, 1, 10, 84)
	export delimited using "`front'/front_table.csv", nolabel replace
	foreach name in sample_audit split_audit baseline_comparison {
		use			"`front'/`name'", clear
		export delimited using "`front'/`name'.csv", nolabel replace
	}


**********************************************************************
**# 2 - within-EA and between-EA variance additions
**********************************************************************

	use			"`space'/spatial_first_stage", clear
	gen double	v_hh = correction * omega_hh / xx^2
	gen double	v_add_ea = correction * omega_within_ea / xx^2
	gen double	v_add_between = correction * omega_pair100 / xx^2
	gen double	v_hh_ea = correction * (omega_hh + omega_within_ea) / xx^2
	gen double	v_sp100 = correction * ///
				(omega_hh + omega_within_ea + omega_pair100) / xx^2
	assert		reldif(v_sp100, var_sp100) < 1e-10
	assert		reldif(sqrt(v_hh), se_hh) < 1e-10
	assert		reldif(sqrt(v_sp100), se_sp100) < 1e-10 if v_sp100 > 0
	gen double	se_hh_ea = sqrt(v_hh_ea) if v_hh_ea > 0 & v_hh_ea < .
	foreach step in hh hh_ea sp100 {
		gen byte	nonpositive_`step' = v_`step' <= 0
		gen byte	missing_`step' = missing(v_`step')
		gen double	abs_t_`step' = abs(beta / se_`step') if ///
					v_`step' > 0 & v_`step' < .
		gen double	ratio_`step' = se_`step' / se_hh if se_hh > 0 & se_hh < .
	}
	gen byte	matched_three = !missing(abs_t_hh, abs_t_hh_ea, abs_t_sp100)
	keep		country outcome spec metric product weather_var outcome_var spec_id ///
				beta n_geo households ea_years years xx correction omega_hh ///
				omega_within_ea omega_pair100 v_* se_hh se_hh_ea se_sp100 ///
				abs_t_* ratio_* nonpositive_* missing_* matched_three
	foreach step in hh hh_ea sp100 {
		gen byte	pass196_`step' = abs_t_`step' > 1.96 if abs_t_`step' < .
		gen byte	pass481_`step' = abs_t_`step' > 4.81 if abs_t_`step' < .
	}
	save		"`out'/spatial_variance_components", replace
	export delimited using "`space'/spatial_variance_components.csv", nolabel replace
	rename		(abs_t_hh abs_t_hh_ea abs_t_sp100) (tabs1 tabs2 tabs3)
	rename		(ratio_hh ratio_hh_ea ratio_sp100) (ratio1 ratio2 ratio3)
	rename		(nonpositive_hh nonpositive_hh_ea nonpositive_sp100) ///
				(nonpositive1 nonpositive2 nonpositive3)
	rename		(missing_hh missing_hh_ea missing_sp100) (missing1 missing2 missing3)
	keep		country outcome spec weather_var tabs1-tabs3 ratio1-ratio3 ///
				nonpositive1-nonpositive3 missing1-missing3 matched_three
	reshape long tabs ratio nonpositive missing, ///
				i(country outcome spec weather_var) j(step)
	expand		2, generate(pooled)
	replace		outcome = 0 if pooled
	gen byte	attempted = 1
	gen byte	estimable = tabs < .
	save		"`components'"
	foreach cut in 1.96 4.81 {
		use			"`components'", clear
		gen double	share = 100 * (tabs > `cut') if matched_three
		collapse	(mean) share mean_se_ratio = ratio ///
					(p50) median_se_ratio = ratio (sum) attempted estimable ///
					n_matched = matched_three n_nonpositive = nonpositive ///
					n_missing = missing, by(country outcome spec step)
		gen double	threshold = `cut'
		if `cut' == 4.81 append using "`table'"
		save		"`table'", replace
	}
	gen str20	stage = cond(step == 1, "Household", ///
				cond(step == 2, "Household + EA", "Spatial (100 km)"))
	sort		country outcome spec threshold step
	save		"`out'/spatial_components_summary", replace
	export delimited using "`space'/spatial_components_summary.csv", nolabel replace


**********************************************************************
**# 3 - matched bandwidth and adjacent-interval audit
**********************************************************************

	use			"`space'/spatial_first_stage", clear
	gen byte	valid_hh = se_hh > 0 & !missing(t_hh)
	reshape long se_sp var_sp t_sp bad_sp, ///
				i(country outcome spec weather_var) j(bandwidth) string
	gen byte	matched = valid_hh & se_sp > 0 & var_sp > 0 & !missing(t_sp)
	gen byte	nonpositive = var_sp <= 0
	gen byte	missing_variance = missing(var_sp)
	gen double	se_ratio = se_sp / se_hh if matched
	expand		2, generate(pooled)
	replace		outcome = 0 if pooled
	gen byte	attempted = 1
	save		"`bands'"
	foreach cut in 1.96 4.81 {
		use			"`bands'", clear
		gen double	share_hh = 100 * (abs(t_hh) > `cut') if matched
		gen double	share_sp = 100 * (abs(t_sp) > `cut') if matched
		collapse	(mean) share_hh share_sp mean_se_ratio = se_ratio ///
					(p50) median_se_ratio = se_ratio (sum) attempted ///
					n_matched = matched n_hh = valid_hh ///
					n_nonpositive = nonpositive n_missing = missing_variance, ///
					by(country outcome spec bandwidth)
		gen double	threshold = `cut'
		if `cut' == 4.81 append using "`table'"
		save		"`table'", replace
	}
	gen double	share_change = share_sp - share_hh
	gen str4	spec_id = "reg" + string(spec)
	sort		country outcome spec threshold bandwidth
	save		"`out'/spatial_bandwidth_audit", replace
	export delimited using "`space'/spatial_bandwidth_audit.csv", nolabel replace


**********************************************************************
**# 4 - geography restrictions versus covariance changes
**********************************************************************

	use			"$data/results_data/reg_results", clear
	keep if		inlist(regname, "reg2", "reg7") & ///
				regexm(weather_var, "^v(0[1-9]|1[0-4])_rf[1-6]$")
	gen str9	outcome_var = cond(depvar == "tf", "lntf_yld", "lncp_yld")
	rename		(regname nclusters) (spec_id hh_original)
	keep		country outcome_var weather_var spec_id hh_original
	isid		country outcome_var weather_var spec_id
	save		"`originals'"
	import delimited using "`space'/geo_model_comparison.csv", varnames(1) clear
	merge		1:1 country outcome_var weather_var spec_id using "`originals'", ///
				assert(match) nogen
	gen double	t_original = beta_original / se_original
	gen double	beta_sample_change = beta - beta_original
	gen double	hh_se_sample_ratio = se_hh / se_original
	gen double	spatial_se_ratio = se_sp100 / se_hh
	gen long	households_excluded = hh_original - households
	save		"`out'/spatial_sample_audit", replace
	export delimited using "`space'/spatial_sample_audit.csv", nolabel replace
	collapse	(firstnm) n_original n_geo hh_original households ///
				n_geo_excluded households_excluded ///
				(p50) hh_se_sample_ratio spatial_se_ratio ///
				(min) beta_change_min = beta_sample_change ///
				(max) beta_change_max = beta_sample_change, ///
				by(country outcome_var spec_id)
	export delimited using "`space'/spatial_sample_summary.csv", nolabel replace


**********************************************************************
**# 5 - vector cells for the six-country by four-model frontier matrix
**********************************************************************

	use			"`front'/selection_frontier", clear
	keep if		rule == 1
	gen byte	column = cond(outcome == 1, cond(spec == 7, 1, 2), ///
				cond(spec == 7, 3, 4))
	assert		_N == 216
	export delimited country outcome spec column k train valid_corr using ///
				"`out'/front_panel_values.csv", nolabel replace
	loc			r = 0
	foreach c in 1 2 4 5 6 7 {
		loc			r = `r' + 1
		forvalues col = 1/4 {
			preserve
			keep if		country == `c' & column == `col'
* the PDF assembly supplies physical-size axes and labels once per row/column
			twoway		(line train k, sort lcolor("`arc2'") lwidth(1.6pt)) ///
						(line valid_corr k, sort lcolor("`era5'") ///
						lpattern(dash) lwidth(1.6pt)), ///
						scheme(stcolor) graphregion(color(white) margin(zero)) ///
						plotregion(color(white) lstyle(none) margin(zero)) ///
						xscale(log range(1 84) off) yscale(range(-.1 .4) off) ///
						xlabel(none) ylabel(none) xtitle("") ytitle("") ///
						yline(-.1 .2 .4, lcolor("242 244 246") ///
						lpattern(solid) lwidth(.6pt)) ///
						yline(0, lcolor("140 140 140") lpattern(solid) lwidth(.8pt)) ///
						legend(off) xsize(4) ysize(1.35)
			graph export "`out'/components/front_`r'_`col'.pdf", replace
			restore
		}
	}


**********************************************************************
**# 6 - unequal-width spatial-inference panels
**********************************************************************

	use			"`space'/score_summary", clear
	keep if		lag == 0
	gen double	distance = cond(band == 1, 12.5, cond(band == 2, 37.5, ///
				cond(band == 3, 75, cond(band == 4, 150, 250))))
	export delimited country metric band distance score_crossproduct using ///
				"`out'/space_score_values.csv", nolabel replace
	label define country 1 "{bf:Ethiopia}" 2 "{bf:Malawi}" 4 "{bf:Niger}" ///
				5 "{bf:Nigeria}" 6 "{bf:Tanzania}" 7 "{bf:Uganda}", replace
	label values country country
	quietly summarize score_crossproduct, meanonly
	loc			ymin = floor(min(0, r(min)) / .1) * .1
	loc			ymax = ceil(max(0, r(max)) / .1) * .1
	twoway		(connected score_crossproduct distance if metric == 5, sort ///
					msymbol(O) msize(2pt) mcolor("`arc2'") ///
					lcolor("`arc2'") lwidth(.7pt)) ///
					(connected score_crossproduct distance if metric == 8, sort ///
					msymbol(D) msize(2pt) mcolor("`era5'") ///
					lcolor("`era5'") lpattern(dash) lwidth(.7pt)), ///
					`frame' xlabel(12.5 "0-25" 37.5 "25-50" 75 "50-100" ///
					150 "100-200" 250 "200-300", nogrid `ticks' angle(45)) ///
					ylabel(`ymin'(.1)`ymax', format(%4.2f) `ticks' `grid') ///
					yline(0, lcolor("140 140 140") lpattern(solid) lwidth(.4pt)) ///
					xtitle("Distance Between EAs (km)", size(9pt)) ///
					ytitle("Mean Standardized Score Cross-Product", size(9pt)) ///
					legend(order(1 "Seasonal Rainfall" 2 "Rainy Days") ///
					rows(1) size(8pt) region(lstyle(none))) ///
					subtitle(, size(9pt) nobox fcolor(white)) ///
					by(country, cols(2) iscale(1) legend(pos(6)) note("") ///
					graphregion(color(white)) imargin(small)) xsize(5.25) ysize(4.65)
	graph export "`out'/components/space_a.pdf", replace
	use			"`space'/spatial_shares", clear
	keep if		spec == 2 & bandwidth == "100" & threshold == 1.96
	assert		n_matched == 168
	egen byte	row = group(country)
	export delimited country share_hh share_sp n_matched using ///
				"`out'/space_share_values.csv", nolabel replace
	loc			labels
	forvalues r = 1/6 {
		loc			name : word `r' of `countries'
		loc			labels `labels' `r' "`name'"
	}
	egen double	largest = rowmax(share_hh share_sp)
	quietly summarize largest, meanonly
	loc			xmax = max(70, ceil(r(max) / 10) * 10)
	twoway		(rspike share_hh share_sp row, horizontal ///
					lcolor("175 175 175") lwidth(.5pt)) ///
					(scatter row share_hh, msymbol(O) msize(4pt) mcolor("`arc2'")) ///
					(scatter row share_sp, msymbol(D) msize(4pt) mcolor("`era5'")), ///
					`frame' xlabel(0(10)`xmax', `ticks' `grid') ///
					ylabel(`labels', nogrid `ticks' angle(horizontal)) ///
					yscale(reverse range(.5 6.5)) ytitle("") ///
					xtitle("Share Of Specifications (%)", size(9pt)) ///
					legend(order(2 "Household Clustering" 3 "Spatial (100 km)") ///
					rows(1) pos(6) size(8pt) region(lstyle(none))) ///
					xsize(3.5) ysize(4.65)
	graph export "`out'/components/space_b.pdf", replace


**********************************************************************
**# 7 - auxiliary selection-optimism contrast, not a composite panel
**********************************************************************

	use			"`out'/front_increment_comparison", clear
	keep if		spec == 2 & rule == 1
	egen byte	row = group(country)
	gen double	position = row + cond(outcome == 1, -.12, .12)
	quietly summarize fe_contrast, meanonly
	loc			xmin = floor(min(0, r(min)) / .02) * .02
	loc			xmax = ceil(max(0, r(max)) / .02) * .02
	twoway		(scatter position fe_contrast if outcome == 1, ///
					msymbol(O) msize(4pt) mcolor("`arc2'")) ///
					(scatter position fe_contrast if outcome == 2, ///
					msymbol(D) msize(4pt) mcolor("`era5'")), ///
					`frame' xlabel(`xmin'(.02)`xmax', `ticks' `grid' format(%5.2f)) ///
					ylabel(`labels', nogrid `ticks' angle(horizontal)) ///
					yscale(reverse range(.5 6.5)) ytitle("") ///
					xtitle("Incremental Optimism: Year + HH FE Minus Year FE", size(9pt)) ///
					xline(0, lcolor("140 140 140") lpattern(solid) lwidth(.5pt)) ///
					legend(order(1 "Farm Production Value" 2 "Maize Yield") ///
					rows(1) pos(6) size(8pt) region(lstyle(none))) xsize(9) ysize(4.2)
	graph export "`xfig'/front_increment.pdf", replace
	graph export "`xfig'/front_increment.png", width(3200) replace
	log close

/* END */
