"""driving_style.py - driving style and shift analysis from CMU D-Bus series (Mazda 3 BM, manual).

analyse(d) -> dict; pages(pdf, r, header) draws 3 PDF pages.
d: numpy series in seconds since start:
  tv,v (km/h)  tr,rpm  tlo,alo (m/s2)  tth,th (%)  gp_t,gp_v (bcm.GearPosNotification)  br_t,br_v  dist_km

Assumptions (own analysis 2026-11-24, unofficial):
- GearPosNotification goes to 0 as soon as rpm/speed no longer matches a gear (clutch in / slipping / neutral)
  and jumps to the new gear once it runs in sync again. Duration of the 0 = shift duration.
- Two jerks per shift (jerk, m/s3, longitudinal G smoothed over 0.4 s): "in" = throttle off/clutch in (-0.3..+0.4 s),
  "out" = engaging (-0.4..+1.2 s). "in" mainly follows how hard you accelerated (r = 0.9); "out" is the clutch technique.
- Throttle 0 % + fuel pulses = cruise control; coasting with fuel cut = FuelPulse ~0. Limits: <2.5 smooth, 2.5-5 noticeable, >5 hard (comfort norms for buses/elevators ~2-3).
- rpm x2 is an estimate; ratios are right, absolute values may deviate ~10 %.
"""
import numpy as np

RATIO = {1: 113, 2: 59, 3: 40, 4: 31, 5: 25, 6: 20}   # rpm per km/h (calibration drive 2026-11-23)
J_OK, J_HARD = 2.5, 5.0
C1, C2, C3, CG = "#9c1c1c", "#1f4e79", "#e08a00", "#666666"
# Shift-type keys stay Dutch in the logic; DISP/disp() map them to English for display only.
KIND_COL = {"op": C2, "terug": "#2e8b57", "uitrol": C3, "wegrijden": "#6c3483"}
KIND_LBL = {"op": "upshift", "terug": "downshift", "uitrol": "engage gear after coasting in neutral",
            "wegrijden": "pulling away"}
KIND_DISP = {"op": "upshift", "terug": "downshift", "uitrol": "engage after coasting", "wegrijden": "pull away"}
# Grade/class keys stay stable; DISP maps them to English for display only.
CLS_DISP = {"soepel": "smooth", "merkbaar": "noticeable", "hard": "hard"}
SCORE_DISP = {"Inkoppelen (koppeling op)": "Engaging (clutch up)",
              "Gas los / koppeling in": "Throttle off / clutch in",
              "Versnelling erin na rollen": "Gear engaged after coasting",
              "Schakelmoment": "Shift point",
              "Rustig optrekken": "Gentle acceleration",
              "Anticiperen / remmen": "Anticipation / braking",
              "Motorvriendelijk": "Engine-friendly",
              "Constante snelheid": "Constant speed",
              "_totaal": "_total"}
DISP = {**KIND_DISP, **CLS_DISP, **SCORE_DISP,
        "1e": "1st", "2e": "2nd", "3e": "3rd", "4e": "4th", "5e": "5th", "6e": "6th",
        "stil/<5": "stop/<5", "uitrollen": "coast", "overgang": "transition",
        "neutraal": "neutral", "achteruit?": "reverse?"}
def disp(k): return DISP.get(k, k)


def _smooth(t, y, dt=0.1, win=0.4):
    g = np.arange(t[0], t[-1], dt)
    yi = np.interp(g, t, y)
    n = max(1, int(win / dt))
    return g, np.convolve(yi, np.ones(n) / n, mode="same")


def _zoh(tx, y, g, default=0):
    i = np.searchsorted(tx, g, side="right") - 1
    return np.where(i >= 0, y[np.clip(i, 0, None)], default)


def _events(t, mask, min_gap):
    out, last, on = [], -1e9, False
    for ti, m in zip(t, mask):
        if m and not on and ti - last > min_gap:
            out.append(ti)
        if m:
            last = ti
        on = m
    return out


def _cls(j):
    return "soepel" if j < J_OK else ("merkbaar" if j < J_HARD else "hard")


def analyse(d):
    tv, v, tr, rpm = d["tv"], d["v"], d["tr"], d["rpm"]
    tlo, alo, tth, th = d["tlo"], d["alo"], d["tth"], d["th"]
    gp_t, gp_v = d["gp_t"], d["gp_v"].astype(int)
    ga, a_s = _smooth(tlo, alo)
    jerk = np.gradient(a_s, ga)
    vg = np.interp(ga, tv, v)
    rg = np.interp(ga, tr, rpm)
    # throttle only arrives on change -> hold (zoh), do not interpolate
    thg = _zoh(tth, th, ga) if len(tth) else np.zeros_like(ga)
    gear = _zoh(gp_t, gp_v, ga)
    brk = (_zoh(d["br_t"], d["br_v"], ga, 1) == 2) if len(d.get("br_t", [])) else np.zeros(len(ga), bool)
    # fuel pulses per second (1 s average): ~0 = fuel cut (engine braking)
    frs = None
    if len(d.get("tfu", [])) > 10:
        cum = np.concatenate([[0], np.cumsum(np.diff(d["fu"]) % 256)])
        frs = np.convolve(np.gradient(np.interp(ga, d["tfu"], cum), ga), np.ones(10) / 10, "same")
    at = lambda arr, t: float(np.interp(t, ga, arr))
    sel = lambda t0, t1: (ga >= t0) & (ga <= t1)
    jmax = lambda w: float(np.abs(jerk[w]).max()) if w.any() else np.nan

    # ---------- shifts: gear -> 0 -> gear ----------
    shifts = []
    seq = list(zip(gp_t, gp_v))
    for k in range(1, len(seq) - 1):
        _, g0 = seq[k - 1]
        tz, gz = seq[k]
        t1, g1 = seq[k + 1]
        if not (gz == 0 and g1 in RATIO):
            continue
        ph = sel(tz, t1)
        vmin = float(vg[ph].min()) if ph.any() else at(vg, t1)
        dur = t1 - tz
        if vmin < 3:                      # came to a stop during the 0-phase
            if g1 == 1:
                kind = "wegrijden"
            elif g1 == 2:                 # 1st not reported (too short/slipping): this is the 1>2
                kind, g0, tz, dur = "op", 1, t1 - 1.5, np.nan
            else:
                continue
        elif g0 not in RATIO or g1 == g0:
            continue
        elif dur > 6:
            kind = "uitrol"
        else:
            kind = "op" if g1 > g0 else "terug"
        j_in = jmax(sel(tz - 0.3, tz + 0.4)) if kind in ("op", "terug") else np.nan
        j_out = jmax(sel(t1 - (3.0 if kind == "wegrijden" else 0.4), t1 + 1.2))
        vv = at(vg, t1)
        rb = at(rg, tz - 0.3)
        shifts.append(dict(t=float(t1), tz=float(tz), van=int(g0), naar=int(g1), soort=kind, duur=float(dur),
                           v=vv, rpm_voor=rb, rpm_na=at(rg, t1 + 0.6), rpm_doel=RATIO[g1] * vv,
                           j_in=j_in, j_uit=j_out, jerk=j_out, klasse=_cls(j_out),
                           klasse_in=_cls(j_in) if not np.isnan(j_in) else "-", tussengas=np.nan,
                           a_voor=at(a_s, tz - 0.3) / 9.81, rem=bool(brk[sel(tz - 0.5, t1 + 1.2)].any()),
                           gas=float(thg[sel(tz - 0.6, tz - 0.1)].max()) if sel(tz - 0.6, tz - 0.1).any() else 0.0))

    mv = vg > 5
    g = a_s[mv] / 9.81
    drive_s = mv.sum() * 0.1
    hard_acc = _events(ga, (a_s / 9.81 > 0.25) & mv, 2.0)
    hard_brk = _events(ga, (a_s / 9.81 < -0.30) & mv, 2.0)
    lug = mv & (gear >= 2) & (rg < 1300) & (thg > 40)
    high = mv & (rg > 3500)
    if frs is not None:
        coast_gear = mv & (gear >= 2) & (frs < 0.2) & (thg < 1)           # real engine braking, fuel cut
        cruise = mv & (gear >= 3) & (thg < 1) & (frs > 1.0) & (vg > 40)   # pedal off but engine delivers: cruise control
    else:
        coast_gear = cruise = np.zeros(len(ga), bool)
    coast_neutral = mv & (gear == 0) & (vg > 20)
    runs, cur = np.zeros(len(ga), int), 0
    for i_, x in enumerate(coast_neutral):
        cur = cur + 1 if x else 0
        runs[i_] = cur
    hw = vg > 80
    cruise_std = np.nan
    if hw.sum() > 600:
        vs = vg[hw]
        n = len(vs) // 600
        cruise_std = float(np.median([vs[i * 600:(i + 1) * 600].std() for i in range(n)])) if n else np.nan
    bands = [0, 1300, 1800, 2500, 3500, 9000]
    band_t = {gg: np.histogram(rg[mv & (gear == gg)], bins=bands)[0] * 0.1 for gg in range(1, 7)}

    ups = [s for s in shifts if s["soort"] == "op"]
    dns = [s for s in shifts if s["soort"] == "terug"]
    med = lambda lst, k: float(np.nanmedian([s[k] for s in lst])) if lst else np.nan
    pm = mv & ~cruise
    r = dict(shifts=shifts, ups=ups, dns=dns, n_up=len(ups), n_down=len(dns),
             up_rpm=med(ups, "rpm_voor"), up_rpm_na=med(ups, "rpm_na"), up_dur=med(ups, "duur"),
             up_jerk=med(ups, "jerk"), up_jin=med(ups, "j_in"), dn_dur=med(dns, "duur"), dn_jerk=med(dns, "jerk"),
             low_after=sum(1 for s in ups if s["rpm_na"] < 1200),
             hard_acc=hard_acc, hard_brk=hard_brk,
             g_p95_acc=float(np.percentile(g[g > 0], 95)) if (g > 0).any() else 0.0,
             g_p95_brk=float(np.percentile(-g[g < 0], 95)) if (g < 0).any() else 0.0,
             g_max_acc=float(g.max()), g_max_brk=float(-g.min()),
             th_p95=float(np.percentile(thg[pm], 95)) if pm.any() else 0.0, full_gas_s=float((mv & (thg >= 95)).sum() * 0.1),
             lug_s=float(lug.sum() * 0.1), high_s=float(high.sum() * 0.1), rpm_max=float(rg[mv].max()),
             coast_gear_s=float(coast_gear.sum() * 0.1), cruise_s=float(cruise.sum() * 0.1),
             coast_neutral_s=float(((runs > 30) & coast_neutral).sum() * 0.1),
             cruise_std=cruise_std, drive_s=float(drive_s), dist_km=float(d["dist_km"]),
             band_t=band_t, bands=bands, ga=ga, a_s=a_s, jerk=jerk, rg=rg, gear=gear, vg=vg, thg=thg, mv=mv)
    r["scores"] = _scores(r)
    return r


def _lin(x, good, bad):
    if x is None or np.isnan(x):
        return np.nan
    return float(np.clip((bad - x) / (bad - good), 0, 1) * 100)


def _scores(r):
    per100 = 100.0 / max(r["dist_km"], 1)
    ph = 3600.0 / max(r["drive_s"], 1)
    pt = {"soepel": 1.0, "merkbaar": 0.5, "hard": 0.0}
    sh = [s for s in r["shifts"] if s["soort"] in ("op", "terug") and not s["rem"]]
    s = {}
    if sh:
        s["Inkoppelen (koppeling op)"] = float(np.mean([pt[x["klasse"]] for x in sh]) * 100)
        s["Gas los / koppeling in"] = float(np.mean([pt[x["klasse_in"]] for x in sh]) * 100)
    wr = [x for x in r["shifts"] if x["soort"] in ("wegrijden", "uitrol") and not x["rem"]]
    if len(wr) >= 3:
        s["Versnelling erin na rollen"] = float(np.mean([pt[x["klasse"]] for x in wr]) * 100)
    ur = r["up_rpm"]
    if not np.isnan(ur):  # petrol (Skyactiv-G): shifting up at 1800-2600 rpm is frugal and smooth
        s["Schakelmoment"] = float(np.clip(100 - max(0, 1800 - ur) / 6 - max(0, ur - 2800) / 8 - r["low_after"] * per100 * 1.5, 0, 100))
    s["Rustig optrekken"] = _lin(len(r["hard_acc"]) * per100, 1, 15)
    s["Anticiperen / remmen"] = _lin(len(r["hard_brk"]) * per100, 1, 10)
    s["Motorvriendelijk"] = _lin((r["lug_s"] + r["high_s"]) * ph, 10, 120)
    s["Constante snelheid"] = _lin(r["cruise_std"], 1.0, 5.0)
    vals = [x for x in s.values() if not np.isnan(x)]
    s["_totaal"] = float(np.mean(vals)) if vals else np.nan
    return s


def verdict(x):
    return "uitstekend" if x >= 85 else "goed" if x >= 70 else "redelijk" if x >= 55 else "verbeterpunt"

VERDICT_DISP = {"uitstekend": "excellent", "goed": "good", "redelijk": "fair", "verbeterpunt": "needs work"}
DISP.update(VERDICT_DISP)
DISP.update({"%de" % g: o for g, o in zip(range(1, 7), ("1st", "2nd", "3rd", "4th", "5th", "6th"))})


# ======================================================================
def pages(pdf, r, header, plt, A4):
    sc = r["scores"]
    tot = sc["_totaal"]
    sh = r["shifts"]
    ups, dns = r["ups"], r["dns"]
    km = r["dist_km"]

    # ===== R1: report card =====
    fig = plt.figure(figsize=A4)
    header(fig, "Driving style - how well do you drive?",
           f"Assessment based on G-forces, rpm, throttle and gear position  |  {km:.0f} km, {r['drive_s']/60:.0f} min driving")
    fig.text(0.06, 0.80, f"{tot/10:.1f}", fontsize=54, weight="bold", color=C1)
    fig.text(0.06, 0.76, f"report card grade ({disp(verdict(tot))})", fontsize=10, color=CG)
    ax = fig.add_axes([0.53, 0.50, 0.42, 0.38])
    items = [(k, v_) for k, v_ in sc.items() if not k.startswith("_") and not np.isnan(v_)]
    names = [disp(k) for k, _ in items][::-1]
    vals = [v_ for _, v_ in items][::-1]
    cols = ["#2e8b57" if x >= 85 else "#7fb069" if x >= 70 else C3 if x >= 55 else C1 for x in vals]
    ax.barh(names, vals, color=cols)
    for i_, x in enumerate(vals):
        ax.text(x + 1, i_, f"{x/10:.1f}  {disp(verdict(x))}", va="center", fontsize=8.5)
    ax.set_xlim(0, 125)
    ax.set_xticks([0, 25, 50, 75, 100], ["0", "2.5", "5", "7.5", "10"])
    ax.set_title("Sub-scores")
    kp = [("Upshift at", f"~{r['up_rpm']:.0f} rpm"), ("Shift time (up)", f"{r['up_dur']:.1f} s"),
          ("Hard on engaging", f"{sum(1 for s in sh if s['klasse']=='hard')}x / {len(sh)}"),
          ("Hard acceleration >0.25 g", f"{len(r['hard_acc'])}x"), ("Hard braking >0.3 g", f"{len(r['hard_brk'])}x"),
          ("Max rpm", f"~{r['rpm_max']:.0f} rpm")]
    for k, (lab, val) in enumerate(kp):
        x = 0.04 + (k % 3) * 0.105
        y = 0.60 - (k // 3) * 0.10
        fig.patches.append(plt.Rectangle((x, y), 0.098, 0.085, transform=fig.transFigure, color="#f3eeee", zorder=0))
        fig.text(x + 0.006, y + 0.047, val, fontsize=11.5, weight="bold", color=C1)
        fig.text(x + 0.006, y + 0.015, lab, fontsize=7, color=CG)
    # tips
    good, tips = [], []
    if sc.get("Constante snelheid", 0) >= 85: good.append("Very constant speed on the motorway (cruise control well used).")
    if sc.get("Anticiperen / remmen", 0) >= 85: good.append(f"Calm and anticipatory braking: max {r['g_max_brk']:.2f} g, {len(r['hard_brk'])}x above 0.3 g.")
    if sc.get("Motorvriendelijk", 0) >= 85: good.append(f"Engine-friendly: never above 3500 rpm, hardly any low-rev lugging ({r['lug_s']:.0f} s).")
    if r["cruise_s"] > 300: good.append(f"~{r['cruise_s']/60:.0f} min on cruise control (pedal off, engine delivers).")
    if r["coast_gear_s"] > 15: good.append(f"{r['coast_gear_s']:.0f} s engine-braked in gear with fuel cut.")
    ok_out = [x for x in ups if x["klasse"] == "soepel"]
    if ups and len(ok_out) >= len(ups) / 2: good.append(f"Engaging after upshift: {len(ok_out)} of {len(ups)}x smooth" + (", never hard." if not any(x["klasse"] == "hard" for x in ups) else "."))
    if dns and np.nanmedian([s["jerk"] for s in dns]) < J_OK: good.append("Downshifting goes smoothly: letting the clutch come up gently works.")
    hard = sorted([s for s in sh if s["klasse"] == "hard"], key=lambda s: -s["jerk"])
    hard_up = [s for s in ups if s["klasse_in"] in ("merkbaar", "hard")]
    if len(hard_up) >= 3:
        hg = [s["gas"] for s in hard_up]
        tips.append(f"{len(hard_up)} of {len(ups)}x upshift: jerk at throttle off/clutch in")
        tips.append(f"   (avg. {np.mean(hg):.0f} % throttle just before). Partly inherent to")
        tips.append("   brisk acceleration; releasing the throttle a moment earlier and more gently helps.")
    mk_out = [s for s in ups if s["klasse"] != "soepel"]
    if len(mk_out) >= 3:
        tips.append(f"{len(mk_out)} of {len(ups)}x noticeable at the engage itself:")
        tips.append("   let the clutch come up slightly more slowly at the very end.")
    for s in hard:
        if s["soort"] in ("uitrol", "wegrijden") and s["naar"] == 1 and s["v"] > 10:
            tips.append(f"At {s['t']/60:.0f} min 1st gear engaged at {s['v']:.0f} km/h: a real jolt.")
            tips.append("   Tip: when rolling below ~20 km/h, prefer the 2nd gear.")
            break
    if r["coast_neutral_s"] > 60:
        tips.append(f"{r['coast_neutral_s']/60:.1f} min coasting in neutral (>20 km/h).")
        tips.append("   Tip: coasting in gear costs 0 fuel and brakes with the engine.")
    if len(r["hard_acc"]) >= 3:
        tips.append(f"{len(r['hard_acc'])}x hard acceleration (>0.25 g, max {r['g_max_acc']:.2f} g).")
    if r["low_after"] >= 3:
        tips.append(f"{r['low_after']}x below 1200 rpm after upshift: shifted up a bit too early.")
    y = 0.42
    fig.text(0.04, y, "What goes well", fontsize=11, weight="bold", color="#2e8b57")
    for k, s in enumerate(good[:6]):
        fig.text(0.04, y - 0.035 - k * 0.029, "+ " + s, fontsize=8.8)
    fig.text(0.52, y, "What can improve", fontsize=11, weight="bold", color=C1)
    for k, s in enumerate(tips[:11]):
        fig.text(0.52, y - 0.035 - k * 0.029, ("- " if not s.startswith("   ") else "") + s, fontsize=8.8)
    fig.text(0.04, 0.03, "Scores are our own estimate from CMU data (no official norm). Jerk = lurch in m/s3: "
             f"<{J_OK} smooth, {J_OK}-{J_HARD} noticeable, >{J_HARD} hard. Shifts with the brake pedal do not count.", fontsize=7.5, color=CG)
    pdf.savefig(fig)
    plt.close(fig)

    # ===== R2: shift quality =====
    fig = plt.figure(figsize=A4)
    header(fig, "Shift quality - jerks and rpm",
           f"{len(sh)} shift moments from bcm.GearPosNotification; dot = jerk on engaging, cross = kink at throttle off/clutch in")
    ax = fig.add_axes([0.06, 0.52, 0.55, 0.33])
    ax.axhspan(0, J_OK, color="#dff0d8", alpha=.6)
    ax.axhspan(J_OK, J_HARD, color="#fcf3d6", alpha=.6)
    ax.axhspan(J_HARD, 12, color="#f6d6d6", alpha=.6)
    for kind, c in KIND_COL.items():
        ss = [s for s in sh if s["soort"] == kind]
        if ss:
            ax.scatter([s["t"] / 60 for s in ss], [s["jerk"] for s in ss], color=c, s=28, label=disp(kind), zorder=3,
                       edgecolor="white", lw=.5)
    xin = [s for s in sh if not np.isnan(s["j_in"])]
    ax.scatter([s["tz"] / 60 for s in xin], [s["j_in"] for s in xin], marker="x", s=14, color="#999999", lw=.8, zorder=2,
               label="throttle off / clutch in")
    for s in sorted(sh, key=lambda s: -s["jerk"])[:4]:
        ax.annotate(f"{s['van'] if s['soort']!='wegrijden' else 'N'}>{s['naar']}", (s["t"] / 60, s["jerk"]),
                    xytext=(4, 4), textcoords="offset points", fontsize=7.5)
    ax.set_ylim(0, max(J_HARD + 2, max(np.nanmax([s["jerk"], s["j_in"]]) for s in sh) + 1))
    ax.set_xlabel("minutes")
    ax.set_ylabel("jerk (m/s3)")
    ax.set_title("Every shift: how hard did it feel?")
    ax.legend(frameon=False, fontsize=7.5, loc="upper left", ncol=2)
    ax.text(1.0, J_OK / 2, disp("soepel"), transform=ax.get_yaxis_transform(), fontsize=7, color="#2e8b57", ha="right")
    ax.text(1.0, (J_OK + J_HARD) / 2, disp("merkbaar"), transform=ax.get_yaxis_transform(), fontsize=7, color=C3, ha="right")
    ax.text(1.0, J_HARD + 0.8, disp("hard"), transform=ax.get_yaxis_transform(), fontsize=7, color=C1, ha="right")
    # rpm before upshifting per pair
    ax = fig.add_axes([0.70, 0.52, 0.27, 0.33])
    pairs = sorted(set((s["van"], s["naar"]) for s in ups))
    for i_, p in enumerate(pairs):
        ys = [s["rpm_voor"] for s in ups if (s["van"], s["naar"]) == p]
        ys2 = [s["rpm_na"] for s in ups if (s["van"], s["naar"]) == p]
        ax.scatter([i_ - 0.12] * len(ys), ys, color=C1, s=16, zorder=3)
        ax.scatter([i_ + 0.12] * len(ys2), ys2, color=C2, s=16, zorder=3)
        for a_, b_ in zip(ys, ys2):
            ax.plot([i_ - 0.12, i_ + 0.12], [a_, b_], color="#cccccc", lw=.6)
    ax.axhspan(1800, 2600, color="#dff0d8", alpha=.6)
    ax.set_xticks(range(len(pairs)), [f"{a}>{b}" for a, b in pairs])
    ax.set_ylabel("rpm")
    ax.set_title("Upshift: rpm before (red) / after (blue)", fontsize=9.5)
    ax.text(0.02, 0.96, "green = frugal zone", transform=ax.transAxes, fontsize=7, color="#2e8b57", va="top")
    # table of the harshest
    top = sorted(sh, key=lambda s: -np.nanmax([s["jerk"], s["j_in"]]))[:7]
    rows = []
    for s in top:
        why = []
        if s["soort"] == "wegrijden":
            why.append(disp("wegrijden"))
        if s["soort"] == "uitrol":
            why.append(f"after {s['duur']:.0f} s coasting in neutral")
        if s["a_voor"] > 0.12 and s["soort"] == "op" and s["j_in"] >= s["jerk"]:
            why.append(f"throttle off/clutch in at {s['a_voor']:.2f} g accelerating")
        if s["rem"]:
            why.append("braking at the same time")
        if s["soort"] == "op" and s["gas"] > 60:
            why.append(f"{s['gas']:.0f} % throttle")
        if s["soort"] in ("uitrol", "terug") and s["naar"] == 1:
            why.append(f"1st at {s['v']:.0f} km/h: engine-braking jolt")
        if s["soort"] == "terug" and s["duur"] > 3:
            why.append(f"long disengaged ({s['duur']:.1f} s), rpm dropped to {s['rpm_voor']:.0f}")
        if s["duur"] < 0.9 and s["soort"] == "op":
            why.append(f"engaged quickly ({s['duur']:.1f} s)")
        if not np.isnan(s["tussengas"]) and s["tussengas"] < 40 and s["soort"] in ("terug", "uitrol") and s["rpm_doel"] > s["rpm_voor"] + 300:
            why.append(f"no rev-match ({s['rpm_voor']:.0f} -> {s['rpm_doel']:.0f} rpm)")
        rows.append([f"{s['t']/60:.1f}", ("N" if s["soort"] == "wegrijden" else str(s["van"])) + f" > {s['naar']}",
                     f"{s['v']:.0f}", f"{s['rpm_voor']:.0f} > {s['rpm_na']:.0f}", "-" if np.isnan(s["duur"]) else f"{s['duur']:.1f}",
                     ("-" if np.isnan(s["j_in"]) else f"{s['j_in']:.1f}") + f" / {s['jerk']:.1f}",
                     disp(_cls(np.nanmax([s["jerk"], s["j_in"]]))), "; ".join(why) or "-"])
    ax = fig.add_axes([0.04, 0.05, 0.92, 0.36])
    ax.axis("off")
    ax.set_title("The harshest moments", loc="left", fontsize=11, weight="bold")
    tb = ax.table(cellText=rows, colLabels=["min", "gear", "km/h", "rpm before > after", "dur s", "in / out", "verdict", "likely cause"],
                  loc="upper center", colWidths=[.06, .07, .06, .12, .07, .08, .08, .46], cellLoc="left")
    tb.auto_set_font_size(False)
    tb.set_fontsize(8)
    tb.scale(1, 1.45)
    for (rr, cc), cell in tb.get_celld().items():
        cell.set_edgecolor("#dddddd")
        if rr == 0:
            cell.set_facecolor(C1)
            cell.get_text().set_color("white")
            cell.get_text().set_weight("bold")
        elif cc == 6:
            cell.set_facecolor({"smooth": "#dff0d8", "noticeable": "#fcf3d6", "hard": "#f6d6d6"}[rows[rr - 1][6]])
    pdf.savefig(fig)
    plt.close(fig)

    # ===== R3: examples + rpm usage =====
    fig = plt.figure(figsize=A4)
    header(fig, "Zoomed in: harshest vs smoothest shift, and rpm usage",
           "Longitudinal acceleration (G), rpm and gear position around the shift moment; right: time per rpm band per gear")
    cand = [s for s in sh if s["soort"] in ("op", "terug")]
    ex = []
    if cand:
        cand = [s for s in cand if not s["rem"] and not np.isnan(s["duur"])] or cand
        tot_j = lambda s: np.nanmax([s["jerk"], s["j_in"]])
        ex = [("Harshest", max(cand, key=tot_j)), ("Smoothest", min(cand, key=tot_j))]
    ga, a_s, rg, gear = r["ga"], r["a_s"], r["rg"], r["gear"]
    for k, (ttl, s) in enumerate(ex):
        m = (ga >= s["tz"] - 3) & (ga <= s["t"] + 4)
        x = ga[m] - s["tz"]
        ax = fig.add_axes([0.06, 0.53 - k * 0.43, 0.42, 0.30])
        ax.plot(x, a_s[m] / 9.81, color=C1, lw=1.4, label="long. G")
        ax.axvspan(0, s["t"] - s["tz"], color="#eeeeee", label="clutch in / not in sync")
        ax.set_ylabel("g", color=C1)
        ax.set_xlabel("seconds relative to clutch in")
        ax2 = ax.twinx()
        ax2.plot(x, rg[m], color=C2, lw=1, label="rpm")
        ax2.set_ylabel("rpm", color=C2)
        ax2.spines["right"].set_visible(True)
        ax.set_title(f"{ttl}: {s['van']} > {s['naar']} at {s['v']:.0f} km/h, {s['t']/60:.1f} min - kink in {s['j_in']:.1f} / engaging {s['jerk']:.1f} m/s3",
                     fontsize=9.5, loc="left")
        ax.legend(frameon=False, fontsize=7, loc="lower left")
        ax.grid(alpha=.25)
    ax = fig.add_axes([0.60, 0.17, 0.36, 0.65])
    bands = r["bands"]
    lbl = ["<1300", "1300-1800", "1800-2500", "2500-3500", ">3500"]
    colsb = ["#bbbbbb", "#9ecae1", "#2e8b57", C3, C1]
    left = np.zeros(6)
    tots = np.array([r["band_t"][gg].sum() for gg in range(1, 7)])
    for b in range(5):
        vals = np.array([r["band_t"][gg][b] for gg in range(1, 7)]) / np.maximum(tots, 1e-9) * 100
        ax.barh([disp(f"{gg}e") for gg in range(1, 7)], vals, left=left, color=colsb[b], label=lbl[b])
        left += vals
    for i_, tot_ in enumerate(tots):
        ax.text(101, i_, f"{tot_/60:.1f} min" if tot_ >= 60 else f"{tot_:.0f} s", va="center", fontsize=8)
    ax.set_xlim(0, 118)
    ax.set_xlabel("% of the time in that gear")
    ax.legend(frameon=False, fontsize=7.5, title="rpm", title_fontsize=8, loc="upper center", ncol=5, bbox_to_anchor=(0.5, -0.09))
    ax.set_title("Rpm usage per gear")
    pdf.savefig(fig)
    plt.close(fig)
