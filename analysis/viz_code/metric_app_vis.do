* Project: WB Weather - metric
* Created on: 3 Nov 2026
* Created by: codex
* edited by: codex
* edited on: 3 Nov 2026
* Stata v.18

* does
	* creates the three additional-evidence appendix figures in Stata
	* preserves saved first-stage results and descriptive percentile definitions

* assumes
	* projectdo.do has established the code and data globals
	* completed exhibit2 and exhibit3 saved results and descriptive summaries

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	global		root	"$data/results_data"
	global		xfig	"$root/figures/metric_paper"
	global		logout	"$root/logs"
	loc			front "$root/additional_evidence/exhibit2"
	loc			space "$root/additional_evidence/exhibit3"
	loc			appendix "$root/additional_evidence/appendix"

* open one log and load the shared style, which includes the palette
	cap log close
	log using	"$logout/metric_app_vis.log", text replace
	include		"$code/analysis/viz_code/metric_style.do"
	loc			axes labsize(8.5pt) labcolor("38 43 47") tlcolor("38 43 47")
	loc			grid grid glcolor("242 244 246") glpattern(solid) glwidth(vthin)
	loc			zero lcolor("140 140 140") lpattern(solid) lwidth(.4pt)
	loc			teal "24 105 112"
	loc			plum "124 83 117"
	tempfile	frontdata gains scores shares reference


**********************************************************************
**# 1 - validate saved inputs and build common plotting summaries
**********************************************************************

* validate the 14-metric by six-product candidate grid
	foreach f in candidates selected_instruments selection_frontier {
		confirm file "`front'/`f'.dta"
	}
	foreach f in score_summary spatial_first_stage spatial_shares {
		confirm file "`space'/`f'.dta"
	}
	use			"`front'/candidates", clear
	isid		metric product
	assert		_N == 84 & inrange(metric, 1, 14) & inrange(product, 1, 6)
	use			"`front'/selected_instruments", clear
	keep if		rule == 1
	confirm variable country outcome spec rep fold ordering k r_train r_valid
	isid		country outcome spec rep fold ordering k
	assert		inlist(country, 1, 2, 4, 5, 6, 7)
	assert		inlist(outcome, 1, 2) & inlist(spec, 2, 7)
	gen double	train = abs(r_train)
	gen double	heldout = sign(r_train) * r_valid

* K=1 is the first candidate in the same permutation; K=84 is the full set
	preserve
	keep if		inlist(k, 1, 84)
	keep		country outcome spec rep fold ordering k train heldout
	reshape wide train heldout, i(country outcome spec rep fold ordering) j(k)
	gen double	gain_train = train84 - train1
	gen double	gain_heldout = heldout84 - heldout1
	gen byte	paired = !missing(gain_train, gain_heldout)
	replace		gain_train = . if !paired
	replace		gain_heldout = . if !paired
	gen byte	attempted = 1

* orderings share a fold: aggregate them before the descriptive split percentiles
	collapse	(median) gain_train gain_heldout (sum) n_pairs = paired ///
				n_attempted = attempted, by(country outcome spec rep fold)
	collapse	(p50) gain_train gain_heldout ///
				(p25) train_lo = gain_train heldout_lo = gain_heldout ///
				(p75) train_hi = gain_train heldout_hi = gain_heldout ///
				(sum) n_pairs n_attempted (count) n_splits = gain_train, ///
				by(country outcome spec)
	isid		country outcome spec
	assert		_N == 24 & n_splits == 100
	save		"`gains'"

* reconcile gains with the previously approved arrow-plot summaries
	import delimited using "`appendix'/front_payoff_values.csv", asdouble clear
	keep		country outcome spec train holdout train_p25 train_p75 ///
				holdout_p25 holdout_p75
	merge		1:1 country outcome spec using "`gains'", assert(match) nogen
	assert		reldif(train, gain_train) < 1e-9
	assert		reldif(holdout, gain_heldout) < 1e-9
	assert		reldif(train_p25, train_lo) < 1e-9 & reldif(train_p75, train_hi) < 1e-9
	assert		reldif(holdout_p25, heldout_lo) < 1e-9 & reldif(holdout_p75, heldout_hi) < 1e-9
	restore

* retain the existing median and p10-p90 frontier definition, without clipping
	collapse	(median) train heldout, by(country outcome spec rep fold k)
	collapse	(p10) lo_train = train lo_valid = heldout ///
				(p50) train valid_corr = heldout ///
				(p90) hi_train = train hi_valid = heldout, by(country outcome spec k)
	isid		country outcome spec k
	assert		_N == 216
	save		"`frontdata'"
	foreach v in train valid_corr lo_train lo_valid hi_train hi_valid {
		rename		`v' check_`v'
	}
	save		"`reference'"
	use			"`front'/selection_frontier", clear
	keep if		rule == 1
	merge		1:1 country outcome spec k using "`reference'", assert(match) nogen
	foreach v in train valid_corr lo_train lo_valid hi_train hi_valid {
		assert		reldif(`v', check_`v') < 1e-9
	}
	display		"Validated 216 frontier rows, four series and p10-p90 bands."


**********************************************************************
**# 2 - selection frontiers: Quantity and Value blocks
**********************************************************************

	use			"`frontdata'", clear
	egen byte	row = group(country)
	gen byte	tile = 4 * floor((row - 1) / 2) + mod(row - 1, 2) + ///
				cond(outcome == 2, 1, 3)
	label define app_tile 1 "Ethiopia" 2 "Malawi" 3 "Ethiopia" 4 "Malawi" ///
				5 "Niger" 6 "Nigeria" 7 "Niger" 8 "Nigeria" ///
				9 "Tanzania" 10 "Uganda" 11 "Tanzania" 12 "Uganda", replace
	label values tile app_tile
	assert		lo_valid >= -.12 & hi_valid <= .38
	assert		lo_train >= -.12 & hi_train <= .38
	twoway		(rarea lo_train hi_train k if spec == 7, sort ///
				color("`arc2'%5") lwidth(none)) ///
				(rarea lo_train hi_train k if spec == 2, sort ///
				color("`era5'%5") lwidth(none)) ///
				(rarea lo_valid hi_valid k if spec == 7, sort ///
				color("`arc2'%11") lwidth(none)) ///
				(rarea lo_valid hi_valid k if spec == 2, sort ///
				color("`era5'%11") lwidth(none)) ///
				(line train k if spec == 7, sort lcolor("`arc2'") lwidth(.7pt)) ///
				(line valid_corr k if spec == 7, sort ///
				lcolor("`arc2'") lpattern(dash) lwidth(.7pt)) ///
				(line train k if spec == 2, sort lcolor("`era5'") lwidth(.7pt)) ///
				(line valid_corr k if spec == 2, sort ///
				lcolor("`era5'") lpattern(dash) lwidth(.7pt)), ///
				`frame' xscale(log range(1 84) noextend) yscale(range(-.12 .38) noextend) ///
				xlabel(1 3 10 40 84, nogrid `axes') ///
				ylabel(-.1 0 .1 .2 .3, format(%4.2f) `axes' `grid' angle(horizontal)) ///
				yline(0, `zero') xtitle("") ytitle("") ///
				legend(order(5 "Year FE: training" 6 "Year FE: held-out" ///
				7 "Year + household FE: training" 8 "Year + household FE: held-out") ///
				rows(1) size(8pt) region(lstyle(none)) symxsize(7)) ///
				plotregion(margin(zero)) ///
				subtitle(, size(8.5pt) color("38 43 47") nobox fcolor(white) margin(zero)) ///
				by(tile, cols(4) compact iscale(1) legend(pos(6)) note("") imargin(small) ///
				title("{space 8}{bf:(A) Quantity}{space 90}{bf:(B) Value}", size(10pt) margin(medsmall)) ///
				l1title("Selected first-stage partial correlation", size(6pt) margin(medium)) ///
				b1title("Number of K Candidate Instruments", size(6pt) margin(medium)) ///
				graphregion(color(white) margin(small))) ///
				name(app_front, replace) xsize(9) ysize(5.4)
	graph display app_front, xsize(9) ysize(5.4)
	gr_edit .b1title.style.editstyle size(9pt) editcopy
	gr_edit .l1title.style.editstyle size(9pt) editcopy
	graph export "$xfig/front.pdf", name(app_front) replace
	graph export "$xfig/front.png", name(app_front) width(3200) replace


**********************************************************************
**# 3 - training and held-out search gains with descriptive IQRs
**********************************************************************

	use			"`gains'", clear
	egen byte	row = group(country)
	gen byte	panel = cond(outcome == 2, 1, 2)
	label define app_outcome 1 "{bf:(A) Quantity}" 2 "{bf:(B) Value}", replace
	label values panel app_outcome
	gen double	position = row + cond(spec == 7, -.18, .18)

* taller training caps and shorter held-out caps share their marker centerline
* nearly coincident gains use a small bent connector so its direction is visible
	gen double	turn_x = (gain_train + gain_heldout) / 2
	gen double	turn_y = position - .13 * (abs(gain_train - gain_heldout) < .008)
	assert		min(train_lo, heldout_lo) > -.08 & max(train_hi, heldout_hi) < .23
	save		"`appendix'/gain_summary", replace
	export delimited country outcome spec gain_train gain_heldout train_lo ///
				train_hi heldout_lo heldout_hi n_pairs n_attempted n_splits using ///
				"`appendix'/gain_summary.csv", nolabel replace
	twoway		(rcap train_lo train_hi position if spec == 7, horizontal ///
				lcolor("`arc2'%45") lwidth(.6pt) msize(8pt)) ///
				(rcap train_lo train_hi position if spec == 2, horizontal ///
				lcolor("`era5'%45") lwidth(.6pt) msize(8pt)) ///
				(rcap heldout_lo heldout_hi position if spec == 7, horizontal ///
				lcolor("`arc2'%75") lwidth(.6pt) msize(4pt)) ///
				(rcap heldout_lo heldout_hi position if spec == 2, horizontal ///
				lcolor("`era5'%75") lwidth(.6pt) msize(4pt)) ///
				(pcspike position gain_train turn_y turn_x if spec == 7, ///
				lcolor("`arc2'%80") lwidth(.6pt)) ///
				(pcspike position gain_train turn_y turn_x if spec == 2, ///
				lcolor("`era5'%80") lwidth(.6pt)) ///
				(pcarrow turn_y turn_x position gain_heldout if spec == 7, ///
				lcolor("`arc2'%80") mcolor("`arc2'%80") lwidth(.6pt) ///
				msize(2.5pt) barbsize(1.5pt) mlwidth(.4pt)) ///
				(pcarrow turn_y turn_x position gain_heldout if spec == 2, ///
				lcolor("`era5'%80") mcolor("`era5'%80") lwidth(.6pt) ///
				msize(2.5pt) barbsize(1.5pt) mlwidth(.4pt)) ///
				(scatter position gain_train if spec == 7, ///
				msymbol(O) msize(4pt) mcolor("`arc2'")) ///
				(scatter position gain_heldout if spec == 7, ///
				msymbol(Oh) msize(4pt) mcolor("`arc2'")) ///
				(scatter position gain_train if spec == 2, ///
				msymbol(O) msize(4pt) mcolor("`era5'")) ///
				(scatter position gain_heldout if spec == 2, ///
				msymbol(Oh) msize(4pt) mcolor("`era5'")), ///
				`frame' xscale(range(-.08 .23) noextend) yscale(reverse range(.5 6.5) noextend) ///
				xlabel(-.05(.05).2, `axes' `grid' format(%4.2f)) ///
				ylabel(1 "Ethiopia" 2 "Malawi" 3 "Niger" 4 "Nigeria" ///
				5 "Tanzania" 6 "Uganda", nogrid `axes' angle(horizontal)) ///
				xline(0, `zero') xtitle("") ytitle("") ///
				legend(order(9 "Year FE: training" 10 "Year FE: held-out" ///
				11 "Year + household FE: training" 12 "Year + household FE: held-out") ///
				cols(2) size(8.5pt) region(lstyle(none)) rowgap(2)) ///
				subtitle(, size(10pt) color("38 43 47") nobox fcolor(white)) ///
				by(panel, cols(2) iscale(1) legend(pos(6)) note("") imargin(medium) ///
				b1title("Change in First-Stage Partial Correlation", size(6pt) margin(medium)) ///
				graphregion(color(white) margin(small))) ///
				name(app_gain, replace) xsize(9) ysize(5.3)
	graph display app_gain, xsize(9) ysize(5.3)
	gr_edit .b1title.style.editstyle size(9pt) editcopy
	graph export "$xfig/gain.pdf", name(app_gain) replace
	graph export "$xfig/gain.png", name(app_gain) width(3200) replace


**********************************************************************
**# 4 - first-stage score dependence and spatial significance
**********************************************************************


**********************************************************************
**## 4.1 - score dependence with the existing country-specific ranges
**********************************************************************

	use			"`space'/score_summary", clear
	keep if		lag == 0
	isid		country metric band
	assert		_N == 60 & inlist(metric, 5, 8) & inrange(band, 1, 5)
	label define app_country 1 "Ethiopia" 2 "Malawi" 4 "Niger" ///
				5 "Nigeria" 6 "Tanzania" 7 "Uganda", replace
	label values country app_country
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
	save		"`scores'"


**********************************************************************
**## 4.2 - matched Quantity and Value significance shares
**********************************************************************

	use			"`space'/spatial_first_stage", clear
	keep if		spec == 2
	isid		country outcome weather_var
	gen byte	matched = !missing(t_hh, t_sp100) & se_hh > 0 & se_sp100 > 0 ///
				& var_sp100 > 0 & var_sp100 < .
	gen double	share_hh = 100 * (abs(t_hh) > 1.96) if matched
	gen double	share_sp = 100 * (abs(t_sp100) > 1.96) if matched
	collapse	(mean) share_hh share_sp (sum) n_matched = matched, by(country outcome)
	isid		country outcome
	assert		_N == 12 & n_matched == 84
	save		"`shares'"
	gen double	num_hh = share_hh * n_matched / 100
	gen double	num_sp = share_sp * n_matched / 100
	collapse	(sum) num_hh num_sp n_matched, by(country)
	gen double	check_hh = 100 * num_hh / n_matched
	gen double	check_sp = 100 * num_sp / n_matched
	rename		n_matched check_n
	save		"`reference'", replace
	use			"`space'/spatial_shares", clear
	keep if		spec == 2 & bandwidth == "100" & threshold == 1.96
	merge		1:1 country using "`reference'", assert(match) nogen
	assert		abs(share_hh - check_hh) < 1e-9 & abs(share_sp - check_sp) < 1e-9
	assert		n_matched == check_n
	use			"`shares'", clear


**********************************************************************
**## 4.3 - one native coordinate layout for the two spatial panels
**********************************************************************

* retain original numeric axes while laying out the six score plots in memory
	use			"`scores'", clear
	egen byte	row = group(country)
	gen double	left = 7.729 + mod(row - 1, 3) * 31.723
	gen double	bottom = 79.085 - floor((row - 1) / 3) * 18.301
	gen double	sx = left + 27.617 * (band - .5) / 5
	gen double	sy = bottom + 13.399 * (score_crossproduct - y_min) / (y_max - y_min)
	assert		sy > bottom & sy < bottom + 13.399
	gen byte	data_kind = 1
	save		"`scores'", replace
	tempfile	strokes labels
	tempname	lines words
	postfile	`lines' double(y1 x1 y2 x2) byte ink using "`strokes'"
	postfile	`words' double(yy xx) byte label_kind str100 label using "`labels'"
	post		`words' (98.04) (3.865) (1) ///
				("{bf:(A) First-stage score dependence by distance}")
	post		`words' (47.386) (3.865) (1) ///
				("{bf:(B) Outcome-specific first-stage significance}")
	loc			countries Ethiopia Malawi Niger Nigeria Tanzania Uganda
	loc			ids 1 2 4 5 6 7
	forvalues r = 1/6 {
		loc			c : word `r' of `ids'
		loc			name : word `r' of `countries'
		quietly summarize y_min if country == `c', meanonly
		loc			lo = r(min)
		quietly summarize y_max if country == `c', meanonly
		loc			hi = r(max)
		quietly summarize y_step if country == `c', meanonly
		loc			step = r(min)
		loc			x = 7.729 + mod(`r' - 1, 3) * 31.723
		loc			y = 79.085 - floor((`r' - 1) / 3) * 18.301
		loc			center = `x' + 27.617 / 2
		loc			title_y = `y' + 15.359
		post		`words' (`title_y') (`center') (2) ("`name'")
		post		`lines' (`y') (`x') (`y' + 13.399) (`x') (3)
		forvalues j = 0/5 {
			loc			value = (ceil(`lo' / `step') + `j') * `step'
			if `value' <= `hi' + 1e-10 {
				loc			py = `y' + 13.399 * (`value' - `lo') / (`hi' - `lo')
				loc			format = cond(`step' < .01, "%5.3f", "%4.2f")
				loc			tick = trim(string(`value', "`format'"))
				post		`words' (`py') (`x' - .35) (3) ("`tick'")
				post		`lines' (`py') (`x') (`py') (`x' + 27.617) ///
							(cond(abs(`value') < 1e-10, 2, 1))
			}
		}
		if `r' >= 4 {
			post		`lines' (`y') (`x') (`y') (`x' + 27.617) (3)
			forvalues j = 1/5 {
				loc			px = `x' + 27.617 * (`j' - .5) / 5
				loc			bin : word `j' of 0-25 25-50 50-100 100-200 200-300
				post		`words' (58.497) (`px') (4) ("`bin'")
				post		`lines' (`y') (`px') (`y' - .6) (`px') (3)
			}
		}
	}

* Quantity then Value; all percentage coordinates use the unchanged 0-90% scale
	use			"`shares'", clear
	egen byte	row = group(country)
	gen double	base = cond(outcome == 2, 28.758, 10.948)
	gen double	py = base + 13.072 * (1 - (row - .5) / 6)
	gen double	hx = 13.285 + 85.024 * share_hh / 90
	gen double	zx = 13.285 + 85.024 * share_sp / 90
	gen double	arrow_x = hx + (2 / 3) * (zx - hx)
	assert		(arrow_x - hx) * (zx - hx) > 0
	assert		min(share_hh, share_sp) >= 0 & max(share_hh, share_sp) <= 90
	gen byte	data_kind = 2
	save		"`shares'", replace
	forvalues o = 1/2 {
		loc			base = cond(`o' == 2, 28.758, 10.948)
		loc			title = cond(`o' == 2, "{bf:Quantity}", "{bf:Value}")
		post		`words' (`base' + 15.196) (55.797) (7) ("`title'")
		forvalues r = 1/6 {
			loc			name : word `r' of `countries'
			loc			y = `base' + 13.072 * (1 - (`r' - .5) / 6)
			post		`words' (`y') (12.319) (5) ("`name'")
		}
		forvalues value = 0(10)90 {
			loc			x = 13.285 + 85.024 * `value' / 90
			post		`lines' (`base') (`x') (`base' + 13.072) (`x') (1)
			if `o' == 1 {
				post		`words' (8.660) (`x') (4) ("`value'")
				post		`lines' (`base') (`x') (`base' - .6) (`x') (3)
			}
		}
	}
	post		`lines' (10.948) (13.285) (10.948) (98.309) (3)

* local legends keep the two rainfall measures separate from the two SE methods
	post		`words' (50.980) (39) (6) ("Seasonal rainfall")
	post		`words' (50.980) (63) (6) ("Rainy days")
	post		`words' (1.634) (27) (6) ("Household-clustered SEs")
	post		`words' (1.634) (60) (6) ("Spatial SEs (100 km)")
	postclose	`words'
	postclose	`lines'
	use			"`scores'", clear
	append using "`shares'" "`strokes'" "`labels'"
	loc			curves
	foreach c of local ids {
		loc			curves `curves' ///
				(connected sy sx if country == `c' & metric == 5, sort ///
				msymbol(T) msize(3pt) mcolor("`teal'") lcolor("`teal'") lwidth(.6pt)) ///
				(connected sy sx if country == `c' & metric == 8, sort ///
				msymbol(T) msangle(180) msize(3pt) mcolor("`plum'") ///
				lcolor("`plum'") lpattern(dash) lwidth(.6pt))
	}
	twoway		(pcspike y1 x1 y2 x2 if ink == 1, ///
				lcolor("242 244 246") lpattern(solid) lwidth(.4pt)) ///
				(pcspike y1 x1 y2 x2 if ink == 2, `zero') ///
				(pcspike y1 x1 y2 x2 if ink == 3, lcolor("38 43 47") lwidth(.4pt)) ///
				`curves' ///
				(pcspike py hx py zx if data_kind == 2, lcolor("75 80 85") lwidth(.7pt)) ///
				(pcarrow py hx py arrow_x if data_kind == 2, lcolor("75 80 85") ///
				mcolor("75 80 85") lwidth(.7pt) msize(2pt) barbsize(1.5pt)) ///
				(scatter py hx if data_kind == 2, msymbol(D) msize(3pt) mcolor("100 105 110")) ///
				(scatter py zx if data_kind == 2, msymbol(S) msize(3pt) mcolor("145 48 59")) ///
				(scatter yy xx if label_kind == 1, msymbol(none) mlabel(label) ///
				mlabpos(3) mlabgap(0) mlabsize(9.2pt) mlabcolor("38 43 47")) ///
				(scatter yy xx if inlist(label_kind, 2, 7), msymbol(none) mlabel(label) ///
				mlabpos(0) mlabsize(9pt) mlabcolor("38 43 47")) ///
				(scatter yy xx if label_kind == 3, msymbol(none) mlabel(label) ///
				mlabpos(9) mlabgap(0) mlabsize(8pt) mlabcolor("38 43 47")) ///
				(scatter yy xx if label_kind == 4, msymbol(none) mlabel(label) ///
				mlabpos(0) mlabsize(8pt) mlabcolor("38 43 47")) ///
				(scatter yy xx if label_kind == 5, msymbol(none) mlabel(label) ///
				mlabpos(9) mlabgap(0) mlabsize(9pt) mlabcolor("38 43 47")) ///
				(scatter yy xx if label_kind == 6, msymbol(none) mlabel(label) ///
				mlabpos(3) mlabgap(0) mlabsize(8.8pt) mlabcolor("38 43 47")) ///
				(pci 50.980 35 50.980 38, lcolor("`teal'") lwidth(.6pt)) ///
				(pci 50.980 59 50.980 62, lcolor("`plum'") lpattern(dash) lwidth(.6pt)) ///
				(scatteri 50.980 36.5, msymbol(T) msize(3pt) mcolor("`teal'")) ///
				(scatteri 50.980 60.5, msymbol(T) msangle(180) msize(3pt) mcolor("`plum'")) ///
				(scatteri 1.634 25, msymbol(D) msize(3pt) mcolor("100 105 110")) ///
				(scatteri 1.634 58, msymbol(S) msize(3pt) mcolor("145 48 59")), ///
				scheme(stcolor) graphregion(color(white) margin(zero)) ///
				plotregion(color(white) lstyle(none) margin(zero)) legend(off) ///
				xscale(range(0 100) off noextend) yscale(range(0 100) off noextend) ///
				xlabel(none) ylabel(none) xtitle("") ytitle("") ///
				text(74.183 1.69 "First-Stage Score Dependence", ///
				orientation(vertical) size(9pt) color("38 43 47")) ///
				text(54.902 50 "EA distance bin (km)", size(9pt) color("38 43 47")) ///
				text(5.556 50 "Share of first-stage specifications with |t| > 1.96 (%)", ///
				size(9pt) color("38 43 47")) name(app_space, replace) xsize(9) ysize(6)
	graph export "$xfig/space.pdf", name(app_space) replace
	graph export "$xfig/space.png", name(app_space) width(3200) replace


**********************************************************************
**# 5 - final consistency checks and log close
**********************************************************************

	foreach figure in front gain space {
		confirm file "$xfig/`figure'.pdf"
		confirm file "$xfig/`figure'.png"
	}
	display		"Created front, gain and space directly in Stata; no estimation executed."
	log close

/* END */
