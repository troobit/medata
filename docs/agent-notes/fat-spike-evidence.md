# Fat spike evidence survey (the "pizza effect")

**This document selects nothing.** It is an evidence survey assembled to feed the staged fat
programme in `specs/data/insulin-dosing` (design.md § "Fat: the staged plan", tasks 18–23). That
spec deliberately refuses to pick a fat rule until its own gates clear; nothing here overrides that,
and no number here is a recommendation. Every non-obvious claim carries a DOI verified against
Crossref or PubMed on 2026-08-14. Where a figure could not be verified from an accessible source,
the document says so instead of asserting it.

Scope: what the medreg dossier already establishes, what the primary literature says for each
candidate strategy, which strategies survive translation to a pen, and what would have to be
measured in this developer's own recorded data before a choice is possible.

---

## 1. What the medreg dossier already establishes

`~/repos/medreg/docs/research/carb-absorption.md` §3–4 is the existing foundation and is broadly
sound. It establishes:

- **The mechanism and the horizon.** High-fat/high-protein (HFHP) meals produce a delayed,
  prolonged, lower-and-later glucose rise: fat slows gastric emptying and then drives late
  hyperglycaemia via free-fatty-acid insulin resistance and hepatic glucose output; protein
  contributes 3–5 h out via gluconeogenesis. Effects are additive, horizon 6–8 h (§3, §3b).
- **The timing mismatch that makes this hard.** Rapid-acting insulin peaks ~60–90 min and is
  largely gone by 4–5 h; HFHP appearance runs 3–8 h (§4).
- **The over-fronting hazard.** Fat can *lower* glucose in the first 2–3 h, so putting all extra
  insulin up front risks an early low then a late high (§4). This is the single most load-bearing
  caution in the dossier and the primary literature confirms it (see §2 and §3 below).
- **Four candidate strategy families** (uplift, split, protein-only, FPU/Warsaw), which the medata
  design carries forward as `fat-uplift-v1`, `fat-split-v1`, `fat-protein-v1`, `fat-fpu-v1`.
- **The modelling hook.** Fat delay is representable by increasing the carb curve's peak time
  (`t_max,G`/`τ`) and scaling total appearance — no separate curve family (§2b, §4).
- **The honest caveat.** "These are population averages from small studies (many paediatric);
  individual variation is large — sources stress CGM-guided titration over fixed formulas" (§3).
  Everything in §2 below reinforces that sentence.

### Three corrections to carry back

1. **DOI 10.2337/dc16-0709 is Campbell, not Bell.** Crossref gives the authors as Campbell MD,
   Walker M, King D, Gonzalez JT, Allerton D, Stevenson EJ, Shaw JA, West DJ, *Diabetes Care*
   2016;39(9):e141–e142. medreg's §4 citation list item 15 ("Bell KJ et al. (secondary bolus at
   3 h)") and `specs/data/insulin-dosing/design.md`'s candidate table ("second-bolus RCT Bell 2016")
   both misattribute it. This matters beyond pedantry: it is the *only* MDI-specific trial behind
   `fat-split-v1`, and it comes from a different group with a different result profile than Bell's.
2. **The "+30–35%, 50% up-front + 50% extended over 2–2.5 h" rule attributed to Bell 2015 could not
   be verified.** The published abstract of Bell 2015 (DOI 10.2337/dc15-0100) states the opposite
   sort of conclusion: of ten dosing studies reviewed, "because of methodological differences and
   limitations in experimental design, study findings were inconsistent regarding optimal bolus
   delivery pattern." The full text is paywalled and could not be opened, so the numeric rule may
   come from its discussion or from a secondary source. Treat it as unverified. The same group's
   later *primary* trials give quite different numbers: +65% at 30/70 over 2.4 h (Bell 2016, DOI
   10.2337/dc15-2855) and +6%/+6%/+21% for 20/40/60 g fat (Bell 2020, DOI 10.2337/dc19-0687).
   Both `fat-uplift-v1` and `fat-split-v1` currently inherit their size from the unverified line.
3. **The 75 g protein threshold comes from a no-insulin study.** Paterson 2016 (DOI
   10.1111/dme.13011) gave whey protein drinks *without insulin*; ≥75 g was where an effect became
   significant. Paterson 2020 (DOI 10.1111/dme.14308) gave 50 g protein *with* 30 g carbohydrate and
   found +30% insulin was required. The medata gate "protein ≥ 75 g alone"
   (`design.md` candidate table, Req 8.6) is therefore probably set too high for a meal that also
   contains carbohydrate.

The dossier does not cover: Bell 2016's model-derived dose, Bell 2020's fat dose-response, the
Paterson 2020 protein dose-response with its hypoglycaemia ceiling, the MDI-specific trials
(Campbell 2016, Smith 2021, Frohock 2022, Hegab 2023), the negative FPU evidence (Kordonouri 2012,
Cai 2023, Atik Altınok 2023, Dymińska 2025), or the individualised-learning work (Jafar 2024).

---

## 2. The literature by strategy

Every trial below is a within-subject or crossover design comparing meals of **identical
carbohydrate content** — that control is what makes the fat/protein effect attributable, and it is
the thing free-living data does not have.

### 2a. Proportional uplift, delivered entirely up front (`fat-uplift-v1`)

| Study | Population | Prescription | Magnitude | Limitation |
|---|---|---|---|---|
| Wolpert 2013, DOI 10.2337/dc12-0092 | **n = 7** adults, age 55 ± 12, A1c 7.2 ± 0.8%, closed-loop | none — measures the requirement | HF (60 g fat) dinner required 12.6 ± 1.9 U vs LF (10 g fat) 9.0 ± 1.3 U, P = 0.01 (**≈ +42%**); carb ratio 9 ± 2 vs 13 ± 3 g/U; still more hyperglycaemia despite the extra insulin | n = 7. Closed-loop delivered the insulin *reactively over 18 h* — this is not an up-front bolus and cannot be given as one. "Marked interindividual differences… percent increase significantly correlated with daily insulin requirement; R² = 0.64" |
| Bell 2020, DOI 10.2337/dc19-0687 | adults, pump, 9–12 clinic visits each | dual-wave, insulin sized by model-predictive bolus | 45 g carb + 20 g fat → **+6%**, 74/26 over 73 min; + 40 g fat → **+6%**, 63/37 over 75 min; + 60 g fat → **+21%**, 49/51 over 105 min. Fat *type* made no significant difference to 5-h iAUC | Dose-dependent **reduction** in 0–2 h iAUC (P = 0.008) and **increase** in 2–5 h iAUC (P = 0.004) — the up-front hazard, measured. Pump-delivered dual-wave throughout |
| Smith 2021, DOI 10.1111/dme.14512 | **n = 24** children and adults, **MDI (≥ 4 injections/day)** | 125% of ICR as a single pre-meal aspart dose | 5-h iAUC 341 [169, 512] vs 620 [451, 788] for 100% (p = 0.016); one hypoglycaemic episode, in the regular-insulin arm | Breakfast only: 30 g carb, 40 g fat, 50 g protein — protein-heavy and carb-light. Single meal, single day per arm |
| Campbell 2016, DOI 10.2337/dc16-0709 | **n = 10 males**, age 26 ± 4, **MDI** (aspart + glargine/detemir) | 130% of the carb dose, all at meal time | **60% of participants went hypoglycaemic (< 3.9 mmol/L)** in this arm; no hypoglycaemia in any other arm | Meal was 68 g carb / 26 g protein / 55 g fat — carb-heavy. Authors state plainly: "increasing meal-time insulin dose alone is not an effective strategy, and is an approach that may increase the risk of early post-prandial hypoglycemia" |

**The two MDI trials disagree.** Smith 2021 found +25% up front was the best of four strategies with
essentially no hypoglycaemia; Campbell 2016 found +30% up front put 6 of 10 participants low. The
meals differed in both carbohydrate (30 g vs 68 g) and macronutrient balance (protein-dominant vs
fat-dominant), and neither trial can separate which difference is responsible. Nothing in the
literature resolves this.

### 2b. Split or extended delivery (`fat-split-v1`)

Pump-delivered (dual-wave / combination bolus):

- **Bell 2016, DOI 10.2337/dc15-2855** — n = 10 adults, pump. Same insulin dose, HFHP vs LFLP with
  identical carbohydrate: HFHP more than **doubled** glucose iAUC. Adaptive model-predictive
  iteration until target control was reached required **+65% insulin, range 17–124%**, delivered
  **30% / 70% over 2.4 h**. The 17–124% range across ten people is the most direct published
  argument that a population constant cannot be adopted for an individual.
- **Lopez 2017, DOI 10.1111/dme.13392** — n = 19, mean age 12.9 y, pump. Six arms comparing splits
  from 70/30 to 30/70 over 2 h. Standard bolus, 70/30 and 60/40 controlled the first 120 min;
  30/70 gave lower AUC than standard at 240–300 min (P = 0.004). Conclusion: **≥ 60% up front** to
  hold the early rise, up to 70% extended to hold the late one — i.e. the two windows want opposite
  things and the split is the compromise.
- **Paterson 2020, DOI 10.1111/dme.14308** — see §2c; delivered as a combination bolus, 65% up
  front, remainder over 3 h.

Injection-delivered (the only ones that answer the pen question):

- **Campbell 2016, DOI 10.2337/dc16-0709** — n = 10 males, MDI. Carb dose at the meal **plus 30% at
  +3 h**: postprandial glucose excursions (time course and AUC) were "similar between Low-Fat100%
  and High-FatSplit, despite the additional 50 g of fat consumed", with no hypoglycaemia. This is
  the positive MDI split result. n = 10, all male, single meal, 6-h window, finger-stick/venous
  sampling.
- **Smith 2021, DOI 10.1111/dme.14512** — n = 24, MDI. A split arm (100% pre-meal + 25% at +1 h)
  gave 5-h iAUC 434 [259, 608] against 341 [169, 512] for the single 125% dose. The paper's
  conclusion: "There was no additional glycaemic benefit from giving insulin in a split dose."
- **Frohock 2022, DOI 10.1111/pedi.13372** — n = 27, median age 13 y, MDI, randomised three-period
  crossover. Additional fat/protein insulin at **+0, +1 or +2 h** produced no difference in mean
  excursion (1.9 / 1.2 / 2.5 mmol/L, p = 0.5), peak glucose (p = 0.9) or time to peak (p = 0.8).
  Mild hypoglycaemia was **common in every arm (55%)**. Conclusion: "no benefit in giving additional
  insulin as a split dose for HFHP meals in children using MDI… Future studies would benefit from
  refinement of the insulin dose algorithm."
- **Hegab 2023, DOI 10.1155/2023/7467652** — n = 43, median age 12 y, MDI on degludec. Pizza,
  40 g carb / 15 g fat / 20 g protein. 130% ICR split 60% pre-meal + 40% at **+30 min** using
  **regular (not rapid-acting) insulin** gave the lowest 0–6 h AUC vs 100% pre-meal alone (p = 0.01)
  and the lowest 3–6 h AUC vs both other arms (p = 0.008, p = 0.02). Hypoglycaemia < 70 mg/dL:
  27.9% / 27.9% / 39.5%, not significantly different. Finger-stick only, 6-h window.

**Net:** four MDI trials, four different timings (+30 min, +1 h, +2 h, +3 h), two positive for
splitting and two null. The one factor that separates the two positive results from the two null
ones is not identifiable from the published designs.

### 2c. Protein-specific contribution (`fat-protein-v1`)

- **Smart 2013, DOI 10.2337/dc13-1195** — n = 33, aged 8–17, intensive insulin therapy, four
  breakfasts of identical carbohydrate. Low fat 4 g vs high 35 g; low protein 5 g vs high 40 g.
  Excursions were greater from **180 min** after high protein (2.4 mmol/L [1.1–3.7] vs 0.5
  [−0.8–1.8], P = 0.02) and from **210 min** after high fat (1.8 [0.3–3.2] vs −0.5 [−1.9–0.8],
  P = 0.01); HF/HP highest from 180–300 min; effects additive. Also: **protein reduced hypoglycaemia
  risk** (OR 0.16 [0.06–0.41], P < 0.001) — protein is not simply "more insulin needed".
- **Paterson 2016, DOI 10.1111/dme.13011** — n = 27, aged 7–40. Whey isolate at 0, 12.5, 25, 50, 75,
  100 g, **without insulin**. 12.5 g and 50 g: no significant excursion. 75 g and 100 g: *lower*
  excursion at 60–120 min, *higher* at 180–300 min. Note the biphasic shape appears for protein too.
- **Paterson 2020, DOI 10.1111/dme.14308** — n = 26, aged 8–40, pump. 50 g protein / 30 g carb /
  < 1 g fat drink, doses at 100/115/130/145/160% of standard, combination bolus (65% up front,
  rest over 3 h). **+30% was optimal**: 4.69 (2.42) mmol/L lower excursion than control, back to
  baseline by 4 h (P < 0.001). Above that the trial found a hard ceiling: hypoglycaemia OR 25.4
  [5.5–206] at 145% and OR 103 [19.2–993] at 160%; **58% and 81% of participants went low**
  respectively; **zero hypoglycaemic events at 130%**. This is the cleanest published dose-response
  with a safety ceiling anywhere in this literature, and the ceiling is only 15 percentage points
  above the optimum.
- **Piechowiak 2017, DOI 10.1111/pedi.12500** — n = 58, age 14.7 ± 2.2, pump, high-protein
  **low-fat** meal. Dual-wave with extra insulin lowered 180-min glucose (130.0 vs 162 mg/dL,
  P = .004) with no difference at 60 or 120 min and no increase in hypoglycaemia. Isolates protein
  from fat and confirms the effect lands late.

### 2d. Fat-protein units / Warsaw method (`fat-fpu-v1`)

The rule: `FPU = (fat_g × 9 + protein_g × 4) / 100`; insulin for 1 FPU ≈ insulin for 10 g
carbohydrate, delivered as an **extended/square-wave** bolus with duration scaled to FPU count.

- **Pankowska 2012, DOI 10.1089/dia.2011.0083** — the source study. 26 screened, **24 randomised**,
  pump, **parallel groups (not crossover)**: Group A dual-wave `nCU × ICR + nFPU × ICR` over 6 h,
  Group B carbohydrate only. Pizza dinner, 45 g carb / 180 kcal plus 400 kcal from fat and protein.
  **The published abstract's result sentence is internally ambiguous** — it reads "In Group A the
  significant glucose increment occurred at 120-360 min, with its maximum at 240 min: 60.2 versus
  -3.0 mg/dL (P=0.04)", which contradicts the stated conclusion that the dual-wave FPU bolus is
  effective. The full text is paywalled and could not be opened to resolve which group the 60.2
  mg/dL belongs to. The most-cited justification for the FPU method rests on a 24-participant
  parallel-group study whose abstract cannot be read consistently.
- **Kordonouri 2012, DOI 10.1111/j.1399-5448.2012.00880.x** — n = 42, aged 6–21, pump,
  pizza-salami test meal (50% carb / 34% fat / 16% protein), four test days. FPU counting genuinely
  lowered glucose: 6-h AUC 805 ± 261 vs 926 ± 285 and mean 137.8 ± 46.2 vs 160.5 ± 51.9 mg/dL, both
  p < 0.001, independent of bolus type. **And**: postprandial hypoglycaemia (< 70 mg/dL) occurred in
  **35.7% with FPU counting vs 9.5% with carbohydrate counting, p < 0.001** (no severe events).
- **Cai 2023, DOI 10.1186/s12986-023-00757-w** — n = 30 adults aged 18–45, randomised crossover,
  four isocaloric meals. Modified FPU lowered late postprandial mean glucose on high protein-fat
  meals (p = 0.026), but produced **significantly more hypoglycaemia on the normal protein-fat
  meal** (p = 0.042). A rule with no materiality gate over-doses ordinary food.
- **Atik Altınok 2023, DOI 10.4274/jcrpe.galenos.2022.2022-8-10** — n = 20 adolescents, pump.
  Standard Pankowska algorithm: **50% experienced hypoglycaemia**, median 6.25 h. Redefining 1 FPU
  as **150 kcal instead of 100 kcal** (dropping the meal's FPU count from 7.7 to 5) gave 0%
  hypoglycaemia over 12 h while still delivering +64% insulin. The constant in the formula is not
  established.
- **Dymińska 2025, DOI 10.3390/nu17203287** — n = 58 adolescents, pump, most recent trial found.
  Pankowska equation (FPU × ICR over 4 h) vs Sieradzki equation (30% × carb units × ICR over 4 h):
  the *simpler carbohydrate-proportional* rule gave longer time in tight range (82.51% vs 70.49%,
  p = 0.0139), lower glucose at 60 min, and fewer hypoglycaemic events at 180 and 300 min.

**Net:** the FPU/Warsaw method reliably lowers late glucose and reliably raises hypoglycaemia. Four
independent groups have now either reduced its dose, gated it, or replaced it with a
carbohydrate-proportional rule.

### 2e. Individualised learning rather than a fixed rule

- **Jafar 2024, DOI 10.1038/s41467-024-50764-5** — n = 15 adults **on MDI**, 16-week single-arm
  feasibility trial (NCT05041621). A reinforcement-learning decision-support system personalised the
  insulin adjustment for high-fat meals and post-meal aerobic exercise. Postprandial iAUC for
  high-fat meals improved from 378 ± 222 to 38 ± 223 mmol/L/min (p = 0.03) and time below
  3.9 mmol/L fell from 5.3 ± 1.6% to 1.8 ± 1.5% (p = 0.003). Single-arm, n = 15, feasibility only;
  authors state "Randomized controlled trials are warranted."

This is the closest published analogue to what the medata/medreg pairing is set up to do: learn the
individual's own adjustment from their own recorded data rather than adopt a population constant. It
also demonstrates the confound that matters most for free-living data — post-meal exercise moves
glucose in the *opposite* direction by a comparable magnitude, and the same system had to model both.

### 2f. What the guidelines say

- **ADA Standards of Care 2026** grade education on the glycaemic impact of carbohydrate as **A** and
  fat and protein as **B**, and state that further prandial adjustment for protein and fat "may be
  more feasible for individuals using CSII than for those using multiple daily injections."
- **ISPAD 2022 nutritional management** (Annan SF et al., *Pediatr Diabetes* 2022;23(8):1297–1321,
  DOI 10.1111/pedi.13429) is the paediatric consensus document. Its recommendation text could not be
  fetched (publisher returned 403), so nothing is quoted from it here.
- **Smart, King & Lopez, "Insulin Dosing for Fat and Protein: Is it Time?"** *Diabetes Care*
  2020;43(1):13–15, DOI 10.2337/dci19-0039 — the commentary accompanying Bell 2020. Citation
  verified; content not retrieved.

### 2g. Population sizes, in one place

No trial in this literature exceeds ~60 participants. Largest: n = 58 (Piechowiak 2017, Dymińska
2025). The strategies medata's design table cites rest on n = 7 (Wolpert), n = 10 (Bell 2016;
Campbell 2016), n = 24 (Pankowska), n = 26–27 (Paterson 2020; Paterson 2016; Frohock). The majority
are **paediatric and pump-based**. An adult on injections is directly represented by two studies:
Campbell 2016 (n = 10, all male) and Jafar 2024 (n = 15, single-arm) — and they take opposite
approaches. There is no long-term outcome trial for any of these strategies.

---

## 3. The pen constraint: which strategies survive translation

The literature is overwhelmingly pump literature. A dual-wave or square-wave bolus is a *continuous
delivery profile*; the only thing a pen can express is a sequence of discrete doses, and the app's
only expressible output is "X U now, consider Y U at +T minutes". Assessed against that:

**`fat-uplift-v1` — survives mechanically; unresolved empirically, and its failure mode is the
dangerous one.** One extra number on the meal-time dose is trivially deliverable by pen and is the
only strategy needing no second action. But the two MDI trials disagree (Smith 2021 positive at
+25%; Campbell 2016 put 6 of 10 low at +30%), and Bell 2020 measured the mechanism: the same fat that
raises late glucose *lowers* early glucose in a dose-dependent way, so an up-front uplift is
strictly the wrong shape and only works when the size stays small enough that the early trough
tolerates it. Paterson 2020's ceiling — optimum at +30%, 58% hypoglycaemia at +45% — shows how
narrow that window is.

**`fat-split-v1` — survives, and is the only candidate designed for injections.** "X U now, Y U at
+T" is precisely its native form; Campbell 2016 is a direct pen-delivered demonstration on a
68 g-carb / 55 g-fat meal. Three qualifications: (a) two of four MDI trials found no benefit over a
single dose (Smith 2021, Frohock 2022); (b) the optimum T is unknown — the four trials used +30 min,
+1 h, +2 h and +3 h, and Frohock found +0/+1/+2 h indistinguishable; (c) it is the only candidate
whose effectiveness depends on a *user action hours later*, which no trial measured under
free-living conditions and which the app has no surface to prompt (the spec already blocks F3 on
exactly this). Its second dose is also the one place where a stale or absent glucose reading is most
consequential, since the dose lands while the first is still active.

**`fat-protein-v1` — survives as an uplift, but not with its published delivery or its threshold.**
Paterson 2020's +30% was delivered as a combination bolus (65% up front, remainder extended over
3 h), so its magnitude is not directly transferable to one pen dose; the +30% figure is attached to
a delivery profile a pen cannot produce. Separately, its trigger in the medata design (protein
≥ 75 g) comes from a no-insulin drink study; the with-insulin trial that produced +30% used 50 g of
protein. If this candidate is ever implemented, both the size and the threshold need restating.

**`fat-fpu-v1` (Warsaw) — does not survive.** Its defining mechanism *is* the extended/square-wave
bolus with a duration scaled to FPU count (3 h at 1 FPU out to 6–8 h for large loads). That is
exactly and only what a pen cannot do. Collapsing it into one deferred injection is no longer the
Warsaw method and inherits none of its evidence — every FPU trial cited above (Pankowska,
Kordonouri, Cai, Atik Altınok, Dymińska) delivered it through a pump. Its evidence is also the
weakest of the four families: the source study is a 24-participant parallel-group trial with an
abstract that cannot be read consistently, and four subsequent groups have had to shrink its
constant, gate it, or replace it because of hypoglycaemia. Recommendation for a later spec decision
(not taken here): either drop `fat-fpu-v1` from the candidate table, or restate it honestly as
`fat-uplift-v1` with an FPU-scaled size — because that is what it becomes on a pen.

**FPU as a covariate is unaffected.** Everything above concerns FPU as a *dosing rule*. The `fpu`
column recorded at F0 (Req 8.1) is a perfectly serviceable scalar for stratifying meals and testing
whether a late rise exists, and none of the negative FPU-dosing evidence argues against recording it.

**One engineering point the literature does not raise: pen resolution is comparable to the effect
size.** Bell 2020's optimal adjustment for 20–40 g of fat was **+6%**. On an 8 U carbohydrate dose
that is 0.48 U — at or below the smallest dosable increment on a half-unit pen, and entirely below a
1 U pen. For moderate fat loads, several of these rules round to zero on the device that has to
deliver them. Any rule adopted later should be checked against the recorded `dosable increment`
column before its size is argued about.

---

## 4. What would have to be measured in this developer's own data

The spec already gates the fat programme on three things (tasks 18, 19, 20; Req 8.8). The literature
sharpens what each of those measurements has to contain.

1. **Does a late rise exist for this user, and how big is it?** Every trial above defines the effect
   as incremental AUC in a late window against a **matched low-fat meal at identical
   carbohydrate**. Free-living data has no matched control, so the comparison has to be constructed
   statistically — late-window excursion regressed on `fat_g`/`protein_g`/`fpu` with carbohydrate,
   dose and pre-meal glucose as covariates. That is medreg's job, off-device. Window choice should
   follow the literature: 0–2 h early, 2–5 h or 3–5 h late (Bell 2020, Smart 2013, Paterson 2016),
   with a 6-h tail for the largest loads (Kordonouri, Pankowska, Campbell).
2. **Which covariate carries the signal — fat, protein, or FPU?** They are collinear in real meals,
   and FPU deliberately destroys the distinction by summing them. The literature says they are not
   interchangeable: protein acts from ~180 min and fat from ~210 min (Smart 2013), protein reduces
   hypoglycaemia risk (Smart 2013) while fat increases late requirement, and their optimal
   adjustments differ (+30% for 50 g protein, +21% for 60 g fat). Test the three recorded columns
   separately before adopting `fpu` as the gate variable, even though `fpu` is the gate the design
   currently names.
3. **Is the fat estimate accurate enough for any rule to be a function of it?** This is task 19, and
   the literature sets the required precision: Bell 2020 gives +6% at 20–40 g fat and +21% at 60 g.
   An estimate error of ±20 g fat spans that entire dose-response. The right way to state task 19's
   pass criterion is therefore not "close enough" but "smaller than the fat interval over which the
   candidate rule's size changes" — which for the only measured dose-response is ~20 g.
4. **Base rate: how often does a meal qualify?** Task 16's FPU distribution. If the knee of this
   user's own distribution is crossed twice a year, no rule earns the risk surface it adds. This is
   already Req 8.7's framing (threshold measured, not cited) and it should be answered before any
   implementation, not after.
5. **The early window must be scored alongside the late one.** Campbell 2016 (60% hypoglycaemic at
   +30% up front), Paterson 2020 (58% at +45%), Kordonouri 2012 (35.7% vs 9.5%), Cai 2023 and Atik
   Altınok 2023 (50%) all fail in the same direction: the rule fixes the late high and creates an
   early low. A scorer that only measures the 3–6 h window will rank a harmful rule as an
   improvement. Any outcome measure specified later needs both windows and needs the early one to be
   a veto, not a term in an average.
6. **Confounders free-living data has and the trials did not.** Post-meal exercise moves glucose the
   opposite way by a comparable magnitude and had to be modelled jointly in the only MDI learning
   trial (Jafar 2024) — the activity-events work is therefore a prerequisite for a clean fat signal,
   not an unrelated feature. Alcohol likewise. A further bolus inside the window is already in
   task 16. **Basal adequacy is the confound most likely to fake the effect**: an underdosed basal
   produces a slow rise over 3–8 h that is indistinguishable from a fat effect on a single meal. The
   only within-user control available is whether the same late rise appears after *low*-fat meals;
   task 20's analysis should compute that comparison explicitly rather than looking only at
   high-FPU meals.
7. **If a split is ever adopted, record when the second dose actually happened and whether it
   happened at all.** Req 8.9 already requires the elapsed time. Frohock 2022 found +0/+1/+2 h
   indistinguishable in a controlled setting, which means free-living timing variance will exceed
   the effect being estimated unless it is recorded per dose. Adherence to the second injection is
   the failure mode that no published trial measures and that this user's own ledger can.
8. **Pre-meal glucose and its age.** Already recorded (Req 7.2). It matters here specifically because
   the early-window hypoglycaemia risk that dominates §5 above is conditional on starting glucose,
   and every trial started participants in a controlled range.

An honest reading of §2 supports the spec's stated willingness to stop: with n = 7 to n = 58 trials
disagreeing among themselves, effect sizes spanning 17–124% within a single ten-person study, and two
of four MDI trials finding no benefit from the only pen-native strategy, "no late rise is visible in
this user's data, so the fat programme stops here" is a well-supported outcome and not a failure.

---

## 5. Verified citations

All DOIs below were resolved against Crossref and the abstracts read via PubMed unless noted.

| Ref | DOI |
|---|---|
| Wolpert HA, Atakov-Castillo A, Smith SA, Steil GM. *Diabetes Care* 2013;36(4):810–816 | 10.2337/dc12-0092 |
| Smart CEM, Evans M, O'Connell SM, et al. *Diabetes Care* 2013;36(12):3897–3902 | 10.2337/dc13-1195 |
| Bell KJ, Smart CE, Steil GM, Brand-Miller JC, King B, Wolpert HA. *Diabetes Care* 2015;38(6):1008–1015 | 10.2337/dc15-0100 |
| Bell KJ, Toschi E, Steil GM, Wolpert HA. *Diabetes Care* 2016;39(9):1631–1634 | 10.2337/dc15-2855 |
| Bell KJ, Fio CZ, Twigg S, et al. *Diabetes Care* 2020;43(1):59–66 | 10.2337/dc19-0687 |
| Paterson MA, Smart CEM, Lopez PE, et al. *Diabet Med* 2016;33(5):592–598 | 10.1111/dme.13011 |
| Paterson MA, Smart CEM, Howley P, et al. *Diabet Med* 2020;37(7):1185–1191 | 10.1111/dme.14308 |
| Lopez PE, Smart CE, McElduff P, et al. *Diabet Med* 2017;34(10):1380–1384 | 10.1111/dme.13392 |
| Campbell MD, Walker M, King D, et al. *Diabetes Care* 2016;39(9):e141–e142 | 10.2337/dc16-0709 |
| Campbell MD, Walker M, Ajjan RA, et al. *Diab Vasc Dis Res* 2017;14(4):336–344 | 10.1177/1479164117698918 |
| Smith TA, Smart CE, Howley PP, Lopez PE, King BR. *Diabet Med* 2021;38(7):e14512 | 10.1111/dme.14512 |
| Frohock AM, Oke J, Yaliwal C, Edge J, Besser REJ. *Pediatr Diabetes* 2022;23(6):742–748 | 10.1111/pedi.13372 |
| Hegab AM, Hasaballah SE, Mohamed MM. *Pediatr Diabetes* 2023;2023:7467652 | 10.1155/2023/7467652 |
| Pańkowska E, Błazik M, Groele L. *Diabetes Technol Ther* 2012;14(1):16–22 | 10.1089/dia.2011.0083 |
| Kordonouri O, Hartmann R, Remus K, et al. *Pediatr Diabetes* 2012;13(7):540–544 | 10.1111/j.1399-5448.2012.00880.x |
| Piechowiak K, Dżygało K, Szypowska A. *Pediatr Diabetes* 2017;18(8):861–868 | 10.1111/pedi.12500 |
| Cai Y, Li M, Zhang L, Zhang J, Su H. *Nutr Metab* 2023;20(1):43 | 10.1186/s12986-023-00757-w |
| Atik Altınok Y, Demir G, Çetin H, et al. *J Clin Res Pediatr Endocrinol* 2023;15(2):138–144 | 10.4274/jcrpe.galenos.2022.2022-8-10 |
| Dymińska M, Kowalczyk-Korcz E, Piechowiak K, Szypowska A. *Nutrients* 2025;17(20):3287 | 10.3390/nu17203287 |
| Jafar A, Kobayati A, Tsoukas MA, Haidar A. *Nat Commun* 2024;15:6585 | 10.1038/s41467-024-50764-5 |
| Smart CEM, King BR, Lopez PE. *Diabetes Care* 2020;43(1):13–15 (commentary) | 10.2337/dci19-0039 |
| Annan SF, Higgins LA, Jelleryd E, et al. ISPAD 2022 nutritional management. *Pediatr Diabetes* 2022;23(8):1297–1321 | 10.1111/pedi.13429 |

## 6. What could not be verified

- **Bell 2015 full text** (paywalled). The "+30–35% of the carb dose, 50% up front + 50% extended
  over 2–2.5 h" rule attributed to it in medreg §3d and in medata's candidate table does not appear
  in its abstract, and its abstract instead reports that findings on optimal bolus delivery pattern
  were inconsistent. Treat the figures as unverified until someone opens the paper.
- **Pankowska 2012 full text** (paywalled). The abstract's results sentence cannot be reconciled with
  its conclusion; which group the +60.2 mg/dL increment belongs to is unresolved here.
- **ISPAD 2022 nutritional management recommendations** — publisher returned HTTP 403; no
  recommendation text or evidence grade is quoted from it above.
- **Smart/King/Lopez 2020 commentary** — citation verified via Crossref, content not retrieved.
- **ADA Standards of Care 2026** grades (A for carbohydrate, B for fat and protein) and the
  CSII-vs-MDI feasibility sentence come from search-result summaries of the Standards, not from a
  direct fetch of the Diabetes Care article; verify against the source before quoting them anywhere
  that matters.
- **Hovorka 2004 and Dalla Man 2007 parameter values** — unchanged from medreg's own caveat; not
  re-checked here, they are outside this survey's scope.
