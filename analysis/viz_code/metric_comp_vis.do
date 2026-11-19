* Project: WB Weather - metric
* Created on: 19 Nov 2026
* Created by: codex
* Stata v.19.5

* does
	* compares 5% significance decisions across products and rainfall metrics
	* illustrates changes in signed t-statistics on adding household FE

* assumes
	* projectdo.do has established the code and data globals
	* lsms_complete_results contains the matched reg7 and reg2 estimates


**********************************************************************
**# 0 - setup
**********************************************************************

* load the same inventory, omission flags and original IDs as the paired charts
	do			"$code/analysis/viz_code/metric_coeff_vis.do" paired
	include		"$code/analysis/viz_code/metric_style.do"
	isid		country outcome_var product metric
	foreach s in reg7 reg2 {
		gen byte	sig_`s' = pval_`s' <= .05 if omission == ""
	}
	tempfile	paired other
	save		"`paired'"

	loc			products ARC2 CHIRPS CPC ERA5 MERRA-2 TAMSAT
	loc			heading size(12pt) color("38 43 47") pos(11)
	loc			subhead size(9pt) color("74 82 89") pos(11)
	loc			panel scheme(stcolor) graphregion(color(white) margin(small)) ///
				plotregion(lstyle(none) margin(zero))


**********************************************************************
**# 1 - pairwise disagreement in significance decisions
**********************************************************************

* Join on all three fixed identifiers. The full inventory retains missing pairs.
	foreach instrument in product metric {
		use			"`paired'", clear
		if "`instrument'" == "product" {
			loc			fixed country outcome_var metric
			loc			k 6
			loc			title "A1. Across remote sensing products"
			loc			subtitle "Within country, outcome and rainfall metric"
			loc			labels
			forvalues p = 1/6 {
				loc			name : word `p' of `products'
				loc			labels `labels' `p' "`name'"
			}
			loc			key legend(order(1 "0%" 6 "25%" 11 "50%" 16 "75%" 21 "100%") ///
						rows(1) pos(6) size(8pt) symxsize(3) symysize(1.8) region(lstyle(none)))
		}
		else {
			loc			fixed country outcome_var product
			loc			k 14
			loc			title "A2. Across rainfall metrics"
			loc			subtitle "Within country, outcome and remote sensing product"
			loc			labels 1(1)14
			loc			key legend(off)
		}
		loc			expected = 1008 / `k'
		keep		`fixed' `instrument' sig_reg7 sig_reg2
		rename		(`instrument' sig_reg7 sig_reg2) (col col7 col2)
		save		"`other'", replace
		rename		(col col7 col2) (row row7 row2)
		joinby		`fixed' using "`other'"
		drop if		row == col
		isid		`fixed' row col
		bysort row col: assert _N == `expected'

	* With row 1 at the top, row < col is the upper triangle (Year FE).
		gen byte	disagree = row7 != col7 if row < col & !missing(row7, col7)
		replace		disagree = row2 != col2 if row > col & !missing(row2, col2)
		collapse	(count) comparisons = disagree (sum) changes = disagree, by(row col)
		gen int		absent = `expected' - comparisons
		assert		inrange(absent, 0, `expected') & _N == `k' * (`k' - 1)
		count if	absent
		display		"`instrument' pairs: " r(N) " cells below " `expected' " comparisons."
		list		row col comparisons absent if absent, noobs
		quietly summarize comparisons, meanonly
		loc			note_n "`expected' comparisons per cell"
		if r(min) < `expected' loc note_n "`=r(min)'-`=r(max)' comparisons per cell"
		gen double	share = 100 * changes / comparisons
		gen str4	cell = cond(comparisons, strtrim(string(share, "%3.0f")), "n/a")
		gen double	lo = row - .49
		gen double	hi = row + .49

	* Common 0-100% scale in five-point steps; the printed cell is rounded to 1%.
		gen byte	shade = round(share / 5)
		loc			tiles
		forvalues j = 0/20 {
			loc			rgb
			forvalues ch = 1/3 {
				loc			from : word `ch' of 243 245 247
				loc			to : word `ch' of `arc2'
				loc			rgb `rgb' `=round(`from' + `j'/20 * (`to' - `from'))'
			}
			loc			tiles `tiles' (rbar lo hi col if shade == `j', ///
						barwidth(.98) color("`rgb'") lcolor(none))
		}
		loc			cells msymbol(none) mlabel(cell) mlabpos(0) mlabsize(8pt)
		loc			axis labsize(8pt) labcolor("38 43 47") noticks nogrid
		twoway		`tiles' (scatter row col if shade < 13 | missing(shade), ///
					`cells' mlabcolor("38 43 47")) (scatter row col if ///
					inrange(shade, 13, 20), `cells' mlabcolor(white)), `panel' ///
					xscale(range(.5 `=`k'+.5') noline) ///
					yscale(reverse range(.5 `=`k'+.5') noline) ///
					xlabel(`labels', `axis') ylabel(`labels', angle(0) `axis') ///
					xtitle("") ytitle("") title("{bf:`title'}", `heading') ///
					subtitle("`subtitle'  |  `note_n'", `subhead') `key' name(comp_`instrument', replace)
	}


**********************************************************************
**# 2 - illustrative change in signed first-stage strength
**********************************************************************

	use			"`paired'", clear
	foreach s in reg7 reg2 {
		gen double	t_`s' = beta_`s' / stdrd_err_`s' if omission == "" & ///
					stdrd_err_`s' > 0
	}
	gen byte	complete = !missing(t_reg7, t_reg2)
	gen byte	flip = sig_reg7 != sig_reg2 if complete
	gen byte	reversal = t_reg7 * t_reg2 < 0 if complete
	gen double	shift = abs(t_reg2 - t_reg7)

* Among complete groups prefer examples exhibiting both types of change.
* Minimize the sum of distances to the median flip and reversal counts.
* Break ties by proximity to the typical median |change in t|, then raw IDs.
	preserve
		collapse	(sum) complete flip reversal (median) shift, by(country product outcome_var)
		keep if		complete == 14
		if _N == 0 {
			display		as error "Panel B requires a group with 14 valid paired t-statistics."
			error		2000
		}
		gen byte	types = (flip > 0) + (reversal > 0)
		quietly summarize types, meanonly
		keep if		types == r(max)
		foreach v in flip reversal shift {
			quietly summarize `v', detail
			gen double	dist_`v' = abs(`v' - r(p50))
		}
		gen double	distance = dist_flip + dist_reversal
		sort		distance dist_shift country product outcome_var
		loc			c = country[1]
		loc			p = product[1]
		loc			y = outcome_var[1]
		list		country product outcome_var flip reversal shift in 1, noobs
	restore
	keep if		country == `c' & product == `p' & outcome_var == "`y'"
	isid		metric, sort
	assert		_N == 14 & metric == _n & complete
	list		weather_var t_reg7 t_reg2 sig_reg7 sig_reg2, noobs
	loc			countries Ethiopia Malawi NA Niger Nigeria Tanzania Uganda
	loc			country : word `c' of `countries'
	loc			product : word `p' of `products'
	loc			outcome = cond("`y'" == "lncp_yld", "Cereal quantity", "Farm production value")

* Use identical bounds on both axes, including both thresholds and all endpoints.
	quietly summarize t_reg7, meanonly
	loc			lo = min(-1.96, r(min))
	loc			hi = max(1.96, r(max))
	quietly summarize t_reg2, meanonly
	loc			lo = min(`lo', r(min))
	loc			hi = max(`hi', r(max))
	loc			unit = 10^floor(log10((`hi' - `lo')/5))
	loc			step = `unit' * cond((`hi'-`lo')/5 < 2*`unit', 1, ///
				cond((`hi'-`lo')/5 < 5*`unit', 2, 5))
	loc			lo = floor(`lo'/`step')*`step'
	loc			hi = ceil(`hi'/`step')*`step'
	loc			span = `hi' - `lo'

* Put nearby numbers in a shared column, in endpoint order, with short leaders.
	sort		t_reg7 metric
	gen byte	column = sum(_n == 1 | t_reg7 - t_reg7[_n-1] > .075*`span')
	bysort column (t_reg2 metric): gen double label_y = t_reg2
	by column: replace label_y = max(t_reg2, label_y[_n-1] + .075*`span') if _n > 1
	egen double	offset = mean(label_y - t_reg2), by(column)
	replace		label_y = label_y - offset
	egen double	label_x = max(t_reg7), by(column)
	replace		label_x = label_x + .045*`span'
	quietly summarize label_x, meanonly
	loc			hi = max(`hi', ceil((r(max) + .045*`span')/`step')*`step')
	quietly summarize label_y, meanonly
	loc			hi = max(`hi', ceil(r(max)/`step')*`step')
	loc			lo = min(`lo', floor(r(min)/`step')*`step')
	loc			arrows lwidth(.8pt) msize(.7) barbsize(.65) mlwidth(.5pt)
	loc			colors arc2 chirps cpc era5 merra2 tamsat
	loc			color : word `p' of `colors'
	loc			dashes lpattern(shortdash) lwidth(.5pt) lcolor("153 160 167")
	twoway		(function y = x, range(`lo' `hi') lcolor("106 114 121") lwidth(.7pt)) ///
				(pcarrow t_reg7 t_reg7 t_reg2 t_reg7 if !flip, `arrows' color("101 110 118")) ///
				(pcarrow t_reg7 t_reg7 t_reg2 t_reg7 if flip, `arrows' color("``color''")) ///
				(scatter t_reg2 t_reg7 if reversal, msymbol(Oh) msize(5.5pt) mlwidth(.6pt) mcolor(black)) ///
				(pcspike t_reg2 t_reg7 label_y label_x, ///
				lcolor("142 149 155") lwidth(.45pt)) ///
				(scatter label_y label_x, msymbol(none) mlabel(metric) mlabpos(3) ///
				mlabgap(.3) mlabsize(8pt) mlabcolor("38 43 47")), `frame' ///
				aspectratio(1, placement(west)) plotregion(margin(zero)) ///
				xlabel(`lo'(`step')`hi', nogrid labsize(8pt)) ///
				ylabel(`lo'(`step')`hi', nogrid angle(0) labsize(8pt)) ///
				xline(-1.96 1.96, `dashes') yline(-1.96 1.96, `dashes') ///
				xtitle("Year FE  (signed t)", size(9pt)) ///
				ytitle("Year + household FE  (signed t)", size(9pt)) ///
				title("{bf:B. Adding household fixed effects}", `heading') ///
				subtitle("`country'  /  `product'  /  `outcome'", `subhead') ///
				legend(order(2 "Same 5% decision" 3 "Changed decision" 4 "Sign reversal") ///
				cols(1) pos(3) size(8pt) symxsize(3) region(lstyle(none))) name(comp_arrows, replace)


**********************************************************************
**# 3 - shared metric key and manuscript exports
**********************************************************************

* The key identifies both the matrix axes and the arrow endpoints.
	label define metric_key 1 "Mean daily rainfall" 2 "Median daily rainfall" ///
				3 "SD of daily rainfall" 4 "Skew of daily rainfall" ///
				5 "Total rainfall" 6 "Deviation in total rainfall" 7 "Z-score of total rainfall" ///
				8 "Rainy days" 9 "Deviation in rainy days" 10 "No rain days" ///
				11 "Deviation in no rain days" 12 "Percent rainy days" ///
				13 "Deviation in percent rainy days" 14 "Longest mid-window dry spell", replace
	label values metric metric_key
	decode		metric, gen(metric_name)
	gen str4	id = string(metric)
	gen byte	x_id = 1
	gen byte	x_name = 2
	gen byte	x_year = 12
	gen byte	x_hh = 16
	foreach s in reg7 reg2 {
		gen str8	label_`s' = strtrim(string(t_`s', "%6.2f"))
	}
	loc			label msymbol(none) mlabgap(0) mlabsize(9pt) mlabcolor("38 43 47")
	twoway		(scatter metric x_id, `label' mlabel(id) mlabpos(9)) ///
				(scatter metric x_name, `label' mlabel(metric_name) mlabpos(3)) ///
				(scatter metric x_year, `label' mlabel(label_reg7) mlabpos(9)) ///
				(scatter metric x_hh, `label' mlabel(label_reg2) mlabpos(9)), `panel' ///
				xscale(range(0 17) off) yscale(range(-.5 14.7) reverse off) ///
				ylabel(1(1)14, nogrid) xlabel(none) legend(off) ///
				text(0 2 "{bf:Rainfall metric}", place(e) size(9pt)) ///
				text(0 12 "{bf:Year FE}" 0 16 "{bf:+ Household FE}", place(w) size(9pt)) ///
				yline(.5, lcolor("177 184 190") lwidth(.6pt) lpattern(solid)) ///
				title("{bf:Metric key and signed t-statistics}", `heading') name(comp_key, replace)

	graph combine comp_product comp_arrows comp_metric comp_key, cols(2) ///
				xsize(11.5) ysize(8.5) iscale(1) imargin(small) ///
				scheme(stcolor) graphregion(color(white) margin(small)) ///
				note("A1 and A2 show disagreement in 5% significance decisions (%). Year FE appears above the diagonal and year + household FE below it." ///
				"In B, arrows start on the equality line. Dashed guides mark t = -1.96 and +1.96. Significance decisions use the saved p-values.", size(8.5pt)) ///
				name(metric_comp, replace)
	graph export "$xfig/metric_comp.pdf", replace
	graph export "$xfig/metric_comp.png", width(4400) replace

/* END */
