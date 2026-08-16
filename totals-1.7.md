# Totals 1.7: encrypted backups, smarter spending

*August 16, 2026*

Money has a habit of refusing to fit into neat little boxes. You can have two accounts at one bank, pay for everyone before they send their share, and need a statement five minutes before someone asks for it. Totals 1.7 is built for that reality: encrypted backups in your own Telegram chat, reimbursements that reduce the right spending, proper multi-account handling, PDF statements, and a redesigned Loans & Debts page.

This is a big one.

## Telegram Backup: your bot, your key

Totals can now back itself up automatically without sending a readable copy of your finances to us—or to Telegram.

Turn on **Telegram Backup** under **Settings → Advanced**, create a private bot with [@BotFather](https://t.me/BotFather), and connect it to Totals. The app creates a full backup, encrypts it on your phone, and sends the encrypted file straight to your private bot chat. There is no Totals backup server in the middle.

A few things to be clear about, because this is us:

- **Encrypted before upload.** Backups use AES-256-GCM on your device. Telegram receives ciphertext, not a readable database; it still sees ordinary service metadata such as the bot and chat identifiers, filename, file size, and upload time.
- **The key stays with you.** Your recovery key is never uploaded to Telegram. You can copy or save it, and you will need it to restore on another device. Lose it and nobody—not Telegram, not us—can open the backup for you.
- **Your schedule.** Back up manually, daily, or weekly. New backup spaces start on the recommended weekly schedule and can use Wi-Fi or mobile data when due.
- **A real full backup.** Accounts, transactions, budgets, categories, Quick Access accounts, categorization rules, loans and debts, reimbursement links, retained original source SMS messages, and failed-message diagnostics are included. The consent screen explains exactly what leaves the device before you enable anything.
- **Off by default.** Telegram Backup is an advanced, opt-in feature. Disconnecting removes the local bot token, key, and configuration; backups already sent remain in Telegram until you delete them there.

From the same page you can back up now, see the backups already in Telegram, and restore one. The bot token and recovery key stay in your phone's secure storage, while the encrypted backup index keeps the list usable across devices.

## Reimbursements: money coming back is not income

You pay ETB 2,000 for dinner. A friend sends back ETB 750. Your bank balance received money, but you did not earn ETB 750—and dinner did not really cost you ETB 2,000.

Totals 1.7 finally understands the difference.

Categorize the incoming transaction as a **Reimbursement**, then link it to the original expense and choose how much to apply. One reimbursement can cover several expenses, an expense can be reimbursed in pieces, and every amount stays editable.

Once linked, Totals uses the net cost in spending totals, budgets, analytics, insights, recaps, and widgets. The reimbursement stops inflating income, while the balance card still shows the real cash that entered and left your accounts. Cash flow and spending are related; they are not the same thing anymore.

## More than one account actually means more than one account

Multiple accounts at the same bank used to create awkward edges: masked account numbers could be ambiguous, transactions could land in the wrong place, and reparsing one account could disturb another. We rebuilt the ownership layer underneath all of it.

Totals now uses stronger account identity and masked-number matching to keep each transaction with the right account. If the app cannot prove where something belongs, it goes into **Other transactions** instead of being guessed into the wrong balance. From there, you can select several transactions and assign them to an account in one move.

Account controls grew up too:

- Mark an account as default, exclude it from the total balance, or make it dormant.
- Filter activity and the ledger by a specific account, including Other transactions.
- Reparse one account, several accounts, or unmatched transactions, with separate options to refresh existing details, import missed transactions, apply auto-categorization, and repair incorrect directions from older imports.
- Tap the credit/debit totals for a breakdown of money received, money paid, transfers between your own accounts, bank fees, VAT, and any balance checkpoints that did not reconcile.
- Open the new **Balance mismatch ledger** to inspect exactly where a reported bank balance and the transaction history stopped agreeing.

Reparsing is faster, duplicate cleanup is stricter, account ordering is consistent, and dormant accounts no longer leak stale balances into totals.

## Bank statements, generated on your phone

Open an account's menu and choose **Generate bank statement**. Add the account holder's name, pick all time, this year, this month, this week, or a custom date range, and Totals produces a clean PDF from the transaction history stored on your device.

The statement includes opening and closing balances, total debit and credit, descriptions, references, and a running balance for every transaction. Save it or share it directly. No upload, no web form, no hunting through months of SMS messages. It is generated from the records in Totals, not fetched from or issued by your bank.

## Loans & Debts, redesigned

The Loans & Debts page has been redesigned around the questions that matter: how much are you owed, how much do you owe, and who is involved?

There is a dashboard for open balances, a page for each person with the net amount between you, and one timeline for loans, debts, and repayments. Unlinked items have their own place until you assign a person. Search and filters cover direction, status, person, bank, amount, and date, and long histories now load continuously instead of making you page through them.

Due dates update correctly, return dates remain optional, and settled or forgiven entries stay visible without cluttering the active totals.

## Faster ways in, less housekeeping

- **Batch categorization:** long-press transactions, select as many as you need, and apply categories together. Mixed selections can receive one category for expenses and another for income.
- **Android app shortcuts:** long-press the Totals icon to add an expense, add income, open Quick Accounts, or verify payments without navigating through the app first.
- **Account Hub:** long-press **Shared** in the bottom navigation to search and copy saved Quick Access accounts, switch to your own accounts, or bring up the QR for sharing them.
- **Discover Totals:** Settings now has short visual guides for features that are useful but easy to miss, starting with auto-categorization, Quick Account Access, and reimbursements.
- **Selective data tools:** exports can be limited by bank and transaction date, imports show what is inside before restoring, and Clear Data lets you choose exactly which institutions and supporting data to remove.

## Also fixed/new

- Cash Wallet is no longer included in the total account balance.
- Categorizing a transaction dismisses its notification; transfers between your own accounts stay quiet; duplicate shared-expense alerts are prevented.
- Startup work and main-page navigation are faster.
- SMS and background-permission setup is clearer, including battery-optimization guidance, and Totals no longer requests media permissions it does not need.
- Telebirr credit receipt links work again.
- Shared-expense amounts can be copied.
- Manual income and expense entry, keyboard dismissal, back navigation, scrolling, bottom sheets, and the lock-screen theme received a round of polish.

---

**Get it:** update on the [Play Store](https://play.google.com/store/apps/details?id=detached.totals). On iPhone, the setup guide is at [totals.detached.space/ios-guide](https://totals.detached.space/ios-guide).

Totals is open source. The whole app: [github.com/detached-space/totals](https://github.com/detached-space/totals).

Questions, bugs, love letters: [t.me/totals_chat](https://t.me/totals_chat).
