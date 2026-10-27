* Project: WB Weather
* Created: April 2020
* Created: jdm
* edited on: 27 Oct 2026
* edited by: codex
* Stata v.18

* does
	* reads in Tanzania, extended wave 4 .dta files with daily values
	* runs wxsum .ado file
	* outputs .dta file of the relevant weather variables
	* does the above for both rainfall and temperature data
	/* 	-the growing season that we care about is defined on the FAO website:
			http://www.fao.org/giews/countrybrief/country.jsp?code=TZA
		-we measure rainfall during the months that the FAO defines as sowing and growing
		-Tanzania has unimodal and bimodal regions. 70% of crop production occurs in regions that are unimodal, so we focus on those
		-We define the relevant months as Nov 1 - April 30
		-but in code below we keep the Jan 1 to Jul 1 since these are "rename" months */

* assumes
	* daily data converted to .dta
	* wxsum.ado

* TO DO:
	* completed


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	loc			root = "$wraw/tanzania/wave_5/daily/npsy4xp_up"
	loc			export 	= 	"$wraw/tanzania/wave_5/refined/npsy4xp_up"
	loc			logout 	= 	"$wraw/tanzania/logs"

* open log
	cap log close
	log			using 	"`logout'/tza_npsy4xp_weather", append


**********************************************************************
**# 1 - run command for rainfall
**********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'" files "*rf_daily.dta"
	if `"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* use the full available period as the reference
		unab		days : rf_*
		local		days : list sort days
		local		n : word count `days'
		local		first : word 1 of `days'
		local		last : word `n' of `days'
		local		first = real(substr("`first'", 4, 4))
		local		last = real(substr("`last'", 4, 4))

	* calculate rainfall metrics for this season
		wxsum		rf_, type(rain) ini_month(1) fin_month(7) ///
			ini_day(1) fin_day(1) rain_threshold(1) ///
			baseline(`first' `last') ref_min(2) shape(wide) keep(y4_hhid)

	* retain the variables and names used by the household build
		keep		y4_hhid mean_???? median_* sd_* total_* skew_* norain_* raindays_* ///
			pct_raindays_* dry_???? dev_total_* z_total_* dev_raindays_* ///
			dev_norain_* dev_pct_raindays_*
		rename		(mean_* median_* sd_* total_* skew_* pct_raindays_* ///
			dev_total_* z_total_* dev_pct_raindays_*) ///
			(mean_season_* median_season_* sd_season_* total_season_* ///
			skew_season_* percent_raindays_* dev_total_season_* ///
			z_total_season_* dev_percent_raindays_*)

	* retain year-major order for the variable ranges used by the build
		forvalues year = `first'/`last' {
			order		mean_season_`year' median_season_`year' sd_season_`year' ///
				total_season_`year' skew_season_`year' norain_`year' ///
				raindays_`year' percent_raindays_`year' dry_`year', last
		}

	* retain full-period reference summaries alongside wxsum deviations
		foreach stat in total_season raindays norain percent_raindays {
			egen		mean_period_`stat' = rowmean(`stat'_*)
			egen		sd_period_`stat' = rowsd(`stat'_*)
			order		mean_period_`stat' sd_period_`stat', last
			forvalues year = `first'/`last' {
				order		dev_`stat'_`year', last
				if "`stat'" == "total_season" {
					order		z_total_season_`year', last
				}
			}
		}
		isid		y4_hhid

	* save file
		compress
		save		"`export'/`dat'.dta", replace
	}


**********************************************************************
**# 2 - run command for temperature
**********************************************************************

* define local with all files in each sub-folder
	loc			fileList : dir "`root'" files "*tp_daily.dta"
	if `"`fileList'"' == "" error 601

* loop through each file in the above local
	foreach file in `fileList' {

	* import the daily data file
		use			"`root'/`file'", clear

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* use the full available period as the reference
		unab		days : tmp_*
		local		days : list sort days
		local		n : word count `days'
		local		first : word 1 of `days'
		local		last : word `n' of `days'
		local		first = real(substr("`first'", 5, 4))
		local		last = real(substr("`last'", 5, 4))

	* calculate temperature metrics and retain daily values for percentile bins
		wxsum		tmp_, type(temp) ini_month(1) fin_month(7) ///
			ini_day(1) fin_day(1) gdd_lo(10) gdd_hi(30) heat_threshold(30) ///
			baseline(`first' `last') ref_min(2) shape(wide)

	* retain within-season percentile shares used by the household build
		forvalues year = `first'/`last' {
			foreach pct in 20 40 60 80 100 {
				gen double	tempbin`pct'`year' = .
				label var	tempbin`pct'`year' ///
					"Share of observed days in within-season percentile bin ending at `pct'"
			}
			capture unab daily : tmp_`year'*
			if _rc continue
			local		season
			foreach var of local daily {
				local		date = daily(substr("`var'", 5, 8), "YMD")
				if inrange(`date', mdy(1,1,`year'), mdy(7,1,`year')) {
					local		season `season' `var'
				}
			}
			if `"`season'"' == "" continue

			tempvar		p20 p40 p60 p80
			foreach pct in 20 40 60 80 {
				quietly egen `p`pct'' = rowpctile(`season'), p(`pct')
			}
			mata: temps = st_data(., tokens("`season'"))
			mata: cuts = st_data(., tokens("`p20' `p40' `p60' `p80'"))
			mata: nobs = st_data(., "nobs_`year'")
			mata: st_store(., "tempbin20`year'", ///
				rowsum((temps :< cuts[.,1]) :& (temps :< .)) :/ nobs)
			mata: st_store(., "tempbin40`year'", ///
				rowsum((temps :>= cuts[.,1]) :& ///
				(temps :< cuts[.,2]) :& (temps :< .)) :/ nobs)
			mata: st_store(., "tempbin60`year'", ///
				rowsum((temps :>= cuts[.,2]) :& ///
				(temps :< cuts[.,3]) :& (temps :< .)) :/ nobs)
			mata: st_store(., "tempbin80`year'", ///
				rowsum((temps :>= cuts[.,3]) :& ///
				(temps :< cuts[.,4]) :& (temps :< .)) :/ nobs)
			mata: st_store(., "tempbin100`year'", ///
				rowsum((temps :>= cuts[.,4]) :& (temps :< .)) :/ nobs)
			mata: mata drop temps cuts nobs
			drop		`p20' `p40' `p60' `p80'
		}

	* retain the variables and names used by the household build
		keep		y4_hhid mean_* median_* sd_* skew_* max_* gdd_* ///
			dev_gdd_* z_gdd_* tempbin*
		rename		(mean_* median_* sd_* skew_* max_*) ///
			(mean_season_* median_season_* sd_season_* skew_season_* max_season_*)

	* retain year-major order for the variable ranges used by the build
		forvalues year = `first'/`last' {
			order		mean_season_`year' median_season_`year' sd_season_`year' ///
				skew_season_`year' max_season_`year' gdd_`year' ///
				tempbin20`year' tempbin40`year' tempbin60`year' ///
				tempbin80`year' tempbin100`year', last
		}

	* retain full-period reference summaries alongside wxsum deviations
		egen		mean_gdd = rowmean(gdd_*)
		egen		sd_gdd = rowsd(gdd_*)
		order		mean_gdd sd_gdd, last
		forvalues year = `first'/`last' {
			order		dev_gdd_`year' z_gdd_`year', last
		}
		isid		y4_hhid

	* save file
		compress
		save		"`export'/`dat'.dta", replace
	}

* close the log
	log			close

/* END */
