# Local Server API

The app can start an embedded HTTP server (Shelf) that listens on `0.0.0.0` and is reachable from other devices on the same network.

- **Base URL**: `http://<device-ip>:8080` (port may differ)
- **Content-Type**: JSON endpoints respond with `application/json`
- **CORS**: `Access-Control-Allow-Origin: *` and standard methods/headers are enabled

## Quick Start

```bash
curl http://<device-ip>:8080/health
curl http://<device-ip>:8080/api/info
curl "http://<device-ip>:8080/api/transactions?limit=10"
```

## Conventions

### Errors

Most API endpoints return JSON errors in this shape:

```json
{ "error": "message" }
```

Common status codes:

- `400` invalid parameter
- `500` internal failure (repository/service errors)

### Pagination

Endpoints that support pagination return:

```json
{
  "pagination": {
    "total": 123,
    "limit": 20,
    "offset": 0,
    "hasMore": true
  }
}
```

## Health & Info

### `GET /health`

Simple health check.

- **Response**: plain text `OK`

### `GET /api/info`

Server info.

- **Response**
```json
{
  "status": "running",
  "version": "1.0.0",
  "timestamp": "2025-01-01T12:00:00.000Z"
}
```

## Accounts

### `GET /api/accounts`

Returns all accounts.

- **Response**: array of account objects

Account object fields:

```json
{
  "id": 123456,
  "accountNumber": "1234",
  "bank": 1,
  "balance": 100.0,
  "accountHolderName": "Jane Doe",
  "settledBalance": 90.0,
  "pendingCredit": 10.0,
  "bankName": "Some Bank"
}
```

### `GET /api/accounts/summary`

Returns totals plus a lightweight per-account list.

- **Response**
```json
{
  "totalBalance": 100.0,
  "totalSettledBalance": 90.0,
  "totalPendingCredit": 10.0,
  "accountCount": 2,
  "bankCount": 1,
  "accounts": [
    { "bank": 1, "bankName": "Some Bank", "balance": 100.0 }
  ]
}
```

### `GET /api/accounts/<bankId>`

Returns accounts filtered by `bankId`.

- **Path params**
  - `bankId` (int)

## Transactions

### `GET /api/transactions`

Returns transactions with filtering + pagination.

### `GET /api/transactions/recent`

Same as `/api/transactions` but defaults to a smaller `limit` (10).

#### Query parameters (both endpoints)

- `bankId` (int, optional)
- `accountNumber` (string, optional): digits are extracted; if longer than 4 digits, only the last 4 digits are used
- `type` (string, optional): compared case-insensitively (commonly `CREDIT` or `DEBIT`)
- `status` (string, optional): compared case-insensitively (commonly `PENDING`, `CLEARED`, `SYNCED`)
- `startDate` (ISO-8601 string, optional): `YYYY-MM-DD` or full ISO datetime
- `endDate` (ISO-8601 string, optional): `YYYY-MM-DD` includes the entire day (through `23:59:59.999`)
- `limit` (int, optional): defaults to `50` (or `10` for `/recent`), clamped to `1..200`
- `offset` (int, optional): defaults to `0`, negative values are treated as `0`

#### Response

```json
{
  "transactions": [
    {
      "id": 987654,
      "amount": 12.34,
      "reference": "ABC123",
      "creditor": "Merchant Name",
      "time": "2025-01-01T12:00:00.000Z",
      "status": "CLEARED",
      "currentBalance": "123.45",
      "bankId": 1,
      "type": "DEBIT",
      "transactionLink": null,
      "accountNumber": "1234",
      "bankName": "Some Bank"
    }
  ],
  "pagination": { "total": 1, "limit": 50, "offset": 0, "hasMore": false }
}
```

#### Examples

```bash
curl "http://<device-ip>:8080/api/transactions?bankId=1&limit=25&offset=0"
curl "http://<device-ip>:8080/api/transactions?type=DEBIT&startDate=2025-01-01&endDate=2025-01-31"
curl "http://<device-ip>:8080/api/transactions/recent?status=CLEARED"
```

## Analytics

### `GET /api/analytics/spending`

Spending totals and category breakdown (debits only).

- **Query**
  - `period` (string, optional): `month` (default), `week`, `year`
  - `bankId` (int, optional)

- **Response**
```json
{
  "period": "month",
  "total": 123.45,
  "categories": [
    { "name": "Food", "value": 50.0, "color": "#f87171", "percentage": 40.5 }
  ]
}
```

### `GET /api/analytics/volume`

Transaction volume and count grouped by bank or account.

- **Query**
  - `period` (string, optional): `month` (default), `week`, `year`
  - `groupBy` (string, optional): `bank` (default) or `account`

- **Response**
```json
{
  "period": "month",
  "volumeByAccount": [{ "name": "CBE", "bankId": 1, "value": 999.99 }],
  "countByAccount": [{ "name": "CBE", "bankId": 1, "value": 42 }],
  "totalVolume": 999.99,
  "totalCount": 42
}
```

### `GET /api/analytics/networth`

Net worth time series and change stats.

- **Query**
  - `period` (string, optional): `1M` (default), `1W`, `3M`, `1Y`, `ALL`
  - `bankId` (int, optional)

- **Response**
```json
{
  "period": "1M",
  "dataPoints": [
    { "date": "2025-01-01", "label": "Jan 1", "value": 123.45 }
  ],
  "currentValue": 123.45,
  "previousValue": 100.0,
  "changePercent": 23.5,
  "changeAmount": 23.45
}
```

## People

### `GET /api/people`

Aggregated “people” list based on transaction `creditor` names.

- **Query**
  - `limit` (int, optional): default `20`
  - `offset` (int, optional): default `0`

- **Response**
```json
{
  "people": [
    {
      "rank": 1,
      "name": "Merchant Name",
      "initials": "MN",
      "totalAmount": 123.45,
      "formattedAmount": "$123.45",
      "transactionCount": 10,
      "lastTransaction": { "type": "DEBIT", "amount": 12.34, "date": "2025-01-01T12:00:00.000Z" }
    }
  ],
  "pagination": { "total": 1, "limit": 20, "offset": 0, "hasMore": false }
}
```

### `GET /api/people/<name>/transactions`

Transactions for a specific person (exact match after normalization).

- **Path params**
  - `name` (string): URL-encoded (example: `John%20Doe`)
- **Query**
  - `limit` (int, optional): default `20`
  - `offset` (int, optional): default `0`

- **Response**
```json
{
  "person": { "name": "John Doe", "totalAmount": 123.45, "totalCredit": 50.0, "totalDebit": 73.45 },
  "transactions": [
    { "amount": 12.34, "type": "DEBIT", "date": "2025-01-01T12:00:00.000Z", "reference": "ABC123", "bankName": "CBE" }
  ]
}
```

## Summary

### `GET /api/summary`

Dashboard-style aggregated payload (accounts + recent transactions + net worth + top people + spending).

- **Response**
```json
{
  "accounts": { "total": 2, "totalBalance": 100.0, "list": [/* apiAccount[] */] },
  "transactions": { "recent": [/* apiTransaction[] */], "todayCount": 1, "todayVolume": 12.34 },
  "netWorth": { "current": 100.0, "changePercent": 0.0, "trend": "flat" },
  "topPeople": [/* from /api/people */],
  "spending": { "thisMonth": 50.0, "categories": [/* from /api/analytics/spending */] }
}
```

## Debug / Demo

### `GET /api/random`

Returns the current in-memory random number.

- **Response**
```json
{ "number": 1234, "timestamp": "2025-01-01T12:00:00.000" }
```

### `POST /api/random/generate`

Generates a new random number and returns it.

- **Request body**: none
- **Response**: same shape as `GET /api/random`

```bash
curl -X POST http://<device-ip>:8080/api/random/generate
```

## Static App Hosting

The server also serves a bundled web app from extracted Flutter assets:

- `GET /` returns `index.html`
- Requests that don’t match an API route or static file fall back to `index.html` (SPA routing)

