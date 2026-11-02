* Project: WB Weather - metric
* Created on: 31 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 2 Nov 2026
* Stata v.18

* does
	* creates selection-frontier figures and companion descriptive tables
	* plots separate outcomes, alternative selection, and year-only FE

* assumes
	* completed metric_front.do results and the project globals

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

	loc			root "$data/results_data/additional_evidence/exhibit2"
	loc			xfig "$data/results_data/figures/metric_paper"
	cap log close
	log using	"`root'/logs/metric_front_vis.log", text replace
	include		"$code/analysis/viz_code/metric_palette.do"
	tempfile	selected splits front
	loc			frame scheme(stcolor) graphregion(color(white)) ///
				plotregion(color(white) lstyle(none))
	loc			ticks labsize(2.5) labcolor("38 43 47") tlcolor("38 43 47")
	loc			grid grid glcolor("231 234 237") glpattern(solid) glwidth(vthin)


**********************************************************************
**# 1 - split summaries and descriptive denominators
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
**# 2 - selection frontiers with descriptive dispersion bands
**********************************************************************

* both outcomes and all countries use the same vertical scale
	use			"`front'", clear
	loc			ymin = -.1
	loc			ymax = .4
	foreach view in main t year {
		loc			spec = cond("`view'" == "year", 7, 2)
		loc			rule = cond("`view'" == "t", 2, 1)
		loc			prefix = cond("`view'" == "main", "front", "front_`view'")
		forvalues o = 1/2 {
			loc			outcome = cond(`o' == 1, "value", "maize")
			preserve
			keep if		spec == `spec' & outcome == `o' & rule == `rule'
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
**# 3 - selection frequencies among all eighty-four candidates
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
	loc			labels
	forvalues m = 1/14 {
		loc			metric : display %02.0f `m'
		loc			labels `labels' `m' "V`metric'"
	}
	forvalues o = 1/2 {
		loc			plots
		forvalues b = 0/10 {
			loc			red = round(242 - 20.2 * `b')
			loc			green = round(244 - 15.8 * `b')
			loc			blue = round(246 - 9.2 * `b')
			loc			plots `plots' (scatter metric product if outcome == `o' & ///
						shade == `b', msymbol(square) msize(3.7) ///
						mcolor("`red' `green' `blue'") mlcolor(none))
		}
		twoway		`plots', `frame' ///
					xlabel(1 "ARC2" 2 "CHIRPS" 3 "CPC" 4 "ERA5" ///
					5 "MERRA-2" 6 "TAMSAT", angle(45) nogrid `ticks') ///
					ylabel(`labels', nogrid `ticks') yscale(reverse) ///
					xtitle("") ytitle("Rainfall Metric", size(3)) ///
					legend(order(1 "0%" 3 "20%" 5 "40%" 7 "60%" 9 "80%" 11 "100%") ///
					rows(1) size(2.8) region(lstyle(none))) ///
					subtitle(, size(2.8) nobox fcolor(white)) ///
					by(country, cols(3) iscale(1) legend(pos(6)) note("") ///
					graphregion(color(white)) imargin(small)) xsize(9) ysize(5.5)
		loc			outcome = cond(`o' == 1, "value", "maize")
		graph export "`xfig'/front_choice_`outcome'.pdf", replace
		graph export "`xfig'/front_choice_`outcome'.png", width(3200) replace
	}
	log close

/* END */
