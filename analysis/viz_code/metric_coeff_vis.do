* Project: WB Weather
* Created on: September 2019
* Created by: jdm
* edited by: codex
* edited on: 30 Oct 2026
* Stata v.19.5

* does
	* reads in results data set
	* creates rainfall specification charts for reg2 and reg7
	
* assumes
	* you have results file

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	global	root 	= 	"$data/results_data"
	global	sfig	= 	"$data/results_data/figures"
	global	xfig    =   "$data/results_data/figures/metric_paper"
	global	logout 	= 	"$data/results_data/logs"

* open log
	cap log close
	log 	using 	"$logout/metric_resultsvis", append

* load product colors
	include		"$code/analysis/viz_code/metric_palette.do"

* load data
	use 			"$root/lsms_complete_results", clear


**********************************************************************
**# 1 - prepare coefficients and significance
**********************************************************************

* retain regression p-values; match bootstrap point and interval styling
	replace 		b_sig = beta
	replace 		b_sig = . if pval > .05
	lab var 		b_sig "p < 0.05"
	replace 		b_ns = beta
	replace 		b_ns= . if pval <= .05
	lab var 		b_ns "n.s."

* generate significance dummy
	replace			sig = 1 if b_sig != .
	replace			sig = 0 if b_ns != .
	lab	def			yesno 0 "Not Significant" 1 "Significant", replace
	lab val			sig yesno
	lab var			sig "Weather variable is significant"

* generate sign dummy
	replace 		b_sign = 1 if b_sig > 0 & b_sig != .
	replace 		b_sign = 0 if b_sig < 0 & b_sig != .
	lab	def			posneg 0 "Negative" 1 "Positive", replace
	lab val			b_sign posneg
	lab var			b_sign "Sign on weather variable"

* rename satellites to actual name
	label define sat 1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT", modify


**********************************************************************
**# 2 - country rainfall charts, year and household FE (reg2)
**********************************************************************
	
*** ethiopia ***
preserve
	keep			if country == 1
	keep 			if regname == 2
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen				k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/eth_all2", replace)

	graph export	"$xfig/eth_all2.png", width(3300) replace
	graph export	"$xfig/eth_all2.eps", replace
	graph export	"$xfig/eth_all2.pdf", replace

restore

*** malawi ***
preserve
	keep			if country == 2
	keep 			if regname == 2
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen				k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/mwi_all2", replace)

	graph export	"$xfig/mwi_all2.png", width(3300) replace
	graph export	"$xfig/mwi_all2.eps", replace
	graph export	"$xfig/mwi_all2.pdf", replace

restore

*** niger ***
preserve
	keep			if country == 4
	keep 			if regname == 2
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen				k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/ner_all2", replace)

	graph export	"$xfig/ner_all2.png", width(3300) replace
	graph export	"$xfig/ner_all2.eps", replace
	graph export	"$xfig/ner_all2.pdf", replace

restore

*** nigeria ***
preserve
	keep			if country == 5
	keep 			if regname == 2
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen				k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/nga_all2", replace)

	graph export	"$xfig/nga_all2.png", width(3300) replace
	graph export	"$xfig/nga_all2.eps", replace
	graph export	"$xfig/nga_all2.pdf", replace

restore

*** tanzania ***
preserve
	keep			if country == 6
	keep 			if regname == 2
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen				k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/tza_all2", replace)

	graph export	"$xfig/tza_all2.png", width(3300) replace
	graph export	"$xfig/tza_all2.eps", replace
	graph export	"$xfig/tza_all2.pdf", replace

restore

*** uganda ***
preserve
	keep			if country == 7
	keep 			if regname == 2
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen				k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/uga_all2", replace)

	graph export	"$xfig/uga_all2.png", width(3300) replace
	graph export	"$xfig/uga_all2.eps", replace
	graph export	"$xfig/uga_all2.pdf", replace

restore


**********************************************************************
**# 3 - country rainfall charts, year FE (reg7)
**********************************************************************
	
*** ethiopia ***
preserve
	keep			if country == 1
	keep 			if regname == 7
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen			k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/eth_all", replace)

	graph export	"$xfig/eth_all.png", width(3300) replace
	graph export	"$xfig/eth_all.eps", replace
	graph export	"$xfig/eth_all.pdf", replace

restore

*** malawi ***
preserve
	keep			if country == 2
	keep 			if regname == 7
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen			k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/mwi_all", replace)

	graph export	"$xfig/mwi_all.png", width(3300) replace
	graph export	"$xfig/mwi_all.eps", replace
	graph export	"$xfig/mwi_all.pdf", replace

restore

*** niger ***
preserve
	keep			if country == 4
	keep 			if regname == 7
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen			k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/ner_all", replace)

	graph export	"$xfig/ner_all.png", width(3300) replace
	graph export	"$xfig/ner_all.eps", replace
	graph export	"$xfig/ner_all.pdf", replace

restore

*** nigeria ***
preserve
	keep			if country == 5
	keep 			if regname == 7
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen			k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/nga_all", replace)

	graph export	"$xfig/nga_all.png", width(3300) replace
	graph export	"$xfig/nga_all.eps", replace
	graph export	"$xfig/nga_all.pdf", replace

restore

*** tanzania ***
preserve
	keep			if country == 6
	keep 			if regname == 7
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen			k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/tza_all", replace)

	graph export	"$xfig/tza_all.png", width(3300) replace
	graph export	"$xfig/tza_all.eps", replace
	graph export	"$xfig/tza_all.pdf", replace

restore

*** uganda ***
preserve
	keep			if country == 7
	keep 			if regname == 7
	keep			if varname < 15
	keep			if sat < 7
	sort 			beta
	replace 		obs = _n

* place the divider between negative and nonnegative coefficients
	count			if beta < 0
	loc				cut = r(N) + .5

* stack values of the specification indicators
	gen 			k1 		= 	depvar
	gen			k2      =   sat + 4
	gen 			k3		=	varname + 12

* label new variables
	lab				var obs "Specification # - sorted by effect size"

	lab 			var k1 "Dependent Variable"
	lab 			var k2 "Remote Sensing Product"
	lab 			var k3 "Rainfall Metric"

	sum			 	ci_up
	global			bmax = r(max)

	sum			 	ci_lo
	global			bmin = r(min)

	global			brange	=	$bmax - $bmin
	global			from_y	=	$bmin - 3*$brange
	global			gheight	=	40

* retain physical marker sizes within the landscape page margins
	twoway		(scatter k1 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 1, mcolor("`arc2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 2, mcolor("`chirps'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 3, mcolor("`cpc'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 4, mcolor("`era5'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 5, mcolor("`merra2'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k2 obs if sat == 6, mcolor("`tamsat'") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(scatter k3 obs, mcolor("93 104 114") ///
				msize(1.5pt) mlwidth(.864pt)) ///
				(rbar ci_lo ci_up obs if b_sig == ., ///
				barwidth(.2) color(black%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig > 0 & b_sig < ., ///
				barwidth(.2) color(edkblue%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(rbar ci_lo ci_up obs if b_sig < 0, ///
				barwidth(.2) color(maroon%50) ///
				lwidth(.576pt) yaxis(2)) ///
				(scatter b_ns obs, yaxis(2) mcolor(black%75) msymbol(Th) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig > 0 & b_sig < ., ///
				yaxis(2) mcolor(edkblue%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)) ///
				(scatter b_sig obs if b_sig < 0, ///
				yaxis(2) mcolor(maroon%75) msymbol(+) ///
				msize(3pt) mlwidth(.864pt)), ///
				xsize(10) ysize(6.5) scheme(stcolor) ///
				graphregion(color(white) margin(l=8pt r=8pt t=6pt b=6pt)) ///
				plotregion(color(white) lstyle(none)) ///
				xlabel(0(8)168, labsize(8.5pt) labcolor("38 43 47") ///
				glcolor("242 244 246") glpattern(solid) glwidth(vthin)) ///
				ylab(0(1)$gheight) xtitle("") ytitle("") ///
				ylabel( ///
				1 "Quantity" ///
				2 "Value" ///
				3 "{bf:Dependent Variable}" ///
				5 "ARC2" ///
				6 "CHIRPS" ///
				7 "CPC" ///
				8 "ERA5" ///
				9 "MERRA-2" ///
				10 "TAMSAT" ///
				11 "{bf:Remote Sensing Product}" ///
				12 " " ///
				13 "Mean Daily Rainfall" ///
				14 "Median Daily Rainfall" ///
				15 "Variance of Daily Rainfall" ///
				16 "Skew of Daily Rainfall" ///
				17 "Total Rainfall" ///
				18 "Deviation in Total Rainfall" ///
				19 "Z-Score of Total Rainfall" ///
				20 "Rainy Days" ///
				21 "Deviation in Rainy Days" ///
				22 "No Rain Days" ///
				23 "Deviation in No Rain Days" ///
				24 "Percent Rainy Days" ///
				25 "Deviation in Percent Rainy Days" ///
				26 "Longest Dry Spell" ///
				27 "{bf:Rainfall Variables}" ///
				40 " " ///
				, angle(0) labsize(8.5pt) labcolor("38 43 47") ///
				tstyle(notick) glcolor("242 244 246") ///
				glpattern(solid) glwidth(vthin)) ///
				ylabel(, axis(2) labsize(8.5pt) angle(0) nogrid ///
				labcolor("38 43 47")) ///
				yscale(range($from_y $bmax) axis(2)) ytitle("", axis(2)) ///
				xline(`cut', lcolor(red) lwidth(.864pt) lpattern(solid)) ///
				yline(0, axis(2) lcolor("112 119 125") ///
				lwidth(.864pt) lpattern(solid)) ///
				legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
				14 "Negative, p < 0.05") cols(3) ///
				size(8.5pt) rowgap(.5) pos(12) region(lstyle(none))) ///
				saving("$sfig/uga_all", replace)

	graph export	"$xfig/uga_all.png", width(3300) replace
	graph export	"$xfig/uga_all.eps", replace
	graph export	"$xfig/uga_all.pdf", replace

restore


**********************************************************************
**# 4 - paired specification charts
**********************************************************************

preserve

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

* retain the existing metric names and alphabetical product order
	loc			rows 40.5 "{bf:Dependent Variable}" 39 "Quantity" 37.5 "Value" ///
				34.5 "{bf:Remote Sensing Product}" 33 "ARC2" 31.5 "CHIRPS" ///
				30 "CPC" 28.5 "ERA5" 27 "MERRA-2" 25.5 "TAMSAT" ///
				22.5 "{bf:Rainfall Metric}" 21 "Mean Daily Rainfall" ///
				19.5 "Median Daily Rainfall" 18 "Variance of Daily Rainfall" ///
				16.5 "Skew of Daily Rainfall" 15 "Total Rainfall" ///
				13.5 "Deviation in Total Rainfall" 12 "Z-Score of Total Rainfall" ///
				10.5 "Rainy Days" 9 "Deviation in Rainy Days" 7.5 "No Rain Days" ///
				6 "Deviation in No Rain Days" 4.5 "Percent Rainy Days" ///
				3 "Deviation in Percent Rainy Days" 1.5 "Longest Dry Spell"
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
					xtitle("Specification rank (ordered by year FE coefficient)", ///
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
					text(60.5 2 "{bf:Year FE}" 51 2 "{bf:Year + household FE}", ///
					yaxis(2) placement(e) justification(left) size(9pt) ///
					color("38 43 47")) ///
					legend(order(12 "n.s." 13 "Positive, p < 0.05" ///
					14 "Negative, p < 0.05") cols(3) size(8.5pt) ///
					rowgap(.5) pos(12) bmargin(zero) ///
					region(lstyle(none) margin(zero)))
		graph export "$xfig/`stub'_pair.pdf", replace
		graph export "$xfig/`stub'_pair.png", width(3300) replace
	}
restore


**********************************************************************
**# 5 - end matter
**********************************************************************

* close the log
	log close

/* END */
