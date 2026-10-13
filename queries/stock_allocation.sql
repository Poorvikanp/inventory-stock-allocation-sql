-- ============================================================
-- CONCURRENCY-SAFE STOCK ALLOCATION (the "solid engineering" part)
--
-- Problem: two orders for the same low-stock item can arrive at almost
-- the same instant. Without protection, both read "stock = 5", both
-- think there's enough, both deduct -> stock goes negative (oversold).
--
-- Fix: SELECT ... FOR UPDATE inside a transaction (InnoDB only — this
-- does NOT work on MyISAM tables, one more reason our schema uses
-- ENGINE=InnoDB). This takes a row-level lock on the inventory row, so
-- a second transaction has to WAIT until the first COMMITs or ROLLBACKs
-- before it can even read the row.
-- ============================================================

-- Run this whole block as ONE transaction per order.
START TRANSACTION;

-- Lock the inventory row for this product so no other transaction can
-- read/modify it until we commit or rollback.
SELECT quantity_available
FROM inventory
WHERE product_id = (SELECT product_id FROM products WHERE sku = 'RIM-001')
FOR UPDATE;

-- Application checks: if quantity_available >= requested_qty, proceed.
-- (If not enough stock, ROLLBACK and mark order REJECTED instead.)

-- Deduct stock
UPDATE inventory
SET quantity_available = quantity_available - 5   -- requested_qty
WHERE product_id = (SELECT product_id FROM products WHERE sku = 'RIM-001');

-- Record the order (audit trail)
INSERT INTO orders (product_id, quantity, status)
VALUES ((SELECT product_id FROM products WHERE sku = 'RIM-001'), 5, 'ALLOCATED');

-- SELECT LAST_INSERT_ID() to get the order_id, then:
-- INSERT INTO stock_reservations (order_id, product_id, quantity)
-- VALUES (<order_id>, (SELECT product_id FROM products WHERE sku='RIM-001'), 5);

COMMIT;

-- ------------------------------------------------------------
-- Interview talking point: what "FOR UPDATE" actually does
-- ------------------------------------------------------------
-- Without it: two concurrent transactions can both SELECT the same
-- quantity_available, both pass the "enough stock?" check, both UPDATE,
-- and you can end up oversold or hit a CHECK constraint violation --
-- a crash, not graceful handling.
--
-- With FOR UPDATE: the second transaction BLOCKS at the SELECT until
-- the first commits. It then sees the UPDATED quantity_available, so
-- its own stock check runs against fresh data. No overselling, no crash.
--
-- Default MySQL isolation level is REPEATABLE READ -- worth mentioning
-- that FOR UPDATE is what forces a fresh read here; without it, under
-- REPEATABLE READ a transaction could keep seeing its own snapshot even
-- after another transaction commits.
--
-- Alternative approach worth mentioning: OPTIMISTIC locking (add a
-- `version` column, UPDATE ... WHERE version = old_version, retry on
-- 0 rows affected) -- trade-off is no blocking, but requires app-level
-- retry logic. Good to mention both and explain when you'd choose each.
