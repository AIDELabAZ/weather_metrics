* Project: WB Weather
* Created on: April 2024
* Created by: jdm
* Edited by: jdm
* Last edit: 4 April 2024
* Stata v.18.0 

* does
	* reads in results data set
	* makes visualziations of results 

* assumes
	* you have results file 
	* grc1leg2.ado

* TO DO:
	* p-value charts by country

	
************************************************************************
**# 0 - setup
************************************************************************

* define paths
	global	root 	= 	"$data/results_data"
	global	stab 	= 	"$data/results_data/tables"
	global	xtab 	= 	"$data/output/metric_paper/tables"
	global	sfig	= 	"$data/results_data/figures"
	global 	xfig    =   "$data/output/metric_paper/figures"
	global	logout 	= 	"$data/results_data/logs"

* open log	
	cap log close
	log 	using 		"$logout/pval_vis", append

		
************************************************************************
**# 1 - load data
************************************************************************

* load data 
	use 			"$root/lsms_complete_results", clear

* generate p-values
	gen 			p99 = 1 if pval <= 0.01
	replace 		p99 = 0 if pval > 0.01
	gen 			p95 = 1 if pval <= 0.05
	replace 		p95 = 0 if pval > 0.05
	gen 			p90 = 1 if pval <= 0.10
	replace 		p90 = 0 if pval > 0.10

* keep HH Bilinear	
	keep			if varname < 15
	keep			if regname < 4

	
************************************************************************
**# 2 - generate p-value graphs by regname
************************************************************************
	
* p-value graph of rainfall by varname
	collapse 		(mean) mu99 = p99 mu95 = p95 mu90 = p90 ///
						(sd) sd99 = p99 sd95 = p95 sd90 = p90 ///
						(count) n99 = p99 n95 = p95 n90 = p90, by(varname regname)
	
	gen 			hi99 = mu99 + invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	gen				lo99 = mu99 - invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	
	gen 			hi95 = mu95 + invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	gen				lo95 = mu95 - invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	
	gen 			hi90 = mu90 + invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	gen				lo90 = mu90 - invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	
	reshape 		long  mu sd n hi lo, i(varname regname) j(p)
	
	drop			if p != 95
	
	sort 			varname p
	gen 			obs = _n
	replace			obs = 1 + obs if obs > 3
	replace			obs = 1 + obs if obs > 7
	replace			obs = 1 + obs if obs > 11
	replace			obs = 1 + obs if obs > 15
	replace			obs = 1 + obs if obs > 19
	replace			obs = 1 + obs if obs > 23
	replace			obs = 1 + obs if obs > 27
	replace			obs = 1 + obs if obs > 31
	replace			obs = 1 + obs if obs > 35
	replace			obs = 1 + obs if obs > 39
	replace			obs = 1 + obs if obs > 43
	replace			obs = 1 + obs if obs > 47
	replace			obs = 1 + obs if obs > 51
	
	sum			 	hi if p == 95 & varname == 1 & regname == 1
	global			bmax = r(max)
	
	sum			 	lo if p == 95 & varname == 1 & regname == 1
	global			bmin = r(min)	
	
	twoway			(bar mu obs if regname == 1, color(emerald*1.5%60)) || ///
						(bar mu obs if regname == 2, color(eltblue*1.5%60)) || ///
						(bar mu obs if regname == 3, color(khaki*1.5%60)) || ///
						(rcap hi lo obs, yscale(r(0 1)) ///
						ylab(0(.1)1, labsize(small)) ///
						ytitle("Share of Significant Point Estimates") ///
						xscale(r(0 24) ex) ///
						yline($bmax, lcolor(maroon) lstyle(solid) ) ///
						yline($bmin, lcolor(maroon)  lstyle(solid) ) ///
						xlabel(2 "Mean Daily Rain " 6 "Median Daily Rain " ///
						10 "Variance of Daily Rain " 14 "Skew of Daily Rain " ///
						18 "Total Seasonal Rain " 22 "Dev. in Total Rain " ///
						26 "z-Score of Total Rain " 30 "Rainy Days " ///
						34 "Dev. in Rainy Days " 38 "No Rain Days " ///
						42 "Dev. in No Rain Days " 46 "% Rainy Days " ///
						50 "Dev. in % Rainy Days " 54 "Longest Dry Spell ", ///
						angle(45) notick labsize(small)) xtitle("")), ///
						legend(pos(12) col(5) order(1 2 3 4) label(1 "Weather Only") ///
						label(2 "Weather + FE") label(3 "Weather + FE + Inputs") label(4 "95% C.I.") size(vsmall))  ///
						saving("$sfig/pval_metric", replace)
						
	graph export 	"$xfig/pval_metric.pdf", as(pdf) replace


************************************************************************
**# 3 - generate p-value graphs by country
************************************************************************
/*
* ethiopia rainfall	
preserve
	keep			if varname < 15
	keep			if country == 1
	
	collapse 		(mean) mu99 = p99 mu95 = p95 mu90 = p90 ///
						(sd) sd99 = p99 sd95 = p95 sd90 = p90 ///
						(count) n99 = p99 n95 = p95 n90 = p90, by(varname)
	
	gen 			hi99 = mu99 + invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	gen				lo99 = mu99 - invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	
	gen 			hi95 = mu95 + invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	gen				lo95 = mu95 - invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	
	gen 			hi90 = mu90 + invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	gen				lo90 = mu90 - invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	
	reshape 		long mu sd n hi lo, i(varname) j(p)	
	
	sort 			varname p
	gen 			obs = _n
/*
	replace			obs = 1 + obs if obs > 3
	replace			obs = 1 + obs if obs > 7
	replace			obs = 1 + obs if obs > 11
	replace			obs = 1 + obs if obs > 15
	replace			obs = 1 + obs if obs > 19
	replace			obs = 1 + obs if obs > 23
	replace			obs = 1 + obs if obs > 27
	replace			obs = 1 + obs if obs > 31
	replace			obs = 1 + obs if obs > 35
	replace			obs = 1 + obs if obs > 39
	replace			obs = 1 + obs if obs > 43
	replace			obs = 1 + obs if obs > 47
	replace			obs = 1 + obs if obs > 51
*/	
	sum			 	hi if p == 95 & varname == 1
	global			bmax = r(max)
	
	sum			 	lo if p == 95 & varname == 1
	global			bmin = r(min)
	
	twoway			(bar mu obs if p == 95, color(eltblue*1.5%60)) || ///
						(rcap hi lo obs if p == 95, yscale(r(0 1)) ///
						ylab(0(.1)1, labsize(small)) title("Ethiopia") ///
						ytitle("Share of Significant Point Estimates") ///
						yline($bmax, lcolor(maroon) lstyle(solid) ) ///
						yline($bmin, lcolor(maroon)  lstyle(solid) ) ///
						lcolor(black) xscale(r(0 42) ex) ///
						xlabel(2 "Mean Daily Rain " 5 "Median Daily Rain " ///
						8 "Variance of Daily Rain " 11 "Skew of Daily Rain " ///
						14 "Total Seasonal Rain " 17 "Dev. in Total Rain " ///
						20 "z-Score of Total Rain " 23 "Rainy Days " ///
						26 "Dev. in Rainy Days " 29 "No Rain Days " ///
						32 "Dev. in No Rain Days " 35 "% Rainy Days " ///
						38 "Dev. in % Rainy Days " 41 "Longest Dry Spell ", ///
						angle(45) notick) xtitle("")), ///
						legend(pos(12) col(5) order(1 2) label(1 "p>0.95") ///
						label(2 "95% C.I."))  ///
						saving("$sfig/eth_pval_varname_rf", replace)
						
	*graph export 	"$sfig/eth_pval_varname_rf.pdf", as(pdf) replace
restore	
	

* malawi rainfall	
preserve
	keep			if varname < 15
	keep			if country == 2
	
	collapse 		(mean) mu99 = p99 mu95 = p95 mu90 = p90 ///
						(sd) sd99 = p99 sd95 = p95 sd90 = p90 ///
						(count) n99 = p99 n95 = p95 n90 = p90, by(varname)
	
	gen 			hi99 = mu99 + invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	gen				lo99 = mu99 - invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	
	gen 			hi95 = mu95 + invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	gen				lo95 = mu95 - invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	
	gen 			hi90 = mu90 + invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	gen				lo90 = mu90 - invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	
	reshape 		long mu sd n hi lo, i(varname) j(p)	
	
	sort 			varname p
	gen 			obs = _n
/*
	replace			obs = 1 + obs if obs > 3
	replace			obs = 1 + obs if obs > 7
	replace			obs = 1 + obs if obs > 11
	replace			obs = 1 + obs if obs > 15
	replace			obs = 1 + obs if obs > 19
	replace			obs = 1 + obs if obs > 23
	replace			obs = 1 + obs if obs > 27
	replace			obs = 1 + obs if obs > 31
	replace			obs = 1 + obs if obs > 35
	replace			obs = 1 + obs if obs > 39
	replace			obs = 1 + obs if obs > 43
	replace			obs = 1 + obs if obs > 47
	replace			obs = 1 + obs if obs > 51
*/	
	sum			 	hi if p == 95 & varname == 1
	global			bmax = r(max)
	
	sum			 	lo if p == 95 & varname == 1
	global			bmin = r(min)
	
	twoway			(bar mu obs if p == 95, color(eltblue*1.5%60)) || ///
						(rcap hi lo obs if p == 95, yscale(r(0 1)) ///
						ylab(0(.1)1, labsize(small)) title("Malawi") ///
						yline($bmax, lcolor(maroon) lstyle(solid) ) ///
						yline($bmin, lcolor(maroon)  lstyle(solid) ) ///
						lcolor(black) xscale(r(0 42) ex) ///
						xlabel(2 "Mean Daily Rain " 5 "Median Daily Rain " ///
						8 "Variance of Daily Rain " 11 "Skew of Daily Rain " ///
						14 "Total Seasonal Rain " 17 "Dev. in Total Rain " ///
						20 "z-Score of Total Rain " 23 "Rainy Days " ///
						26 "Dev. in Rainy Days " 29 "No Rain Days " ///
						32 "Dev. in No Rain Days " 35 "% Rainy Days " ///
						38 "Dev. in % Rainy Days " 41 "Longest Dry Spell ", ///
						angle(45) notick) xtitle("")), ///
						legend(pos(12) col(5) order(1 2) label(1 "p>0.95") ///
						label(2 "95% C.I."))  ///
						saving("$sfig/mwi_pval_varname_rf", replace)
						
	*graph export 	"$sfig/mwi_pval_varname_rf.pdf", as(pdf) replace
restore	
	

* niger rainfall	
preserve
	keep			if varname < 15
	keep			if country == 4
	
	collapse 		(mean) mu99 = p99 mu95 = p95 mu90 = p90 ///
						(sd) sd99 = p99 sd95 = p95 sd90 = p90 ///
						(count) n99 = p99 n95 = p95 n90 = p90, by(varname)
	
	gen 			hi99 = mu99 + invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	gen				lo99 = mu99 - invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	
	gen 			hi95 = mu95 + invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	gen				lo95 = mu95 - invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	
	gen 			hi90 = mu90 + invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	gen				lo90 = mu90 - invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	
	reshape 		long mu sd n hi lo, i(varname) j(p)	
	
	sort 			varname p
	gen 			obs = _n
/*
	replace			obs = 1 + obs if obs > 3
	replace			obs = 1 + obs if obs > 7
	replace			obs = 1 + obs if obs > 11
	replace			obs = 1 + obs if obs > 15
	replace			obs = 1 + obs if obs > 19
	replace			obs = 1 + obs if obs > 23
	replace			obs = 1 + obs if obs > 27
	replace			obs = 1 + obs if obs > 31
	replace			obs = 1 + obs if obs > 35
	replace			obs = 1 + obs if obs > 39
	replace			obs = 1 + obs if obs > 43
	replace			obs = 1 + obs if obs > 47
	replace			obs = 1 + obs if obs > 51
*/	
	sum			 	hi if p == 95 & varname == 1
	global			bmax = r(max)
	
	sum			 	lo if p == 95 & varname == 1
	global			bmin = r(min)
	
	twoway			(bar mu obs if p == 95, color(eltblue*1.5%60)) || ///
						(rcap hi lo obs if p == 95, yscale(r(0 1)) ///
						ylab(0(.1)1, labsize(small)) title("Niger") ///
						yline($bmax, lcolor(maroon) lstyle(solid) ) ///
						yline($bmin, lcolor(maroon)  lstyle(solid) ) ///
						lcolor(black) xscale(r(0 42) ex) ///
						xlabel(2 "Mean Daily Rain " 5 "Median Daily Rain " ///
						8 "Variance of Daily Rain " 11 "Skew of Daily Rain " ///
						14 "Total Seasonal Rain " 17 "Dev. in Total Rain " ///
						20 "z-Score of Total Rain " 23 "Rainy Days " ///
						26 "Dev. in Rainy Days " 29 "No Rain Days " ///
						32 "Dev. in No Rain Days " 35 "% Rainy Days " ///
						38 "Dev. in % Rainy Days " 41 "Longest Dry Spell ", ///
						angle(45) notick) xtitle("")), ///
						legend(pos(12) col(5) order(1 2) label(1 "p>0.95") ///
						label(2 "95% C.I."))  ///
						saving("$sfig/ngr_pval_varname_rf", replace)
						
	*graph export 	"$sfig/ngr_pval_varname_rf.pdf", as(pdf) replace
restore	
	

* nigeria rainfall	
preserve
	keep			if varname < 15
	keep			if country == 5
	
	collapse 		(mean) mu99 = p99 mu95 = p95 mu90 = p90 ///
						(sd) sd99 = p99 sd95 = p95 sd90 = p90 ///
						(count) n99 = p99 n95 = p95 n90 = p90, by(varname)
	
	gen 			hi99 = mu99 + invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	gen				lo99 = mu99 - invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	
	gen 			hi95 = mu95 + invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	gen				lo95 = mu95 - invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	
	gen 			hi90 = mu90 + invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	gen				lo90 = mu90 - invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	
	reshape 		long mu sd n hi lo, i(varname) j(p)	
	
	sort 			varname p
	gen 			obs = _n
/*
	replace			obs = 1 + obs if obs > 3
	replace			obs = 1 + obs if obs > 7
	replace			obs = 1 + obs if obs > 11
	replace			obs = 1 + obs if obs > 15
	replace			obs = 1 + obs if obs > 19
	replace			obs = 1 + obs if obs > 23
	replace			obs = 1 + obs if obs > 27
	replace			obs = 1 + obs if obs > 31
	replace			obs = 1 + obs if obs > 35
	replace			obs = 1 + obs if obs > 39
	replace			obs = 1 + obs if obs > 43
	replace			obs = 1 + obs if obs > 47
	replace			obs = 1 + obs if obs > 51
*/	
	sum			 	hi if p == 95 & varname == 1
	global			bmax = r(max)
	
	sum			 	lo if p == 95 & varname == 1
	global			bmin = r(min)
	
	twoway			(bar mu obs if p == 95, color(eltblue*1.5%60)) || ///
						(rcap hi lo obs if p == 95, yscale(r(0 1)) ///
						ylab(0(.1)1, labsize(small)) title("Nigeria") ///
						ytitle("Share of Significant Point Estimates") ///
						yline($bmax, lcolor(maroon) lstyle(solid) ) ///
						yline($bmin, lcolor(maroon)  lstyle(solid) ) ///
						lcolor(black) xscale(r(0 42) ex) ///
						xlabel(2 "Mean Daily Rain " 5 "Median Daily Rain " ///
						8 "Variance of Daily Rain " 11 "Skew of Daily Rain " ///
						14 "Total Seasonal Rain " 17 "Dev. in Total Rain " ///
						20 "z-Score of Total Rain " 23 "Rainy Days " ///
						26 "Dev. in Rainy Days " 29 "No Rain Days " ///
						32 "Dev. in No Rain Days " 35 "% Rainy Days " ///
						38 "Dev. in % Rainy Days " 41 "Longest Dry Spell ", ///
						angle(45) notick) xtitle("")), ///
						legend(pos(12) col(5) order(1 2) label(1 "p>0.95") ///
						label(2 "95% C.I."))  ///
						saving("$sfig/nga_pval_varname_rf", replace)
						
	*graph export 	"$sfig/nga_pval_varname_rf.pdf", as(pdf) replace
restore	
	

* tanzania rainfall	
preserve
	keep			if varname < 15
	keep			if country == 6
	
	collapse 		(mean) mu99 = p99 mu95 = p95 mu90 = p90 ///
						(sd) sd99 = p99 sd95 = p95 sd90 = p90 ///
						(count) n99 = p99 n95 = p95 n90 = p90, by(varname)
	
	gen 			hi99 = mu99 + invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	gen				lo99 = mu99 - invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	
	gen 			hi95 = mu95 + invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	gen				lo95 = mu95 - invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	
	gen 			hi90 = mu90 + invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	gen				lo90 = mu90 - invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	
	reshape 		long mu sd n hi lo, i(varname) j(p)	
	
	sort 			varname p
	gen 			obs = _n
/*
	replace			obs = 1 + obs if obs > 3
	replace			obs = 1 + obs if obs > 7
	replace			obs = 1 + obs if obs > 11
	replace			obs = 1 + obs if obs > 15
	replace			obs = 1 + obs if obs > 19
	replace			obs = 1 + obs if obs > 23
	replace			obs = 1 + obs if obs > 27
	replace			obs = 1 + obs if obs > 31
	replace			obs = 1 + obs if obs > 35
	replace			obs = 1 + obs if obs > 39
	replace			obs = 1 + obs if obs > 43
	replace			obs = 1 + obs if obs > 47
	replace			obs = 1 + obs if obs > 51
*/	
	sum			 	hi if p == 95 & varname == 1
	global			bmax = r(max)
	
	sum			 	lo if p == 95 & varname == 1
	global			bmin = r(min)
	
	twoway			(bar mu obs if p == 95, color(eltblue*1.5%60)) || ///
						(rcap hi lo obs if p == 95, yscale(r(0 1)) ///
						ylab(0(.1)1, labsize(small)) title("Tanzania") ///
						yline($bmax, lcolor(maroon) lstyle(solid) ) ///
						yline($bmin, lcolor(maroon)  lstyle(solid) ) ///
						lcolor(black) xscale(r(0 42) ex) ///
						xlabel(2 "Mean Daily Rain " 5 "Median Daily Rain " ///
						8 "Variance of Daily Rain " 11 "Skew of Daily Rain " ///
						14 "Total Seasonal Rain " 17 "Dev. in Total Rain " ///
						20 "z-Score of Total Rain " 23 "Rainy Days " ///
						26 "Dev. in Rainy Days " 29 "No Rain Days " ///
						32 "Dev. in No Rain Days " 35 "% Rainy Days " ///
						38 "Dev. in % Rainy Days " 41 "Longest Dry Spell ", ///
						angle(45) notick) xtitle("")), ///
						legend(pos(12) col(5) order(1 2) label(1 "p>0.95") ///
						label(2 "95% C.I."))  ///
						saving("$sfig/tza_pval_varname_rf", replace)
						
	*graph export 	"$sfig/tza_pval_varname_rf.pdf", as(pdf) replace
restore	
	

* uganda rainfall	
preserve
	keep			if varname < 15
	keep			if country == 7
	
	collapse 		(mean) mu99 = p99 mu95 = p95 mu90 = p90 ///
						(sd) sd99 = p99 sd95 = p95 sd90 = p90 ///
						(count) n99 = p99 n95 = p95 n90 = p90, by(varname)
	
	gen 			hi99 = mu99 + invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	gen				lo99 = mu99 - invttail(n99-1,0.025)*(sd99 / sqrt(n99))
	
	gen 			hi95 = mu95 + invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	gen				lo95 = mu95 - invttail(n95-1,0.025)*(sd95 / sqrt(n95))
	
	gen 			hi90 = mu90 + invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	gen				lo90 = mu90 - invttail(n90-1,0.025)*(sd90 / sqrt(n90))
	
	reshape 		long mu sd n hi lo, i(varname) j(p)	
	
	sort 			varname p
	gen 			obs = _n
/*
	replace			obs = 1 + obs if obs > 3
	replace			obs = 1 + obs if obs > 7
	replace			obs = 1 + obs if obs > 11
	replace			obs = 1 + obs if obs > 15
	replace			obs = 1 + obs if obs > 19
	replace			obs = 1 + obs if obs > 23
	replace			obs = 1 + obs if obs > 27
	replace			obs = 1 + obs if obs > 31
	replace			obs = 1 + obs if obs > 35
	replace			obs = 1 + obs if obs > 39
	replace			obs = 1 + obs if obs > 43
	replace			obs = 1 + obs if obs > 47
	replace			obs = 1 + obs if obs > 51
*/	
	sum			 	hi if p == 95 & varname == 1
	global			bmax = r(max)
	
	sum			 	lo if p == 95 & varname == 1
	global			bmin = r(min)
	
	twoway			(bar mu obs if p == 95, color(eltblue*1.5%60)) || ///
						(rcap hi lo obs if p == 95, yscale(r(0 1)) ///
						ylab(0(.1)1, labsize(small)) title("Uganda") ///
						yline($bmax, lcolor(maroon) lstyle(solid) ) ///
						yline($bmin, lcolor(maroon)  lstyle(solid) ) ///
						lcolor(black) xscale(r(0 42) ex) ///
						xlabel(2 "Mean Daily Rain " 5 "Median Daily Rain " ///
						8 "Variance of Daily Rain " 11 "Skew of Daily Rain " ///
						14 "Total Seasonal Rain " 17 "Dev. in Total Rain " ///
						20 "z-Score of Total Rain " 23 "Rainy Days " ///
						26 "Dev. in Rainy Days " 29 "No Rain Days " ///
						32 "Dev. in No Rain Days " 35 "% Rainy Days " ///
						38 "Dev. in % Rainy Days " 41 "Longest Dry Spell ", ///
						angle(45) notick) xtitle("")), ///
						legend(pos(12) col(5) order(1 2) label(1 "p>0.95") ///
						label(2 "95% C.I."))  ///
						saving("$sfig/uga_pval_varname_rf", replace)
						
	*graph export 	"$sfig/uga_pval_varname_rf.pdf", as(pdf) replace
restore	

			
* p-value varname and country for rainfall
	grc1leg2 		"$sfig/eth_pval_varname_rf.gph" "$sfig/mwi_pval_varname_rf.gph" ///
						"$sfig/ngr_pval_varname_rf.gph" "$sfig/nga_pval_varname_rf.gph" ///
						"$sfig/tza_pval_varname_rf.gph" "$sfig/uga_pval_varname_rf.gph", ///
						col(3) iscale(.5) pos(12) commonscheme imargin(0 0 0 0)
						
	graph export 	"$xfig\pval_varname_rf.pdf", as(pdf) replace

	
************************************************************************
**# 4 - end matter
************************************************************************


* close the log
	log	close

/* END */		