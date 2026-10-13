"""
Concurrency demo: two threads simultaneously try to allocate stock for the
SAME low-stock item. This proves the SELECT ... FOR UPDATE lock prevents
overselling -- one thread commits first, the second waits, sees updated
stock, and is correctly rejected if not enough remains.

Run: python3 concurrency_demo.py
Requires: pip install mysql-connector-python
"""

import mysql.connector
import threading
import time

DB = dict(database="bom_demo", user="root", host="localhost")

# Set SEAT-001 stock artificially low so both orders can't be satisfied
SETUP_SQL = """
UPDATE inventory SET quantity_available = 12
WHERE product_id = (SELECT product_id FROM (
    SELECT product_id FROM products WHERE sku = 'SEAT-001'
) AS t);
"""

def allocate_stock(thread_name, requested_qty, delay_before_commit):
    conn = mysql.connector.connect(**DB)
    conn.autocommit = False
    cur = conn.cursor()
    try:
        print(f"[{thread_name}] starting transaction, requesting {requested_qty} seats")

        # This blocks if another transaction holds the lock on this row
        cur.execute("""
            SELECT quantity_available FROM inventory
            WHERE product_id = (SELECT product_id FROM products WHERE sku = 'SEAT-001')
            FOR UPDATE
        """)
        available = cur.fetchone()[0]
        print(f"[{thread_name}] acquired lock, sees {available} seats available")

        if available < requested_qty:
            print(f"[{thread_name}] NOT enough stock -> rejecting order")
            conn.rollback()
            return

        # simulate some processing time while holding the lock
        time.sleep(delay_before_commit)

        cur.execute("""
            UPDATE inventory SET quantity_available = quantity_available - %s
            WHERE product_id = (SELECT product_id FROM products WHERE sku = 'SEAT-001')
        """, (requested_qty,))

        cur.execute("""
            INSERT INTO orders (product_id, quantity, status)
            VALUES ((SELECT product_id FROM products WHERE sku = 'SEAT-001'), %s, 'ALLOCATED')
        """, (requested_qty,))

        conn.commit()
        print(f"[{thread_name}] COMMITTED - allocated {requested_qty} seats")
    except Exception as e:
        conn.rollback()
        print(f"[{thread_name}] ERROR, rolled back: {e}")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    setup_conn = mysql.connector.connect(**DB)
    setup_conn.autocommit = True
    setup_cur = setup_conn.cursor()
    setup_cur.execute("""
        UPDATE inventory SET quantity_available = 12
        WHERE product_id = (SELECT product_id FROM products WHERE sku = 'SEAT-001')
    """)
    setup_cur.close()
    setup_conn.close()
    print("Stock reset to 12 seats. Firing two concurrent orders for 10 seats each...\n")

    t1 = threading.Thread(target=allocate_stock, args=("Order-A", 10, 1.5))
    t2 = threading.Thread(target=allocate_stock, args=("Order-B", 10, 0.5))

    t1.start()
    time.sleep(0.1)  # ensure Order-A grabs the lock first
    t2.start()

    t1.join()
    t2.join()

    # Final check
    conn = mysql.connector.connect(**DB)
    cur = conn.cursor()
    cur.execute("""
        SELECT quantity_available FROM inventory
        WHERE product_id = (SELECT product_id FROM products WHERE sku = 'SEAT-001')
    """)
    print(f"\nFinal stock: {cur.fetchone()[0]} (started at 12 -- only ONE order of 10 should have gone through)")
    conn.close()
