# Inventory & Stock Allocation System with BOM Explosion

A small backend-only SQL project (MySQL 8.0, InnoDB) modeling two problems
every manufacturing/ERP system has to solve:

1. **"How much raw material do I need?"** — a product is built from
   components, which are built from their own components (a tree, not a
   flat list) — solved with a **recursive CTE**.
2. **"Two orders, one stock, same second — who wins?"** — solved with
   **transactions + row-level locking (`SELECT ... FOR UPDATE`)**.

No frontend. This is deliberately backend/SQL-only so every line can be
explained in depth.

## Schema

```
products(product_id, sku, name, unit, is_raw_material)
bom(bom_id, parent_product_id -> products, component_product_id -> products, quantity_required)
inventory(product_id -> products, quantity_available, reorder_level)
orders(order_id, product_id -> products, quantity, status, created_at)
stock_reservations(reservation_id, order_id -> orders, product_id -> products, quantity, created_at)
```

`bom` is **self-referencing**: both `parent_product_id` and
`component_product_id` point back to `products`. That's what makes the
tree — and what makes the recursive query necessary.

All tables use `ENGINE=InnoDB` — required for foreign keys and for
`SELECT ... FOR UPDATE` row-level locking (MyISAM doesn't support either).

Seed data models a bicycle:
```
Bicycle
  ├── Frame        x1
  ├── Wheel         x2   (Wheel is itself an assembly)
  │     ├── Rim      x1
  │     ├── Tire     x1
  │     └── Spoke    x32
  └── Seat          x1
```

## Setup

```bash
mysql -e "CREATE DATABASE bom_demo;"
mysql bom_demo < schema/01_schema.sql
mysql bom_demo < seed/02_seed.sql
mysql bom_demo < queries/bom_explosion.sql
```

Requires MySQL 8.0+ (recursive CTEs — `WITH RECURSIVE` — were added in
8.0; they don't exist in 5.7 and earlier).

## 1. BOM Explosion (`queries/bom_explosion.sql`)

Given an order for 10 bicycles, the recursive CTE walks the tree and
returns total raw material needed. Actual output from running it:

| sku       | name  | total_required |
|-----------|-------|-----------------|
| SPOKE-001 | Spoke | 640.00          |
| RIM-001   | Rim   | 20.00           |
| TIRE-001  | Tire  | 20.00           |
| FRAME-001 | Frame | 10.00           |
| SEAT-001  | Seat  | 10.00           |
| WHEEL-001 | Wheel | 20.00           |

(20 wheels x 32 spokes each = 640 — verified by running it.)

## 2. Concurrency-safe allocation (`queries/stock_allocation.sql`, `demo/concurrency_demo.py`)

`demo/concurrency_demo.py` sets stock to 12 seats, then fires **two
threads** each ordering 10 seats at nearly the same instant.

Actual output from running it:
```
Stock reset to 12 seats. Firing two concurrent orders for 10 seats each...

[Order-A] starting transaction, requesting 10 seats
[Order-A] acquired lock, sees 12.00 seats available
[Order-B] starting transaction, requesting 10 seats
[Order-A] COMMITTED - allocated 10 seats
[Order-B] acquired lock, sees 2.00 seats available
[Order-B] NOT enough stock -> rejecting order

Final stock: 2.00 (started at 12 -- only ONE order of 10 should have gone through)
```

Order-B's `SELECT ... FOR UPDATE` **blocks** until Order-A commits, then
sees the *updated* stock (2, not 12) and correctly rejects itself. Without
`FOR UPDATE`, both would have read 12, both would have "passed", and stock
would have gone to -8.

## Interview talking points (in your own words, ~30 sec each)

- **Why recursive CTE, not a JOIN:** a product's components can have
  their own components — that's an unknown-depth tree. A fixed-depth
  JOIN chain only works if you know the tree depth in advance.
- **ACID in this project:** the allocation is wrapped in one transaction
  (`START TRANSACTION` / `COMMIT`) — either the stock deduction AND the
  order insert both happen, or neither does (atomicity), and no other
  transaction sees a half-updated row (isolation).
- **Pessimistic vs optimistic locking:** I used pessimistic (`FOR
  UPDATE`) here because stock contention is common enough that blocking
  briefly is cheaper than retrying. I'd use optimistic locking (a
  `version` column) if writes were rare and I wanted to avoid blocking.
- **MySQL's default isolation level:** REPEATABLE READ. `FOR UPDATE` is
  what forces the second transaction to block and re-read fresh data —
  worth mentioning why that matters under this isolation level.
- **Why InnoDB, not MyISAM:** MyISAM doesn't support foreign keys or
  row-level locking (table-level only) — both are core to this project.
- **Indexing choices:** indexed both FK columns on `bom` since the
  recursive query joins on `parent_product_id` repeatedly while walking
  down the tree.
- **Normalization:** products/bom/inventory/orders/reservations are
  separated to 3NF — no repeating groups, no derived data stored twice.

## Files

```
schema/01_schema.sql       -- DDL: tables, constraints, indexes, InnoDB
seed/02_seed.sql           -- bicycle BOM tree + starting inventory
queries/bom_explosion.sql  -- the recursive CTE
queries/stock_allocation.sql -- transaction + row-lock pattern
demo/concurrency_demo.py   -- proves the lock works, with two threads
```
