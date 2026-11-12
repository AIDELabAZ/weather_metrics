* Project: WB Weather - metric
* Created on: 31 Oct 2026
* Created by: codex
* Last updated: 12 Nov 2026
* Last updated by: codex
* Stata v.18

* does
	* estimates geographically held-out rainfall selection frontiers
	* saves candidate scores, choices, sample counts, and recorded folds
	* defines shared Mata routines without estimation when called with routines

* assumes
	* projectdo.do has established the code, raw, and data globals
	* metric_keys.do has recovered the panel's geographic keys

* TO DO:
	* done


**********************************************************************
**# 0 - arguments and routine definitions
**********************************************************************

* shared callers load the routines without reading data or opening a log
*	do "$code/analysis/reg_code/metric_front.do" routines
	args reps orders
	capture mata: mata drop metric_sums() metric_demean() metric_resid() metric_stats()
	capture mata: mata drop metric_root() metric_blocks() metric_folds()
	capture mata: mata drop metric_choices() metric_add() metric_front()


**********************************************************************
**# 1 - fixed-effects calculations
**********************************************************************


**********************************************************************
**## 1.1 - grouped sums and residualization
**********************************************************************

mata:
	real matrix metric_sums(real matrix a, real colvector group)
	{
		real colvector o
		o = order(group, 1)
		return(panelsum(a[o, .], panelsetup(group[o], 1)))
	}

	real matrix metric_demean(real matrix a, real colvector group)
	{
		real colvector o, g, index
		real matrix info, means, b
		o = order(group, 1)
		g = group[o]
		info = panelsetup(g, 1)
		index = runningsum(1 \ (g[|2 \ rows(g)|] :!= g[|1 \ rows(g)-1|]))
		means = panelsum(a[o, .], info) :/ (info[, 2] - info[, 1] :+ 1)
		b = a[o, .] - means[index, .]
		return(b[invorder(o), .])
	}

	real matrix metric_resid(real matrix a, real colvector h,
		real colvector year, real scalar spec, | real scalar k)
	{
		real matrix d, w, wd, wa
		real colvector levels
		real scalar j
		levels = uniqrows(sort(year, 1))
		if (spec == 7) {
			k = rows(levels) + 1
			return(metric_demean(a, year))
		}
		d = J(rows(year), rows(levels) - 1, .)
		for (j = 2; j <= rows(levels); j++) d[, j-1] = year :== levels[j]
		w = metric_demean((a, d), h)
		wa = w[, 1..cols(a)]
		wd = w[, (cols(a)+1)..cols(w)]
		/* use the same QR rank for residualization and the degrees of freedom */
		wa = wa - wd * qrsolve(wd, wa, k)
		k = k + 2
		return(wa)
	}
end


**********************************************************************
**## 1.2 - single-instrument fits on the same observations
**********************************************************************

mata:
	real matrix metric_stats(real matrix a, real colvector h,
		real colvector year, real scalar spec)
	{
		real matrix r, z, q, sums, result
		real colvector y
		real rowvector xx, xy, beta, se, corr
		real scalar n, g, k, correction, j
		r = metric_resid(a, h, year, spec, k)
		y = r[, 1]
		z = r[, 2..cols(r)]
		xx = colsum(z:^2)
		xy = colsum(z :* y)
		beta = xy :/ xx
		corr = xy :/ sqrt(xx :* sum(y:^2))

		/* keep an omitted candidate from contaminating other score columns */
		for (j = 1; j <= cols(z); j++) {
			if (xx[j] <= 1e-20 | xx[j] >= .) beta[j] = 0
		}
		q = z :* (y :- z :* beta)
		sums = metric_sums(q, h)
		n = rows(a)
		g = rows(sums)
		correction = g / (g - 1) * (n - 1) / (n - k)
		se = sqrt(colsum(sums:^2) * correction) :/ xx
		result = (beta', se', (beta :/ se)', corr', xx')
		for (j = 1; j <= cols(z); j++) {
			if (xx[j] <= 1e-20 | xx[j] >= .) result[j, .] = J(1, 5, .)
		}
		return(result)
	}
end


**********************************************************************
**# 2 - geographic folds and instrument selection
**********************************************************************


**********************************************************************
**## 2.1 - connected household and EA-wave groups
**********************************************************************

mata:
	real scalar metric_root(real colvector parent, real scalar node)
	{
		while (parent[node] != node) node = parent[node]
		return(node)
	}

	void metric_blocks()
	{
		real colvector h, ea, parent, block
		real scalar i, a, b, offset
		h = st_data(., "hhid")
		ea = st_data(., "ea_wave_id")
		offset = max(h)
		parent = 1::(offset + max(ea))
		for (i = 1; i <= rows(h); i++) {
			a = metric_root(parent, h[i])
			b = metric_root(parent, offset + ea[i])
			parent[max((a, b))] = min((a, b))
		}
		block = J(rows(h), 1, .)
		for (i = 1; i <= rows(h); i++) block[i] = metric_root(parent, h[i])
		st_store(., "block", block)
	}

	void metric_folds(string scalar target)
	{
		real matrix data
		real colvector o, fold, ranking
		real rowvector load
		real scalar i, current, f
		data = st_data(., ("stratum_id", "nhh"))
		o = order((data[, 1], runiform(rows(data), 1)), (1, 2))
		fold = J(rows(data), 1, .)
		current = .
		for (i = 1; i <= rows(o); i++) {
			if (data[o[i], 1] != current) {
				current = data[o[i], 1]
				load = J(1, 5, 0)
			}
			ranking = order((load' + runiform(5, 1) * 1e-6), 1)
			f = ranking[1]
			fold[o[i]] = f
			load[f] = load[f] + data[o[i], 2]
		}
		st_store(., target, fold)
	}
end


**********************************************************************
**## 2.2 - candidate selection and sign-oriented validation
**********************************************************************

mata:
	real matrix metric_choices(real matrix train, real matrix valid,
		real scalar permutations)
	{
		real rowvector sizes
		real colvector ordering, score, prefix
		real matrix result
		real scalar p, rule, j, k, winner, best, s, row, rank
		sizes = (1, 2, 3, 5, 10, 20, 40, 60, 84)
		result = J(permutations * 2 * cols(sizes), 21, .)
		row = 0
		for (p = 1; p <= permutations; p++) {
			ordering = order(runiform(84, 1), 1)
			for (rule = 1; rule <= 2; rule++) {
				score = abs(train[, rule == 1 ? 4 : 3])
				for (j = 1; j <= cols(sizes); j++) {
					k = sizes[j]
					prefix = ordering[|1 \ k|]
					winner = .
					best = -1
					for (s = 1; s <= k; s++) {
						if (score[prefix[s]] < . & score[prefix[s]] > best) {
							winner = prefix[s]
							best = score[winner]
						}
					}
					row++
					result[row, 1..3] = (p, rule, k)
					result[row, 21] = sum(score[prefix] :< .)
					if (winner >= .) continue
					rank = 1 + sum((score :> best) :& (score :< .))
					result[row, 4..20] = (winner, train[winner, 1..4],
						valid[winner, 1..4], abs(train[winner, 4]),
						sign(train[winner, 4]) * valid[winner, 4],
						abs(train[winner, 4]) - sign(train[winner, 4]) *
						valid[winner, 4], train[winner, 1] * valid[winner, 1] < 0,
						abs(valid[winner, 3]) > 1.96 & valid[winner, 3] < .,
						abs(valid[winner, 3]) > 4.81 & valid[winner, 3] < .,
						rank, sign(train[winner, 4]))
				}
			}
		}
		return(result)
	}

	void metric_add(string scalar frame, string scalar variables, real matrix data)
	{
		string scalar previous
		real scalar n
		previous = st_framecurrent()
		st_framecurrent(frame)
		n = st_nobs()
		st_addobs(rows(data))
		st_store((n+1)::(n+rows(data)), tokens(variables), data)
		st_framecurrent(previous)
	}
end


**********************************************************************
**## 2.3 - cached fits for each partition and fixed-effects model
**********************************************************************

mata:
	void metric_front(real scalar country, real scalar outcome,
		real scalar repetitions, real scalar permutations)
	{
		real matrix a, folds, train, valid, choices, candidates, selected, base
		real matrix ta, va, audit, baseline
		real colvector h, year, it, iv
		real scalar spec, rep, f, nc, ns, nr, ntrain, nvalid, ht, hv, yt, yv, years
		string scalar y
		y = outcome == 1 ? "lntf_yld" : "lncp_yld"
		a = st_data(., tokens(y + " " + st_local("rain")))
		h = st_data(., "hhid")
		year = st_data(., "year")
		years = rows(uniqrows(sort(year, 1)))
		folds = st_data(., tokens(st_local("foldvars")))
		candidates = J(2 * repetitions * 5 * 84, 20, .)
		selected = J(2 * repetitions * 5 * permutations * 18, 30, .)
		audit = J(2 * repetitions * 5, 12, .)
		baseline = J(168, 11, .)
		nc = ns = nr = 0
		for (spec = 2; spec <= 7; spec = spec + 5) {
			base = metric_stats(a, h, year, spec)
			ta = (J(84, 1, country), J(84, 1, outcome), J(84, 1, spec),
				(1::84), base[, 1..4], J(84, 1, rows(a)),
				J(84, 1, rows(uniqrows(sort(h, 1)))),
				J(84, 1, rows(uniqrows(sort(year, 1)))))
			baseline[(1::84) :+ (spec == 2 ? 0 : 84), .] = ta
			for (rep = 1; rep <= repetitions; rep++) {
				for (f = 1; f <= 5; f++) {
					it = selectindex(folds[, rep] :!= f)
					iv = selectindex(folds[, rep] :== f)
					ntrain = rows(it)
					nvalid = rows(iv)
					ht = rows(uniqrows(sort(h[it], 1)))
					hv = rows(uniqrows(sort(h[iv], 1)))
					yt = rows(uniqrows(sort(year[it], 1)))
					yv = rows(uniqrows(sort(year[iv], 1)))
					nr++
					audit[nr, .] = (country, outcome, spec, rep, f, ntrain,
						nvalid, ht, hv, yt, yv, ht > 1 & hv > 1 & yt == years & yv == years)
					if (!audit[nr, 12]) continue
					train = metric_stats(a[it, .], h[it], year[it], spec)
					valid = metric_stats(a[iv, .], h[iv], year[iv], spec)
					ta = (J(84, 1, country), J(84, 1, outcome), J(84, 1, spec),
						J(84, 1, rep), J(84, 1, f), (1::84), train, valid[, 1..4],
						J(84, 1, ntrain), J(84, 1, nvalid),
						J(84, 1, ht), J(84, 1, hv), valid[, 5])
					candidates[|nc+1, 1 \ nc+84, 20|] = ta
					nc = nc + 84
					rseed(20261031 + country * 10000 + rep * 100 + f)
					choices = metric_choices(train, valid, permutations)
					va = (J(rows(choices), 1, country), J(rows(choices), 1, outcome),
						J(rows(choices), 1, spec), J(rows(choices), 1, rep),
						J(rows(choices), 1, f), choices,
						J(rows(choices), 1, ntrain), J(rows(choices), 1, nvalid),
						J(rows(choices), 1, ht), J(rows(choices), 1, hv))
					selected[|ns+1, 1 \ ns+rows(choices), 30|] = va
					ns = ns + rows(choices)
				}
				printf("Country %g, outcome %g, reg%g: allocation %g of %g\n",
					country, outcome, spec, rep, repetitions)
			}
		}
		metric_add("candidates", "country outcome spec rep fold candidate " +
			"beta_train se_train t_train r_train xx_train beta_valid se_valid " +
			"t_valid r_valid n_train n_valid hh_train hh_valid xx_valid",
			candidates[|1, 1 \ nc, 20|])
		metric_add("selected", "country outcome spec rep fold ordering rule k " +
			"candidate beta_train se_train t_train r_train beta_valid se_valid " +
			"t_valid r_valid strength_train strength_valid gap reversal pass196 " +
			"pass481 rank direction estimable_prefix n_train n_valid hh_train hh_valid",
			selected[|1, 1 \ ns, 30|])
		metric_add("split_audit", "country outcome spec rep fold n_train n_valid " +
			"hh_train hh_valid years_train years_valid accepted", audit)
		metric_add("baseline", "country outcome spec candidate beta se t corr n hh years",
			baseline)
	}
end


* return to spatial, bootstrap, and audit callers after loading the routines
	if "`reps'" == "routines" exit


**********************************************************************
**# 3 - estimation setup
**********************************************************************

* use five allocations for the pilot, then twenty for the full analysis
*	do "$code/analysis/reg_code/metric_front.do" 5 20
	if "`reps'" == "" loc reps = 20
	if "`orders'" == "" loc orders = 20
	loc			suffix = cond(`reps' == 20, "", "_pilot")
	loc			out "$data/results_data/additional_evidence/exhibit2"
	cap log close
	log using	"`out'/logs/metric_front`suffix'.log", text replace
	timer clear 1
	timer on 1
	tempfile	panel assignments


**********************************************************************
**# 4 - candidate dictionary and geographically grouped folds
**********************************************************************

* verify the suffix mapping against the current country append files
	clear
	set obs		84
	gen byte	candidate = _n
	gen byte	metric = ceil(candidate / 6)
	gen byte	product = mod(candidate - 1, 6) + 1
	gen str8	weather_var = "v" + string(metric, "%02.0f") + ///
				"_rf" + string(product)
	gen str8	product_name = ""
	loc			products ARC2 CHIRPS CPC ERA5 MERRA-2 TAMSAT
	forvalues p = 1/6 {
		loc			name : word `p' of `products'
		replace		product_name = "`name'" if product == `p'
	}
	isid		weather_var
	save		"`out'/candidates", replace
	export delimited using "`out'/candidates.csv", replace
	loc			rain
	forvalues j = 1/84 {
		loc			x = weather_var[`j']
		loc			rain `rain' `x'
	}

* connect households that share any observed EA-wave or parish-wave block
	use			"`out'/panel_keys", clear
	egen		ea_wave_id = group(country wave ea_key)
	gen long	block = .
	mata: metric_blocks()
	egen		stratum_id = group(country stratum)
	sort		block hhid year
	by block: replace stratum_id = stratum_id[1]
	keep		country hhid block stratum_id
	duplicates drop
	isid		hhid
	save		"`assignments'"
	contract	country block stratum_id, freq(nhh)
	forvalues r = 1/20 {
		set seed	`=20261031 + `r''
		gen byte	fold`r' = .
		mata: metric_folds("fold`r'")
	}
	merge		1:m country block stratum_id using "`assignments'", nogen
	isid		country hhid
	char _dta[fold_seed] "Allocation r uses seed 20261031+r; 20 allocations"
	char _dta[grouping] "Connected household/EA-wave groups; Uganda parish-wave blocks"
	save		"`out'/folds", replace
	keep		country hhid block fold*
	save		"`assignments'", replace

* retain the existing outcome transformations and weather values
	use			country hhid year lntf_yld lncp_yld `rain' using ///
				"$data/regression_data/lsms_panel", clear
	isid		country hhid year
	merge		1:1 country hhid year using "`out'/panel_keys", ///
				keepusing(wave ea_key rain_missing) assert(match) nogen
	merge		m:1 country hhid using "`assignments'", assert(match) nogen
	egen		missing_now = rowmiss(`rain')
	gen byte	weather_ok = rain_missing == 0 & missing_now == 0
	save		"`panel'"


**********************************************************************
**# 5 - common samples and cached candidate scores
**********************************************************************

* keep score and selection records separate from the observation-level panel
	foreach f in candidates selected split_audit baseline {
		capture frame drop `f'
	}
	frame create candidates double(country outcome spec rep fold candidate ///
		beta_train se_train t_train r_train xx_train beta_valid se_valid ///
		t_valid r_valid n_train n_valid hh_train hh_valid xx_valid)
	frame create selected double(country outcome spec rep fold ordering rule k ///
		candidate beta_train se_train t_train r_train beta_valid se_valid ///
		t_valid r_valid strength_train strength_valid gap reversal pass196 ///
		pass481 rank direction estimable_prefix n_train n_valid hh_train hh_valid)
	frame create split_audit double(country outcome spec rep fold n_train n_valid ///
		hh_train hh_valid years_train years_valid accepted)
	frame create baseline double(country outcome spec candidate beta se t corr n hh years)
	tempname	samples
	postfile	`samples' byte(country outcome) long(n_panel n_outcome ///
				n_weather n_single n_common households eas years) using ///
				"`out'/sample_audit`suffix'", replace
	loc			foldvars
	forvalues r = 1/`reps' {
		loc			foldvars `foldvars' fold`r'
	}
	foreach c in 1 2 4 5 6 7 {
		forvalues o = 1/2 {
			use			"`panel'", clear
			keep if		country == `c'
			loc			n_panel = _N
			loc			y = cond(`o' == 1, "lntf_yld", "lncp_yld")
			drop if		missing(`y')
			loc			n_outcome = _N
			keep if		weather_ok
			loc			n_weather = _N
			bysort hhid: gen int waves = _N
			quietly count if waves == 1
			loc			n_single = r(N)
			keep if		waves >= 2
			loc			n_common = _N
			egen		hh_tag = tag(hhid)
			quietly count if hh_tag
			loc			hh = r(N)
			egen		ea_tag = tag(wave ea_key)
			quietly count if ea_tag
			loc			eas = r(N)
			quietly levelsof year, local(years)
			loc			nyears : word count `years'
			post		`samples' (`c') (`o') (`n_panel') (`n_outcome') ///
						(`n_weather') (`n_single') (`n_common') (`hh') ///
						(`eas') (`nyears')
			mata: metric_front(`c', `o', `reps', `orders')
		}
	}
	postclose	`samples'


**********************************************************************
**# 6 - save results and compare the common sample with the existing fits
**********************************************************************

	foreach f in candidates selected baseline {
		frame `f' {
			merge		m:1 candidate using "`out'/candidates", ///
						assert(match) nogen
			gen str9	outcome_var = cond(outcome == 1, "lntf_yld", "lncp_yld")
			gen str4	spec_id = "reg" + string(spec)
			if "`f'" == "candidates" {
				isid		country outcome_var weather_var spec_id rep fold
				count if	missing(se_train, r_train, se_valid, r_valid)
			}
			if "`f'" == "selected" {
				isid		country outcome_var spec_id rep fold ordering rule k
				count if	missing(strength_train, strength_valid, t_valid)
			}
			if "`f'" == "baseline" isid country outcome_var weather_var spec_id
			compress
			loc			name = cond("`f'" == "candidates", ///
						"candidate_scores", cond("`f'" == "selected", ///
						"selected_instruments", "baseline_common"))
			save		"`out'/`name'`suffix'", replace
		}
	}
	frame split_audit {
		list		country outcome spec rep fold if !accepted, noobs
		save		"`out'/split_audit`suffix'", replace
		export delimited using "`out'/split_audit`suffix'.csv", replace
	}

* compare every common-sample fit with its original regression-result row
	use			"$data/results_data/reg_results", clear
	keep if		inlist(regname, "reg2", "reg7") & ///
				regexm(weather_var, "^v(0[1-9]|1[0-4])_rf[1-6]$")
	gen str9	outcome_var = cond(depvar == "tf", "lntf_yld", "lncp_yld")
	rename		regname spec_id
	rename		(betarain serain obs nclusters) (beta_original se_original n_original hh_original)
	keep		country outcome_var weather_var spec_id *_original
	merge		1:1 country outcome_var weather_var spec_id using ///
				"`out'/baseline_common`suffix'", assert(match) nogen
	gen double	beta_change = beta - beta_original
	gen double	se_change = se - se_original
	gen long	n_excluded = n_original - n
	save		"`out'/baseline_comparison`suffix'", replace
	export delimited using "`out'/baseline_comparison`suffix'.csv", replace
	use			"`out'/sample_audit`suffix'", clear
	list, noobs
	export delimited using "`out'/sample_audit`suffix'.csv", replace
	timer off 1
	timer list 1
	log close

/* END */
