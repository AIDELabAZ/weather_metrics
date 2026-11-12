* Project: WB Weather - metric
* Created on: 31 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 31 Oct 2026
* Stata v.18

* does
	* plots prespecified score dependence and paired precision shares
	* exports the matched denominators and bandwidth sensitivities

* assumes
	* completed metric_space.do results and the project globals

* TO DO:
	* rerun when the pending coordinates are available


**********************************************************************
**# 0 - setup
**********************************************************************

	loc			root "$data/results_data/additional_evidence/exhibit3"
	loc			xfig "$data/results_data/figures/metric_paper"
	cap log close
	log using	"`root'/logs/metric_space_vis.log", text replace
	include		"$code/analysis/viz_code/metric_palette.do"
	loc			frame scheme(stcolor) graphregion(color(white)) ///
				plotregion(color(white) lstyle(none))
	loc			ticks labsize(2.8) labcolor("38 43 47") tlcolor("38 43 47")
	loc			grid grid glcolor("231 234 237") glpattern(solid) glwidth(vthin)
	tempfile	table model


**********************************************************************
**# 1 - prespecified first-stage score correlograms
**********************************************************************

	use			"`root'/score_correlogram", clear
	keep if		spec == 2
	collapse	(median) score_crossproduct (count) specifications = score_crossproduct ///
				(sum) pairs, by(country metric band lag)
	save		"`root'/score_summary", replace
	export delimited using "`root'/score_summary.csv", replace
	keep if		lag == 0
	gen double	distance = 12.5 if band == 1
	replace		distance = 37.5 if band == 2
	replace		distance = 75 if band == 3
	replace		distance = 150 if band == 4
	replace		distance = 250 if band == 5
	label define country 1 "Ethiopia" 2 "Malawi" 4 "Niger" ///
				5 "Nigeria" 6 "Tanzania" 7 "Uganda", replace
	label values country country
	foreach c in 1 2 4 5 6 7 {
		loc			name : label country `c'
		quietly count if country == `c' & specifications > 0
		if r(N) == 0 loc name "`name' (Coordinates Pending)"
		label define country `c' "{bf:`name'}", modify
	}
	quietly summarize score_crossproduct, meanonly
	loc			step = .1
	if r(max) - r(min) > 1 loc step = .25
	if r(max) - r(min) > 2 loc step = .5
	loc			ymin = floor(min(0, r(min)) / `step') * `step'
	loc			ymax = ceil(max(0, r(max)) / `step') * `step'
	twoway		(connected score_crossproduct distance if metric == 5, ///
				sort msymbol(O) msize(small) mcolor("`arc2'") ///
				lcolor("`arc2'") lwidth(medium)) ///
				(connected score_crossproduct distance if metric == 8, ///
				sort msymbol(D) msize(small) mcolor("`era5'") ///
				lcolor("`era5'") lpattern(dash) lwidth(medium)), ///
				`frame' ///
				xlabel(12.5 "0-25" 37.5 "25-50" 75 "50-100" ///
				150 "100-200" 250 "200-300", nogrid `ticks' angle(45)) ///
				ylabel(`ymin'(`step')`ymax', format(%4.2f) `ticks' `grid') ///
				yline(0, lcolor("140 140 140") lpattern(solid) lwidth(vthin)) ///
				xtitle("Distance Between Released Locations (km)", size(3)) ///
				ytitle("Standardized Score Cross-Product", size(3)) ///
				legend(order(1 "Seasonal Rainfall" 2 "Rainy Days") ///
				rows(1) size(2.8) region(lstyle(none))) ///
				subtitle(, size(2.8) nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) legend(pos(6)) note("") ///
				graphregion(color(white)) imargin(small)) xsize(9) ysize(5.5)
	graph export "`xfig'/space_score.pdf", replace
	graph export "`xfig'/space_score.png", width(3200) replace


**********************************************************************
**# 2 - matched exceedance shares and variance warnings
**********************************************************************

	use			"`root'/spatial_first_stage", clear
	gen byte	valid_hh = !missing(t_hh) & se_hh > 0
	reshape long se_sp var_sp t_sp bad_sp, ///
				i(country outcome spec weather_var) j(bandwidth) string
	gen byte	matched = valid_hh & !missing(t_sp) & se_sp > 0 & var_sp > 0
	gen byte	n_all = 1
	save		"`model'"
	foreach cut in 1.96 4.81 {
		use			"`model'", clear
		gen double	share_hh = 100 * (abs(t_hh) > `cut') if matched
		gen double	share_sp = 100 * (abs(t_sp) > `cut') if matched
		gen double	share_hh_all = 100 * (abs(t_hh) > `cut') if valid_hh
		collapse	(mean) share_hh share_sp share_hh_all ///
					(sum) n_all n_matched = matched n_hh = valid_hh ///
					n_bad_variance = bad_sp, by(country spec bandwidth)
		gen double	threshold = `cut'
		if `cut' == 4.81 append using "`table'"
		save		"`table'", replace
	}
	gen double	share_change = share_sp - share_hh
	gen int		n_unmatched = n_all - n_matched
	gen str4	spec_id = "reg" + string(spec)
	char _dta[denominator] "Paired HH/spatial shares use the same estimable specifications; n_matched is reported"
	char _dta[lag1] "100_lag1 adds adjacent-survey-interval covariance with Bartlett weight 0.5"
	save		"`root'/spatial_shares", replace
	export delimited using "`root'/spatial_shares.csv", replace
	list		country spec bandwidth threshold n_all n_matched n_bad_variance ///
				if bandwidth == "100" & threshold == 1.96, noobs


**********************************************************************
**# 3 - paired country shares at the paper's reference thresholds
**********************************************************************

	keep if		spec == 2 & bandwidth == "100"
	egen byte	row = group(country)
	loc			labels
	loc			countries Ethiopia Malawi Niger Nigeria Tanzania Uganda
	forvalues r = 1/6 {
		loc			name : word `r' of `countries'
		quietly count if row == `r' & n_hh > 0
		if r(N) == 0 loc name "`name' (Coordinates Pending)"
		loc			labels `labels' `r' "`name'"
	}
	foreach cut in 1.96 4.81 {
		preserve
		keep if		threshold == `cut'
		twoway		(rspike share_hh share_sp row, horizontal ///
					lcolor("175 175 175") lwidth(thin)) ///
					(scatter row share_hh, msymbol(O) msize(2.5) mcolor("`arc2'")) ///
					(scatter row share_sp, msymbol(D) msize(2.5) mcolor("`era5'")), ///
					`frame' xlabel(0(20)100, `ticks' `grid') ///
					ylabel(`labels', nogrid `ticks' angle(horizontal)) ///
					yscale(reverse range(.5 6.5)) ytitle("") ///
					xtitle("Specifications With |t| > `cut' (%)", size(3)) ///
					legend(order(2 "Household Clustering" 3 "Spatial Adjustment (100 km)") ///
					rows(1) pos(6) size(2.8) region(lstyle(none))) ///
					xsize(9) ysize(5.5)
		loc			name = cond(`cut' == 1.96, "space_share", "space_share481")
		graph export "`xfig'/`name'.pdf", replace
		graph export "`xfig'/`name'.png", width(3200) replace
		restore
	}
	log close

/* END */
