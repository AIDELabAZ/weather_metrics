* project: wb weather - metric
* created on: 26 oct 2026
* created by: codex
* edited on: 26 oct 2026
* edited by: codex
* stata v.18
* does
* adapts wxsum statistics to the names and order used by wave builds
* uses corrected wxsum definitions with the historical season and reference

* assumes
* daily weather data are loaded and the calling wave has opened its log
* arguments: stub, type, first month, final month, identifier

**********************************************************************
**# 0 - setup
**********************************************************************

* read and check the metric request
	version		18
	args		stub type first_month last_month id
	if			!inlist("`type'", "rain", "temp") error 198
	confirm		variable `id'
	isid		`id'
	which		wxsum
	unab		daily : `stub'*
	local		offset = strlen("`stub'") + 1
	mata:		wm_years = strtoreal(substr(tokens(st_local("daily")), `offset', 4))
	mata:		st_local("first_year", strofreal(min(wm_years))); st_local("last_year", ///
				strofreal(max(wm_years)))
	mata:		mata drop wm_years
	if			`last_year' <= `first_year' {
		display		as error ///
					"At least two seasons are needed for the historical full-period reference."
		error		198
	}

**********************************************************************
**# 1 - retain the within-season percentile bins
**********************************************************************

* retain the percentile-bin columns used by wave builds (v23-v27)
* They are not wxsum's absolute-temperature bins, and are dropped by panel_build.
* Compute shares over observed days; an empty season has missing shares.
	tempfile	percentile_bins
	if			"`type'" == "temp" {
		preserve
		local		bin_variables
		forvalues	year = `first_year'/`last_year' {
			foreach		percentile in 20 40 60 80 100 {
				quietly		gen double	tempbin`percentile'`year' = .
				label var	tempbin`percentile'`year' ///
							"Share of observed days in within-season percentile bin ending at `percentile'"
				local		bin_variables `bin_variables' tempbin`percentile'`year'
			}
			capture		unab		year_daily : `stub'`year'*
			if			_rc continue
			local		season
			foreach		variable of local year_daily {
				local		date = daily(substr("`variable'", `offset', 8), "YMD")
				if			inrange(`date', mdy(`first_month',1,`year'), ///
							mdy(`last_month',1,`year')) local season `season' ///
							`variable'
			}
			if			`"`season'"' == "" continue
			tempvar		p20 p40 p60 p80 nobs
			quietly		egen		`nobs' = rownonmiss(`season')
			foreach		percentile in 20 40 60 80 {
				quietly		egen		`p`percentile'' = rowpctile(`season'), ///
							p(`percentile')
			}
			mata:		wm_t = st_data(., tokens("`season'")); wm_p = st_data(., ///
						tokens("`p20' `p40' `p60' `p80'")); wm_n = st_data(., ///
						"`nobs'")
			mata:		st_store(., "tempbin20`year'", rowsum((wm_t :< wm_p[.,1]) :& ///
						(wm_t ///
						:< .)) :/ wm_n)
			mata:		st_store(., "tempbin40`year'", rowsum((wm_t :>= wm_p[.,1]) :& ///
						(wm_t :< wm_p[.,2]) :& (wm_t :< .)) :/ wm_n)
			mata:		st_store(., "tempbin60`year'", rowsum((wm_t :>= wm_p[.,2]) :& ///
						(wm_t :< wm_p[.,3]) :& (wm_t :< .)) :/ wm_n)
			mata:		st_store(., "tempbin80`year'", rowsum((wm_t :>= wm_p[.,3]) :& ///
						(wm_t :< wm_p[.,4]) :& (wm_t :< .)) :/ wm_n)
			mata:		st_store(., "tempbin100`year'", rowsum((wm_t :>= wm_p[.,4]) :& ///
						(wm_t :< .)) :/ wm_n)
			mata:		mata drop wm_t wm_p wm_n
			drop		`p20' `p40' `p60' `p80' `nobs'
		}
		keep		`id' `bin_variables'
		save		`percentile_bins'
		restore
	}

**********************************************************************
**# 2 - calculate wxsum statistics
**********************************************************************

* retain day 1 at both ends of the historical season
* The old reference covered all available seasons, not a rolling ten-year window.
	local		temp_options
	if			"`type'" == "temp" local temp_options ///
				"gdd_lo(10) gdd_hi(30) heat_threshold(30)"
	wxsum		`stub', type(`type') ini_month(`first_month') fin_month(`last_month') ///
				ini_day(1) fin_day(1) baseline(`first_year' `last_year') ref_min(2) ///
				shape(long) keep(`id') `temp_options'
	quietly		count		if nobs == 0
	if			r(N) display as error "wxsum: " r(N) ///
				" unit-seasons have no observed days; statistics remain missing."
	rename		(mean median sd skew) (mean_season_ median_season_ sd_season_ ///
				skew_season_)
	local		stubs mean_season_ median_season_ sd_season_ skew_season_
	if			"`type'" == "rain" {
		rename		(total norain raindays pct_raindays dry dev_total z_total ///
					dev_raindays dev_norain dev_pct_raindays) ///
					(total_season_ norain_ raindays_ percent_raindays_ dry_ ///
					dev_total_season_ z_total_season_ dev_raindays_ dev_norain_ ///
					dev_percent_raindays_)
		local		stubs `stubs' total_season_ norain_ raindays_ percent_raindays_ dry_ ///
					dev_total_season_ z_total_season_ dev_raindays_ dev_norain_ ///
					dev_percent_raindays_
	}
	else		{
		rename		(max gdd dev_gdd z_gdd) (max_season_ gdd_ dev_gdd_ z_gdd_)
		local		stubs `stubs' max_season_ gdd_ dev_gdd_ z_gdd_
	}
	keep		`id' year `stubs'
	levelsof	year, local(years)
	reshape		wide `stubs', i(`id') j(year)
	if			"`type'" == "temp" merge 1:1 `id' using `percentile_bins', assert(match) ///
				nogen

**********************************************************************
**# 3 - restore the wave-file schema
**********************************************************************

* retain year-major order for the downstream variable ranges
	local		annual_order
	foreach		year of local years {
		local		annual_order `annual_order' mean_season_`year' median_season_`year' ///
					sd_season_`year'
		if			"`type'" == "rain" local annual_order `annual_order' ///
					total_season_`year'
		local		annual_order `annual_order' skew_season_`year'
		if			"`type'" == "rain" local annual_order `annual_order' norain_`year' ///
					raindays_`year' percent_raindays_`year' dry_`year'
		else		local annual_order `annual_order' max_season_`year' gdd_`year' ///
					tempbin20`year' tempbin40`year' tempbin60`year' tempbin80`year' ///
					tempbin100`year'
	}
	local		reference_order
	if			"`type'" == "rain" {
		foreach		statistic in total_season raindays norain percent_raindays {
			egen		mean_period_`statistic' = rowmean(`statistic'_*)
			egen		sd_period_`statistic' = rowsd(`statistic'_*)
			local		reference_order `reference_order' mean_period_`statistic' ///
						sd_period_`statistic'
			foreach		year of local years {
				local		reference_order `reference_order' dev_`statistic'_`year'
				if			"`statistic'" == "total_season" local reference_order ///
							`reference_order' z_total_season_`year'
			}
		}
	}
	else		{
		egen		mean_gdd = rowmean(gdd_*)
		egen		sd_gdd = rowsd(gdd_*)
		local		reference_order mean_gdd sd_gdd
		foreach		year of local years {
			local		reference_order `reference_order' dev_gdd_`year' z_gdd_`year'
		}
	}
**********************************************************************
**# 4 - end matter
**********************************************************************

* retain the output contract and record the weather engine
	order		`id' `annual_order' `reference_order'
	keep		`id' `annual_order' `reference_order'
	char		_dta[weather_metrics_engine] ///
				"wxsum; corrected GDD, skewness, missing-day and dry-spell definitions"
	char		_dta[weather_metrics_contract] ///
				"legacy wide names and ordering; full-period reference; day 1 endpoints"
	isid		`id'

/* END */
