## Insights & Categorization – Implementation Decisions

### Context

Since we now have category support (needs vs wants, income vs expense) and most old SMS transactions are uncategorized, using categories directly in the health score would skew results. We treat uncategorized spend carefully and gate category influence by data coverage.

### Problem: Old Uncategorized Data Skews the Score

**The Issue:**
- Essentials share needs a denominator.
- If we include uncategorized in that denominator, known essentials look too small.
- Example: 1,000 ETB essential, 1,000 ETB wants, 8,000 ETB uncategorized.
  - If we divide by all spending: 1,000 / 10,000 = 10% essentials (seems bad).
  - If we divide only by known categories: 1,000 / 2,000 = 50% essentials (normal).
- So historic uncategorized SMS data would make the user look much worse than they are.

### Categories Model

- Each transaction can have a category.
- Categories have:
  - `flow`: `'income'` or `'expense'`
  - `essential`: `true` (needs) or `false` (wants)
  - `uncategorized`: `true` for categories like "Misc" that should be treated as uncategorized
- `null` category = **Uncategorized**, treated as neutral (not automatically bad).

### Category Spend Aggregation

We aggregate expense amounts into three buckets:

1. **Essential**: 
   - `category.essential == true`
   - `category.flow == 'expense'`
   - `category.uncategorized == false`

2. **Non-Essential**: 
   - `category.essential == false`
   - `category.flow == 'expense'`
   - `category.uncategorized == false`

3. **Uncategorized**: 
   - `categoryId == null` (transaction has no category)
   - OR `category.uncategorized == true` (e.g., "Misc" category)
   - OR `category.flow == 'income'` but attached to an expense (edge case)

**Important**: Categories with the `uncategorized` flag (like the built-in "Misc" category) are explicitly treated as uncategorized spending, not as essential or non-essential. This ensures users who categorize transactions as "Misc" don't skew their essentials ratio.

### Metrics Calculation

**Essentials Ratio:**
```
essentialsRatio = essential / (essential + nonEssential)
```
- **Key Point**: Uncategorized spending is **excluded** from the denominator.
- This prevents uncategorized historical data from making the ratio look artificially low.

**Coverage:**
```
categorizedCoverage = (essential + nonEssential) / totalExpense
```
- Represents what percentage of total expenses have been categorized.
- Range: 0.0 (no categorization) to 1.0 (fully categorized).
- Higher coverage = more confidence in the essentials ratio.

### Health Score Logic: Coverage-Based Weighting

The health score combines multiple factors with weighted components:

```dart
score = 0.40 * (1 - expenseIncomeRatio) +
        0.30 * savingsRate +
        0.20 * stabilityIndex +
        0.10 * essentialsComponent
```

**The Essentials Component:**
- Only contributes **10%** of the total score (smallest component).
- Further gated by a **coverage factor** to prevent bias from low coverage.

**Coverage Factor Implementation:**

The coverage factor determines how much weight the essentials component has:

```dart
double coverageFactor = 0.0;
if (categorizedCoverage < 0.3) {
  // Low coverage: don't use essentials ratio at all
  coverageFactor = 0.0;
} else if (categorizedCoverage >= 0.3 && categorizedCoverage <= 0.7) {
  // Medium coverage: partial weight
  coverageFactor = 0.5;
} else {
  // High coverage (> 0.7): full weight
  coverageFactor = 1.0;
}

essentialsComponent = (1 - essentialsRatio).clamp(0.0, 0.1) * coverageFactor;
```

**Thresholds:**
- **Low coverage (< 30%)**: `coverageFactor = 0.0`
  - Essentials component has **zero weight**.
  - Score focuses entirely on income/expense ratio, savings rate, and stability.
  - Users with mostly uncategorized historical data are not penalized.

- **Medium coverage (30-70%)**: `coverageFactor = 0.5`
  - Essentials component has **half weight** (effectively 5% of total score).
  - Partial confidence in categorization data.

- **High coverage (> 70%)**: `coverageFactor = 1.0`
  - Essentials component has **full weight** (10% of total score).
  - High confidence in categorization data.

**Why This Works:**

1. **Low coverage doesn't penalize**: When coverage is below 30%, the essentials component contributes nothing to the score. The score is based entirely on:
   - Income vs expense ratio (40%)
   - Savings rate (30%)
   - Spending stability (20%)
   - These metrics don't require categorization.

2. **Gradual influence**: As users categorize more transactions, the essentials component gradually gains influence, but never dominates (max 10%).

3. **Double protection**: Even at full weight, the essentials component is clamped to a maximum of 0.1 (10% of score), and the ratio itself excludes uncategorized spending.

### Budget Suggestions

- We use the 50/30/20 guideline (needs / wants / savings).
- Essential vs non-essential amounts feed into needs vs wants calculations.
- Tips call out overspending on wants or heavy fixed (essential) costs.
- Budget suggestions use the categorized essential/non-essential amounts, not uncategorized spending.

### User Communication & UI

**What we explain to users:**
- "Your score becomes more accurate as you categorize more of your spending."
- Insights UI shows categorized coverage and uncategorized share so users understand data quality.
- Low coverage is not presented as a problem, but as an opportunity to improve insights.

**UI Improvements for Low Coverage:**

When coverage is below 70%, we display a prominent banner on the insights page that:
- Shows the current coverage percentage
- Displays the number of uncategorized transactions
- Provides a call-to-action button to navigate to uncategorized transactions
- Uses visual design (gradient, primary color theming) to draw attention
- Encourages users to categorize more transactions for better insights

The banner appears at the top of the insights page, making it highly visible when users need to take action.

### Production Logging

**Coverage Metrics Logging:**

We log structured coverage data for production analysis to understand user categorization patterns:

```dart
_logCoverageMetrics(
  categorizedCoverage: categorizedCoverage,
  categorizedTotal: categorizedTotal,
  totalExpense: totalExpense,
  essential: categoryBreakdown.essential,
  nonEssential: categoryBreakdown.nonEssential,
  uncategorized: categoryBreakdown.uncategorized,
  essentialsRatio: essentialsRatio,
);
```

**Log Format:**
```
[INSIGHTS_COVERAGE] coverage: 45.2%, level: MEDIUM, categorized: 4520.00, total: 10000.00, essential: 3000.00, nonEssential: 1520.00, uncategorized: 5480.00, essentialsRatio: 66.4%
```

**What We Track:**
- Coverage percentage and level (LOW/MEDIUM/HIGH)
- Categorized vs total expense amounts
- Breakdown of essential, non-essential, and uncategorized spending
- Essentials ratio

**Purpose:**
- Understand user categorization patterns in production
- Identify users who might benefit from UI improvements
- Track coverage distribution across user base
- Make data-driven decisions about threshold adjustments

### Implementation Notes

**Key Files:**
- `app/lib/services/financial_insights.dart`: Main insights calculation logic, coverage logging
- `app/lib/models/category.dart`: Category model with `uncategorized` flag support
- `app/lib/providers/transaction_provider.dart`: Provides `getCategoryById` function
- `app/lib/screens/insights_page.dart`: UI with categorization encouragement banner

**Important Implementation Details:**

1. **Category Lookup**: The `InsightsService` requires a `getCategoryById` function to look up categories. This must be provided by the `TransactionProvider`.

2. **Service Initialization**: All places that create `InsightsService` must pass `getCategoryById`:
   - `InsightsPage`: ✅ Passes `txProvider.getCategoryById`
   - `InsightsDialog`: ✅ Passes `txProvider.getCategoryById`
   - `InsightsProvider`: ✅ Passes `txProvider.getCategoryById`

3. **Category Flag Handling**: The `_computeCategorySpend()` method explicitly checks `category.uncategorized` before checking `category.essential` to ensure "Misc" and similar categories are treated as uncategorized.

4. **Edge Cases Handled**:
   - Income categories attached to expenses → treated as non-essential
   - Null categoryId → treated as uncategorized
   - Categories with `uncategorized: true` → treated as uncategorized
   - Zero total expense → coverage defaults to 0.0
   - Zero categorized total → essentials ratio defaults to 0.0

5. **Logging**: Coverage metrics are logged on every insights calculation. Logs are prefixed with `[INSIGHTS_COVERAGE]` for easy filtering in production logs.

6. **UI Banner**: The categorization encouragement banner is conditionally rendered when `categorizedCoverage < 0.7`. It navigates to `TransactionsForPeriodPage` filtered to show uncategorized transactions when available.

### Future Considerations

- Consider making coverage thresholds configurable if user feedback suggests different values.
- Consider adding a "categorization progress" indicator to motivate users.
- Analyze production logs to understand coverage distribution and adjust thresholds if needed.
- Consider A/B testing different UI approaches for encouraging categorization.
