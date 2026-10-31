/* Project: WB Weather - metric
   Created by: codex; edited by: codex; edited on: 31 Oct 2026
   does: geographic folds and the nested rainfall selection frontier
   assumes: metric_fe.mata is loaded; candidates use one common sample
*/


/*********************************************************************
**# 1 - connected household and EA-wave groups
*********************************************************************/

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


/*********************************************************************
**# 2 - candidate-set selection and sign-oriented validation
*********************************************************************/

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


/*********************************************************************
**# 3 - fit each candidate once per partition and fixed-effects model
*********************************************************************/

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
