# API Implementation Plan: Totals Local Server

## 1. Overview

This document provides a comprehensive implementation plan for the local HTTP server embedded within the **Totals** Flutter application. The server exposes locally stored financial data to the **Totals Web Dashboard** over the local Wi-Fi network.

The web dashboard has **4 main pages** that require data:
1. **Dashboard** - Overview with accounts, net worth chart, recent transactions, totals, top people, spending stats
2. **Accounts** - Account selection, account details, activity chart, account-specific transactions
3. **Transactions** - Transaction analytics (volume/count by account), transaction list with filters
4. **People** - Leaderboard of top contacts, contacts list with transaction history

---

## 2. Architecture

### 2.1 Technology Stack
| Component | Technology |
|-----------|------------|
| Server Framework | `shelf` |
| Routing | `shelf_router` |
| Static Files | `shelf_static` |
| Database Access | `sqflite` via existing Repositories |
| JSON Serialization | `dart:convert` |
| Concurrency | Dart Async I/O |

### 2.2 Component Diagram
```
┌─────────────────────────────────────────────────────────────────┐
│                    Totals Web Dashboard                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌──────────┐       │
│  │Dashboard │ │ Accounts │ │ Transactions │ │  People  │       │
│  └────┬─────┘ └────┬─────┘ └──────┬───────┘ └────┬─────┘       │
└───────┼────────────┼──────────────┼──────────────┼─────────────┘
        │            │              │              │
        └────────────┴──────────────┴──────────────┘
                           │ HTTP
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Shelf Server (Mobile App)                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      Router                                 │ │
│  │  /api/accounts ─────────────► AccountRepository             │ │
│  │  /api/transactions ─────────► TransactionRepository         │ │
│  │  /api/summary ──────────────► SummaryService                │ │
│  │  /api/people ───────────────► PeopleService (derived)       │ │
│  │  /api/analytics ────────────► AnalyticsService (derived)    │ │
│  │  /* ────────────────────────► Static File Handler (SPA)     │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              ▼                                   │
│                    ┌──────────────────┐                         │
│                    │   SQLite DB      │                         │
│                    │  ┌────────────┐  │                         │
│                    │  │transactions│  │                         │
│                    │  │  accounts  │  │                         │
│                    │  └────────────┘  │                         │
│                    └──────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Bank ID Mapping Reference

The web app uses these bank IDs consistently:

| Bank ID | Bank Name |
|---------|-----------|
| 1 | Commercial Bank of Ethiopia (CBE) |
| 2 | Awash Bank |
| 3 | Bank of Abyssinia (BOA) |
| 4 | Dashen Bank |
| 6 | Telebirr |

---

## 4. API Specification

### 4.1 Base Configuration
| Setting | Value |
|---------|-------|
| Protocol | HTTP |
| Host | `0.0.0.0` (all interfaces) |
| Port | `8080` (configurable) |
| Base URL | `http://<DEVICE_LOCAL_IP>:8080` |
| Content-Type | `application/json` |

### 4.2 CORS Headers
```dart
{
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
}
```

---

## 5. Endpoint Specifications

### 5.1 System Endpoints

#### `GET /health`
Simple health check for connectivity testing.

**Response:**
```
200 OK
Body: "OK"
```

---

#### `GET /api/info`
Server status and version information.

**Response:**
```json
{
  "status": "running",
  "version": "1.0.0",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

---

### 5.2 Account Endpoints

#### `GET /api/accounts`
Fetch all bank accounts. Used by Dashboard (account cards, totals card) and Accounts page.

**Repository:** `AccountRepository.getAccounts()`

**Response:**
```json
[
  {
    "id": 1,
    "accountNumber": "1000123456789",
    "bank": 1,
    "bankName": "Commercial Bank of Ethiopia",
    "balance": 24500.80,
    "accountHolderName": "Jane Doe",
    "settledBalance": 24000.00,
    "pendingCredit": 500.80
  }
]
```

**Web App Usage:**
- `Dashboard.tsx` - Renders `AccountCard` components
- `TotalsCard.tsx` - Calculates total balance, shows account count
- `Accounts.tsx` - Account selector dropdown, selected account details

**Implementation Notes:**
- Add `bankName` field derived from `bank` ID
- Add `id` field (can be composite of bank + accountNumber or DB id)

---

#### `GET /api/accounts/:bankId`
Fetch accounts for a specific bank.

**Query Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `bankId` | int | Bank ID (path parameter) |

**Response:** Same structure as `/api/accounts` but filtered

---

#### `GET /api/accounts/summary`
Aggregated account summary for the Totals Card widget.

**Response:**
```json
{
  "totalBalance": 86901.60,
  "totalSettledBalance": 85000.00,
  "totalPendingCredit": 1901.60,
  "accountCount": 5,
  "bankCount": 4,
  "accounts": [
    {
      "bank": 1,
      "bankName": "Commercial Bank of Ethiopia",
      "balance": 24500.80
    }
  ]
}
```

**Web App Usage:**
- `TotalsCard.tsx` - Shows total balance and connected accounts

---

### 5.3 Transaction Endpoints

#### `GET /api/transactions`
Fetch transactions with optional filtering and pagination.

**Repository:** `TransactionRepository.getTransactions()`

**Query Parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `limit` | int | 50 | Max results to return |
| `offset` | int | 0 | Pagination offset |
| `bankId` | int | null | Filter by bank |
| `accountNumber` | string | null | Filter by account (last 4 digits) |
| `type` | string | null | Filter by CREDIT or DEBIT |
| `status` | string | null | Filter by PENDING, CLEARED, SYNCED |
| `startDate` | string | null | ISO date string (inclusive) |
| `endDate` | string | null | ISO date string (inclusive) |

**Response:**
```json
{
  "transactions": [
    {
      "id": 1,
      "amount": 1500.00,
      "reference": "FT123456789",
      "creditor": "John Doe",
      "time": "2024-03-20T10:30:00.000",
      "status": "CLEARED",
      "currentBalance": "5000.00",
      "bankId": 1,
      "bankName": "Commercial Bank of Ethiopia",
      "type": "CREDIT",
      "transactionLink": null,
      "accountNumber": "1234"
    }
  ],
  "pagination": {
    "total": 243,
    "limit": 50,
    "offset": 0,
    "hasMore": true
  }
}
```

**Web App Usage:**
- `TransactionsTable.tsx` - Recent transactions list
- `Transactions.tsx` - Full transaction list with details
- `Accounts.tsx` - Account-specific transactions

---

#### `GET /api/transactions/recent`
Fetch most recent transactions (optimized for dashboard).

**Query Parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `limit` | int | 10 | Max results |

**Response:** Same as `/api/transactions` but defaults to 10 items

---

### 5.4 Analytics Endpoints

#### `GET /api/analytics/spending`
Spending breakdown by category (derived from transaction patterns).

**Query Parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `period` | string | "month" | "week", "month", "year" |
| `bankId` | int | null | Filter by bank |

**Response:**
```json
{
  "period": "month",
  "total": 2100.00,
  "categories": [
    { "name": "Food", "value": 400.00, "color": "#f87171", "percentage": 19.0 },
    { "name": "Rent", "value": 1200.00, "color": "#60a5fa", "percentage": 57.1 },
    { "name": "Travel", "value": 300.00, "color": "#fbbf24", "percentage": 14.3 },
    { "name": "Subscriptions", "value": 200.00, "color": "#a3a3a3", "percentage": 9.5 }
  ]
}
```

**Web App Usage:**
- `SpendingStats.tsx` - Pie chart with spending breakdown

**Implementation Notes:**
- Categories can be derived from `creditor` field patterns
- Fallback to "Other" for unclassified transactions
- Only include DEBIT transactions

---

#### `GET /api/analytics/volume`
Transaction volume and count per account/bank.

**Query Parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `period` | string | "month" | "week", "month", "year" |
| `groupBy` | string | "bank" | "bank" or "account" |

**Response:**
```json
{
  "period": "month",
  "volumeByAccount": [
    { "name": "Awash", "bankId": 2, "value": 400.00 },
    { "name": "Telebirr", "bankId": 6, "value": 300.00 },
    { "name": "CBE", "bankId": 1, "value": 300.00 },
    { "name": "Dashen", "bankId": 4, "value": 200.00 }
  ],
  "countByAccount": [
    { "name": "Awash", "bankId": 2, "value": 12 },
    { "name": "Telebirr", "bankId": 6, "value": 18 },
    { "name": "CBE", "bankId": 1, "value": 8 },
    { "name": "Dashen", "bankId": 4, "value": 5 }
  ],
  "totalVolume": 1200.00,
  "totalCount": 43
}
```

**Web App Usage:**
- `Transactions.tsx` - Two pie charts (Volume by Account, Transactions by Account)

---

#### `GET /api/analytics/networth`
Historical net worth data for charting.

**Query Parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `period` | string | "1M" | "1W", "1M", "3M", "1Y", "ALL" |
| `bankId` | int | null | Filter by bank |

**Response:**
```json
{
  "period": "1M",
  "dataPoints": [
    { "date": "2024-01-01", "label": "Jan 1", "value": 12000.00 },
    { "date": "2024-01-08", "label": "Jan 8", "value": 14500.00 },
    { "date": "2024-01-15", "label": "Jan 15", "value": 13800.00 },
    { "date": "2024-01-22", "label": "Jan 22", "value": 16200.00 },
    { "date": "2024-01-29", "label": "Jan 29", "value": 21000.00 }
  ],
  "currentValue": 24500.00,
  "previousValue": 19500.00,
  "changePercent": 25.6,
  "changeAmount": 5000.00
}
```

**Web App Usage:**
- `NetWorthChart.tsx` - Area chart showing net worth over time
- `Dashboard.tsx` - Net worth section with timeframe selector
- `Accounts.tsx` - Account-specific activity chart

**Implementation Notes:**
- Calculate from `currentBalance` field in transactions
- Group by day/week depending on period
- For "ALL", use monthly aggregation

---

### 5.5 People Endpoints

#### `GET /api/people`
Get contacts/creditors ranked by transaction volume.

**Query Parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `limit` | int | 20 | Max results |
| `offset` | int | 0 | Pagination offset |

**Response:**
```json
{
  "people": [
    {
      "rank": 1,
      "name": "Anna",
      "initials": "AN",
      "totalAmount": 15240.00,
      "formattedAmount": "$15.2k",
      "transactionCount": 24,
      "lastTransaction": {
        "type": "CREDIT",
        "amount": 500.00,
        "date": "2024-01-15T10:30:00.000"
      }
    },
    {
      "rank": 2,
      "name": "Mark",
      "initials": "MA",
      "totalAmount": 8500.00,
      "formattedAmount": "$8.5k",
      "transactionCount": 12,
      "lastTransaction": {
        "type": "DEBIT",
        "amount": 200.00,
        "date": "2024-01-14T16:20:00.000"
      }
    }
  ],
  "pagination": {
    "total": 50,
    "limit": 20,
    "offset": 0,
    "hasMore": true
  }
}
```

**Web App Usage:**
- `QuickTransfer.tsx` (TopPeople widget) - Top 3 leaderboard
- `People.tsx` - Full leaderboard and contacts list

**Implementation Notes:**
- Derive from `creditor` field in transactions
- Calculate `initials` from first 2 characters of name
- Group transactions by creditor and sum amounts
- Sort by total amount descending

---

#### `GET /api/people/:name/transactions`
Get all transactions for a specific person/creditor.

**Path Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `name` | string | URL-encoded creditor name |

**Query Parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `limit` | int | 20 | Max results |
| `offset` | int | 0 | Pagination offset |

**Response:**
```json
{
  "person": {
    "name": "Anna",
    "totalAmount": 15240.00,
    "totalCredit": 10000.00,
    "totalDebit": 5240.00
  },
  "transactions": [
    {
      "amount": 500.00,
      "type": "CREDIT",
      "date": "2024-01-15T10:30:00.000",
      "reference": "FT123456",
      "bankName": "CBE"
    }
  ]
}
```

---

### 5.6 Summary Endpoint

#### `GET /api/summary`
All-in-one summary endpoint for dashboard initialization.

**Response:**
```json
{
  "accounts": {
    "total": 5,
    "totalBalance": 86901.60,
    "list": [/* Account objects */]
  },
  "transactions": {
    "recent": [/* Last 10 transactions */],
    "todayCount": 5,
    "todayVolume": 2500.00
  },
  "netWorth": {
    "current": 86901.60,
    "changePercent": 24.0,
    "trend": "up"
  },
  "topPeople": [/* Top 3 people */],
  "spending": {
    "thisMonth": 2100.00,
    "categories": [/* Category breakdown */]
  }
}
```

**Web App Usage:**
- Initial dashboard load - reduces multiple API calls to one

---

## 6. Implementation Checklist

### 6.1 Files to Create/Modify

#### New Files:
```
lib/local_server/
├── server_service.dart        # UPDATE: Add new routes
├── handlers/
│   ├── account_handler.dart   # NEW: Account endpoint handlers
│   ├── transaction_handler.dart # NEW: Transaction endpoint handlers
│   ├── analytics_handler.dart # NEW: Analytics calculations
│   ├── people_handler.dart    # NEW: People/creditor aggregation
│   └── summary_handler.dart   # NEW: Combined summary
├── services/
│   ├── analytics_service.dart # NEW: Analytics calculations
│   ├── people_service.dart    # NEW: People aggregation logic
│   └── category_service.dart  # NEW: Transaction categorization
└── models/
    └── api_models.dart        # NEW: API response models
```

#### Models to Add (`lib/local_server/models/api_models.dart`):
```dart
// Pagination wrapper
class PaginatedResponse<T> {
  final List<T> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;
}

// Person aggregate
class PersonSummary {
  final int rank;
  final String name;
  final String initials;
  final double totalAmount;
  final int transactionCount;
  final Transaction? lastTransaction;
}

// Spending category
class SpendingCategory {
  final String name;
  final double value;
  final String color;
  final double percentage;
}

// Net worth data point
class NetWorthDataPoint {
  final String date;
  final String label;
  final double value;
}

// Volume analytics
class VolumeAnalytics {
  final String name;
  final int bankId;
  final double value;
}
```

### 6.2 Route Registration

Update `server_service.dart` router setup:

```dart
final router = Router();

// System
router.get('/health', healthHandler);
router.get('/api/info', infoHandler);

// Accounts
router.get('/api/accounts', accountHandler.getAll);
router.get('/api/accounts/summary', accountHandler.getSummary);
router.get('/api/accounts/<bankId>', accountHandler.getByBank);

// Transactions
router.get('/api/transactions', transactionHandler.getAll);
router.get('/api/transactions/recent', transactionHandler.getRecent);

// Analytics
router.get('/api/analytics/spending', analyticsHandler.getSpending);
router.get('/api/analytics/volume', analyticsHandler.getVolume);
router.get('/api/analytics/networth', analyticsHandler.getNetWorth);

// People
router.get('/api/people', peopleHandler.getAll);
router.get('/api/people/<name>/transactions', peopleHandler.getTransactions);

// Summary
router.get('/api/summary', summaryHandler.getDashboardSummary);
```

### 6.3 Handler Implementation Example

```dart
// lib/local_server/handlers/account_handler.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:totals/repositories/account_repository.dart';

class AccountHandler {
  final AccountRepository _accountRepo = AccountRepository();
  
  static const Map<int, String> bankNames = {
    1: 'Commercial Bank of Ethiopia',
    2: 'Awash Bank',
    3: 'Bank of Abyssinia',
    4: 'Dashen Bank',
    6: 'Telebirr',
  };

  Future<Response> getAll(Request request) async {
    try {
      final accounts = await _accountRepo.getAccounts();
      
      final enrichedAccounts = accounts.map((a) => {
        ...a.toJson(),
        'bankName': bankNames[a.bank] ?? 'Unknown Bank',
      }).toList();
      
      return Response.ok(
        jsonEncode(enrichedAccounts),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch accounts'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> getSummary(Request request) async {
    try {
      final accounts = await _accountRepo.getAccounts();
      
      final totalBalance = accounts.fold<double>(
        0, (sum, a) => sum + a.balance,
      );
      
      final banks = accounts.map((a) => a.bank).toSet();
      
      return Response.ok(
        jsonEncode({
          'totalBalance': totalBalance,
          'accountCount': accounts.length,
          'bankCount': banks.length,
          'accounts': accounts.map((a) => {
            'bank': a.bank,
            'bankName': bankNames[a.bank],
            'balance': a.balance,
          }).toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch summary'}),
      );
    }
  }
}
```

---

## 7. Testing Checklist

### 7.1 Manual Testing Steps

1. **Start server** - Verify startup message with IP and port
2. **Health check** - `curl http://<IP>:8080/health`
3. **API info** - Verify JSON response with version
4. **Accounts list** - Verify all accounts return with bank names
5. **Transactions list** - Verify pagination works
6. **Transactions filter** - Test bankId, type, date filters
7. **Analytics endpoints** - Verify calculated values match expected
8. **People endpoint** - Verify ranking is correct
9. **Summary endpoint** - Verify all sections populated
10. **Web app integration** - Load dashboard, verify all widgets show data

### 7.2 Web App Integration Points

| Web Component | Endpoint | Data Field |
|---------------|----------|------------|
| `Dashboard.tsx` accounts | `/api/accounts` | Full list |
| `AccountCard.tsx` | `/api/accounts` | id, name, balance, accountNumber |
| `TotalsCard.tsx` | `/api/accounts/summary` | totalBalance, accountCount |
| `NetWorthChart.tsx` | `/api/analytics/networth` | dataPoints |
| `TransactionsTable.tsx` | `/api/transactions/recent` | transactions |
| `SpendingStats.tsx` | `/api/analytics/spending` | categories |
| `QuickTransfer.tsx` | `/api/people?limit=3` | people[0..2] |
| `Accounts.tsx` chart | `/api/analytics/networth?bankId=X` | dataPoints |
| `Transactions.tsx` charts | `/api/analytics/volume` | volumeByAccount, countByAccount |
| `Transactions.tsx` list | `/api/transactions` | transactions with pagination |
| `People.tsx` leaderboard | `/api/people` | people with ranks |
| `People.tsx` contacts | `/api/people?offset=3` | remaining people |

---

## 8. Security Considerations

| Concern | Mitigation |
|---------|------------|
| Network Exposure | Server only binds to local network (LAN) |
| Authentication | Currently open - consider PIN/token pairing |
| Data Access | Read-only API (GET only except test endpoints) |
| CORS | Permissive for development, restrict in production |
| Error Messages | Generic errors returned, no stack traces |

---

## 9. Future Enhancements

### 9.1 Phase 2 - Real-time Updates
- WebSocket endpoint for live transaction push
- Server-Sent Events (SSE) alternative
- Notification when new SMS parsed

### 9.2 Phase 3 - Authentication
- PIN-based pairing
- QR code for connection
- Token-based session management

### 9.3 Phase 4 - Write Operations
- Manual transaction entry
- Category assignment
- Account nickname editing

---

## 10. Quick Start Implementation Order

1. **Basic endpoints** (accounts, transactions) - 2 hours
2. **Analytics endpoints** (networth, spending, volume) - 3 hours
3. **People endpoint** - 2 hours
4. **Summary endpoint** - 1 hour
5. **Filtering & pagination** - 2 hours
6. **Testing & integration** - 2 hours

**Total Estimated Time: ~12 hours**