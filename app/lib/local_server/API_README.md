# Totals Local Server API Documentation

This document describes all available API endpoints in the Totals local server and how to use them.

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Base URL](#base-url)
- [Response Format](#response-format)
- [Endpoints](#endpoints)
  - [Accounts](#accounts-endpoints)
  - [Transactions](#transactions-endpoints)
  - [Summary](#summary-endpoints)
  - [Banks](#banks-endpoints)
  - [Utility](#utility-endpoints)
- [Examples](#examples)
- [Error Handling](#error-handling)

---

## Overview

The Totals local server provides a RESTful API to access your financial data including accounts, transactions, summaries, and bank information. The server runs locally on your device and is accessible from any device on the same WiFi network.

---

## Getting Started

### Starting the Server

1. Open the Totals app on your device
2. Navigate to the **Web Dashboard** page
3. Tap **Start Server**
4. Wait for the server to start (you'll see "Server Running!" status)
5. Note the server URL displayed (e.g., `http://192.168.1.100:8080`)

### Accessing the API

Once the server is running, you can access the API from:
- **Same device**: `http://localhost:8080`
- **Other devices on same network**: `http://<your-ip>:8080` (e.g., `http://192.168.1.100:8080`)

---

## Base URL

All API endpoints are prefixed with `/api/`:

```
http://<server-ip>:8080/api/<endpoint>
```

---

## Response Format

All endpoints return JSON responses with the following structure:

### Success Response
```json
{
  "data": [...],
  // or endpoint-specific fields
}
```

### Error Response
```json
{
  "error": true,
  "message": "Error description"
}
```

---

## Endpoints

### Accounts Endpoints

#### `GET /api/accounts`

Returns all registered accounts with enriched bank information.

**Response:**
```json
[
  {
    "accountNumber": "1234567890",
    "bank": 1,
    "bankName": "Commercial Bank of Ethiopia",
    "bankShortName": "CBE",
    "bankImage": "assets/images/cbe.png",
    "balance": 50000.00,
    "accountHolderName": "John Doe",
    "settledBalance": 49000.00,
    "pendingCredit": 1000.00
  }
]
```

**Example:**
```bash
curl http://localhost:8080/api/accounts
```

---

#### `GET /api/accounts/<bankId>/<accountNumber>`

Returns a specific account by bank ID and account number.

**Path Parameters:**
- `bankId` (integer) - The bank ID (1=CBE, 2=Awash, 3=BOA, 4=Dashen, etc.)
- `accountNumber` (string) - The account number

**Response:**
```json
{
  "accountNumber": "1234567890",
  "bank": 1,
  "bankName": "Commercial Bank of Ethiopia",
  "bankShortName": "CBE",
  "bankImage": "assets/images/cbe.png",
  "balance": 50000.00,
  "accountHolderName": "John Doe",
  "settledBalance": 49000.00,
  "pendingCredit": 1000.00
}
```

**Example:**
```bash
curl http://localhost:8080/api/accounts/1/1234567890
```

---

### Transactions Endpoints

#### `GET /api/transactions`

Returns transactions with optional filtering and pagination.

**Query Parameters:**
- `bankId` (integer, optional) - Filter by bank ID
- `type` (string, optional) - Filter by transaction type: `CREDIT` or `DEBIT`
- `status` (string, optional) - Filter by status: `PENDING`, `CLEARED`, `SYNCED`
- `limit` (integer, optional) - Number of results per page (default: 20)
- `offset` (integer, optional) - Pagination offset (default: 0)
- `from` (string, optional) - Start date in ISO 8601 format (e.g., `2024-01-01T00:00:00Z`)
- `to` (string, optional) - End date in ISO 8601 format (e.g., `2024-12-31T23:59:59Z`)

**Response:**
```json
{
  "data": [
    {
      "amount": 1000.00,
      "reference": "TXN123456",
      "creditor": "John Doe",
      "receiver": "Jane Smith",
      "time": "2024-01-15T10:30:00Z",
      "status": "CLEARED",
      "currentBalance": "50000.00",
      "bankId": 1,
      "bankName": "CBE",
      "bankFullName": "Commercial Bank of Ethiopia",
      "bankImage": "assets/images/cbe.png",
      "type": "CREDIT",
      "transactionLink": "https://...",
      "accountNumber": "1234567890"
    }
  ],
  "total": 150,
  "limit": 20,
  "offset": 0
}
```

**Examples:**

Get all transactions:
```bash
curl http://localhost:8080/api/transactions
```

Get transactions for a specific bank:
```bash
curl http://localhost:8080/api/transactions?bankId=1
```

Get credit transactions only:
```bash
curl http://localhost:8080/api/transactions?type=CREDIT
```

Get transactions with pagination:
```bash
curl http://localhost:8080/api/transactions?limit=50&offset=0
```

Get transactions in a date range:
```bash
curl "http://localhost:8080/api/transactions?from=2024-01-01T00:00:00Z&to=2024-01-31T23:59:59Z"
```

Combine multiple filters:
```bash
curl "http://localhost:8080/api/transactions?bankId=1&type=CREDIT&limit=10"
```

---

#### `GET /api/transactions/stats`

Returns transaction statistics grouped by bank account.

**Response:**
```json
{
  "byAccount": [
    {
      "bankId": 1,
      "name": "CBE",
      "bankName": "Commercial Bank of Ethiopia",
      "volume": 500000.00,
      "count": 150
    }
  ],
  "totals": {
    "totalVolume": 1000000.00,
    "totalCount": 300
  }
}
```

**Example:**
```bash
curl http://localhost:8080/api/transactions/stats
```

---

### Summary Endpoints

#### `GET /api/summary`

Returns aggregated summary across all accounts.

**Response:**
```json
{
  "totalBalance": 500000.00,
  "totalSettledBalance": 490000.00,
  "totalPendingCredit": 10000.00,
  "totalCredit": 200000.00,
  "totalDebit": 150000.00,
  "accountCount": 5,
  "bankCount": 3,
  "transactionCount": 500
}
```

**Example:**
```bash
curl http://localhost:8080/api/summary
```

---

#### `GET /api/summary/by-bank`

Returns summary grouped by bank.

**Response:**
```json
[
  {
    "bankId": 1,
    "bankName": "Commercial Bank of Ethiopia",
    "bankShortName": "CBE",
    "bankImage": "assets/images/cbe.png",
    "totalBalance": 200000.00,
    "settledBalance": 195000.00,
    "pendingCredit": 5000.00,
    "totalCredit": 100000.00,
    "totalDebit": 50000.00,
    "accountCount": 2,
    "transactionCount": 200
  }
]
```

**Example:**
```bash
curl http://localhost:8080/api/summary/by-bank
```

---

#### `GET /api/summary/by-account`

Returns summary for each individual account.

**Response:**
```json
[
  {
    "accountNumber": "1234567890",
    "accountHolderName": "John Doe",
    "bankId": 1,
    "bankName": "Commercial Bank of Ethiopia",
    "bankShortName": "CBE",
    "bankImage": "assets/images/cbe.png",
    "balance": 100000.00,
    "settledBalance": 98000.00,
    "pendingCredit": 2000.00,
    "totalCredit": 50000.00,
    "totalDebit": 25000.00,
    "transactionCount": 75
  }
]
```

**Example:**
```bash
curl http://localhost:8080/api/summary/by-account
```

---

### Banks Endpoints

#### `GET /api/banks`

Returns all supported banks.

**Response:**
```json
[
  {
    "id": 1,
    "name": "Commercial Bank of Ethiopia",
    "shortName": "CBE",
    "codes": ["9090"],
    "image": "assets/images/cbe.png"
  },
  {
    "id": 2,
    "name": "Awash Bank",
    "shortName": "Awash",
    "codes": ["9091"],
    "image": "assets/images/awash.png"
  }
]
```

**Example:**
```bash
curl http://localhost:8080/api/banks
```

---

#### `GET /api/banks/<id>`

Returns a specific bank by ID.

**Path Parameters:**
- `id` (integer) - The bank ID

**Response:**
```json
{
  "id": 1,
  "name": "Commercial Bank of Ethiopia",
  "shortName": "CBE",
  "codes": ["9090"],
  "image": "assets/images/cbe.png"
}
```

**Example:**
```bash
curl http://localhost:8080/api/banks/1
```

**Bank IDs:**
- `1` - Commercial Bank of Ethiopia (CBE)
- `2` - Awash Bank
- `3` - Bank of Abyssinia (BOA)
- `4` - Dashen Bank
- `5` - Cooperative Bank of Oromia (CBO)
- `6` - Telebirr

---

### Utility Endpoints

#### `GET /health`

Health check endpoint to verify server is running.

**Response:**
```
OK
```

**Example:**
```bash
curl http://localhost:8080/health
```

---

#### `GET /api/info`

Returns server information.

**Response:**
```json
{
  "status": "running",
  "version": "1.0.0"
}
```

**Example:**
```bash
curl http://localhost:8080/api/info
```

---

#### `GET /api/random`

Returns the current random number (for testing/demo purposes).

**Response:**
```json
{
  "number": 1234,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Example:**
```bash
curl http://localhost:8080/api/random
```

---

#### `POST /api/random/generate`

Generates a new random number (for testing/demo purposes).

**Response:**
```json
{
  "number": 5678,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Example:**
```bash
curl -X POST http://localhost:8080/api/random/generate
```

---

## Examples

### JavaScript/Fetch Example

```javascript
// Get all accounts
fetch('http://localhost:8080/api/accounts')
  .then(response => response.json())
  .then(data => console.log(data));

// Get transactions with filters
fetch('http://localhost:8080/api/transactions?bankId=1&type=CREDIT&limit=10')
  .then(response => response.json())
  .then(data => console.log(data));

// Get summary
fetch('http://localhost:8080/api/summary')
  .then(response => response.json())
  .then(data => console.log(data));
```

### Python Example

```python
import requests

# Get all accounts
response = requests.get('http://localhost:8080/api/accounts')
accounts = response.json()
print(accounts)

# Get transactions with filters
params = {
    'bankId': 1,
    'type': 'CREDIT',
    'limit': 10
}
response = requests.get('http://localhost:8080/api/transactions', params=params)
transactions = response.json()
print(transactions)
```

### cURL Examples

```bash
# Get all accounts
curl http://localhost:8080/api/accounts

# Get transactions for bank ID 1
curl http://localhost:8080/api/transactions?bankId=1

# Get credit transactions only
curl http://localhost:8080/api/transactions?type=CREDIT

# Get summary by bank
curl http://localhost:8080/api/summary/by-bank

# Get a specific account
curl http://localhost:8080/api/accounts/1/1234567890
```

---

## Error Handling

All endpoints return standard HTTP status codes:

- `200 OK` - Request successful
- `400 Bad Request` - Invalid request parameters
- `404 Not Found` - Resource not found
- `500 Internal Server Error` - Server error

Error responses follow this format:

```json
{
  "error": true,
  "message": "Error description"
}
```

**Example Error Response:**
```json
{
  "error": true,
  "message": "Account not found"
}
```

---

## CORS

The server includes CORS headers allowing cross-origin requests from any origin. This enables web applications to access the API from different domains.

**CORS Headers:**
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS`
- `Access-Control-Allow-Headers: Origin, Content-Type, Accept, Authorization`

---

## Notes

- The server runs on port `8080` by default
- All endpoints return JSON responses
- Date filters use ISO 8601 format: `YYYY-MM-DDTHH:mm:ssZ`
- Pagination uses `limit` and `offset` parameters
- Transaction amounts are in ETB (Ethiopian Birr)
- Account numbers are matched using bank-specific logic:
  - **CBE**: Last 4 digits
  - **Dashen**: Last 3 digits
  - **Bank of Abyssinia**: Last 2 digits
  - **Other banks**: Full account number match

---

## Web Dashboard

The server also serves a web dashboard at the root URL (`http://<server-ip>:8080`). This provides a user-friendly interface to view and interact with your financial data.

Access the interactive API documentation at:
```
http://<server-ip>:8080/docs
```

---

## Support

For issues or questions about the API, please refer to the main Totals app documentation or contact support.

