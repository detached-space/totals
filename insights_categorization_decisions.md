## Insights & Categorization – Team Notes

- **Context**
  - Since we now have category support (needs vs wants, income vs expense) and most old SMS transactions are uncategorized, using categories directly in the health score would skew results.
  - I decided to treat uncategorized spend carefully and gate category influence by data coverage.

- **Proof that old uncategorized data skews the score**
  - Essentials share needs a denominator.
  - If we include uncategorized in that denominator, known essentials look too small.
  - Example: 1,000 ETB essential, 1,000 ETB wants, 8,000 ETB uncategorized.
  - If we divide by all spending: 1,000 / 10,000 = 10% essentials (seems bad).
  - If we divide only by known categories: 1,000 / 2,000 = 50% essentials (normal).
  - So historic uncategorized SMS data would make the user look much worse than they are.

- **Categories model**
  - Each transaction can have a category.
  - Categories have `flow` (`income` or `expense`) and `essential` (need vs want).
  - `null` category = **Uncategorized**, treated as neutral (not automatically bad).

- **How categories affect insights**
  - We aggregate expense amounts into three buckets: **essential**, **non‑essential**, **uncategorized**.
  - We compute:
    - **Essentials ratio** = essential / (essential + non‑essential).
    - **Coverage** = (essential + non‑essential) / total expense.
  - Uncategorized spend is shown separately and **excluded** from the essentials ratio.

- **Health score logic**
  - Score combines:
    - Expense vs income.
    - Savings rate.
    - Spending stability (normalized index from variance).
    - Needs vs wants (essentials ratio), **only when coverage is high enough**.
  - Low coverage:
    - Essentials component has reduced or zero weight.
    - Score focuses on income/expense and stability.
  - This avoids punishing users for historic uncategorized SMS data.

- **Budget tips**
  - We use the 50/30/20 guideline (needs / wants / savings).
  - Essential vs non‑essential amounts feed into needs vs wants.
  - Tips call out overspending on wants or heavy fixed (essential) costs.

- **User communication**
  - We explain that:
    - “Your score becomes more accurate as you categorize more of your spending.”
  - Insights UI will show categorized coverage and uncategorized share so users understand data quality.

## Insights & Categorization – Team Notes

- **Categories model**
  - Each transaction can have a category.
  - Categories have `flow` (`income` or `expense`) and `essential` (need vs want).
  - `null` category = **Uncategorized**, treated as neutral (not automatically bad).

- **How categories affect insights**
  - We aggregate expense amounts into three buckets: **essential**, **non‑essential**, **uncategorized**.
  - We compute:
    - **Essentials ratio** = essential / (essential + non‑essential).
    - **Coverage** = (essential + non‑essential) / total expense.
  - Uncategorized spend is shown separately and **excluded** from the essentials ratio.

- **Health score logic**
  - Score combines:
    - Expense vs income.
    - Savings rate.
    - Spending stability (normalized index from variance).
    - Needs vs wants (essentials ratio), **only when coverage is high enough**.
  - Low coverage:
    - Essentials component has reduced or zero weight.
    - Score focuses on income/expense and stability.
  - This avoids punishing users for historic uncategorized SMS data.

- **Budget tips**
  - We use the 50/30/20 guideline (needs / wants / savings).
  - Essential vs non‑essential amounts feed into needs vs wants.
  - Tips call out overspending on wants or heavy fixed (essential) costs.

- **User communication**
  - We explain that:
    - “Your score becomes more accurate as you categorize more of your spending.”
  - Insights UI will show categorized coverage and uncategorized share so users understand data quality.

