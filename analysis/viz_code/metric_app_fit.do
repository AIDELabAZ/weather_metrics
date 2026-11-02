* Project: WB Weather - metric
* Created on: 2 Nov 2026
* Created by: codex
* edited by: codex
* edited on: 2 Nov 2026
* Stata v.18

* does
	* redraws three appendix figures from saved selection and spatial estimates
	* saves plotted values, empirical bands and matched denominators

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
	capture mkdir "`out'/fit"
	cap log close
	log using	"`out'/metric_app_fit.log", text replace
	include		"$code/analysis/viz_code/metric_palette.do"
	loc			teal "24 105 112"
	loc			plum "124 83 117"
	loc			ink "38 43 47"
	loc			frame scheme(stcolor) graphregion(color(white) margin(zero)) ///
				plotregion(color(white) lstyle(none) margin(zero)) ///
				xlabel(none) ylabel(none) xtitle("") ytitle("") legend(off)
	loc			pale lcolor("242 244 246") lpattern(solid) lwidth(.45pt)
	loc			zero lcolor("140 140 140") lpattern(solid) lwidth(.5pt)
	tempfile	pooled shares


**********************************************************************
**# 1 - twelve country-outcome frontiers with empirical dispersion
**********************************************************************

	use			"`front'/selection_frontier", clear
	keep if		rule == 1
	egen byte	country_row = group(country)
	gen byte	row = floor((country_row - 1) / 2) + 1
	gen byte	column = 2 * mod(country_row - 1, 2) + outcome
	egen double	low = rowmin(lo_train lo_valid train valid_corr)
	egen double	high = rowmax(hi_train hi_valid train valid_corr)
	quietly summarize low, meanonly
	loc			ymin = min(-.05, floor((r(min) - .01) * 100) / 100)
	quietly summarize high, meanonly
	loc			ymax = max(.35, ceil((r(max) + .01) * 100) / 100)
	gen double	y_min = `ymin'
	gen double	y_max = `ymax'
	assert		_N == 216
	export delimited country outcome spec row column k train valid_corr ///
				lo_train hi_train lo_valid hi_valid attempts valid invalid ///
				y_min y_max using "`out'/front_fit_values.csv", nolabel replace
	display		"Frontier range including all ribbons: `ymin' to `ymax'."
	foreach c in 1 2 4 5 6 7 {
		forvalues o = 1/2 {
			preserve
			keep if		country == `c' & outcome == `o'
			twoway		(rarea lo_train hi_train k if spec == 7, sort ///
						color("`arc2'%5") lwidth(none)) ///
						(rarea lo_train hi_train k if spec == 2, sort ///
						color("`era5'%5") lwidth(none)) ///
						(rarea lo_valid hi_valid k if spec == 7, sort ///
						color("`arc2'%11") lwidth(none)) ///
						(rarea lo_valid hi_valid k if spec == 2, sort ///
						color("`era5'%11") lwidth(none)) ///
						(line train k if spec == 7, sort ///
						lcolor("`arc2'") lwidth(.9pt)) ///
						(line valid_corr k if spec == 7, sort ///
						lcolor("`arc2'") lpattern(dash) lwidth(.9pt)) ///
						(line train k if spec == 2, sort ///
						lcolor("`era5'") lwidth(.9pt)) ///
						(line valid_corr k if spec == 2, sort ///
						lcolor("`era5'") lpattern(dash) lwidth(.9pt)), ///
						`frame' xscale(log range(1 84) off noextend) ///
						yscale(range(`ymin' `ymax') off noextend) ///
						yline(-.1 .1 .2 .3, `pale') yline(0, `zero') ///
						xsize(2.6) ysize(2.055)
			graph export "`out'/fit/front_`c'_`o'.pdf", replace
			restore
		}
	}


**********************************************************************
**# 2 - paired difference of incremental search gaps
**********************************************************************

* form the FE contrast before aggregating the shared candidate orderings
	use			"`front'/selected_instruments", clear
	keep if		rule == 1 & inlist(k, 1, 84)
	gen double	raw_gap = abs(r_train) - sign(r_train) * r_valid
	assert		abs(raw_gap - gap) < 1e-12 if !missing(raw_gap, gap)
	keep		country outcome spec rep fold ordering k candidate raw_gap
	reshape wide candidate raw_gap, ///
				i(country outcome spec rep fold ordering) j(k)
	gen double	increment = raw_gap84 - raw_gap1
	keep		country outcome spec rep fold ordering candidate1 increment
	reshape wide candidate1 increment, i(country outcome rep fold ordering) j(spec)
	assert		candidate12 == candidate17 if !missing(increment2, increment7)
	gen double	difference = increment2 - increment7
	gen byte	matched = !missing(difference)
	gen byte	attempted = 1
	collapse	(median) difference (sum) n_pairs = matched n_attempted = attempted, ///
				by(country outcome rep fold)
	collapse	(p50) difference (p10) p10 = difference (p90) p90 = difference ///
				(sum) n_pairs n_attempted (count) n_folds = difference, ///
				by(country outcome)
	quietly summarize p10, meanonly
	loc			xmin = min(-.04, floor((r(min) - .01) / .02) * .02)
	quietly summarize p90, meanonly
	loc			xmax = max(.11, ceil((r(max) + .01) / .02) * .02)
	gen double	x_min = `xmin'
	gen double	x_max = `xmax'
	egen byte	country_row = group(country)
	export delimited country outcome difference p10 p90 n_pairs n_attempted ///
				n_folds x_min x_max using "`out'/front_forest_values.csv", nolabel replace
	list		country outcome difference p10 p90 n_pairs n_folds, noobs
	display		"Paired forest range: `xmin' to `xmax'."
	forvalues o = 1/2 {
		twoway		(rspike p10 p90 country_row if outcome == `o', horizontal ///
					lcolor("`ink'") lwidth(.7pt)) ///
					(scatter country_row difference if outcome == `o', ///
					msymbol(O) msize(4pt) mcolor("`ink'")), ///
					`frame' xscale(range(`xmin' `xmax') off noextend) ///
					yscale(reverse range(.5 6.5) off noextend) ///
					xline(-.2(.05).2, `pale') xline(0, `zero') ///
					xsize(5.9) ysize(1.6)
		graph export "`out'/fit/forest_`o'.pdf", replace
	}


**********************************************************************
**# 3 - categorical-distance scores with country-specific scales
**********************************************************************

	use			"`space'/score_summary", clear
	keep if		lag == 0
	bysort country: egen double low = min(score_crossproduct)
	bysort country: egen double high = max(score_crossproduct)
	replace		low = min(0, low)
	replace		high = max(0, high)
	gen double	span = high - low
	gen double	unit = 10^floor(log10(span / 4))
	gen double	ratio = span / 4 / unit
	gen double	y_step = unit * cond(ratio <= 1, 1, cond(ratio <= 2, 2, ///
				cond(ratio <= 2.5, 2.5, cond(ratio <= 5, 5, 10))))
	gen double	y_min = floor((low - .13 * span) / (y_step / 5)) * y_step / 5
	gen double	y_max = ceil((high + .13 * span) / (y_step / 5)) * y_step / 5
	export delimited country metric band score_crossproduct specifications pairs ///
				y_min y_max y_step using "`out'/space_fit_values.csv", nolabel replace
	foreach c in 1 2 4 5 6 7 {
		preserve
		keep if		country == `c'
		loc			ymin = y_min[1]
		loc			ymax = y_max[1]
		loc			step = y_step[1]
		loc			first = ceil(`ymin' / `step') * `step'
		twoway		(connected score_crossproduct band if metric == 5, sort ///
					msymbol(O) msize(3.5pt) mcolor("`teal'") ///
					lcolor("`teal'") lwidth(.9pt)) ///
					(connected score_crossproduct band if metric == 8, sort ///
					msymbol(D) msize(3.5pt) mcolor("`plum'") ///
					lcolor("`plum'") lpattern(dash) lwidth(.9pt)), ///
					`frame' xscale(range(.5 5.5) off noextend) ///
					yscale(range(`ymin' `ymax') off noextend) ///
					yline(`first'(`step')`ymax', `pale') yline(0, `zero') ///
					xsize(3.35) ysize(1.55)
		graph export "`out'/fit/score_`c'.pdf", replace
		restore
	}


**********************************************************************
**# 4 - outcome-specific paired spatial shares
**********************************************************************

	use			"`space'/spatial_first_stage", clear
	keep if		spec == 2
	gen byte	matched = !missing(t_hh, t_sp100) & se_hh > 0 & se_sp100 > 0 ///
				& var_sp100 > 0 & var_sp100 < .
	gen byte	attempted = 1
	gen byte	invalid = !matched
	gen double	share_hh = 100 * (abs(t_hh) > 1.96) if matched
	gen double	share_sp = 100 * (abs(t_sp100) > 1.96) if matched
	collapse	(mean) share_hh share_sp (sum) n_matched = matched ///
				n_attempted = attempted n_invalid = invalid, by(country outcome)
	assert		_N == 12
	egen byte	country_row = group(country)
	egen double	largest = rowmax(share_hh share_sp)
	quietly summarize largest, meanonly
	loc			xmax = max(70, ceil(r(max) / 10) * 10)
	gen double	x_max = `xmax'
	export delimited country outcome share_hh share_sp n_matched n_attempted ///
				n_invalid x_max using "`out'/space_outcome_values.csv", nolabel replace
	list		country outcome share_hh share_sp n_matched n_invalid, noobs
	save		"`shares'", replace

* outcome-specific denominators must recover the saved pooled comparisons
	gen double	num_hh = share_hh * n_matched / 100
	gen double	num_sp = share_sp * n_matched / 100
	collapse	(sum) num_hh num_sp n_matched, by(country)
	gen double	check_hh = 100 * num_hh / n_matched
	gen double	check_sp = 100 * num_sp / n_matched
	rename		n_matched check_n
	save		"`pooled'"
	use			"`space'/spatial_shares", clear
	keep if		spec == 2 & bandwidth == "100" & threshold == 1.96
	merge		1:1 country using "`pooled'", assert(match) nogen
	assert		abs(share_hh - check_hh) < 1e-10
	assert		abs(share_sp - check_sp) < 1e-10 & n_matched == check_n
	use			"`shares'", clear
	forvalues o = 1/2 {
		twoway		(rspike share_hh share_sp country_row if outcome == `o', ///
					horizontal lcolor("185 185 185") lwidth(.7pt)) ///
					(scatter country_row share_hh if outcome == `o', ///
					msymbol(O) msize(4pt) mcolor("100 105 110")) ///
					(scatter country_row share_sp if outcome == `o', ///
					msymbol(S) msize(4pt) mcolor("145 48 59")), ///
					`frame' xscale(range(0 `xmax') off noextend) ///
					yscale(reverse range(.5 6.5) off noextend) ///
					xline(0(10)`xmax', `pale') xsize(10) ysize(1.2)
		graph export "`out'/fit/share_`o'.pdf", replace
	}
	display		"Outcome-specific spatial-share axis: 0 to `xmax' percent."
	log close

/* END */
