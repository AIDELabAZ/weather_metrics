* Project: WB Weather - metric
* Created on: 27 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 27 Oct 2026
* Stata v.18.0

* does
	* draws signed bootstrap coefficient differences and specification strips

* assumes
	* metric_boot.do has saved the selected results

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths and select pilot or production outputs
	global		root	"$data/results_data"
	global		xfig	"$data/results_data/figures/metric_paper"
	global		logout	"$data/results_data/logs"
	args mode
	if "`mode'" == "" loc mode pilot
	loc			suffix = cond("`mode'" == "pilot", "_pilot", "")
	cap log close
	log using	"$logout/cloudy_rainfall_fe_bootstrap_vis", append
	include		"$code/analysis/viz_code/metric_palette.do"
	use			"$root/rainfall_FE_bootstrap_differences`suffix'", clear


**********************************************************************
**# 1 - prepare specification indicators
**********************************************************************

* failed pairs remain in the results table and are reported in the log
	tabulate	status, missing
	keep if		status == "ok"
	count
	if r(N) == 0 {
		log close
		exit
	}
	gen byte	outcome = cond(outcome_var == "lncp_yld", 1, 2)
	gen byte	product_row = product + 4
	gen byte	metric_row = metric + 12
	gen byte	crosses_zero = ci_lo_std <= 0 & ci_hi_std >= 0
	tabulate	country crosses_zero
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

	levelsof	country, local(countries)
	foreach c of local countries {
		preserve
			keep if		country == `c'
			sort		delta_std outcome_var weather_var
			gen int		rank = _n
			loc			n = _N
			loc			country : label (country) `c'
			loc			stub = lower("`country'")

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
			loc			points
			loc			strips
			forvalues p = 1/6 {
				loc			color : word `p' of `colors'
				loc			points `points' ///
					(scatter delta_std rank if product == `p', yaxis(2) ///
					mcolor("``color''") mlcolor(none) msymbol(O) msize(1.3))
				loc			strips `strips' ///
					(scatter product_row rank if product == `p', ///
					mcolor("``color''") mlcolor(none) msymbol(O) msize(1))
			}

		* percentile intervals and point estimates use the saved signed scale
			twoway		(rcap ci_lo_std ci_hi_std rank, yaxis(2) ///
						lcolor("165 172 179%65") lwidth(vthin) msize(.5)) ///
						(function y = 0, range(.5 `=`n'+.5') yaxis(2) ///
						lcolor("112 119 125") lwidth(thin)) ///
						`points' `strips' ///
						(scatter outcome metric_row rank, ///
						mcolor("93 104 114" "93 104 114") ///
						mlcolor(none none) msymbol(O O) msize(.8 .8)), ///
						scheme(stcolor) legend(off) ///
						graphregion(color(white) margin(small)) ///
						plotregion(color(white) lstyle(none)) ///
						yscale(range(0 40) noline axis(1)) ///
						yscale(range(`bottom' `hi') noline axis(2)) ///
						ylabel(`rows', axis(1) labsize(2.1) ///
						labcolor("38 43 47") noticks nogrid angle(horizontal)) ///
						ylabel(`tick_lo'(`step')`tick_hi', axis(2) format(%6.3g) ///
						labsize(2.5) labcolor("38 43 47") nogrid angle(horizontal)) ///
						xscale(range(.5 `=`n'+.5') lcolor("38 43 47")) ///
						xlabel(#6, labsize(2.5) nogrid) ///
						xtitle("Specification rank", size(3)) ///
						ytitle("", axis(1)) ///
						ytitle("Standardized coefficient difference (reg2 - reg7)", ///
						axis(2) size(3)) ///
						title("{bf:`country'}", size(3.8) color("38 43 47")) ///
						xsize(9) ysize(6.5)
			graph export ///
				"$xfig/rainfall_FE_bootstrap_coefficient_difference_`stub'`suffix'.pdf", replace
			graph export ///
				"$xfig/rainfall_FE_bootstrap_coefficient_difference_`stub'`suffix'.png", ///
						width(3200) replace
		restore
	}

* close the log
	log close

/* END */
