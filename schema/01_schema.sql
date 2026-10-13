-- ============================================================
-- Inventory & Stock Allocation System with BOM Explosion
-- Schema: products, bill-of-materials (self-referencing tree),
--         inventory, orders, stock_reservations
-- Engine: InnoDB (required for FOREIGN KEY + row-level locking)
-- ============================================================

DROP TABLE IF EXISTS stock_reservations;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS inventory;
DROP TABLE IF EXISTS bom;
DROP TABLE IF EXISTS products;

-- 1. PRODUCTS
-- Every item is a "product": finished goods, sub-assemblies, and raw materials
-- all live in the same table. is_raw_material tells us where the tree ends.
CREATE TABLE products (
    product_id      INT AUTO_INCREMENT PRIMARY KEY,
    sku             VARCHAR(30) UNIQUE NOT NULL,
    name            VARCHAR(120) NOT NULL,
    unit            VARCHAR(20) NOT NULL DEFAULT 'unit',
    is_raw_material BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;

-- 2. BILL OF MATERIALS (self-referencing tree)
-- A product (parent) is made of components (also products).
-- A component can itself have its own components -> recursive structure.
CREATE TABLE bom (
    bom_id                  INT AUTO_INCREMENT PRIMARY KEY,
    parent_product_id       INT NOT NULL,
    component_product_id    INT NOT NULL,
    quantity_required       DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_bom_parent FOREIGN KEY (parent_product_id) REFERENCES products(product_id),
    CONSTRAINT fk_bom_component FOREIGN KEY (component_product_id) REFERENCES products(product_id),
    CONSTRAINT chk_qty_positive CHECK (quantity_required > 0),
    CONSTRAINT chk_no_self_reference CHECK (parent_product_id <> component_product_id),
    CONSTRAINT uq_parent_component UNIQUE (parent_product_id, component_product_id)
) ENGINE=InnoDB;

-- 3. INVENTORY
-- Current stock on hand for any product (usually raw materials / purchasable parts)
CREATE TABLE inventory (
    product_id          INT PRIMARY KEY,
    quantity_available   DECIMAL(12,2) NOT NULL DEFAULT 0,
    reorder_level        DECIMAL(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT chk_qty_non_negative CHECK (quantity_available >= 0)
) ENGINE=InnoDB;

-- 4. ORDERS
-- A customer order for a finished product, in some quantity
CREATE TABLE orders (
    order_id        INT AUTO_INCREMENT PRIMARY KEY,
    product_id      INT NOT NULL,
    quantity        DECIMAL(10,2) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING / ALLOCATED / REJECTED
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_orders_product FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT chk_order_qty_positive CHECK (quantity > 0)
) ENGINE=InnoDB;

-- 5. STOCK RESERVATIONS
-- Audit trail: every time stock is allocated to an order, log it here.
CREATE TABLE stock_reservations (
    reservation_id   INT AUTO_INCREMENT PRIMARY KEY,
    order_id         INT NOT NULL,
    product_id       INT NOT NULL,
    quantity         DECIMAL(12,2) NOT NULL,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_res_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_res_product FOREIGN KEY (product_id) REFERENCES products(product_id)
) ENGINE=InnoDB;

-- Helpful indexes (talk about these in the interview: "I indexed the FK
-- columns that get filtered/joined on most, e.g. walking the BOM tree
-- and looking up reservations per order").
CREATE INDEX idx_bom_parent ON bom(parent_product_id);
CREATE INDEX idx_bom_component ON bom(component_product_id);
CREATE INDEX idx_reservations_order ON stock_reservations(order_id);
