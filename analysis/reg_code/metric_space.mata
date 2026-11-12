/* Project: WB Weather - metric
   Created by: codex; edited by: codex; edited on: 31 Oct 2026
   does: sparse spatial neighbors, score diagnostics, and spatial covariance
   assumes: metric_front.do routines; released coordinates in decimal degrees
*/


/*********************************************************************
**# 1 - great-circle distances and a geographic neighbor index
*********************************************************************/

mata:
	real colvector metric_distance(real colvector lat1, real colvector lon1,
		real colvector lat2, real colvector lon2)
	{
		real colvector a
		real scalar rad
		rad = pi() / 180
		a = sin((lat2 :- lat1) * rad / 2):^2 +
			cos(lat1 * rad) :* cos(lat2 * rad) :*
			sin((lon2 :- lon1) * rad / 2):^2
		a = rowmin((J(rows(a), 1, 1), rowmax((J(rows(a), 1, 0), a))))
		return(2 * 6371.0088 * asin(sqrt(a)))
	}

	real matrix metric_neighbors(real matrix points, real rowvector years)
	{
		transmorphic scalar cells
		real matrix pairs
		real colvector target, source, bucket, js, distance, good
		real rowvector key
		real scalar t, lag, i, j, dx, dy, rlat, rlon, n, needed
		pairs = J(10000, 4, .)
		n = 0
		rlat = ceil(300 / 110) + 1
		rlon = ceil(300 / (110 * cos((max(abs(points[, 3])) +
			300 / 110) * pi() / 180))) + 1
		for (t = 1; t <= cols(years); t++) {
			target = selectindex(points[, 2] :== years[t])
			cells = asarray_create("real", 2)
			for (j = 1; j <= rows(target); j++) {
				key = floor(points[target[j], 3..4])
				bucket = J(0, 1, .)
				if (asarray_contains(cells, key)) bucket = asarray(cells, key)
				asarray(cells, key, (bucket \ target[j]))
			}
			for (lag = 0; lag <= 1; lag++) {
				if (t == 1 & lag == 1) continue
				source = selectindex(points[, 2] :== years[t-lag])
				for (j = 1; j <= rows(source); j++) {
					i = source[j]
					for (dx = -rlat; dx <= rlat; dx++) {
						for (dy = -rlon; dy <= rlon; dy++) {
							key = floor(points[i, 3..4]) + (dx, dy)
							if (!asarray_contains(cells, key)) continue
							js = vec(asarray(cells, key))
							if (lag == 0) js = select(js, js :> i)
							if (!length(js)) continue
							distance = metric_distance(points[i, 3], points[i, 4],
								points[js, 3], points[js, 4])
							good = distance :<= 300
							if (!sum(good)) continue
							js = vec(select(js, good))
							distance = vec(select(distance, good))
							needed = n + length(js)
							while (needed > rows(pairs)) pairs = pairs \ J(rows(pairs), 4, .)
							pairs[|n+1, 1 \ needed, 4|] = (J(length(js), 1, i),
								js, distance, J(length(js), 1, lag))
							n = needed
						}
					}
				}
			}
		}
		if (!n) return(J(0, 4, .))
		return(pairs[|1, 1 \ n, 4|])
	}

	void metric_save_neighbors(real matrix points, real matrix pairs)
	{
		string scalar previous
		real matrix data
		if (!rows(pairs)) return
		data = (points[pairs[, 1], 1], points[pairs[, 2], 1], pairs[, 3..4],
			points[pairs[, 1], 2], points[pairs[, 2], 2])
		previous = st_framecurrent()
		st_framecurrent("neighbors")
		st_addobs(rows(data))
		st_store(., tokens("ea1 ea2 distance lag year1 year2"), data)
		st_framecurrent(previous)
	}


/*********************************************************************
**# 2 - household scores and the same-sample spatial sandwich
*********************************************************************/

	void metric_spatial(real scalar spec, real matrix points,
		real matrix pairs, real rowvector years)
	{
		real matrix a, r, z, q, hhscore, ea, info, meat, variance, se, result
		real matrix normalized, usable, b, product, mask, diagnostic, totals, counts
		real colvector h, year, loc, lookup, o, ea_levels, n, idx, ii, jj, d, w
		real colvector prior, current, year_rank, lat, lon, band
		real rowvector xx, xy, beta, hh, same_ea, lag_meat, mu, sd, chosen, qvars, bandwidths
		real scalar k, g, correction, e, j, t, lo, hi, bandwidth, lag, row
		string rowvector weather, names
		weather = tokens(st_local("rain"))
		a = st_data(., tokens(st_local("y") + " " + st_local("rain")))
		h = st_data(., "hhid")
		year = st_data(., "year")
		lat = st_data(., "latitude")
		lon = st_data(., "longitude")
		r = metric_resid(a, h, year, spec, k)
		z = r[, 2..cols(r)]
		xx = colsum(z:^2)
		xy = colsum(z :* r[, 1])
		beta = xy :/ xx
		for (j = 1; j <= cols(z); j++) if (xx[j] <= 1e-20) beta[j] = 0
		q = z :* (r[, 1] :- z :* beta)
		hhscore = metric_sums(q, h)
		hh = colsum(hhscore:^2)
		g = rows(hhscore)
		correction = g / (g - 1) * (rows(a) - 1) / (rows(a) - k)

		/* align EA sums to the geometry cached for both outcomes */
		lookup = J(max(points[, 1]), 1, .)
		lookup[points[, 1]] = 1::rows(points)
		loc = lookup[st_data(., "ea_wave_id")]
		o = order(loc, 1)
		info = panelsetup(loc[o], 1)
		ea_levels = uniqrows(loc[o])
		ea = J(rows(points), cols(q), 0)
		n = J(rows(points), 1, 0)
		ea[ea_levels, .] = panelsum(q[o, .], info)
		n[ea_levels] = info[, 2] - info[, 1] :+ 1
		same_ea = colsum(ea:^2) - colsum(q:^2)
		meat = J(3, cols(q), 0)
		lag_meat = J(1, cols(q), 0)
		bandwidths = (50, 100, 200)

		/* prespecified diagnostic metrics: seasonal rainfall and rainy days */
		chosen = J(1, 0, .)
		for (j = 1; j <= cols(weather); j++) {
			if (substr(weather[j], 2, 2) == "05" | substr(weather[j], 2, 2) == "08") {
				chosen = (chosen, j)
			}
		}
		normalized = J(rows(points), cols(chosen), 0)
		usable = J(rows(points), cols(chosen), 0)
		for (t = 1; t <= cols(years); t++) {
			idx = selectindex((points[, 2] :== years[t]) :& (n :> 0))
			if (rows(idx) < 2) continue
			b = ea[idx, chosen] :/ sqrt(n[idx])
			mu = mean(b)
			sd = sqrt(colsum((b :- mu):^2) / (rows(b) - 1))
			for (j = 1; j <= cols(chosen); j++) {
				if (sd[j] <= 1e-20) continue
				normalized[idx, j] = (b[, j] :- mu[j]) / sd[j]
				usable[idx, j] = J(rows(idx), 1, 1)
			}
		}
		totals = counts = J(10, cols(chosen), 0)

		/* sparse pair batches keep memory proportional to observed neighbors */
		for (lo = 1; lo <= rows(pairs); lo = lo + 10000) {
			hi = min((lo + 9999, rows(pairs)))
			for (lag = 0; lag <= 1; lag++) {
				idx = selectindex(pairs[|lo, 4 \ hi, 4|] :== lag) :+ lo :- 1
				if (!rows(idx)) continue
				ii = pairs[idx, 1]
				jj = pairs[idx, 2]
				d = pairs[idx, 3]
				product = ea[ii, .] :* ea[jj, .]
				if (lag == 0) {
					for (j = 1; j <= 3; j++) {
						bandwidth = bandwidths[j]
						w = rowmax((J(rows(d), 1, 0), 1 :- d / bandwidth))
						meat[j, .] = meat[j, .] + 2 * colsum(product :* w)
					}
				}
				else {
					/* two directions times the lag-one Bartlett weight of 0.5 */
					w = rowmax((J(rows(d), 1, 0), 1 :- d / 100))
					lag_meat = lag_meat + colsum(product :* w)
				}
				band = 1 :+ (d :> 25) :+ (d :> 50) :+ (d :> 100) :+ (d :> 200)
				product = normalized[ii, .] :* normalized[jj, .]
				mask = usable[ii, .] :* usable[jj, .]
				for (j = 1; j <= 5; j++) {
					idx = selectindex(band :== j)
					if (!rows(idx)) continue
					row = lag * 5 + j
					totals[row, .] = totals[row, .] + colsum(product[idx, .] :* mask[idx, .])
					counts[row, .] = counts[row, .] + colsum(mask[idx, .])
				}
			}
		}

		/* remove own-household covariance from the adjacent-interval addition */
		year_rank = J(max(years), 1, .)
		year_rank[years'] = 1::cols(years)
		o = order((h, year), (1, 2))
		prior = o[|1 \ rows(o)-1|]
		current = o[|2 \ rows(o)|]
		idx = selectindex((h[prior] :== h[current]) :&
			(year_rank[year[current]] :- year_rank[year[prior]] :== 1))
		if (rows(idx)) {
			prior = prior[idx]
			current = current[idx]
			d = metric_distance(lat[prior], lon[prior], lat[current], lon[current])
			w = rowmax((J(rows(d), 1, 0), 1 :- d / 100))
			lag_meat = lag_meat - colsum(q[prior, .] :* q[current, .] :* w)
		}

		variance = ((hh :+ same_ea :+ meat) * correction) :/ (xx:^2)
		variance = variance \ (((hh + same_ea + meat[2, .] + lag_meat) *
			correction) :/ (xx:^2))
		se = J(5, cols(q), .)
		se[1, .] = sqrt(hh * correction) :/ xx
		for (j = 1; j <= cols(q); j++) {
			for (t = 1; t <= 4; t++) {
				if (variance[t, j] >= 0 & variance[t, j] < .) se[t+1, j] = sqrt(variance[t, j])
			}
		}
		result = (beta', se', variance', hh', same_ea', meat', lag_meat', xx',
			J(cols(q), 1, correction), J(cols(q), 1, rows(a)), J(cols(q), 1, g),
			J(cols(q), 1, rows(ea_levels)),
			J(cols(q), 1, rows(uniqrows(sort(year, 1)))), J(cols(q), 1, k))
		for (j = 1; j <= cols(q); j++) {
			if (xx[j] <= 1e-20) result[j, 1..10] = J(1, 10, .)
		}
		st_matrix("sp_fit", result)

		diagnostic = J(10 * cols(chosen), 5, .)
		row = 0
		for (j = 1; j <= cols(chosen); j++) {
			for (t = 1; t <= 10; t++) {
				row++
				diagnostic[row, .] = (chosen[j], mod(t-1, 5)+1, t > 5,
					totals[t, j] / counts[t, j], counts[t, j])
			}
		}
		st_matrix("sp_diag", diagnostic)
		names = "q_" :+ weather
		qvars = st_addvar("double", names)
		st_store(., qvars, q)
	}

end
