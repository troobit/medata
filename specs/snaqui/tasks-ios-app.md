---
references:
    - prd.md
---
# SNAQ-inspired UI uplift — iOS app

## Graph corrected totals

- [x] 1. TrendsModel carb bars use corrected display totals (day + week/month aggregates) — PRD Req 3 <!-- id:z1bc7x1 -->

## Portion adjustment

- [x] 2. Portion control on ResultView: N-of-M fractions + multiples, live scaled preview, full-plate line, default writes nothing — PRD Req 1 <!-- id:z1bc7wy -->

- [x] 3. Persist applied portion as appended PbUserCorrection (scaled total + per-class + portion note); original record untouched — PRD Req 2 <!-- id:z1bc7wz -->
  - Blocked-by: z1bc7wy (Portion control on ResultView: N-of-M fractions + multiples, live scaled preview, full-plate line, default writes nothing — PRD Req 1)

- [x] 4. History re-entry seeds portion from last portion correction; re-adjust (incl. back to full plate) appends further correction — PRD Req 2 <!-- id:z1bc7x0 -->
  - Blocked-by: z1bc7wz (Persist applied portion as appended PbUserCorrection scaled total + per-class + portion note; original record untouched — PRD Req 2)

## Page chrome

- [x] 5. Remove navigation titles from TrendsView, RecordsView, IntakeView, SettingsView, MealOverviewView, ManualCorrectionView, SegmentationReviewView; content reclaims the band — PRD Req 4 <!-- id:z1bc7x2 -->

- [ ] 6. Graph metric-chip row and result-screen surfaces render without ellipsis truncation in portrait; frontend-design uplift pass — PRD Req 5/6 <!-- id:z1bc7x3 -->

## Gates

- [ ] 7. Quality gates: make build, make test (report both totals), make spell; simulator app build of MeData.xcodeproj <!-- id:z1bc7x4 -->
  - Blocked-by: z1bc7x1 (TrendsModel carb bars use corrected display totals day + week/month aggregates — PRD Req 3), z1bc7wy (Portion control on ResultView: N-of-M fractions + multiples, live scaled preview, full-plate line, default writes nothing — PRD Req 1), z1bc7wz (Persist applied portion as appended PbUserCorrection scaled total + per-class + portion note; original record untouched — PRD Req 2), z1bc7x0 (History re-entry seeds portion from last portion correction; re-adjust incl. back to full plate appends further correction — PRD Req 2), z1bc7x2 (Remove navigation titles from TrendsView, RecordsView, IntakeView, SettingsView, MealOverviewView, ManualCorrectionView, SegmentationReviewView; content reclaims the band — PRD Req 4), z1bc7x3 (Graph metric-chip row and result-screen surfaces render without ellipsis truncation in portrait; frontend-design uplift pass — PRD Req 5/6)

- [ ] 8. STOP — on-device looks-right pass on iPhone 16 Pro (portion ergonomics, no portrait truncation, reclaimed space) — user verification <!-- id:z1bc7x5 -->
  - Blocked-by: z1bc7x4 (Quality gates: make build, make test report both totals, make spell; simulator app build of MeData.xcodeproj)
