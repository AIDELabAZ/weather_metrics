* Project: WB Weather - metric
* Created on: 27 Oct 2026
* Created by: codex
* edited on: 28 Oct 2026
* edited by: codex
* Stata v.19.5

* does
	* reads paired rainfall regression results
	* creates coefficient-precision and pooled/product strength figures

* assumes
	* completed regression results
	* projectdo.do has established the data global

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	global		root	"$data/results_data"
	global		xfig	"$data/results_data/figures/metric_paper"
	global		logout	"$data/results_data/logs"

* open log
	cap log close
	log using	"$logout/rainfall_diagnostics", append

* load data
	use			"$root/lsms_complete_results", clear


**********************************************************************
**# 1 - prepare paired rainfall results
**********************************************************************

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

* load product colors and define the shared graph appearance
	include		"$code/analysis/viz_code/metric_palette.do"
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
**# 2 - coefficient magnitude versus precision
**********************************************************************

	preserve

	* calculate ratios in double precision, retaining negative SE changes
		gen double	x_beta = ln(abs(beta_reg2) / abs(beta_reg7)) / ln(2)
		gen double	y_se = ln(stdrd_err_reg2 / stdrd_err_reg7) / ln(2)

	* report invalid ratios and points outside the plotting window
		gen byte	invalid_ratio = missing(x_beta, y_se)
		gen byte	outside_window = !invalid_ratio & !inrange(x_beta, -6, 6)
		label var	invalid_ratio "Invalid log ratios"
		label var	outside_window "Outside -6 to +6"
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
					xtitle("Change in |rainfall coefficient| (log2 ratio)", ///
					size(3) color("38 43 47")) ///
					ytitle("Change in standard error (log2 ratio)", ///
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
**# 3 - first-stage strength survival curves
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
					xtitle("Absolute cluster-robust t-statistic", ///
					size(3) color("38 43 47")) ///
					ytitle("Share of specifications above threshold", ///
					size(3) color("38 43 47")) ///
					legend(order(1 "Year FE" 2 "Year + household FE") ///
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
**# 4 - experimental strength curves by product
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
					xtitle("Absolute cluster-robust t-statistic", ///
					size(3) color("38 43 47")) ///
					ytitle("Share of specifications above threshold", ///
					size(3) color("38 43 47")) ///
					legend(order(1 "ARC2" 3 "CHIRPS" 5 "CPC" 7 "ERA5" ///
					9 "MERRA-2" 11 "TAMSAT" 13 "Year FE" ///
					14 "Year + household FE") cols(6) holes(7 8 11 12) ///
					size(2.7) color("38 43 47") region(lstyle(none)) symxsize(8)) ///
					subtitle(, size(2.8) color("38 43 47") nobox fcolor(white)) ///
					by(country, cols(3) iscale(1) legend(pos(6)) note("") ///
					imargin(small) graphregion(color(white) margin(small))) ///
					xsize(7.2) ysize(4.8)

		graph export "$xfig/strength_product.pdf", replace
		graph export "$xfig/strength_product.png", width(3200) replace
	restore


**********************************************************************
**# 5 - end matter
**********************************************************************

* close log
	log close

/* END */
