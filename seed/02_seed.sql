-- ============================================================
-- Seed data: a Bicycle built from a small multi-level BOM tree
--   Bicycle
--     ├── Frame        x1
--     ├── Wheel         x2   (Wheel is itself an assembly)
--     │     ├── Rim      x1
--     │     ├── Tire     x1
--     │     └── Spoke    x32
--     └── Seat          x1
-- ============================================================

INSERT INTO products (sku, name, unit, is_raw_material) VALUES
    ('BIKE-001',  'Bicycle',        'unit', FALSE),
    ('FRAME-001', 'Frame',          'unit', TRUE),
    ('WHEEL-001', 'Wheel',          'unit', FALSE),
    ('SEAT-001',  'Seat',           'unit', TRUE),
    ('RIM-001',   'Rim',            'unit', TRUE),
    ('TIRE-001',  'Tire',           'unit', TRUE),
    ('SPOKE-001', 'Spoke',          'unit', TRUE);

-- Bicycle's direct + nested components
INSERT INTO bom (parent_product_id, component_product_id, quantity_required)
SELECT p1.product_id, p2.product_id, v.qty FROM
(
    SELECT 'BIKE-001' AS parent_sku, 'FRAME-001' AS component_sku, 1 AS qty UNION ALL
    SELECT 'BIKE-001', 'WHEEL-001', 2 UNION ALL
    SELECT 'BIKE-001', 'SEAT-001',  1 UNION ALL
    SELECT 'WHEEL-001','RIM-001',   1 UNION ALL
    SELECT 'WHEEL-001','TIRE-001',  1 UNION ALL
    SELECT 'WHEEL-001','SPOKE-001', 32
) AS v
JOIN products p1 ON p1.sku = v.parent_sku
JOIN products p2 ON p2.sku = v.component_sku;

-- Current stock on hand for raw/purchased materials
INSERT INTO inventory (product_id, quantity_available, reorder_level)
SELECT p.product_id, v.qty, v.reorder FROM
(
    SELECT 'FRAME-001' AS sku, 50   AS qty, 10  AS reorder UNION ALL
    SELECT 'SEAT-001',  40,  10  UNION ALL
    SELECT 'RIM-001',   120, 30  UNION ALL
    SELECT 'TIRE-001',  100, 30  UNION ALL
    SELECT 'SPOKE-001', 3000,500
) AS v
JOIN products p ON p.sku = v.sku;
