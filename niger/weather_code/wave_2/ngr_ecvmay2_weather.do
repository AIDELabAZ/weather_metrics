* Project: WB Weather
* Created on: April 2020
* Created by: jdm
* edited on: 27 Oct 2026
* edited by: codex
* Stata v.18

* does
	* reads in Niger, wave 2 .dta files with daily values
	* runs wxsum .ado file
	* outputs .dta file of the relevant weather variables
	* does the above for both rainfall and temperature data
	/* 	-the growing season that we care about is defined on the FAO website:
			http://www.fao.org/giews/countrybrief/country.jsp?code=NER
		-we measure rainfall during the months that the FAO defines as sowing and growing
		-we define the relevant months as 1 June - 31 October */

* assumes
	* NGR_ECVMAY2_converter.do
	* wxsum.ado

* TO DO:
	* completed


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	loc			root = "$wraw/niger/wave_2/daily/ecvmay2_up"
	loc			export = "$wraw/niger/wave_2/refined/ecvmay2_up"
	loc			logout = "$wraw/niger/logs"

* open log
	cap log close
	log			using "`logout'/ngr_ecvmay2_weather", replace


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

	* drop weather variables beyond 2014
		keep		hhid_y2 rf_19830101-rf_20141231

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* calculate rainfall metrics for this season
		wxsum		rf_, type(rain) ini_month(6) fin_month(10) ///
			ini_day(1) fin_day(1) rain_threshold(1) ///
			baseline(1983 2014) ref_min(2) shape(wide) keep(hhid_y2)

	* retain the variables and names used by the household build
		keep		hhid_y2 mean_???? median_* sd_* total_* skew_* norain_* raindays_* ///
			pct_raindays_* dry_???? dev_total_* z_total_* dev_raindays_* ///
			dev_norain_* dev_pct_raindays_*
		rename		(mean_* median_* sd_* total_* skew_* pct_raindays_* ///
			dev_total_* z_total_* dev_pct_raindays_*) ///
			(mean_season_* median_season_* sd_season_* total_season_* ///
			skew_season_* percent_raindays_* dev_total_season_* ///
			z_total_season_* dev_percent_raindays_*)

	* retain year-major order for the variable ranges used by the build
		forvalues year = 1983/2014 {
			order		mean_season_`year' median_season_`year' sd_season_`year' ///
				total_season_`year' skew_season_`year' norain_`year' ///
				raindays_`year' percent_raindays_`year' dry_`year', last
		}

	* retain full-period reference summaries alongside wxsum deviations
		foreach stat in total_season raindays norain percent_raindays {
			egen		mean_period_`stat' = rowmean(`stat'_*)
			egen		sd_period_`stat' = rowsd(`stat'_*)
			order		mean_period_`stat' sd_period_`stat', last
			forvalues year = 1983/2014 {
				order		dev_`stat'_`year', last
				if "`stat'" == "total_season" {
					order		z_total_season_`year', last
				}
			}
		}
		isid		hhid_y2

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
		use			"`root'/`folder'/`file'", clear

	* drop weather variables beyond 2014
		keep		hhid_y2 tmp_19830101-tmp_20141231

	* define locals to govern file naming
		loc			dat = substr("`file'", 1, length("`file'") - 10)

	* calculate temperature metrics and retain daily values for percentile bins
		wxsum		tmp_, type(temp) ini_month(6) fin_month(10) ///
			ini_day(1) fin_day(1) gdd_lo(10) gdd_hi(30) heat_threshold(30) ///
			baseline(1983 2014) ref_min(2) shape(wide)

	* retain within-season percentile shares used by the household build
		forvalues year = 1983/2014 {
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
				if inrange(`date', mdy(6,1,`year'), mdy(10,1,`year')) {
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
		keep		hhid_y2 mean_* median_* sd_* skew_* max_* gdd_* ///
			dev_gdd_* z_gdd_* tempbin*
		rename		(mean_* median_* sd_* skew_* max_*) ///
			(mean_season_* median_season_* sd_season_* skew_season_* max_season_*)

	* retain year-major order for the variable ranges used by the build
		forvalues year = 1983/2014 {
			order		mean_season_`year' median_season_`year' sd_season_`year' ///
				skew_season_`year' max_season_`year' gdd_`year' ///
				tempbin20`year' tempbin40`year' tempbin60`year' ///
				tempbin80`year' tempbin100`year', last
		}

	* retain full-period reference summaries alongside wxsum deviations
		egen		mean_gdd = rowmean(gdd_*)
		egen		sd_gdd = rowsd(gdd_*)
		order		mean_gdd sd_gdd, last
		forvalues year = 1983/2014 {
			order		dev_gdd_`year' z_gdd_`year', last
		}
		isid		hhid_y2

	* save file
		compress
		save		"`export'/`dat'.dta", replace
	}

* close the log
	log			close

/* END */
