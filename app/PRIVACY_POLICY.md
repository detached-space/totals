# Privacy Policy for Totals

Effective date: April 23, 2026

Totals is a personal finance application published by Detached. This Privacy Policy explains how Totals accesses, uses, stores, and shares data when you use the Android application package `detached.totals`.

## Summary

- Totals is designed to work primarily on-device.
- For core SMS-based transaction tracking, supported bank SMS messages are read, parsed, and stored locally on your device. Those SMS contents are not sent to our servers for normal transaction tracking.
- Some optional features use the internet:
  - Payment verification can send the image, payment reference, selected account number, and selected bank identifier you submit to our verification service to process your request.
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

## How We Use Data

- To detect and parse bank SMS messages into transactions.
- To display balances, transaction history, budgets, widgets, insights, and related finance features.
- To scan account-sharing QR codes and import account data locally.
- To verify payments when you manually use the verification feature.
- To download updated SMS parsing patterns and bank configuration files.
- To secure access to the app if you use device authentication or app lock.
- To export, import, or share data when you explicitly choose those actions.

## When Data Leaves Your Device

- Core SMS tracking: SMS contents used for normal transaction tracking stay on your device.
- Payment verification: If you use the payment verification feature, the data you submit may be transmitted over HTTPS to our verification service hosted at `sms-parsing-visualizer.vercel.app` to process your request.
- Configuration updates: When Totals downloads updated SMS parsing patterns or bank configuration files, it connects to our hosted configuration endpoints. The app may also perform basic connectivity checks to confirm internet access. These requests are used to download configuration, not to upload your SMS contents for normal tracking.
- Support and external links: If you open external links from the app, such as support pages, Telegram, or bank links, those services receive information according to their own privacy policies.
- Local network dashboard: If you manually start the optional local web dashboard or server, your financial data may be available to devices on the same local network using the URL shown in the app until you stop the server.

## Sharing

- We do not sell your personal or financial data.
- We do not share SMS contents or SMS-derived transaction data with advertisers.
- We may use hosting, content delivery, networking, security, or infrastructure providers to deliver the optional online features described above.
- We may disclose information if required by law, to protect users, or to prevent fraud, abuse, or security issues.

## Storage and Retention

- Most Totals data is stored locally on your device until you delete it, clear app data, or uninstall the app.
- Exported backup files remain wherever you save or share them.
- QR scan results are processed locally in the app.
- Payment verification submissions may be processed by the verification service and retained only for the period reasonably necessary to operate, secure, debug, and protect the service, or as required by law.
- Downloaded SMS pattern files and bank configuration files may be cached on your device for future use.

## Security

- We rely on your device operating system and application sandbox for local storage protection.
- In the current app implementation, online requests are sent over HTTPS.
- No method of storage or transmission is completely secure, and we cannot guarantee absolute security.

## Your Choices

- You can deny permissions, although some features may not work without them.
- You can avoid optional online features if you do not want to send verification data or download remote configuration updates.
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
