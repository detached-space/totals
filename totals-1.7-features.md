# Totals 1.7 — features and improvements brief

## Release scope

- Version: Totals 1.7
- Change range: `c762098c23d1006d6ab96ded0f001b5761d17cc1` through `00cf26565541e15d75e9080b7f14d4b86e91e44c`, inclusive
- Development period represented by the commits: July 11–August 14, 2026
- Content rule: describe the final user-visible additions and improvements compared with the code immediately before `c762098c`.
- This document is a factual source brief, not finished announcement copy.

## New features

### Telegram Backup

- Optional advanced feature for sending automatic encrypted Totals backups to a private Telegram bot chat controlled by the user.
- Enable it from **Settings → Advanced → Telegram Backup**. Enabling it first shows an explicit consent screen.
- Setup flow:
  1. Create a Telegram bot with [@BotFather](https://t.me/BotFather).
  2. Paste the bot's HTTP API token into Totals.
  3. Open the bot and tap **Start** to pair the private chat.
- Totals creates and encrypts the backup on the device before uploading it directly to Telegram. There is no Totals-operated backup server in the path.
- Encryption uses AES-256-GCM. The encrypted backup index is also protected.
- The recovery key is generated and stored on the device and is never uploaded to Telegram. It can be revealed, copied, or saved as a text file.
- Restoring on another device requires the bot token and the recovery key.
- Available schedules are manual, daily, and weekly. Weekly is the recommended default for a newly connected backup space.
- Scheduled backups may use Wi-Fi or mobile data when due.
- Users can create a backup immediately, list backups stored in Telegram, and restore a selected backup from inside Totals.
- Full backups include accounts, transactions, bank definitions, categories, budgets, Quick Access accounts, auto-categorization rules and dismissals, loans and debts, repayments, reimbursement links, available original source SMS messages linked to transactions, and failed-message diagnostics.
- Bot tokens and recovery keys are stored using secure device storage.

### Reimbursements

- New reimbursement flow for treating returned money differently from ordinary income.
- An incoming credit can be categorized as **Reimbursement** and linked to the original expense it reimburses.
- Users can choose the exact amount applied to an expense.
- One incoming reimbursement can be divided across multiple expenses.
- One expense can receive multiple partial reimbursements over time.
- Reimbursement links can be viewed, edited, removed, or changed back so the incoming transaction counts as normal income.
- Linked reimbursement credits do not inflate income.
- The reimbursed portion is subtracted from spending, so budgets and spending views reflect the user's actual net cost.
- Reimbursement-aware calculations were added to spending totals, budgets, analytics, financial insights, recaps, yearly wrapped views, widgets, local-server summaries, and data sync.
- The main balance card still shows actual cash flow: the original debit remains money out and the reimbursement remains money in.
- Transaction tiles can indicate that an expense has been reimbursed.
- Reimbursement relationships are preserved in exports, imports, and Telegram backups.

### Bank statement PDF generation

- A bank statement can be generated from the menu for an individual account.
- The user can enter or confirm the account holder's full name.
- Date options include all time, this year, this month, this week, and a custom start/end range.
- The PDF contains:
  - Bank and account details
  - Account holder name
  - Statement date range
  - Opening balance
  - Closing balance
  - Total debit
  - Total credit
  - Transaction dates
  - Descriptions
  - References
  - Debit/credit type
  - Amounts
  - Running balances
- Transaction descriptions are derived from the locally available SMS parsing information when possible, with safe fallback labels.
- PDF generation happens on the device and includes visible progress for large histories.
- The finished PDF can be saved or shared.
- The document is generated locally from the records available in Totals.

### Batch transaction categorization

- Long-press a transaction to enter selection mode, select multiple transactions, and categorize them together.
- Available from the main transaction surfaces, including today's transactions and account transaction lists.
- For a mixed selection, the user can choose one expense category for debits and a separate income category for credits.
- The selected category is added without removing other existing categories.
- New categories can be created directly from the batch categorization sheet.
- Categorizing a transaction also dismisses its transaction notification.

### Android app-icon shortcuts

- Long-pressing the Totals app icon on Android exposes four direct actions:
  - Add Expense
  - Add Income
  - Quick Accounts
  - Verify Payments
- Each shortcut opens the relevant Totals screen or sheet directly.
- Shortcut labels are available in English and Amharic.

### Discover Totals

- New **Discover Totals** section in Settings for previewing useful features and tutorials.
- Initial guides cover:
  - Auto-Categorization
  - Quick Account Access
  - Linking Reimbursements
- Guides use short video previews to demonstrate each workflow.

## Major improvements

### Multi-account ownership and account controls

- Transaction ownership was reworked to better support multiple accounts at the same bank.
- Stronger account identity and masked-account-number matching reduce incorrect assignments when banks show only part of an account number in SMS messages.
- Transactions are assigned to an account only when Totals has sufficient evidence.
- Ambiguous or unmatched items are kept under **Other transactions** instead of being assigned to the wrong account.
- Users can select multiple Other transactions and manually move them to the correct account.
- Account-aware filters were added across transaction lists, today's activity, analytics, and the ledger.
- Account display ordering is now consistent throughout the app.
- Account controls now include:
  - Set as default account
  - Include in or exclude from the total balance
  - Mark as dormant or active
  - View account transactions
  - Reparse the account
  - Generate a bank statement
  - Delete the account
- Dormant accounts are excluded from the total balance and no longer display a stale balance on their cards.
- Transfers between accounts owned by the same user are handled separately from external income and spending.

### Account reparsing

- Multiple accounts can be selected and reparsed as one guided operation.
- **Other transactions** can also be selected as a reparse target, including when no bank account has been added yet.
- Reparse actions can be enabled independently:
  - Refresh fields on existing transactions
  - Import missed transactions
  - Apply saved auto-categorization rules
  - Repair incorrect credit/debit directions from legacy imports
- A start date can limit the scope of the operation.
- Reparse progress and results are shown per selected target.
- The results page reports updated, imported, auto-categorized, duplicate-removed, and direction-repaired transaction counts.
- Reparse performance was improved, especially for legacy direction repair and large histories.
- Duplicate detection and cleanup are stricter.
- Existing manual account assignments and categories are preserved when reparsing.

### Account totals, money flow, and reconciliation

- The account balance card can now open a detailed credit/debit breakdown.
- The breakdown separates:
  - Money received from other people or organizations
  - Money moved in from another owned account
  - Money paid or sent externally
  - Money moved out to another owned account
  - Bank fees and VAT
  - Unreconciled balance adjustments
- A new **Balance mismatch ledger** lists periods where transaction-derived balances did not match balance checkpoints reported by the bank.
- Mismatches can be filtered and sorted for investigation.
- The main product wording now uses **Money Flow** instead of **Cash Flow**.
- Cash Wallet is no longer included in the combined total account balance.
- The main balance card distinguishes real money movement from reimbursement-adjusted spending calculations.

### Loans & Debts redesign

- Loans & Debts is an existing feature. Its page and navigation have been redesigned in 1.7.
- The redesigned summary shows:
  - Amount owed to the user
  - Amount the user owes
  - Number of people involved
  - Number of unassigned/open items
- The page is organized into people, linked transactions, and unlinked transactions.
- Each person has a dedicated detail page showing:
  - Net balance between the user and that person
  - Total lent
  - Total borrowed
  - Forgiven and settled counts
  - A combined timeline of loans, debts, and repayments
- Search and filters cover loan/debt direction, status, person, bank, amount range, and date range.
- Long transaction histories now use continuous/infinite loading instead of manual pagination.
- Due-date updates were fixed.
- Active, settled, and forgiven states are shown more clearly.

### Import, export, and Clear Data controls

- Exports can now be customized by bank or wallet.
- Exports can be limited to a transaction date range.
- Optional exported sections include Quick Access accounts, budgets, auto-categorization data, loans and debts, and failed-message diagnostics.
- Available original source SMS messages are included with selected transactions.
- Import now inspects a backup before applying it and shows its schema version, export date, whether it was filtered, bank/account counts, transaction counts, and optional section counts.
- The import preview lets users choose which banks and optional sections to add from the backup.
- Clear Data now allows selecting specific banks or wallets and optional supporting datasets instead of only offering an all-or-nothing reset.
- Separately clearable supporting data includes Quick Access accounts, budgets, auto-categorization rules, loans and debts, and failed-message diagnostics.

### Account Hub and quick access

- Long-pressing **Shared** in the bottom navigation opens Account Hub.
- Account Hub provides two views:
  - Saved Quick Access accounts belonging to other people
  - The user's own registered accounts
- Quick Access accounts can be searched by account, bank, or name and copied with one tap.
- The user's accounts can be copied or shared together using a QR code.
- The Android app-icon **Quick Accounts** shortcut opens the Quick Accounts screen directly.

## Reliability, privacy, and performance improvements

- Startup work was reduced and deferred so the app becomes usable sooner.
- Main-page and bottom-navigation transitions were optimized.
- Notifications are more reliable in release builds.
- Transfers between the user's own accounts no longer create ordinary transaction notifications.
- Duplicate shared-expense notifications are prevented.
- Categorizing a transaction dismisses its existing notification.
- Permission onboarding now explains SMS access and background reliability more clearly.
- Battery-optimization exemption guidance was added to help background transaction processing work consistently.
- Unnecessary Android media permissions are explicitly excluded.
- The lock screen now follows the selected app theme more consistently.

## Smaller improvements and fixes

- Manual income/expense entry now uses the same category layout as the transaction category sheet.
- Keyboard dismissal and back-navigation behavior were improved on transaction-heavy pages.
- Money-page scrolling behavior was refined.
- Bottom-sheet sizing, dragging, keyboard avoidance, and closing behavior were improved in several flows.
- Shared-expense amounts can now be copied.
- Telebirr credit receipt links work correctly again.
