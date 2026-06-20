# Privacy Policy for Totals

Effective date: June 4, 2026

Totals is a personal finance application published by Detached. This Privacy Policy explains how Totals accesses, uses, stores, and shares data when you use the Android application package `detached.totals`.

## Summary

- Totals is designed to work primarily on-device.
- For core SMS-based transaction tracking, supported bank SMS messages are read, parsed, and stored locally on your device. Those SMS contents are not sent to our servers for normal transaction tracking.
- Optional internet features include payment verification, shared expenses, and configuration updates.
- Payment verification can send the image, payment reference, selected account number, and selected bank identifier you submit to our verification service.
- Shared expenses can use the Totals Engine relay service to create groups, exchange encrypted group data, sync shared expenses, and deliver pending updates between approved group members.
- Data Sync is an optional, off-by-default advanced feature that lets you push selected local records to a third-party server that you configure. When you enable it and create rules, the specific fields and records you choose are sent to the destination you specify; Totals does not control, operate, or secure that destination.
- For Google Play Data Safety purposes, the user data Totals collects or shares off-device is disclosed as Financial info - Other financial info, used for app functionality.
- The app may download updated SMS parsing patterns and bank configuration files from our servers during setup, refresh, or manual update actions. This does not upload your SMS contents.
- User data collected by Totals is encrypted in transit.
- Totals does not allow users to create an account and does not support login with accounts created outside the app.
- Totals does not use advertising SDKs or analytics telemetry to profile you.

## Play Console Data Safety Summary

- Totals collects or shares required user data types.
- The selected data type for off-device collection or sharing is Financial info - Other financial info.
- The purpose for collecting or sharing that user data is app functionality.
- User data collected by Totals is encrypted in transit.
- Totals does not allow account creation in the app.
- Users cannot log in to Totals with accounts created outside the app.

## Data We Access

- SMS messages from supported bank notification senders.
- SMS-derived financial information, such as transaction amount, balance, date, account number, sender or receiver labels, references, service charges, VAT, bank identifiers, and transaction type.
- Account information you enter or import, such as account holder name, account number, bank, nickname, balance, and related account settings.
- Budget, category, auto-categorization, insight, widget, and notification settings.
- Camera access for QR scanning and for capturing an image in the payment verification feature.
- Images you choose to capture or submit for payment verification.
- Payment verification inputs, such as payment references, selected account numbers, and bank identifiers.
- Shared expense data you create or join, such as group names, member display names, invite or group identifiers, device public keys, join requests, expense amounts, reasons, dates, currency, payer, split participants, settlement records, activity history, and optional linked transaction references.
- QR contents you choose to scan, generate, import, or share for app features such as account sharing, category or rule sharing, and shared expense invites.
- Local authentication prompts, if you use the app lock feature. Totals does not receive your raw fingerprint, face scan, or other biometric template; biometric verification is handled by your device operating system.
- Exported or imported backup files that you choose to create or restore.
- Optional local network access if you manually start the in-app local web dashboard or server.
- Data Sync configuration you enter, such as destination names, server URLs, authentication type, and credentials, when you use the optional Data Sync feature.

## How We Use Data

- To detect and parse bank SMS messages into transactions.
- To display balances, transaction history, budgets, widgets, insights, categories, and related finance features.
- To scan QR codes and import data locally when you choose to use sharing or import tools.
- To verify payments when you manually use the verification feature.
- To create, join, approve, leave, and sync shared expense groups.
- To calculate shared expense balances, split amounts, settlement suggestions, and group activity.
- To authenticate shared expense devices using locally generated cryptographic keys.
- To download updated SMS parsing patterns and bank configuration files.
- To secure access to the app if you use device authentication or app lock.
- To export, import, or share data when you explicitly choose those actions.
- To operate, secure, debug, and protect optional online services.
- To send the records and fields you select to the external server you configure when you enable the optional Data Sync feature.

## When Data Leaves Your Device

- Core SMS tracking: SMS contents used for normal transaction tracking stay on your device.
- Payment verification: If you use the payment verification feature, the data you submit may be transmitted over HTTPS to our verification service hosted at `sms-parsing-visualizer.vercel.app` to process your request.
- Shared expenses: If you use shared expenses, Totals may connect over HTTPS to the Totals Engine relay service, currently configured at `engine-staging.totals.detached.space` or another configured Totals Engine endpoint.
- Shared expense contents: Group names, member display names, expense details, settlement records, and activity entries are encrypted on your device before being sent to the relay service. The relay service is designed to handle encrypted blobs and not read the plaintext contents.
- Shared expense metadata: The relay service can receive metadata needed to operate the feature, such as device public keys, group IDs, group membership, sender public keys, payload IDs, delivery and acknowledgement status, timestamps, payload sizes, IP addresses, and operational logs.
- Shared expense members: Approved members of a shared expense group can receive and decrypt the shared expense data for that group. If you split a local transaction into a group, the selected shared-expense details may be shared with those members; Totals does not automatically share the full SMS message or your full account balance unless you include that information in shared fields.
- Configuration updates: When Totals downloads updated SMS parsing patterns or bank configuration files, it connects to our hosted configuration endpoints. The app may also perform basic connectivity checks to confirm internet access. These requests are used to download configuration, not to upload your SMS contents for normal tracking.
- Support and external links: If you open external links from the app, such as support pages, Telegram, or bank links, those services receive information according to their own privacy policies.
- Local network dashboard: If you manually start the optional local web dashboard or server, your financial data may be available to devices on the same local network using the URL shown in the app until you stop the server.
- Data Sync (optional, off by default): If you enable Data Sync and create one or more rules, Totals sends the records and fields you select to the destination URL you configure, using the authentication you provide. Depending on your rules this may include transaction amounts, references, dates, counterparties, balances, account numbers, bank identifiers, budgets, and any other fields you map. This is a one-way export controlled by you; Totals never pulls data back, and Totals cannot see, verify, or secure the destination, which is operated by you or a third party of your choosing.

## Sharing

- We do not sell your personal or financial data.
- We do not share SMS contents or SMS-derived transaction data with advertisers.
- We do not use shared expense data for advertising or profiling.
- For Google Play Data Safety purposes, shared user data is disclosed as Financial info - Other financial info and is shared for app functionality.
- Shared expense data is shared with the group members you approve or join, as described above.
- We may use hosting, content delivery, networking, database, security, monitoring, or infrastructure providers to deliver the optional online features described in this policy.
- We may disclose information if required by law, to protect users, or to prevent fraud, abuse, or security issues.

## Storage and Retention

- Most Totals data is stored locally on your device until you delete it, clear app data, or uninstall the app.
- Shared expense groups, expenses, activity history, display names, and related local state may be stored locally in the app database.
- Shared expense private keys and group keys are intended to be stored locally using secure device storage. These keys are needed to decrypt group data. If they are lost, group data may not be recoverable.
- Shared expense encrypted payloads may be stored by the Totals Engine relay service until they are delivered and acknowledged or until they expire. Current implementation materials describe encrypted payload expiry of up to 30 days, and groups may expire or be removed when empty.
- Leaving a shared expense group removes local group data from your device and asks the relay service to remove your membership, but it does not remove copies already delivered to other group members.
- Exported backup files remain wherever you save or share them.
- QR scan results are processed locally unless the related feature explicitly uses an online service.
- Payment verification submissions may be processed by the verification service and retained only for the period reasonably necessary to operate, secure, debug, and protect the service, or as required by law.
- Downloaded SMS pattern files and bank configuration files may be cached on your device for future use.
- Data Sync settings (destinations and rules) are stored locally in the app database, and any credentials you enter are stored using secure device storage. A local outbox queue records which selected records are pending, sent, or failed. Disabling Data Sync and choosing to wipe its data deletes these settings, credentials, and the queue from your device.

## Security

- We rely on your device operating system and application sandbox for local storage protection.
- In the current app implementation, online requests are sent over HTTPS.
- Shared expense payload contents are encrypted on-device before being sent to the relay service. Device private keys and shared group keys are not intended to be sent to the relay service.
- Shared expense encryption protects relay traffic, but approved group members can decrypt the group data they receive and may retain or share it outside Totals.
- No method of storage, encryption, or transmission is completely secure, and we cannot guarantee absolute security.

## Your Choices

- You can deny permissions, although some features may not work without them.
- You can avoid optional online features if you do not want to send verification data, use shared expenses, or download remote configuration updates.
- You can choose what display name and expense details you enter for shared expenses.
- You can leave a shared expense group, but other members may keep data already shared with them.
- Totals does not provide app accounts, so there is no account login or account deletion flow.
- You can export or import your data using in-app tools.
- You can clear local app data or uninstall the app to remove locally stored data from your device.
- You can stop the optional local web dashboard or server at any time.

## Children

Totals is not directed to children.

## Changes to This Policy

We may update this Privacy Policy from time to time. When we do, we will update the effective date above and the in-app copy where appropriate.

## Contact

Detached

For privacy questions, use one of the following support channels:

- https://t.me/totals_chat
