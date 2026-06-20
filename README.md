# Totals

**Totals** is a Flutter mobile app that automatically tracks your bank transactions by parsing SMS messages from Ethiopian banks. It provides real-time balance updates, transaction history, budgeting, analytics, and financial insights — all stored locally on your device.

## Screenshots

<table>
  <tr>
    <td align="center">
      <a href="screenshots/1.png">
        <img src="screenshots/1.png" width="100%" alt="Screenshot 1"/>
      </a>
    </td>
    <td align="center">
      <a href="screenshots/2.png">
        <img src="screenshots/2.png" width="100%" alt="Screenshot 2"/>
      </a>
    </td>
    <td align="center">
      <a href="screenshots/3.png">
        <img src="screenshots/3.png" width="100%" alt="Screenshot 3"/>
      </a>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="screenshots/4.png">
        <img src="screenshots/4.png" width="100%" alt="Screenshot 4"/>
      </a>
    </td>
    <td align="center">
      <a href="screenshots/5.png">
        <img src="screenshots/5.png" width="100%" alt="Screenshot 5"/>
      </a>
    </td>
    <td align="center">
      <a href="screenshots/6.png">
        <img src="screenshots/6.png" width="100%" alt="Screenshot 6"/>
      </a>
    </td>
  </tr>
</table>

## Features

### Multi-Bank Support
- Commercial Bank of Ethiopia (CBE)
- Awash Bank
- Bank of Abyssinia (BOA)
- Dashen Bank
- Telebirr
- Amhara Bank
- Nib Bank

### Core Functionality

- **Automatic SMS Parsing** — monitors incoming bank SMS and extracts transaction details
- **Real-Time Balance Updates** — balances update automatically when transactions are detected
- **Transaction History** — full history with filtering, search, and category tagging
- **Budgets** — create budgets with alerts and track spending against them
- **Account Management** — multiple bank accounts with QR code sharing
- **Analytics Dashboard** — income vs expense charts, net worth over time, spending patterns by day/week/month/year
- **Financial Insights** — automated spending analysis and trends
- **Home Screen Widgets** — balance and expense summary widgets for Android
- **Biometric Security** — fingerprint or face authentication with auto-lock
- **Dark/Light Theme** — Material Design 3 with Google Fonts and custom font selection
- **Local Web Server** — access your data from a browser on the same network
- **Data Export/Import** — backup and restore your financial data
- **Data Sync (optional, advanced)** — push selected data to a backend you configure, with per-rule filters, field mapping, HTTP method/path, and triggers (manual, periodic, on new transaction, on reconnect). Off by default, behind a consent screen; one-way export only — bring your own server

### Privacy & Security

- **Local-First Storage** — all data stored on-device using sqflite
- **No Cloud Sync by Default** — financial data stays on your device unless you explicitly enable the optional, off-by-default Data Sync feature
- **Biometric Authentication** — secure access with fingerprint or face recognition
- **Offline-First** — works completely offline after initial setup

## Getting Started

### Prerequisites

- Flutter 3.27.1 (managed via [FVM](https://fvm.app/))
- Android Studio (Android only — iOS is not currently supported)

### Installation

```bash
git clone <repository-url>
cd totals/app
fvm flutter pub get
fvm flutter run --flavor qa
```

### First-Time Setup

1. **Grant SMS Permissions** — required to monitor bank transaction notifications
2. **Add Your First Account** — enter account number, select bank, and provide holder name
3. **Initial Internet Connection** — needed once to download SMS parsing patterns; fully offline after that

## Architecture

### Project Structure

```
app/lib/
├── main.dart
├── _redesign/                 # New UI (redesign in progress)
│   ├── screens/               # Redesigned pages
│   ├── widgets/               # Redesign-specific widgets
│   └── theme/                 # Colors, icons, theme
├── background/                # Background tasks (daily spending, etc.)
├── components/                # Shared UI components
├── data/                      # Static data and constants
├── database/
│   ├── database_helper.dart   # sqflite setup
│   └── migration_helper.dart  # Schema migrations
├── local_server/              # Built-in HTTP server
│   └── handlers/              # API route handlers
├── models/                    # Domain models (account, transaction, budget, etc.)
├── providers/                 # State management (Provider/ChangeNotifier)
├── repositories/              # Data access layer
├── screens/                   # App screens (legacy)
├── services/                  # Business logic (SMS, budgets, notifications, widgets, etc.)
├── theme/                     # App-wide theming
├── utils/                     # Helpers
└── widgets/                   # Reusable UI widgets
```

### Key Components

- **SMS Service** — monitors SMS in foreground/background, identifies bank messages by sender, parses transactions via regex, and updates balances
- **Local Server** — Shelf-based HTTP server exposing REST endpoints (`/api/accounts`, `/api/transactions`, `/api/banks`, `/api/summary`)
- **Database** — sqflite with automatic migrations; tables for accounts, transactions, budgets, categories, failed parses, and profiles
- **Budget Service** — budget creation, tracking, and threshold alerts
- **Widget Service** — Android home screen widget data providers and refresh scheduling
- **Notification Service** — transaction notifications and budget alerts

## Development

### Build Flavors

The app uses build flavors. Run with:

```bash
fvm flutter run --flavor qa
```

### Building for Production

```bash
fvm flutter build apk --release --flavor stable
```

## Dependencies

Key dependencies:
- `provider` — state management
- `sqflite` — local database
- `another_telephony` — SMS monitoring
- `shelf` / `shelf_router` — HTTP server
- `local_auth` — biometric authentication
- `fl_chart` — charts
- `home_widget` — Android home screen widgets
- `google_fonts` — typography
- `phosphor_flutter` — icons
- `mobile_scanner` / `pretty_qr_code` — QR code scanning and generation

See `app/pubspec.yaml` for the complete list.

## License

[MIT License](LICENSE.md)
