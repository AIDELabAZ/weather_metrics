* Project: WB Weather
* Created on: 27 Oct 2026
* Created by: codex
* edited by: codex
* edited on: 28 Oct 2026
* Stata v.18.0

* does
	* defines the shared appearance of the fourteen summary figures

* assumes
	* included within metric_sum.do so style locals share its scope
	* canonical order: ARC2, CHIRPS, CPC, ERA5, MERRA-2, TAMSAT

* TO DO:
	* done


**********************************************************************
**# 1 - product colors and line patterns
**********************************************************************

* map the filename product order to the named palette
	include		"$code/analysis/viz_code/metric_palette.do"

	loc			p1 lcolor("`arc2'") lpattern(shortdash) lwidth(medium)
	loc			p2 lcolor("`chirps'") lpattern(solid) lwidth(medium)
	loc			p3 lcolor("`cpc'") lpattern(dash) lwidth(medium)
	loc			p4 lcolor("`era5'") lpattern(dash_dot) lwidth(medium)
	loc			p5 lcolor("`merra2'") lpattern(longdash) lwidth(medium)
	loc			p6 lcolor("`tamsat'") lpattern(longdash_dot) lwidth(medium)


**********************************************************************
**# 2 - axes, backgrounds and shared legend
**********************************************************************

* use a white background, dark axes and pale horizontal gridlines
	loc			frame scheme(stcolor) ///
				graphregion(color(white) margin(small)) ///
				plotregion(color(white) lstyle(none)) ///
				xscale(lcolor("38 43 47")) ///
				yscale(lcolor("38 43 47"))
	loc			ticks labsize(3) labcolor("38 43 47") ///
				tlcolor("38 43 47")
	loc			grid grid glcolor("231 234 237") glwidth(vthin)

* use solid pale gridlines in the two manuscript rainfall figures
	loc			pale grid glcolor("242 244 246") glwidth(vthin) glpattern(solid)
	loc			years xlabel(#5, nogrid `ticks') ///
				xtitle("Year", size(3) color("38 43 47"))

* place one six-product legend below the complete country grid
	loc			key legend(order(1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT") cols(6) size(2.7) ///
				color("38 43 47") region(lstyle(none)) symxsize(8))

/* END */
