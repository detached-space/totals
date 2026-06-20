# Privacy Policy for Totals

Effective date: June 14, 2026

Totals is a personal finance application published by Detached. This Privacy Policy explains how Totals accesses, uses, stores, and shares data when you use the Android application package `detached.totals`.

## Summary

- Totals is designed to work primarily on-device.
- For core SMS-based transaction tracking, supported bank SMS messages are read, parsed, and stored locally on your device. Those SMS contents are not sent to our servers for normal transaction tracking.
- Some optional features use the internet:
  - Payment verification can send the image, payment reference, selected account number, and selected bank identifier you submit to our verification service to process your request.
  - Shared expenses lets you split expenses with friends in end-to-end encrypted groups. The Totals Engine relays encrypted payloads it cannot read, and push notifications are doorbell pings that do not include expense content.
  - Data Sync (optional, off by default) lets you push selected local records to a third-party server you configure. Only the fields and records your rules select are sent, to the destination you specify; Totals does not control or secure that destination.
  - An optional identity backup vault lets you restore your shared-expense identity and group keys on a new device using a recovery code shown to you in the app plus a PIN you choose. Vault contents are encrypted on-device before being uploaded.
  - The app may download updated SMS parsing patterns and bank configuration files from our servers during setup, refresh, or manual update actions. This does not upload your SMS contents.
- Totals does not require account registration.
- Totals does not use advertising SDKs or analytics telemetry to profile you.

## Data We Access

- SMS messages and SMS-derived transaction data from supported bank notifications.
- Financial information derived from those messages, such as transaction amount, balance, date, account numbers, sender or receiver labels, and references.
- Camera access for QR scanning and for capturing an image in the payment verification feature.
- Images you choose to capture or submit for payment verification.
- Payment verification inputs, such as payment references, selected account numbers, and bank identifiers.
- Notification settings and locally generated notifications.
- Local authentication prompts, if you use the app lock feature. Totals does not receive your raw fingerprint, face scan, or other biometric template; biometric verification is handled by your device operating system.
- Exported or imported backup files that you choose to create or restore.
- Optional local network access if you manually start the in-app local web dashboard or server.
- An on-device key pair used to identify your device for the shared-expenses feature and to encrypt payloads to other members of your shared groups.
- Per-group symmetric encryption keys used to encrypt expense, settlement, and activity data shared within each group.
- The display name, payment account details, and expense data you choose to share with members of a group you have joined.
- A Firebase Cloud Messaging device token, when shared-expense notifications are enabled, used to deliver doorbell pings.
- The recovery code and PIN you provide when setting up or unlocking the optional identity backup vault. The PIN is used only on-device to derive an encryption key and is never transmitted.
- Data Sync configuration you enter, such as destination names, server URLs, authentication type, and credentials, when you use the optional Data Sync feature.

## How We Use Data

- To detect and parse bank SMS messages into transactions.
- To display balances, transaction history, budgets, widgets, insights, and related finance features.
- To scan account-sharing QR codes and import account data locally.
- To verify payments when you manually use the verification feature.
- To download updated SMS parsing patterns and bank configuration files.
- To secure access to the app if you use device authentication or app lock.
- To export, import, or share data when you explicitly choose those actions.
- To synchronize shared-expense activity, group membership, approvals, and settlement updates between you and the other members of your shared groups using end-to-end encryption.
- To deliver doorbell push notifications that prompt the app to pull and decrypt new shared-expense activity locally.
- To store and retrieve an optional encrypted identity vault so that you can restore your shared-expense identity and group keys on a new device.
- To send the records and fields you select to the external server you configure when you enable the optional Data Sync feature.

## When Data Leaves Your Device

- Core SMS tracking: SMS contents used for normal transaction tracking stay on your device.
- Payment verification: If you use the payment verification feature, the data you submit may be transmitted over HTTPS to our verification service hosted at `sms-parsing-visualizer.vercel.app` to process your request.
- Configuration updates: When Totals downloads updated SMS parsing patterns or bank configuration files, it connects to our hosted configuration endpoints. The app may also perform basic connectivity checks to confirm internet access. These requests are used to download configuration, not to upload your SMS contents for normal tracking.
- Shared expenses (optional): If you create or join a shared expense group, the app exchanges encrypted payloads with our Totals Engine service at `engine.totals.detached.space` over HTTPS. Each payload is encrypted on-device with a group symmetric key (for group-wide payloads) or with a one-to-one shared secret derived from device key pairs (for targeted payloads). The Totals Engine stores and relays the encrypted blobs and the public identifiers needed for delivery, such as the random group identifier and the sender and recipient device public keys. The Totals Engine cannot decrypt expense amounts, descriptions, member display names, or other group contents.
- Push notifications (optional): If you enable shared-expense notifications, the app registers a Firebase Cloud Messaging device token with the Totals Engine so the engine can wake the app when there is new activity. The push payload itself does not include expense content; the app pulls the encrypted payload over HTTPS and composes the notification text locally on your device.
- Identity backup vault (optional): If you turn on the identity backup feature, the app encrypts your shared-expense identity seed and your group keys on-device using a key derived from a PIN you choose and a random recovery code shown to you in the app. The encrypted blob is then uploaded to the Totals Engine, indexed only by an opaque identifier derived from the recovery code. The PIN is not transmitted, and the engine cannot derive it or decrypt the blob.
- Support and external links: If you open external links from the app, such as support pages, Telegram, or bank links, those services receive information according to their own privacy policies.
- Local network dashboard: If you manually start the optional local web dashboard or server, your financial data may be available to devices on the same local network using the URL shown in the app until you stop the server.
- Data Sync (optional, off by default): If you enable Data Sync and create one or more rules, Totals sends the records and fields you select to the destination URL you configure, using the authentication you provide. Depending on your rules this may include transaction amounts, references, dates, counterparties, balances, account numbers, bank identifiers, budgets, and any other fields you map. This is a one-way export controlled by you; Totals never pulls data back, and Totals cannot see, verify, or secure the destination, which is operated by you or a third party of your choosing.

## Sharing

- We do not sell your personal or financial data.
- We do not share SMS contents or SMS-derived transaction data with advertisers.
- We may use hosting, content delivery, networking, security, or infrastructure providers to deliver the optional online features described above.
- We may disclose information if required by law, to protect users, or to prevent fraud, abuse, or security issues.

## Storage and Retention

- Most Totals data is stored locally on your device until you delete it, clear app data, or uninstall the app.
- Data Sync settings (destinations and rules) are stored locally in the app database, and any credentials you enter are stored using secure device storage. A local outbox queue records which selected records are pending, sent, or failed. Disabling Data Sync and choosing to wipe its data deletes these settings, credentials, and the queue from your device.
- Exported backup files remain wherever you save or share them.
- QR scan results are processed locally in the app.
- Payment verification submissions may be processed by the verification service and retained only for the period reasonably necessary to operate, secure, debug, and protect the service, or as required by law.
- Downloaded SMS pattern files and bank configuration files may be cached on your device for future use.
- Your shared-expense identity key pair, your per-group symmetric keys, and your locally cached copy of group activity are stored in app-private storage on your device. They are removed when you leave the group, clear app data, or uninstall the app.
- Encrypted payloads relayed by the Totals Engine on your behalf are stored on the server only as long as needed to deliver them to every intended recipient. Once a recipient acknowledges a payload, the engine removes its copy for that recipient.
- If you upload an encrypted identity vault blob, it remains stored on the Totals Engine, in encrypted form indexed by the opaque recovery code identifier, until you delete it from within the app or replace it with a new vault. Without the matching recovery code and PIN, the engine cannot recover the contents.

## Security

- We rely on your device operating system and application sandbox for local storage protection.
- In the current app implementation, online requests are sent over HTTPS.
- No method of storage or transmission is completely secure, and we cannot guarantee absolute security.

## Your Choices

- You can deny permissions, although some features may not work without them.
- You can avoid optional online features if you do not want to send verification data or download remote configuration updates.
- You can choose not to use the shared-expenses feature, or to leave a group at any time. Leaving a group removes its local data on your device and unregisters your device from that group on the Totals Engine.
- You can disable shared-expense push notifications from the in-app settings. This unregisters your Firebase Cloud Messaging token with the Totals Engine.
- You can choose not to set up an identity backup vault, or delete an existing vault from within the app.
- You can export or import your data using in-app tools.
- You can clear local app data or uninstall the app to remove locally stored data.
- You can stop the optional local web dashboard or server at any time.

## Children

Totals is not directed to children.

## Changes to This Policy

We may update this Privacy Policy from time to time. When we do, we will update the effective date above and the in-app copy where appropriate.

## Contact

Detached

For privacy questions or requests, use one of the following support channels:

- https://t.me/totals_chat
