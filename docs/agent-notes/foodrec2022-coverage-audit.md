# Food Recognition 2022 → 36-channel coverage audit

Generated 2026-07-26 by the myfoodrepo-bridge dataset-bridge context
(task 2, amended by MD-30) from `class_mapping_foodrec2022_v1.json`
applied to the dataset's own `annotations.json`. Counts are images
containing at least one annotation routed to the channel.

## train (public_training_set_release_2.0: 39962 images, 76491 annotations)

| channel | images | annotations |
|---------|--------|-------------|
| white_rice | 1156 | 1171 |
| brown_rice | 131 | 132 |
| pasta | 1821 | 1852 |
| bread_white | 3184 | 3333 |
| bread_wholemeal | 2547 | 2666 |
| potato_boiled | 775 | 810 |
| potato_mashed | 150 | 151 |
| chips_fries | 512 | 517 |
| chicken | 788 | 805 |
| beef | 657 | 678 |
| pork | 1885 | 2078 |
| fish_white | 960 | 988 |
| egg | 1257 | 1319 |
| cheese | 3423 | 3886 |
| salad_leaves | 3274 | 3387 |
| broccoli | 421 | 431 |
| carrot | 1564 | 1587 |
| peas | 431 | 435 |
| beans_baked | 0 | 0 |
| lentils | 464 | 494 |
| apple | 892 | 972 |
| banana | 654 | 736 |
| tomato | 1952 | 2003 |
| mixed_vegetables | 5620 | 7116 |
| cereal | 592 | 642 |
| water | 3314 | 5880 |
| coffee | 2741 | 3666 |
| tea | 1310 | 1577 |
| milk | 198 | 201 |
| fruit_juice | 380 | 415 |
| soup | 508 | 527 |
| beer | 247 | 285 |
| wine | 1308 | 1528 |
| unknown_food | 13285 | 16636 |
| unsupported_liquid | 667 | 726 |
| dropped | 5724 | 6861 |

## validation (public_validation_set_2.0: 1000 images, 1830 annotations)

| channel | images | annotations |
|---------|--------|-------------|
| white_rice | 27 | 27 |
| brown_rice | 3 | 3 |
| pasta | 42 | 42 |
| bread_white | 89 | 89 |
| bread_wholemeal | 75 | 77 |
| potato_boiled | 15 | 15 |
| potato_mashed | 4 | 4 |
| chips_fries | 14 | 14 |
| chicken | 14 | 14 |
| beef | 18 | 18 |
| pork | 44 | 47 |
| fish_white | 24 | 25 |
| egg | 27 | 28 |
| cheese | 101 | 111 |
| salad_leaves | 94 | 96 |
| broccoli | 10 | 10 |
| carrot | 29 | 29 |
| peas | 11 | 11 |
| beans_baked | 0 | 0 |
| lentils | 21 | 21 |
| apple | 18 | 18 |
| banana | 7 | 7 |
| tomato | 63 | 63 |
| mixed_vegetables | 148 | 181 |
| cereal | 14 | 15 |
| water | 82 | 87 |
| coffee | 69 | 71 |
| tea | 16 | 16 |
| milk | 6 | 6 |
| fruit_juice | 5 | 5 |
| soup | 15 | 15 |
| beer | 7 | 7 |
| wine | 22 | 30 |
| unknown_food | 381 | 447 |
| unsupported_liquid | 21 | 23 |
| dropped | 139 | 158 |

## Verdicts on the four target classes (train split)

The classes this bridge exists to fix, previously **zero** FoodSeg103
images each (segmenter-foundation Decision 21;
`estimation-improvement-avenues.md` caveats now settled):

- **cereal: 592 images** (`birchermuesli-prepared-no-sugar-added` 148, `flakes-oat` 137, `muesli` 137, `crunch-muesli` 111, `porridge-prepared-with-partially-skimmed-milk` 50, `corn-flakes` 18)
- **brown_rice: 131 images** (`rice-whole-grain` 81, `rice-wild` 50)
- **bread_wholemeal: 2547 images** (`bread-wholemeal` 1452, `bread-whole-wheat` 504, `bread-grain` 198, `bread-wholemeal-toast` 104, `bread-black` 84, `bread-rye` 69, `bread-5-grain` 69, `rusk-wholemeal` 45, `bread-spelt` 40)
- **potato_mashed: 150 images** (`mashed-potatoes-prepared-with-full-fat-milk-with-butter` 150)

## Channels with no supervision in this dataset

- **beans_baked: 0 images.** The menuCH-style ontology has no
  baked-beans category (`beans-kidney`/`beans-white` are plain pulses,
  routed to `lentils` per the FoodSeg103 red-beans precedent).
  The class stays unsupervised by this corpus — stated plainly, not
  faked. FoodSeg103 supervision for it is likewise absent.

## Routing posture

498 source categories: 245 `curated_food`, 48 `curated_drop`
(sauces/dressings/condiments/garnish — FoodSeg103 `sauce` precedent),
12 `curated_liquid` (standalone drinks with no palette home), 193
`default_unknown_food` (real food without a palette home; deliberate
rich supervision for the sentinel channel).
