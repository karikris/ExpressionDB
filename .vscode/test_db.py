# save as test_db.py (run from VS Code with your .venv/.venv39)
import psycopg2
conn = psycopg2.connect("dbname=expressiondb user=expressiondb password=supersecret host=localhost port=5432")
with conn, conn.cursor() as cur:
    cur.execute("select 1;")
    print("DB says:", cur.fetchone())
