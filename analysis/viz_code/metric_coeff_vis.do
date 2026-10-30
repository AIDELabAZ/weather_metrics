* Project: WB Weather - metric
* Created on: 30 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 30 Oct 2026
* Stata v.19.5

* does
	* creates bootstrap, paired coefficient, and diagnostic figures

* assumes
	* projectdo.do has established the code and data globals
	* completed regression and bootstrap results

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	global		root	"$data/results_data"
	global		xfig	"$data/results_data/figures/metric_paper"
	global		logout	"$data/results_data/logs"

* open one log for the complete visualization file
	cap log close
	log using	"$logout/metric_coeff.log", text replace

* load the shared product colors
	include		"$code/analysis/viz_code/metric_palette.do"


**********************************************************************
**# 1 - bootstrap figures
**********************************************************************


**********************************************************************
**## 1.1 - prepare and validate the completed specifications
**********************************************************************

* load results for this figure group
	use			"$root/rainfall_FE_bootstrap_differences", clear

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
	label define metric 1 "Mean Rainfall" 2 "Median Rainfall" ///
				3 "SD Of Rainfall" 4 "Skewness" 5 "Total Rainfall" ///
				6 "Deviation In Total" 7 "Standardized Total" ///
				8 "Rainy Days" 9 "Deviation In Rainy Days" 10 "Dry Days" ///
				11 "Deviation In Dry Days" 12 "Share Of Rainy Days" ///
				13 "Deviation In Share" 14 "Mid-Window Dry Spell", replace
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
	loc			rows 1 "Cereal Quantity" 2 "Farm Production Value" ///
				3 "{bf:Outcome}" 5 "ARC2" 6 "CHIRPS" 7 "CPC" ///
				8 "ERA5" 9 "MERRA-2" 10 "TAMSAT" 11 "{bf:Product}" ///
				13 "Mean Rainfall" 14 "Median Rainfall" 15 "SD Of Rainfall" ///
				16 "Skewness" 17 "Total Rainfall" 18 "Deviation In Total" ///
				19 "Standardized Total" 20 "Rainy Days" ///
				21 "Deviation In Rainy Days" 22 "Dry Days" ///
				23 "Deviation In Dry Days" 24 "Share Of Rainy Days" ///
				25 "Deviation In Share" 26 "Mid-Window Dry Spell" 27 "{bf:Rainfall Metric}"


**********************************************************************
**## 1.2 - country specification charts
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
						legend(order(5 "95% CI Includes Zero" ///
						6 "Positive, CI Excludes Zero" 7 "Negative, CI Excludes Zero") ///
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
						xtitle("Specification Rank", size(3)) ///
						ytitle("", axis(1)) ///
						ytitle("Standardized Coefficient Difference", ///
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
**## 1.3 - country-product shares for the heat map
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
**## 1.4 - metric dot plot with six country series
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
				xtitle("Share With Significant Coefficient Change (%)", size(9pt)) ///
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
**## 1.5 - country-product heat maps on one percentage scale
**********************************************************************

* keep the same country-product shares and alphabetical product columns
	use			"$root/boot_country_product", clear
	reshape long n_ share_, i(country product) j(measure) string
	rename		(n_ share_) (numerator share)
	gen byte	measure_id = cond(measure == "change", 1, ///
				cond(measure == "smaller", 2, 3))
	label define measure 1 "Significant Change" ///
				2 "Smaller Absolute Coefficient" 3 "Sign Reversal", replace
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
				text(.125 3.5 "Significant Change (%)" ///
				.125 11.5 "Smaller Absolute Coefficient (%)" ///
				.125 19.5 "Sign Reversal (%)", size(8.5pt) ///
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
**# 2 - paired specification charts
**********************************************************************


**********************************************************************
**## 2.1 - prepare paired regression results
**********************************************************************

* pair the original outcome and full rainfall-variable identifiers
	use			"$root/lsms_complete_results", clear
	keep if		paired_sample == 1 & inlist(spec_id, "reg7", "reg2") & ///
				inlist(outcome_var, "lncp_yld", "lntf_yld") & ///
				regexm(weather_var, "^v(0[1-9]|1[0-4])_rf[1-6]$")
	isid		country outcome_var weather_var spec_id
	assert		year_fe == 1 & household_fe == (spec_id == "reg2")
	keep		country outcome_var weather_var spec_id beta ci_lo ci_up ///
				pval estimable
	gen byte	present = 1
	rename		(beta ci_lo ci_up pval estimable present) ///
				(beta_ ci_lo_ ci_up_ pval_ estimable_ present_)
	reshape wide beta_ ci_lo_ ci_up_ pval_ estimable_ present_, ///
				i(country outcome_var weather_var) j(spec_id) string
	tempfile	paired
	save		"`paired'"

* account for all 168 possible pairs in each of the six countries
	clear
	set obs		6
	gen byte	country = real(word("1 2 4 5 6 7", _n))
	expand		2
	bysort country: gen str9 outcome_var = ///
				cond(_n == 1, "lncp_yld", "lntf_yld")
	expand		84
	bysort country outcome_var: gen str7 weather_var = ///
				"v" + string(ceil(_n / 6), "%02.0f") + ///
				"_rf" + string(mod(_n - 1, 6) + 1)
	merge		1:1 country outcome_var weather_var using "`paired'", nogen
	gen str40	omission = ""
	replace		omission = "reg7 missing" if present_reg7 != 1
	replace		omission = "reg2 missing" if present_reg2 != 1
	replace		omission = "Both models missing" if ///
				present_reg7 != 1 & present_reg2 != 1
	replace		omission = "Non-estimable coefficient" if ///
				present_reg7 == 1 & present_reg2 == 1 & ///
				(estimable_reg7 != 1 | estimable_reg2 != 1)
	replace		omission = "Missing coefficient, CI or p-value" if ///
				omission == "" & missing(beta_reg7, beta_reg2, ///
				ci_lo_reg7, ci_up_reg7, ci_lo_reg2, ci_up_reg2, ///
				pval_reg7, pval_reg2)
	count		if omission != ""
	if r(N) > 0 {
		tabulate	country outcome_var if omission != "", missing
		list		country outcome_var weather_var omission if omission != "", ///
					noobs sepby(country outcome_var)
	}
	egen int	pairs = total(omission == ""), by(country)
	gen int		omitted = 168 - pairs
	egen byte	first = tag(country)
	list		country pairs omitted if first, noobs
	keep if		omission == ""

* rank once by signed reg7; every plotted layer uses this same index
	bysort country (beta_reg7 outcome_var weather_var): gen int rank = _n
	gen byte	product = real(substr(weather_var, 7, 1))
	gen byte	metric = real(substr(weather_var, 2, 2))
	gen double	outcome_row = cond(outcome_var == "lncp_yld", 39, 37.5)
	gen double	product_row = 34.5 - 1.5 * product
	gen double	metric_row = 22.5 - 1.5 * metric
	egen double	ci_min = rowmin(ci_lo_reg7 ci_lo_reg2)
	egen double	ci_max = rowmax(ci_up_reg7 ci_up_reg2)
	save		"`paired'", replace


**********************************************************************
**## 2.2 - paired specification charts
**********************************************************************

* retain the existing metric names and alphabetical product order
	loc			rows 40.5 "{bf:Dependent Variable}" 39 "Quantity" 37.5 "Value" ///
				34.5 "{bf:Remote Sensing Product}" 33 "ARC2" 31.5 "CHIRPS" ///
				30 "CPC" 28.5 "ERA5" 27 "MERRA-2" 25.5 "TAMSAT" ///
				22.5 "{bf:Rainfall Metric}" 21 "Mean Daily Rainfall" ///
				19.5 "Median Daily Rainfall" 18 "Variance Of Daily Rainfall" ///
				16.5 "Skew Of Daily Rainfall" 15 "Total Rainfall" ///
				13.5 "Deviation In Total Rainfall" 12 "Z-Score Of Total Rainfall" ///
				10.5 "Rainy Days" 9 "Deviation In Rainy Days" 7.5 "No Rain Days" ///
				6 "Deviation In No Rain Days" 4.5 "Percent Rainy Days" ///
				3 "Deviation In Percent Rainy Days" 1.5 "Longest Dry Spell"
	loc			countries 1 2 4 5 6 7
	loc			stubs eth mwi ngr nga tza uga
	loc			colors arc2 chirps cpc era5 merra2 tamsat
	loc			i = 0
	foreach c of local countries {
		use			"`paired'", clear
		keep if		country == `c'
		loc			i = `i' + 1
		loc			stub : word `i' of `stubs'
		loc			n = _N
		loc			xmax = `n' + 1
		quietly count if beta_reg7 < 0
		loc			cut = r(N) + .5

	* use one coefficient range for both panels, including all CIs and zero
		quietly summarize ci_min, meanonly
		loc			lo = min(0, r(min))
		quietly summarize ci_max, meanonly
		loc			hi = max(0, r(max))
		loc			span = `hi' - `lo'
		loc			unit = 10^floor(log10(`span' / 4))
		loc			fraction = `span' / (4 * `unit')
		loc			step = `unit' * cond(`fraction' <= 1, 1, ///
					cond(`fraction' <= 2, 2, cond(`fraction' <= 5, 5, 10)))
		loc			lo = floor((`lo' - .03 * `span') / `step') * `step'
		loc			hi = ceil((`hi' + .03 * `span') / `step') * `step'
		loc			gain = 7.5 / (`hi' - `lo')
		loc			nticks = round((`hi' - `lo') / `step')
		loc			ticks
		forvalues j = 0/`nticks' {
			loc			value = `lo' + `j' * `step'
			loc			label = strtrim(string(`value', "%6.3g"))
			loc			y7 = 52 + `gain' * (`value' - `lo')
			loc			y2 = 42.5 + `gain' * (`value' - `lo')
			loc			ticks `ticks' `y7' "`label'" `y2' "`label'"
		}

	* position two bands on one canvas; axis labels retain the original units
		loc			plots
		foreach m in reg7 reg2 {
			loc			bottom = cond("`m'" == "reg7", 52, 42.5)
			gen double	y_`m' = `bottom' + `gain' * (beta_`m' - `lo')
			gen double	lo_`m' = `bottom' + `gain' * (ci_lo_`m' - `lo')
			gen double	hi_`m' = `bottom' + `gain' * (ci_up_`m' - `lo')
			loc			zero_`m' = `bottom' - `gain' * `lo'
			loc			plots `plots' ///
				(rbar lo_`m' hi_`m' rank if pval_`m' > .05, yaxis(2) ///
				barwidth(.2) color(black%50) lwidth(.576pt)) ///
				(rbar lo_`m' hi_`m' rank if pval_`m' <= .05 & beta_`m' >= 0, ///
				yaxis(2) barwidth(.2) color(edkblue%50) lwidth(.576pt)) ///
				(rbar lo_`m' hi_`m' rank if pval_`m' <= .05 & beta_`m' < 0, ///
				yaxis(2) barwidth(.2) color(maroon%50) lwidth(.576pt)) ///
				(scatter y_`m' rank if pval_`m' > .05, yaxis(2) ///
				mcolor(black%75) msymbol(Th) msize(3pt) mlwidth(.864pt)) ///
				(scatter y_`m' rank if pval_`m' <= .05 & beta_`m' >= 0, ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) msize(3pt) mlwidth(.864pt)) ///
				(scatter y_`m' rank if pval_`m' <= .05 & beta_`m' < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) msize(3pt) mlwidth(.864pt))
		}

	* draw the shared indicator strip from those same ranks
		loc			strips
		forvalues p = 1/6 {
			loc			color : word `p' of `colors'
			loc			strips `strips' ///
				(scatter product_row rank if product == `p', ///
				mcolor("``color''") msize(1.5pt) mlwidth(.864pt))
		}
		twoway		`strips' ///
					(scatter outcome_row metric_row rank, ///
					mcolor("93 104 114" "93 104 114") msymbol(O O) ///
					msize(1.5pt 1.5pt) mlwidth(.864pt .864pt)) `plots', ///
					scheme(stcolor) xsize(9) ysize(5.5) ///
					graphregion(color(white) margin(l=8pt r=8pt t=4pt b=4pt)) ///
					plotregion(color(white) lstyle(none) margin(zero)) ///
					xscale(range(0 `xmax') noextend lcolor("112 119 125")) ///
					xlabel(1 24(24)`n', labsize(8.5pt) labcolor("38 43 47") ///
					glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
					xtitle("Specification Rank (Ordered By Year FE Coefficient)", ///
					size(8.5pt) color("38 43 47")) ///
					yscale(range(0 62) noline axis(1)) ///
					yscale(range(0 62) noline axis(2)) ///
					ylabel(`rows', axis(1) labsize(8pt) angle(0) ///
					labcolor("38 43 47") noticks nogrid) ///
					ylabel(`ticks', axis(2) labsize(8.5pt) angle(0) ///
					labcolor("38 43 47") noticks ///
					glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
					ytitle("", axis(1)) ytitle("", axis(2)) ///
					yline(`zero_reg7' `zero_reg2', axis(2) ///
					lcolor("112 119 125") lwidth(.864pt) lpattern(solid)) ///
					xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
					text(60.5 2 "{bf:Year FE}" 51 2 "{bf:Year + Household FE}", ///
					yaxis(2) placement(e) justification(left) size(9pt) ///
					color("38 43 47")) ///
					legend(order(12 "N.S." 13 "Positive, p < 0.05" ///
					14 "Negative, p < 0.05") cols(3) size(8.5pt) ///
					rowgap(.5) pos(12) bmargin(zero) ///
					region(lstyle(none) margin(zero)))
		graph export "$xfig/`stub'_pair.pdf", replace
		graph export "$xfig/`stub'_pair.png", width(3300) replace
	}


**********************************************************************
**# 3 - coefficient and strength diagnostics
**********************************************************************


**********************************************************************
**## 3.1 - prepare paired rainfall results
**********************************************************************

* load results for this figure group
	use			"$root/lsms_complete_results", clear

* retain the two outcomes and paired rainfall specifications
	keep if		paired_sample == 1 & inlist(spec_id, "reg2", "reg7") & ///
				inlist(outcome_var, "lncp_yld", "lntf_yld") & ///
				regexm(weather_var, "^v(0[1-9]|1[0-4])_rf[1-6]$")

* match models by country, outcome and the full weather identifier
	keep		country outcome_var weather_var spec_id beta stdrd_err estimable
	rename		(beta stdrd_err estimable) (beta_ stdrd_err_ estimable_)
	reshape wide beta_ stdrd_err_ estimable_, ///
				i(country outcome_var weather_var) j(spec_id) string
	keep if		estimable_reg2 == 1 & estimable_reg7 == 1

* calculate the absolute cluster-robust t-statistics
	gen 		double	abs_t_reg7 = abs(beta_reg7 / stdrd_err_reg7)
	gen 		double	abs_t_reg2 = abs(beta_reg2 / stdrd_err_reg2)

* identify regression products using their original weather suffixes
	gen byte	product = real(substr(weather_var, -1, 1))

* define the diagnostic graph appearance
	loc			teal "34 127 144"
	loc			copper "190 118 64"
	loc			frame scheme(stcolor) ///
				graphregion(color(white) margin(small)) ///
				plotregion(color(white) lstyle(none)) ///
				xscale(lcolor("38 43 47")) yscale(lcolor("38 43 47"))
	loc			ticks labsize(3) labcolor("38 43 47") tlcolor("38 43 47")
	loc			grid grid glcolor("242 244 246") glwidth(vthin) glpattern(solid)
	loc			labels 1 "{bf:Ethiopia}" 2 "{bf:Malawi}" ///
				4 "{bf:Niger}" 5 "{bf:Nigeria}" ///
				6 "{bf:Tanzania}" 7 "{bf:Uganda}"


**********************************************************************
**## 3.2 - coefficient magnitude versus precision
**********************************************************************

	preserve

	* calculate ratios in double precision, retaining negative SE changes
		gen double	x_beta = ln(abs(beta_reg2) / abs(beta_reg7)) / ln(2)
		gen double	y_se = ln(stdrd_err_reg2 / stdrd_err_reg7) / ln(2)

	* report invalid ratios and points outside the plotting window
		gen byte	invalid_ratio = missing(x_beta, y_se)
		gen byte	outside_window = !invalid_ratio & !inrange(x_beta, -6, 6)
		label var	invalid_ratio "Invalid Log Ratios"
		label var	outside_window "Outside -6 To +6"
		table		(country), statistic(frequency) ///
					statistic(sum invalid_ratio) statistic(sum outside_window)

	* narrow only the display window and retain the original common y-axis
		loc			xr = 6
		loc			dx = 3
		quietly summarize y_se if !invalid_ratio, meanonly
		loc			ymin = min(0, floor(r(min)))
		loc			ymax = max(1, ceil(r(max)))
		loc			dy = max(1, ceil((`ymax' - `ymin') / 5))
		loc			dmin = max(-`xr', `ymin')
		loc			dmax = min(`xr', `ymax')
		label define rain_country `labels', replace
		label values country rain_country

	* color both outcomes by the product identified by the regression suffix
		twoway		(scatter y_se x_beta if product == 1 & ///
					inrange(x_beta, -6, 6), ///
					mcolor("`arc2'%60") mlcolor(none) msymbol(O) msize(1.1)) ///
					(scatter y_se x_beta if product == 2 & ///
					inrange(x_beta, -6, 6), ///
					mcolor("`chirps'%60") mlcolor(none) msymbol(O) msize(1.1)) ///
					(scatter y_se x_beta if product == 3 & ///
					inrange(x_beta, -6, 6), ///
					mcolor("`cpc'%60") mlcolor(none) msymbol(O) msize(1.1)) ///
					(scatter y_se x_beta if product == 4 & ///
					inrange(x_beta, -6, 6), ///
					mcolor("`era5'%60") mlcolor(none) msymbol(O) msize(1.1)) ///
					(scatter y_se x_beta if product == 5 & ///
					inrange(x_beta, -6, 6), ///
					mcolor("`merra2'%60") mlcolor(none) msymbol(O) msize(1.1)) ///
					(scatter y_se x_beta if product == 6 & ///
					inrange(x_beta, -6, 6), ///
					mcolor("`tamsat'%60") mlcolor(none) msymbol(O) msize(1.1)) ///
					(function y = x, range(`dmin' `dmax') ///
					lcolor("112 119 125") lpattern(dash) lwidth(thin)), ///
					`frame' xscale(range(-`xr' `xr')) ///
					yscale(range(`ymin' `ymax')) ///
					xlabel(-`xr'(`dx')`xr', `grid' `ticks') ///
					ylabel(`ymin'(`dy')`ymax', `grid' `ticks' angle(horizontal)) ///
					xline(0, lcolor("112 119 125") lwidth(vthin) lpattern(solid)) ///
					yline(0, lcolor("112 119 125") lwidth(vthin) lpattern(solid)) ///
					xtitle("Change In |Rainfall Coefficient| (Log2 Ratio)", ///
					size(3) color("38 43 47")) ///
					ytitle("Change In Standard Error (Log2 Ratio)", ///
					size(3) color("38 43 47")) ///
					legend(order(1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
					4 "ERA5" 5 "MERRA-2" 6 "TAMSAT") cols(6) size(2.7) color("38 43 47") ///
					region(lstyle(none))) ///
					subtitle(, size(2.8) color("38 43 47") nobox fcolor(white)) ///
					by(country, cols(3) iscale(1) legend(pos(6)) note("") ///
					imargin(small) graphregion(color(white) margin(small))) ///
					xsize(7.2) ysize(4.8)

		graph export "$xfig/coef_precision.pdf", replace
		graph export "$xfig/coef_precision.png", ///
					width(3200) replace
	restore


**********************************************************************
**## 3.3 - first-stage strength survival curves
**********************************************************************

	preserve

	* count the full paired sample at every threshold, including its upper tail
		tempname	curves
		tempfile	survival
		postfile	`curves' byte country ///
					double(threshold share_reg7 share_reg2) using "`survival'", replace
		levelsof	country, local(countries)
		foreach c of local countries {
			quietly count if country == `c'
			loc			n = r(N)
			forvalues k = 0/300 {
				loc			cut = `k' / 20
				quietly count if country == `c' & abs_t_reg7 >= `cut'
				loc			s7 = r(N) / `n'
				quietly count if country == `c' & abs_t_reg2 >= `cut'
				loc			s2 = r(N) / `n'
				post		`curves' (`c') (`cut') (`s7') (`s2')
			}
		}
		postclose	`curves'
		use			"`survival'", clear
		label define rain_country `labels', replace
		label values country rain_country

		loc			benchmark = sqrt(23.1)

	* distinguish the two FE specifications with one shared legend
		twoway		(line share_reg7 threshold, sort ///
					lcolor("`teal'") lwidth(medium) lpattern(solid)) ///
					(line share_reg2 threshold, sort ///
					lcolor("`copper'") lwidth(medium) lpattern(solid)), ///
					`frame' xscale(range(0 15)) yscale(range(0 1)) ///
					xlabel(0(5)15, nogrid `ticks') ///
					ylabel(0(.2)1, format(%3.1f) `grid' `ticks' angle(horizontal)) ///
					xline(1.96, lcolor("160 166 172") ///
					lpattern(dot) lwidth(thin)) ///
					xline(`benchmark', lcolor("112 119 125") ///
					lpattern(dash) lwidth(thin)) ///
					xtitle("Absolute Cluster-Robust T-Statistic", ///
					size(3) color("38 43 47")) ///
					ytitle("Share Of Specifications Above Threshold", ///
					size(3) color("38 43 47")) ///
					legend(order(1 "Year FE" 2 "Year + Household FE") ///
					cols(2) size(3) color("38 43 47") region(lstyle(none))) ///
					subtitle(, size(2.8) color("38 43 47") nobox fcolor(white)) ///
					by(country, cols(3) iscale(1) legend(pos(6)) note("") ///
					imargin(small) graphregion(color(white) margin(small))) ///
					xsize(7.2) ysize(4.8)

		graph export "$xfig/strength_dist.pdf", replace
		graph export "$xfig/strength_dist.png", ///
					width(3200) replace
	restore


**********************************************************************
**## 3.4 - experimental strength curves by product
**********************************************************************

* both FE specifications use each country-product's paired inventory
	tabulate	country product
	display		"Each country-product count applies to both reg7 and reg2."
	preserve
		tempname	curves
		tempfile	products
		postfile	`curves' byte(country product) int eligible ///
					double(threshold share_reg7 share_reg2) using "`products'", replace
		levelsof	country, local(countries)
		foreach c of local countries {
			forvalues p = 1/6 {
				quietly count if country == `c' & product == `p'
				loc			n = r(N)
				forvalues k = 0/300 {
					loc			cut = `k' / 20
					quietly count if country == `c' & product == `p' & ///
								abs_t_reg7 >= `cut'
					loc			s7 = r(N) / `n'
					quietly count if country == `c' & product == `p' & ///
								abs_t_reg2 >= `cut'
					loc			s2 = r(N) / `n'
					post		`curves' (`c') (`p') (`n') (`cut') (`s7') (`s2')
				}
			}
		}
		postclose	`curves'
		use			"`products'", clear
		label define rain_country `labels', replace
		label values country rain_country

	* encode products by color and FE specifications by line pattern
		loc			colors arc2 chirps cpc era5 merra2 tamsat
		loc			lines
		forvalues p = 1/6 {
			loc			color : word `p' of `colors'
			loc			lines `lines' ///
					(line share_reg7 threshold if product == `p', sort ///
					lcolor("``color''") lwidth(medium) lpattern(solid)) ///
					(line share_reg2 threshold if product == `p', sort ///
					lcolor("``color''") lwidth(medium) lpattern(dash))
		}
		loc			benchmark = sqrt(23.1)

	* use two invisible series solely to supply neutral line-pattern keys
		twoway		`lines' ///
					(function y = ., range(0 15) ///
					lcolor("112 119 125") lwidth(medium) lpattern(solid)) ///
					(function y = ., range(0 15) ///
					lcolor("112 119 125") lwidth(medium) lpattern(dash)), ///
					`frame' xscale(range(0 15)) yscale(range(0 1)) ///
					xlabel(0(5)15, nogrid `ticks') ///
					ylabel(0(.2)1, format(%3.1f) `grid' `ticks' angle(horizontal)) ///
					xline(1.96, lcolor("160 166 172") ///
					lpattern(dot) lwidth(thin)) ///
					xline(`benchmark', lcolor("112 119 125") ///
					lpattern(dash) lwidth(thin)) ///
					xtitle("Absolute Cluster-Robust T-Statistic", ///
					size(3) color("38 43 47")) ///
					ytitle("Share Of Specifications Above Threshold", ///
					size(3) color("38 43 47")) ///
					legend(order(1 "ARC2" 3 "CHIRPS" 5 "CPC" 7 "ERA5" ///
					9 "MERRA-2" 11 "TAMSAT" 13 "Year FE" ///
					14 "Year + Household FE") cols(6) holes(7 8 11 12) ///
					size(2.7) color("38 43 47") region(lstyle(none)) symxsize(8)) ///
					subtitle(, size(2.8) color("38 43 47") nobox fcolor(white)) ///
					by(country, cols(3) iscale(1) legend(pos(6)) note("") ///
					imargin(small) graphregion(color(white) margin(small))) ///
					xsize(7.2) ysize(4.8)

		graph export "$xfig/strength_product.pdf", replace
		graph export "$xfig/strength_product.png", width(3200) replace
	restore


**********************************************************************
**# 4 - end matter
**********************************************************************

* close the log
	log close

/* END */
