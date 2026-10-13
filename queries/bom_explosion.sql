-- ============================================================
-- BOM EXPLOSION (the "smart" part of the project)
--
-- Question this answers: "If I need to build N units of product X,
-- how much of EVERY raw material / sub-component do I need in total?"
--
-- Why recursive: a product's components can themselves have their own
-- components (Wheel is a component of Bicycle, but Wheel also has its
-- own components — Rim, Tire, Spoke). It's a tree, not a flat list,
-- so a plain JOIN can't walk it — we need a recursive CTE.
--
-- Requires MySQL 8.0+ (WITH RECURSIVE was added in 8.0).
-- Change the sku / order_qty literals below to explode a different order.
-- ============================================================

WITH RECURSIVE bom_tree AS (
    -- Anchor member: direct components of the product we're ordering
    SELECT
        b.component_product_id AS product_id,
        b.quantity_required * 10 AS total_qty,   -- <-- 10 = order quantity, change here
        1 AS depth
    FROM bom b
    JOIN products root ON root.product_id = b.parent_product_id
    WHERE root.sku = 'BIKE-001'                  -- <-- change product sku here

    UNION ALL

    -- Recursive member: for every component found so far, pull ITS
    -- components, multiplying quantities down the tree
    SELECT
        b.component_product_id,
        bt.total_qty * b.quantity_required,
        bt.depth + 1
    FROM bom b
    JOIN bom_tree bt ON b.parent_product_id = bt.product_id
)
SELECT
    p.sku,
    p.name,
    p.is_raw_material,
    SUM(bt.total_qty) AS total_required,
    MAX(bt.depth) AS max_depth
FROM bom_tree bt
JOIN products p ON p.product_id = bt.product_id
GROUP BY p.sku, p.name, p.is_raw_material
ORDER BY p.is_raw_material DESC, total_required DESC;

-- Expected result for 10 bicycles:
--   Spoke  : 640    (32 per wheel x 20 wheels)
--   Rim    : 20     (1 per wheel x 20 wheels)
--   Tire   : 20     (1 per wheel x 20 wheels)
--   Seat   : 10     (1 per bike x 10)
--   Frame  : 10     (1 per bike x 10)
--   Wheel  : 20     (2 per bike x 10)   <- intermediate assembly, also shown
