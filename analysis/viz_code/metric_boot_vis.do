* Project: WB Weather - metric
* Created on: 27 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 30 Oct 2026
* Stata v.18.0

* does
	* summarizes completed bootstrap coefficient changes
	* draws six specification charts, a heat map, and a metric-country plot
	* saves the collapsed counts and shares used in each figure

* assumes
	* projectdo.do has established the code and data globals
	* metric_boot.do has saved the completed production results

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	global		root	"$data/results_data"
	global		xfig	"$data/results_data/figures/metric_paper"
	global		logout	"$data/results_data/logs"

* open log and completed bootstrap results
	cap log close
	log using	"$logout/metric_boot_vis", text replace
	include		"$code/analysis/viz_code/metric_palette.do"
	use			"$root/rainfall_FE_bootstrap_differences", clear


**********************************************************************
**# 1 - prepare and validate the completed specifications
**********************************************************************

* flag incomplete results before calculating any descriptive shares
	isid		country outcome_var weather_var
	gen byte	valid = status == "ok" & run_mode == "full" & ///
				ci_method == "percentile" & return_code == 0 & ///
				successful_reps == requested_reps & failed_reps == 0 & ///
				ref_okreg2 == 1 & ref_okreg7 == 1 & ///
				!missing(beta_reg2, beta_reg7, ci_lo_raw, ci_hi_raw) & ///
				ci_lo_raw <= ci_hi_raw & ///
				N == ref_nreg2 & N == ref_nreg7 & ///
				N_clusters == ref_hhreg2 & N_clusters == ref_hhreg7
	list		country outcome_var weather_var status successful_reps ///
				failed_reps if !valid, noobs
	assert		valid
	assert		_N == 1008
	assert		inlist(country, 1, 2, 4, 5, 6, 7)
	assert		metric == real(substr(weather_var, 2, 2))
	assert		product == real(substr(weather_var, 7, 1))
	bysort country: assert _N == 168
	bysort country product: assert _N == 28
	bysort country metric: assert _N == 12
	display		"Validated 1,008 specifications: 168 per country, " ///
				"28 per country-product, 12 per country-metric."
	summarize	successful_reps requested_reps

* only the saved percentile interval defines a significant change
	gen byte	sig_change = ci_lo_raw > 0 | ci_hi_raw < 0
	gen byte	smaller = abs(beta_reg2) < abs(beta_reg7)
	gen byte	reversal = beta_reg2 * beta_reg7 < 0
	foreach v in sig_change smaller reversal {
		quietly count if `v'
		display		"`v': " r(N) " of " _N " (" ///
					%5.1f (100 * r(N) / _N) "%)"
	}

* retain the metric descriptions used in the existing bootstrap charts
	label define metric 1 "Mean rainfall" 2 "Median rainfall" ///
				3 "SD of rainfall" 4 "Skewness" 5 "Total rainfall" ///
				6 "Deviation in total" 7 "Standardized total" ///
				8 "Rainy days" 9 "Deviation in rainy days" 10 "Dry days" ///
				11 "Deviation in dry days" 12 "Share of rainy days" ///
				13 "Deviation in share" 14 "Mid-window dry spell", replace
	label values metric metric

* verify raw product codes against both names and weather-variable suffixes
	loc			products ARC2 CHIRPS CPC ERA5 MERRA-2 TAMSAT
	forvalues p = 1/6 {
		loc			product : word `p' of `products'
		assert		product_name == "`product'" if product == `p'
	}
	label define product 1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT", replace
	label values product product
	label define country 1 "Ethiopia" 2 "Malawi" 4 "Niger" ///
				5 "Nigeria" 6 "Tanzania" 7 "Uganda", replace
	label values country country
	levelsof	country, local(countries)
	loc			country_rows
	loc			i = 0
	foreach c of local countries {
		loc			i = `i' + 1
		loc			country : label (country) `c'
		loc			country_rows `country_rows' `i' "`country'"
	}


* prepare the specification strips and saved bootstrap interval groups
	gen byte	outcome = cond(outcome_var == "lncp_yld", 1, 2)
	gen byte	product_row = product + 4
	gen byte	metric_row = metric + 12
	gen byte	crosses_zero = ci_lo_std <= 0 & ci_hi_std >= 0
	assert		!missing(delta_std, ci_lo_std, ci_hi_std)
	assert		ci_lo_std <= ci_hi_std
	gen byte	sig_group = cond(crosses_zero, 0, cond(delta_std > 0, 1, 2))
	tabulate	country crosses_zero
	tabulate	country sig_group
	loc			colors arc2 chirps cpc era5 merra2 tamsat
	loc			rows 1 "Cereal quantity" 2 "Farm production value" ///
				3 "{bf:Outcome}" 5 "ARC2" 6 "CHIRPS" 7 "CPC" ///
				8 "ERA5" 9 "MERRA-2" 10 "TAMSAT" 11 "{bf:Product}" ///
				13 "Mean rainfall" 14 "Median rainfall" 15 "SD of rainfall" ///
				16 "Skewness" 17 "Total rainfall" 18 "Deviation in total" ///
				19 "Standardized total" 20 "Rainy days" ///
				21 "Deviation in rainy days" 22 "Dry days" ///
				23 "Deviation in dry days" 24 "Share of rainy days" ///
				25 "Deviation in share" 26 "Mid-window dry spell" 27 "{bf:Rainfall metric}"


**********************************************************************
**# 2 - country specification charts
**********************************************************************

	loc			stubs eth mwi ngr nga tza uga
	loc			i = 0
	foreach c of local countries {
		preserve
			keep if		country == `c'
			sort		delta_std outcome_var weather_var
			gen int		rank = _n
			loc			n = _N
			loc			xticks 1
			if `n' >= 24 loc xticks "1 24(24)`n'"
			if `n' > 1 & mod(`n', 24) != 0 loc xticks "`xticks' `n'"
			loc			country : label (country) `c'
			loc			i = `i' + 1
			loc			stub : word `i' of `stubs'

		* put the coefficient band above the existing specification strips
			quietly summarize ci_lo_std, meanonly
			loc			lo = min(0, r(min))
			quietly summarize ci_hi_std, meanonly
			loc			hi = max(0, r(max))
			loc			span = `hi' - `lo'
			loc			lo = `lo' - .05 * `span'
			loc			hi = `hi' + .05 * `span'
			loc			unit = 10^floor(log10((`hi' - `lo') / 4))
			loc			fraction = (`hi' - `lo') / (4 * `unit')
			loc			step = `unit' * cond(`fraction' >= 5, 5, ///
						cond(`fraction' >= 2, 2, 1))
			loc			tick_lo = ceil(`lo' / `step') * `step'
			loc			tick_hi = floor(`hi' / `step') * `step'
			loc			bottom = `lo' - 3 * (`hi' - `lo')
			loc			strips
			forvalues p = 1/6 {
				loc			color : word `p' of `colors'
				loc			strips `strips' ///
					(scatter product_row rank if product == `p', ///
					mcolor("``color''") mlcolor(none) msymbol(O) msize(1))
			}

		* match the plus and hollow-triangle scheme in the specification plots
		* classify the difference using its saved 95% percentile interval
			twoway		(rbar ci_lo_std ci_hi_std rank if sig_group == 0, ///
						yaxis(2) barwidth(.2) color(black%50) lwidth(.576pt)) ///
						(rbar ci_lo_std ci_hi_std rank if sig_group == 1, ///
						yaxis(2) barwidth(.2) color(edkblue%50) lwidth(.576pt)) ///
						(rbar ci_lo_std ci_hi_std rank if sig_group == 2, ///
						yaxis(2) barwidth(.2) color(maroon%50) lwidth(.576pt)) ///
						(function y = 0, range(.5 `=`n'+.5') yaxis(2) ///
						lcolor("112 119 125") lwidth(thin)) ///
						(scatter delta_std rank if sig_group == 0, yaxis(2) ///
						mcolor(black%75) msymbol(Th) msize(3pt) mlwidth(.864pt)) ///
						(scatter delta_std rank if sig_group == 1, yaxis(2) ///
						mcolor(edkblue%75) msymbol(+) msize(3pt) mlwidth(.864pt)) ///
						(scatter delta_std rank if sig_group == 2, yaxis(2) ///
						mcolor(maroon%75) msymbol(+) msize(3pt) mlwidth(.864pt)) ///
						`strips' ///
						(scatter outcome metric_row rank, ///
						mcolor("93 104 114" "93 104 114") ///
						mlcolor(none none) msymbol(O O) msize(.8 .8)), ///
						scheme(stcolor) ///
						legend(order(5 "95% CI includes zero" ///
						6 "Positive, CI excludes zero" 7 "Negative, CI excludes zero") ///
						cols(3) size(2.1) pos(6) region(lstyle(none))) ///
						graphregion(color(white) margin(small)) ///
						plotregion(color(white) lstyle(none)) ///
						yscale(range(0 40) noline axis(1)) ///
						yscale(range(`bottom' `hi') noline axis(2)) ///
						ylabel(`rows', axis(1) labsize(2.1) ///
						labcolor("38 43 47") noticks nogrid angle(horizontal)) ///
						ylabel(`tick_lo'(`step')`tick_hi', axis(2) format(%6.3g) ///
						labsize(2.5) labcolor("38 43 47") nogrid angle(horizontal)) ///
						xscale(range(.5 `=`n'+.5') noextend lcolor("38 43 47")) ///
						xlabel(`xticks', labsize(2.5) nogrid) ///
						xtitle("Specification rank", size(3)) ///
						ytitle("", axis(1)) ///
						ytitle("Standardized coefficient difference (reg2 - reg7)", ///
						axis(2) size(3)) ///
						title("{bf:`country'}", size(3.8) color("38 43 47")) ///
						xsize(9) ysize(6.5) name(boot_`c', replace)
			graph export ///
				"$xfig/`stub'_boot.pdf", name(boot_`c') replace
			graph export ///
				"$xfig/`stub'_boot.png", name(boot_`c') ///
						width(3200) replace

		restore
	}


**********************************************************************
**# 3 - country-product shares for the heat map
**********************************************************************

preserve
	collapse	(count) denominator = sig_change ///
				(sum) n_change = sig_change n_smaller = smaller ///
				n_reversal = reversal, by(country product)
	assert		denominator == 28
	gen double	share_change = 100 * n_change / denominator
	gen double	share_smaller = 100 * n_smaller / denominator
	gen double	share_reversal = 100 * n_reversal / denominator
	egen byte	country_row = group(country)
	decode		country, gen(country_name)
	decode		product, gen(product_name)
	save		"$root/boot_country_product", replace

restore


**********************************************************************
**# 4 - metric dot plot with six country series
**********************************************************************

* calculate one pooled metric order, retaining every country-metric cell
	collapse	(count) denominator = sig_change ///
				(sum) n_change = sig_change n_smaller = smaller ///
				n_reversal = reversal, by(country metric)
	assert		denominator == 12
	gen double	share_change = 100 * n_change / denominator
	gen double	share_smaller = 100 * n_smaller / denominator
	gen double	share_reversal = 100 * n_reversal / denominator
	egen int	pooled_changes = total(n_change), by(metric)
	egen int	pooled_n = total(denominator), by(metric)
	gen double	pooled_share = 100 * pooled_changes / pooled_n
	gen int		pooled_sort = -pooled_changes
	egen byte	metric_order = group(pooled_sort metric)
	decode		country, gen(country_name)
	decode		metric, gen(metric_name)
	sort		country metric_order
	save		"$root/boot_country_metric", replace
	export delimited country country_name metric metric_name metric_order ///
				denominator n_change n_smaller n_reversal share_change ///
				share_smaller share_reversal pooled_share using ///
				"$root/metric_boot_metric.csv", nolabel replace
	loc			rows
	forvalues m = 1/14 {
		quietly summarize metric_order if metric == `m', meanonly
		loc			row = r(min)
		loc			metric : label (metric) `m'
		loc			rows `rows' `row' "`metric'"
	}

* country colors and shapes are distinct from the product encoding
	loc			eth "68 119 170"
	loc			mwi "102 204 238"
	loc			ngr "34 136 51"
	loc			nga "204 187 68"
	loc			tza "238 102 119"
	loc			uga "170 51 119"
	loc			country_colors eth mwi ngr nga tza uga
	loc			symbols O D T S + X
	loc			points
	loc			i = 0
* keep six fixed vertical slots while leaving percentages unchanged
	foreach c of local countries {
		loc			i = `i' + 1
		loc			color : word `i' of `country_colors'
		loc			symbol : word `i' of `symbols'
		gen double	dot_`c' = metric_order + .16 * (`i' - 3.5)
		loc			points `points' ///
			(scatter dot_`c' share_change if country == `c', ///
			mcolor("``color''") msymbol(`symbol') msize(2.7pt))
	}
	twoway		`points', scheme(stcolor) xsize(6.5) ysize(6.5) ///
				graphregion(color(white) margin(small)) ///
				plotregion(color(white) lstyle(none)) ///
				xscale(range(0 100) noextend lcolor("112 119 125")) ///
				xlabel(0(20)100, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				xtitle("Share with significant coefficient change (%)", size(9pt)) ///
				ytitle("") yscale(reverse range(.5 14.5) noline) ///
				ylabel(`rows', labsize(8.5pt) labcolor("38 43 47") ///
				angle(0) noticks nogrid) ///
				legend(order(1 "Ethiopia" 2 "Malawi" 3 "Niger" ///
				4 "Nigeria" 5 "Tanzania" 6 "Uganda") cols(3) size(8pt) ///
				pos(6) bmargin(zero) region(lstyle(none) margin(zero))) ///
				name(boot_metric, replace)
	graph export "$xfig/boot_metric.pdf", name(boot_metric) replace
	graph export "$xfig/boot_metric.png", name(boot_metric) ///
				width(3300) replace


**********************************************************************
**# 5 - country-product heat maps on one percentage scale
**********************************************************************

* keep the same country-product shares and alphabetical product columns
	use			"$root/boot_country_product", clear
	reshape long n_ share_, i(country product) j(measure) string
	rename		(n_ share_) (numerator share)
	gen byte	measure_id = cond(measure == "change", 1, ///
				cond(measure == "smaller", 2, 3))
	label define measure 1 "Significant change" ///
				2 "Smaller absolute coefficient" 3 "Sign reversal", replace
	label values measure_id measure
	gen double	heat_x = product + 8 * (measure_id - 1)
	gen double	row_lo = country_row - .49
	gen double	row_hi = country_row + .49
	gen str4	cell_label = strtrim(string(share, "%3.0f")) + "%"
	save		"$root/boot_country_product_heatmap", replace

* exact shares occur in steps of 1/28; use one sequential 0-100% palette
	loc			tiles
	forvalues j = 0/28 {
		loc			r = round(243 + (`j' / 28) * (40 - 243))
		loc			g = round(245 + (`j' / 28) * (86 - 245))
		loc			b = round(247 + (`j' / 28) * (154 - 247))
		loc			tiles `tiles' ///
			(rbar row_lo row_hi heat_x if numerator == `j', ///
			barwidth(.98) color("`r' `g' `b'") fintensity(100) ///
			lcolor(white) lwidth(vthin))
	}
	loc			key
	forvalues j = 0/4 {
		loc			r = round(243 + (`j' / 4) * (40 - 243))
		loc			g = round(245 + (`j' / 4) * (86 - 245))
		loc			b = round(247 + (`j' / 4) * (154 - 247))
		loc			key `key' (scatteri . ., msymbol(S) ///
			mcolor("`r' `g' `b'") mlcolor(none) msize(7pt))
	}
	loc			columns
	forvalues m = 0/2 {
		forvalues p = 1/6 {
			loc			product : word `p' of `products'
			loc			x = `p' + 8 * `m'
			loc			columns `columns' `x' "`product'"
		}
	}
	twoway		`tiles' ///
				(scatter country_row heat_x if share < 75, msymbol(none) ///
				mlabel(cell_label) mlabpos(0) mlabsize(8pt) mlabcolor("38 43 47")) ///
				(scatter country_row heat_x if share >= 75, msymbol(none) ///
				mlabel(cell_label) mlabpos(0) mlabsize(8pt) mlabcolor(white)) ///
				`key', scheme(stcolor) xsize(9) ysize(4.2) ///
				graphregion(color(white) margin(small)) ///
				plotregion(color(white) lstyle(none)) ///
				xscale(range(.5 22.5) noline) ///
				xlabel(`columns', angle(45) labsize(8pt) ///
				labcolor("38 43 47") noticks nogrid) ///
				text(.125 3.5 "Significant change (%)" ///
				.125 11.5 "Smaller absolute coefficient (%)" ///
				.125 19.5 "Sign reversal (%)", size(8.5pt) ///
				color("38 43 47") placement(center)) ///
				xtitle("") ytitle("") yscale(reverse range(-.25 6.5) noline) ///
				ylabel(`country_rows', labsize(9pt) labcolor("38 43 47") ///
				angle(0) noticks nogrid) ///
				legend(order(32 "0%" 33 "25%" 34 "50%" 35 "75%" 36 "100%") ///
				cols(5) size(8pt) pos(6) bmargin(zero) ///
				region(lstyle(none) margin(zero))) ///
				name(boot_heat, replace)
	graph export "$xfig/boot_heat.pdf", name(boot_heat) replace
	graph export "$xfig/boot_heat.png", name(boot_heat) width(3300) replace


**********************************************************************
**# 6 - end matter
**********************************************************************

* close the log
	display		"Completed eight figures and their collapsed datasets; no bootstrap rerun."
	log close

/* END */
