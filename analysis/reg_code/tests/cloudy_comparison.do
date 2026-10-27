* project: wb weather - metric
* created on: 26 oct 2026
* created by: codex
* edited on: 26 oct 2026
* edited by: codex
* stata v.18
* does
	* checks matched rainfall samples, saved metadata, and historical estimates

* assumes
	* run from the repository root with a new scratch directory argument
	* optional second argument: original regressions.do for comparison


**********************************************************************
**# 0 - setup
**********************************************************************

* initialize the synthetic panel test
	version		18
	clear		all
	set			processors 1
	set			more off
	args		testroot baseline
	if `"`testroot'"' == "" error 198
	global		code `"`c(pwd)'"'
	capture mkdir "`testroot'"
	capture mkdir "`testroot'/regression_data"
	capture mkdir "`testroot'/regression_data/logs"
	capture mkdir "`testroot'/results_data"
* record the comparison test
	tempname	test_log
	log			using "`testroot'/cloudy_comparison.log", text append name(`test_log')


**********************************************************************
**# 1 - create the synthetic panel
**********************************************************************

* protect existing research inputs
	confirm		new file "`testroot'/regression_data/lsms_panel.dta"
	global		data `"`testroot'"'
	set			seed 27491
	set			obs 320
	gen long	hhid = ceil(_n/4)
	gen byte	country = 1 + (hhid > 40)
	bysort		hhid: gen int year = 2010 + _n
	gen double	lntf_yld = hhid/30 + rnormal() + (year-2010)/4
	gen double	lncp_yld = hhid/40 + rnormal() + (year-2010)/5
	foreach prefix in tf cp {
		gen double	ln`prefix'_lab = rnormal()
		gen double	ln`prefix'_frt = rnormal()
		foreach input in pst hrb irr {
			gen byte	`prefix'_`input' = runiform() > .5
		}
	}
	forvalues metric = 1/14 {
		local		metric_id : display %02.0f `metric'
		forvalues product = 1/6 {
			gen double	v`metric_id'_rf`product' = rnormal() + hhid/20 + (year-2010)/3
		}
	}
	gen double	v15_tp1 = rnormal() + hhid/20
* Exercise omitted within-household coefficients and incomplete cases.
	replace		v14_rf6 = hhid
	replace		year = . in 1/3
	replace		v05_rf1 = . in 11/15
	replace		lntf_yld = . in 21/25
	replace		lncp_yld = . in 31/35
	replace		lntf_lab = . in 41/45
	replace		lncp_lab = . in 51/55
	save		"$data/regression_data/lsms_panel.dta", replace


**********************************************************************
**# 2 - calculate independent reference estimates
**********************************************************************

* retain reference estimates for the saved-result checks
	xtset		hhid
	quietly xtreg lntf_yld v05_rf1 i.year if country == 1, fe vce(cluster ///
				hhid)
	scalar		expected_fe = _b[v05_rf1]
	scalar		expected_fe_se = _se[v05_rf1]
	tempvar		sample
	gen byte	`sample' = e(sample)
	quietly reg lntf_yld v05_rf1 i.year if `sample', vce(cluster hhid)
	scalar		expected_pooled = _b[v05_rf1]
	scalar		expected_pooled_se = _se[v05_rf1]
	scalar		expected_n = e(N)
	scalar		expected_clusters = e(N_clust)


**********************************************************************
**# 3 - check saved results and historical replication
**********************************************************************

* compare specifications on the same synthetic observations
	tempfile	historical_raw historical_complete
	if `"`baseline'"' != "" {
		quietly do "`baseline'"
		use			"$data/results_data/reg_results.dta", clear
		sort		country sat depvar regname varname
		save		`historical_raw'
		use			"$data/results_data/lsms_complete_results.dta", clear
		sort		country sat depvar regname varname
		save		`historical_complete'
	}
	quietly do "$code/analysis/reg_code/regressions.do"
	use			"$data/results_data/reg_results.dta", clear
	assert		_N == 2*2*(6*85+84)
	isid		country outcome_var weather_var spec_id
	count		if spec_id == "reg7"
	assert		r(N) == 2*2*84
	assert		year_fe == 1 if paired_sample
	assert		household_fe == (spec_id == "reg2") if paired_sample
	assert		!paired_sample if weather_var == "v15_tp1"
	assert		!estimable if weather_var == "v14_rf6" & spec_id == "reg2"
	assert		reldif(betarain, scalar(expected_fe)) < 1e-6 if country == 1 & ///
				outcome_var == "lntf_yld" & weather_var == "v05_rf1" & spec_id == ///
				"reg2"
	assert		reldif(serain, scalar(expected_fe_se)) < 1e-6 if country == 1 & ///
				outcome_var == "lntf_yld" & weather_var == "v05_rf1" & spec_id == ///
				"reg2"
	assert		reldif(betarain, scalar(expected_pooled)) < 1e-6 if country == 1 & ///
				outcome_var == "lntf_yld" & weather_var == "v05_rf1" & spec_id == ///
				"reg7"
	assert		reldif(serain, scalar(expected_pooled_se)) < 1e-6 if country == 1 & ///
				outcome_var == "lntf_yld" & weather_var == "v05_rf1" & spec_id == ///
				"reg7"
	assert		obs == scalar(expected_n) & nclusters == scalar(expected_clusters) if ///
				country == 1 & outcome_var == "lntf_yld" & weather_var == "v05_rf1" ///
				& paired_sample
	if `"`baseline'"' != "" {
		preserve
		keep		if spec_id != "reg7"
		sort		country sat depvar regname varname
		cf			country sat depvar regname varname betarain serain adjustedr ///
					loglike dfr ///
					obs using `historical_raw', all
		restore
	}
	keep		if paired_sample
	bysort		country outcome_var weather_var (spec_id): assert _N == 2
	by			country outcome_var weather_var: assert obs[1] == obs[2] & ///
				nclusters[1] == ///
				nclusters[2]

	use			"$data/results_data/lsms_complete_results.dta", clear
	assert		_N == 2376
	isid		reg_id
	isid		country outcome_var weather_var spec_id
	assert		regname == 7 if spec_id == "reg7"
	assert		missing(ci_lo) & missing(ci_up) & missing(sig) if !estimable
	if `"`baseline'"' != "" {
		keep		if spec_id != "reg7"
		sort		country sat depvar regname varname
		cf			reg_id country sat depvar regname varname beta stdrd_err adjustedr ///
					loglike dfr obs using `historical_complete', all
	}
	display		as result ///
				"PASS: Cloudy sample matching, full grid, omitted coefficients, historical estimates and IDs."


**********************************************************************
**# 4 - end matter
**********************************************************************

* close the test log
	log			close `test_log'

/* END */
