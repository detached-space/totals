# Insights & Categorization – Quick Reference

> **For detailed information, see `insights_categorization_decisions.md`**

## Core Problem

Old uncategorized SMS transactions would skew the health score if we included them in essentials ratio calculations. **Solution**: Exclude uncategorized spending from ratio calculations and gate category influence by coverage level.

## Key Metrics

- **Essentials Ratio** = `essential / (essential + nonEssential)` 
  - ❌ **Excludes** uncategorized spending from denominator
  
- **Coverage** = `(essential + nonEssential) / totalExpense`
  - Represents % of spending that's categorized (0.0 to 1.0)

## Health Score Protection

**Score Formula:**
```
40% income/expense ratio + 
30% savings rate + 
20% stability + 
10% essentials component (gated by coverage)
```

**Coverage Factor:**
- **< 30% coverage**: Essentials component = 0% (no penalty)
- **30-70% coverage**: Essentials component = 5% (half weight)
- **> 70% coverage**: Essentials component = 10% (full weight)

**Result**: Low coverage doesn't penalize users. Score focuses on income/expense, savings, and stability when categorization is low.

## Category Buckets

1. **Essential**: `category.essential == true` + `flow == 'expense'` + `uncategorized == false`
2. **Non-Essential**: `category.essential == false` + `flow == 'expense'` + `uncategorized == false`
3. **Uncategorized**: `categoryId == null` OR `category.uncategorized == true` OR income category on expense

## Implementation

- **Service**: `InsightsService` requires `getCategoryById` function
- **Logging**: Coverage metrics logged with `[INSIGHTS_COVERAGE]` prefix
- **UI**: Banner shown when coverage < 70% to encourage categorization

## Files

- `app/lib/services/financial_insights.dart` - Core logic & logging
- `app/lib/screens/insights_page.dart` - UI with encouragement banner
- `app/lib/models/category.dart` - Category model

