## Medata Project

The "medata" name is chosen for the broader intent of the application and future expansions or a parallel suite of applications to hold data about individuals. This sounds initially benign, but is increasingly pertinent as both our medical devices and online subscriptions get more and more diverse and disparate.

Data have immense power - to inform, to help, to hedge bets, to create arbitrage and profitable opportunities, and inform meaningful health decisions. The pie in the sky version of MeData would hold your health, biometric data, health data, (heartrate and so on from your fitbit/smart watch), blood glucose from a CGM (continuous glucose monitors), insulin dosing from a smart pen or pump, and (the initial phase being worked on now), recording and accurately measuring carbohydrate, protein, fats, and booze intake.

With the above set of data alone - we can create _hugely and genuinely impactful_ products for people living with diabetes.

For context for those with fully functioning pancreases: there is an intense mental load required for calculating an insulin dose. Estimating a plate of food, calculating insulin sensitivity, factoring for the previous meal and decay functions of food content like fats, complex proteins ect, the recent exercise done over the last 3 days (or even week), hormonal factors or stress levels, and a plethora of other factors, ALL come into play for calculating **1 single dose**. Imagine having to do that _every time you eat_. This is what people with T1DM live with. Every. Damn. Day.

The upside to this now however is that there has been consistent research on making this problem simpler. There are now clever AI models and suites that can try and quantify and assess food's macro data. A person could reasonably ask _"Why hasn't this been done before?"_. It has. But: it's behind paywalls and subscriptions. Entities like SNAQ (now part of Ascensia ) or GoCARB have done this. But instead of allowing access to this fundamentally life changing technology at a reasonable price - they paywall it. Taking _publicly funded_ research on health and patient outcomes and _privatising it_ for personal gain is frankly - the height of captialism gone wrong. It's what's wrong with North American (excepting Canadia) healthcare. It's profiting off a captive market, who have no say in whether they need your overpriced and poorly engineered product. (It may be clear from this line that it's a somewhat personal gripe of the author...).

_THERE IS HOWEVER HOPE!_ With a few significant caveats:

1. The AI models require internet connectivity, and incurr a cost for EVERY call or photograph of food you send. It can get expensive quickly. This is (relatively) easily offset however by the fact that for over **ten years** published research has shown that this can be done in a deterministic fasion, _on a local device_ (see [the references page](docs/references.md)) This  makes it seem immediately outrageous that one would even consider an AI model for it. Why pay to ask `<arbitrary LLM>` how to find the answer to a complex maths problem - when you've got a scientific calculator in your pocket. You're throwing away money and compute that can be used for better things.

2. Money. It's always money. Pharmaceutical firms have a perverse incentive when it comes to data. When asked about the initial research for GoCARB and SNAQ (now owned by Ascensia. A publicly traded firm. Who care about shareholder value more than patients), we were told years ago that GoCARB and the weights that model has used have been sold. There is also the likes of Abbott, GSK, who manufacture CGM devices. They lock your data (data about **you**), behind their _safety features_. It is dismissive and insulting to people who have lived with this ailment for decades to have a faceless firm say _"Hey! We've got this amazing new device to read ALL about your personal biometric data! But we own the data. You never get to see it and use it in real time. Unless you buy ALL of our products. Even then, we won't let you USE these data in any way. It's ours. Even though it's inherently **you**"_.
It's the Apple/Windows/Android vendor device lock in all over again, but with VERY personal data. Why do big pharmaceutical companies get to see YOUR data in real time before you do? Why do they get to determine arbitrarily what is safe for you to know in real time?

The answer is profit. We've been told literally for decades the cure for T1DM is within 5 years. Now obviously research pipelines are ALWAYS difficult to predict - but if leagues of medical researchers and professionals say it's close: and are consistently knocked back: you really have to start looking more closely as to why that may be.

For the sake of this demonstrative argument, we'll use Melbourne, Victoria for our point of reference, and numbers akin to _"back of the napkin"_ maths.

According to cursory googling (as at July 2026), approximately 3500 people in Melbourne live with diabetes (both t1 and t2), with 350 of those being for type 1. The cost of a CGM that lasts 15 days (if you're lucky!) is ~$17. That is ONLY however if you have T1DM. If you've type 2, the cost rockets up to $130. It's not subsidised. Then there's the cost of insulin itsself. About $120 for 3 month supply (in 1 personal case - so let's stretch this to $120 for 6 months for the sake of lowballing the estimate).

So let's do that maths, for 1 city, for revenue (accross the whole spectrum of diabetes ailments).
    `(17.5 x 350 + 120 x 3500) x 26 = 11,079,250`. That is **just** for CGM devices. For 1 city. In one country with relatively good subsidies for healthcare.

    `(120 x 350 + 12 x 3500) x 6 = 504,000`. Assuming (not all t2 diabetes is treated with insulin) approximately 10% of cases, and intentionally low-balling the estimate, that's half a million of revenue for insulin for pharma companies. For 1 city. 1 year.

Do the maths and the numbers are absolutely staggering globally.

Then start thinking about the fact that diabetes affects a set percentage of the population and that number is not declining. If you sold the 'cure to diabetes!', even at an exorbitant cost - you're _immediately_ saying - _"Heya shareholders! We COULD have just let this cash cow run ad infinitum, but instead, we made a product that damages our long running profit margin AND that of our competition!"_. Medical research is driven by the very firms that profit from medicine. It's abhorrent and the fact that it's not a worldwide outrage is something that bewilders me.

SO. The state of affairs:
 - Pharma companies have an interest in continuing to supply a captive market with products rather than work towards making the world and people in it better off (unless you're a shareholder).
 - Data ownership (excepting sort of in the EU, but that get's weird with medical), is dictated by the same companies selling you their product: that in a lot of cases people die without.
 - Cognitive load for diabetes management and record keeping (doses, carbs, BSL), is onerous - and creates more capacity for human error: which has compounding effects. _(Mess up a dose, screw up your lunch, mess up the next dose, be stressed, have more issues...)_
 - Data are available which can help use simple linear (and then extending to more complex multi-variate) regressions to **drastically** simplify this load.
 - Most of it is stuck behind paywalls by veritable assholes.

Next however:
 - Medata actually get's good at recording/estimating carbs (that's the current P1).
 - Insulin and BSL recording (and eventually healthkit data) are recorded in the same format, in the same place, owned by you the user.
 - INDIVIDUAL user data is amalgamated and used to inform decisions around dosing.
 - We own data that are about us. Data on me, is mine. _(Imagine a lad from Wicklow yellin' out "Give us me data mam!", and you've got the idea)_.
 - It's sold at cost price, or hosted and sold for services. (Basically, if the app get's through Apple's review, It'll be sold for a reasonable 1 off fee to cover the app store developer fees and other dev costs). It will not be a subscription. People should NOT have to pay for access and use of their own data. (So if you want, you can build and run this on your own device by cloning the repo and doing cody type things).

Then if there's profit beyond that, it just means I've done something useful.


