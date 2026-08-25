---
references:
    - specs/ui/unified-dark-theme/requirements.md
    - specs/ui/unified-dark-theme/design.md
    - specs/ui/unified-dark-theme/decision_log.md
---
# Unified Dark Theme

- [x] 1. Force dark: UIUserInterfaceStyle in MeData/Info.plist, Colors.swift comment amendment <!-- id:wenwhit -->
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5)

- [x] 2. Reconcile design-system/MASTER.md — style-table scope, grouped block annotation, colour block level with Colors.swift <!-- id:wenwhiu -->
  - Blocked-by: wenwhit (Force dark: UIUserInterfaceStyle in MeData/Info.plist, Colors.swift comment amendment)
  - Requirements: [3.1](requirements.md#3.1), [3.4](requirements.md#3.4)

- [x] 3. Page docs — amend meal-overview.md and data.md in place; author records.md <!-- id:wenwhiv -->
  - Blocked-by: wenwhit (Force dark: UIUserInterfaceStyle in MeData/Info.plist, Colors.swift comment amendment)
  - Requirements: [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 4. make build-app and make spell <!-- id:wenwhiw -->
  - Blocked-by: wenwhit (Force dark: UIUserInterfaceStyle in MeData/Info.plist, Colors.swift comment amendment), wenwhiu (Reconcile design-system/MASTER.md — style-table scope, grouped block annotation, colour block level with Colors.swift), wenwhiv (Page docs — amend meal-overview.md and data.md in place; author records.md)
  - Requirements: [1.1](requirements.md#1.1)

- [ ] 5. STOP — device look on the iPhone 16 Pro against the acceptance band <!-- id:wenwhix -->
  - Blocked-by: wenwhiw (make build-app and make spell)
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2)
