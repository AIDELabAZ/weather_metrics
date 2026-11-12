* Project: WB Weather - metric
* Created on: 31 Oct 2026
* Created by: codex
* Last updated: 12 Nov 2026
* Last updated by: codex
* Stata v.18

* does
	* pilots household and geographic-block bootstrap coefficient differences
	* uses CHIRPS total rainfall and rainy days, both outcomes, available countries

* assumes
	* metric_geo.do has created the georeferenced panel

* TO DO:
	* assess this pilot before designing any full spatial bootstrap


**********************************************************************
**# 0 - setup
**********************************************************************

	loc			out "$data/results_data/additional_evidence/exhibit3"
	loc			reps = 199
	loc			width = 100
	cap log close
	log using	"`out'/logs/metric_block.log", text replace
	tempfile	panel groups draws
	capture mata: mata drop metric_weighted_beta() metric_block_draws()
	do			"$code/analysis/reg_code/metric_front.do" routines


**********************************************************************
**# 1 - geographic blocks that keep household histories together
**********************************************************************

	use			"`out'/lsms_panel_geo", clear
	keep if		geo_available

* a local equirectangular projection defines fixed 100-km grid cells
	bysort country: egen double ref_lat = mean(latitude)
	gen double	grid_x = floor((6371.0088 * cos(ref_lat * _pi / 180) * ///
				longitude * _pi / 180) / `width')
	gen double	grid_y = floor((6371.0088 * latitude * _pi / 180) / `width')
	egen long	cell = group(country grid_x grid_y)
	gen long	block = hhid
	loc			changes = 1
	while `changes' > 0 {
		bysort cell: egen long cell_min = min(block)
		bysort hhid: egen long hh_min = min(cell_min)
		quietly count if block != hh_min
		loc			changes = r(N)
		replace		block = hh_min
		drop		cell_min hh_min
	}
	save		"`panel'"
	keep		country hhid block ref_lat
	duplicates drop
	isid		country hhid
	char _dta[blocks] "100-km equirectangular cells connected through household histories"
	save		"`out'/block_groups", replace


**********************************************************************
**# 2 - frequency-weighted coefficient statistic
**********************************************************************

* integer frequencies reproduce copied households/blocks with separate HH FE
mata:
	real rowvector metric_weighted_beta(real matrix a, real matrix d,
		real colvector weights)
	{
		real matrix ar, dr, r, z
		ar = a :* sqrt(weights)
		dr = d :* sqrt(weights)
		r = ar - dr * qrsolve(dr, ar)
		z = r[, 2..cols(r)]
		return(colsum(z :* r[, 1]) :/ colsum(z:^2))
	}

	void metric_block_draws(real scalar country, real scalar outcome,
		real scalar reps)
	{
		real matrix a, ah, d, dh, result, base
		real colvector h, block, year, levels, units, frequency, sampled, weights, sd
		real rowvector b2, b7, delta
		real scalar j, r, design, g
		a = st_data(., tokens(st_local("y") + " v05_rf2 v08_rf2"))
		h = st_data(., "hgroup")
		block = st_data(., "bgroup")
		year = st_data(., "year")
		levels = uniqrows(sort(year, 1))
		d = J(rows(a), rows(levels), .)
		for (j = 1; j <= rows(levels); j++) d[, j] = year :== levels[j]
		ah = metric_demean(a, h)
		dh = metric_demean(d, h)
		weights = J(rows(a), 1, 1)
		b2 = metric_weighted_beta(ah, dh, weights)
		b7 = metric_weighted_beta(a, d, weights)
		sd = sqrt(diagonal(variance(a)))
		base = (b2', b7', (b2-b7)', sd[|2 \ rows(sd)|] / sd[1])
		st_matrix("block_base", base)
		result = J(reps, 4, .)
		for (design = 1; design <= 2; design++) {
			units = design == 1 ? h : block
			g = max(units)
			if (g < 2) continue
			rseed(20261031 + country * 1000 + outcome * 10 + design)
			for (r = 1; r <= reps; r++) {
				frequency = J(g, 1, 0)
				sampled = floor(runiform(g, 1) * g) :+ 1
				for (j = 1; j <= g; j++) {
					frequency[sampled[j]] = frequency[sampled[j]] + 1
				}
				weights = frequency[units]
				b2 = metric_weighted_beta(ah, dh, weights)
				b7 = metric_weighted_beta(a, d, weights)
				delta = b2 - b7
				result[r, (design*2-1)..(design*2)] = delta
			}
		}
		st_matrix("block_draws", result)
	}
end


**********************************************************************
**# 3 - the predeclared metric-product subset across available countries
**********************************************************************

	tempname	post
	postfile	`post' byte(country outcome design) str8 weather_var int rep ///
				double(delta original scale) long(n households blocks) using ///
				"`draws'", replace
	foreach c in 1 2 4 5 6 7 {
		forvalues o = 1/2 {
			use			"`panel'", clear
			loc			y = cond(`o' == 1, "lntf_yld", "lncp_yld")
			keep if		country == `c' & !missing(`y')
			egen long	hgroup = group(hhid)
			egen long	bgroup = group(block)
			quietly summarize hgroup, meanonly
			loc			hh = r(max)
			quietly summarize bgroup, meanonly
			loc			blocks = r(max)
			loc			n = _N
			mata: metric_block_draws(`c', `o', `reps')
			foreach design in 1 2 {
				forvalues j = 1/2 {
					loc			x = cond(`j' == 1, "v05_rf2", "v08_rf2")
					loc			col = (`design' - 1) * 2 + `j'
					forvalues r = 1/`reps' {
						post		`post' (`c') (`o') (`design') ("`x'") (`r') ///
								(block_draws[`r', `col']) (block_base[`j', 3]) ///
								(block_base[`j', 4]) (`n') (`hh') (`blocks')
					}
				}
			}
			display		"Country `c', `y': `hh' households, `blocks' geographic blocks."
		}
	}
	postclose	`post'
	use			"`draws'", clear
	gen str9	outcome_var = cond(outcome == 1, "lntf_yld", "lncp_yld")
	gen str12	resampling = cond(design == 1, "Household", "Geographic")
	gen double	delta_std = delta * scale
	gen double	original_std = original * scale
	char _dta[pilot] "199 draws; CHIRPS total rainfall/rainy days; both outcomes; available countries"
	save		"`out'/block_boot_draws", replace
	bysort country outcome_var weather_var design: egen double ci_lo = ///
				pctile(delta_std), p(2.5)
	bysort country outcome_var weather_var design: egen double ci_hi = ///
				pctile(delta_std), p(97.5)
	collapse	(p50) median = delta_std (count) successful = delta_std ///
				(firstnm) ci_lo ci_hi original_std n households blocks, ///
				by(country outcome_var weather_var design resampling)
	gen int		requested = `reps'
	gen int		failed = requested - successful
	gen byte	complete = successful >= .95 * requested
	replace		ci_lo = . if !complete
	replace		ci_hi = . if !complete
	gen byte	significant = (ci_lo > 0 | ci_hi < 0) if complete
	save		"`out'/block_boot_pilot", replace
	export delimited using "`out'/block_boot_pilot.csv", replace
	preserve
	keep		country outcome_var weather_var original_std n households blocks ///
				design ci_lo ci_hi successful complete significant
	reshape wide ci_lo ci_hi successful complete significant, ///
				i(country outcome_var weather_var) j(design)
	gen byte	paired = complete1 & complete2
	gen double	width_ratio = (ci_hi2 - ci_lo2) / (ci_hi1 - ci_lo1) if paired
	label var	width_ratio "Geographic/household interval width; complete pairs only"
	save		"`out'/block_boot_comparison", replace
	export delimited using "`out'/block_boot_comparison.csv", replace
	restore
	list		country outcome_var weather_var resampling blocks successful ///
				ci_lo ci_hi significant, noobs
	log close

/* END */
