# Career Copilot AI: Market Study

Optional, after release (M9). Purpose: decide with evidence whether to turn the portfolio app into a paid product.
Rule: do not publish revenue, user, or market claims unless verified. Mark every number as **verified** or **assumption**.

Last updated: ____  Owner: ____

## 1. Decision rule (set BEFORE collecting data)
Go to a paid v2 only if ALL are true:
- [ ] Waitlist signups from the target niche >= ____ (suggested: 100)
- [ ] At least ____ interviewees (suggested: 5 of 15) say they would pay $____ /month
- [ ] A clear gap exists that top competitors do not cover (written in section 4)
- [ ] Estimated break-even is reachable with organic growth only (section 3)
Otherwise: keep it as a portfolio project.

## 2. Benchmarks used (third-party, 2026; re-check before relying on them)
| Metric | Value | Source | Status |
|---|---|---|---|
| Avg monthly revenue of apps 1 year after launch (all categories) | about $72; top 10% $2,500+ | RevenueCat State of Subscription Apps 2026 | verify |
| New apps reaching $1k MRR within 2 years | 17% | RevenueCat 2026 | verify |
| Download-to-paid, North America / India+SE Asia | 2.6% / 1.4% | RevenueCat 2026 | verify |
| Download-to-paid, freemium / hard paywall | 2.1% / 10.7% | RevenueCat 2026 | verify |
| Year-1 revenue per payer, North America median | $32 | RevenueCat 2026 | verify |
| Apple fee with Small Business Program | 15% (30% otherwise) | Apple | verify eligibility |
| Apple Ads CPI, US median / global median | about $4.06 / $1.80 | AppTweak (via third-party summary) | verify |

Caveat: the RevenueCat data covers apps that already earn subscription revenue, so it likely flatters a typical new app.

## 3. Revenue model (fill in; formulas below)
Inputs:
- Price per month: $____
- Paid conversion (download to paid): ____%
- Revenue per payer in year 1: $____ (benchmark: $32)
- Apple fee: ____% (15% or 30%)
- Fixed costs per year: $____ (Apple $99 + hosting about $156 + other)
- LLM cost per analysis: $____ (estimate about $0.02 on Sonnet, about $0.001 on Haiku; measure from real usage)
- Free-user analyses per install: ____

Formulas:
- Payers = installs x conversion
- Gross revenue = payers x revenue per payer
- Net of Apple = gross x (1 - Apple fee)
- LLM cost = installs x analyses per install x cost per analysis
- Profit = net of Apple - LLM cost - fixed costs
- CAC (paid ads) = cost per install / conversion. Compare to net revenue per payer.

| Scenario | Installs | Conversion | Payers | Net of Apple | LLM cost | Fixed | Profit |
|---|---|---|---|---|---|---|---|
| Low | 500 | 2% | | | | | |
| Mid | 5,000 | 2.5% | | | | | |
| High | 25,000 | 3% | | | | | |

Break-even payers = (fixed costs + LLM cost) / (net revenue per payer): ____

## 4. Competitor teardown
Pre-filled names are starting points. Prices were reported by third-party articles and conflict between sources, so **check each official site and record the date**.

| Competitor | Focus | Price seen | Date checked | Free tier | Strengths | Gaps |
|---|---|---|---|---|---|---|
| Teal | job tracker + resume | | | | | |
| Jobscan | ATS resume scanner | | | | | |
| Resume Worded | resume/LinkedIn feedback | | | | | |
| Rezi | ATS resume builder | | | | | |
| Final Round AI | mock interviews/copilot | | | | | |
| AIApply | auto-apply + resume | | | | | |
| General chatbots (ChatGPT, Claude) | free substitute | | | | | |

For each, read 20 one- and two-star App Store or Trustpilot reviews. Log recurring complaints:
| Complaint | Competitor | Count | Could we solve it? |
|---|---|---|---|

Our differentiator (one sentence, must be specific): ____

## 5. Niche candidates (hypotheses to test, not facts)
- [ ] iOS / mobile developer interview prep from resume + job description
- [ ] Fresh graduates
- [ ] Arabic-speaking or MENA job seekers
- [ ] Other: ____
Chosen niche and why: ____

## 6. App Store search research
- Keywords to check (App Store search, record top 5 apps and rating counts): ____
- Is there room for a new app in the top results? ____
- Candidate app name and subtitle: ____

## 7. Waitlist test
- Landing page URL: ____ (one page: problem, screenshots/demo video, email field)
- Traffic sources used (communities, LinkedIn, X, forums; follow each community's rules): ____
- Visitors: ____  Signups: ____  Conversion: ____%
- Result vs decision rule: ____

## 8. Interviews (aim for 15 job seekers in the niche)
Script:
1. Tell me about your last job search. What was hardest?
2. What tools did you use for your resume and interview prep? What did you pay?
3. What did you wish those tools did?
4. Show the demo. What would you use it for? What is missing?
5. Would you pay for this? How much per month? What would stop you?
Log (no personal data beyond what people agree to share):
| # | Role/level | Tools used | Pain point | Would pay? | Price | Notes |
|---|---|---|---|---|---|---|

## 9. Privacy and policy checks before charging anyone
- [ ] Privacy policy and data retention note published
- [ ] Account and data deletion tested end to end
- [ ] In-app purchase / subscription flow planned (StoreKit or RevenueCat) and App Store review rules checked
- [ ] Usage caps and cost alerts in place

## 10. Findings and decision
- Summary of evidence: ____
- Decision: [ ] Go  [ ] Pivot niche  [ ] Stay portfolio-only
- Next steps: ____
