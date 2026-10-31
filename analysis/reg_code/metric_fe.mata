/* Project: WB Weather - metric
   Created by: codex; edited by: codex; edited on: 31 Oct 2026
   does: batch fixed-effects residualization and household-clustered scores
   assumes: one observation per household and survey year
*/


/*********************************************************************
**# 1 - grouped sums and residualization
*********************************************************************/

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
		/* disconnected survey cohorts leave some year indicators redundant */
		k = rank(wd) + 2
		return(wa - wd * qrsolve(wd, wa))
	}


/*********************************************************************
**# 2 - separate single-instrument fits on the same observations
*********************************************************************/

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
