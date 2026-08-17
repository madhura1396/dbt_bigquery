# Retail Analytics: Kimball Star Schema on BigQuery + dbt

A dimensional model built over the [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), following Kimball methodology. Built with dbt Core on BigQuery.

---

## What this is

A production-style data warehouse demonstrating dimensional modelling from raw source data to a queryable star schema. The focus is on the decisions, not the pipeline — grain declaration, surrogate key design, customer deduplication, source conforming, and SCD Type 2 change tracking.

---

## Why not just query the raw tables?

The raw Olist data is five disconnected CSVs with Portuguese category names, per-order customer IDs (not per-person), no surrogate keys, and no history tracking. Three things break immediately:

**Divergence.** Two analysts writing their own category translation logic produce two different revenue numbers. `dim_product` is a written-down decision everyone is forced to share.

**Wrong customer counts.** Olist issues a new `customer_id` per order, not per person. A customer who orders three times has three IDs. Querying raw gives 99,441 "customers" when there are 96,096 people.

**No history.** If a product's category changes, the raw table overwrites the old value. Historical sales silently reclassify. The SCD Type 2 snapshot preserves both versions.

---

## Architecture

```
BigQuery
├── raw                   Olist CSVs, untouched
├── staging               dbt views: cleaned, cast, renamed
├── analytics             dbt tables: dimensions and fact table
└── snapshots             dbt snapshot: SCD Type 2 history
```

The staging / analytics boundary is the Kimball back room / front room split. In production, analysts would have SELECT on `analytics` only.

---

## Data model

**Grain:** one row per unit of a product purchased on an order.

```
fct_order_items  (112,650 rows)
├── date_key         → date_dim         (1,096 rows, 2016-2018)
├── product_key      → dim_product      (32,951 rows)
├── customer_key     → dim_customer     (96,096 rows)
├── seller_key       → dim_seller       (3,095 rows)
├── order_id         (degenerate dimension)
├── price            (numeric, per unit)
└── freight_value    (numeric, verified allocated to item grain)
```

---

## Key modelling decisions

**Grain.** No quantity column exists in `olist_order_items` — three units of the same product appear as three separate rows. Grain is one row per unit, not per distinct product line. `count(*)` = units sold; `count(distinct product_id)` = distinct products.

**Freight value is additive.** Shipping is charged per order but stored at item level. Verified by cross-checking `sum(price) + sum(freight_value)` against `olist_order_payments.payment_value` across a sample of multi-item orders. Values matched exactly, confirming allocation rather than repetition.

**Customer deduplication.** Olist issues a new `customer_id` per order. `customer_unique_id` identifies the actual person. `dim_customer` is keyed on `customer_unique_id` and deduplicated with `row_number()`, producing 96,096 rows from 99,441 source rows. The 3,345 gap is repeat purchasers.

**Category translation.** Raw product categories are Portuguese. `product_category_name_translation` maps them to English via a LEFT JOIN in `dim_product`. 610 products had no category in the source (set to `Unknown`). 13 had a Portuguese category not covered by the translation table (also `Unknown`). Both cases handled by a single `coalesce()`.

**Surrogate keys.** Generated via `dbt_utils.generate_surrogate_key()` — a hash of the natural key. Consistent across rebuilds. Required because natural keys from Olist are 32-character hashes that would add ~12 GB to a billion-row fact table vs 4-byte integers, and because SCD Type 2 produces multiple rows per natural key.

**SCD Type 2.** `snapshots/product_snapshot.sql` uses dbt's snapshot feature with `strategy='check'` watching `product_category_name_pt`. Any category change closes the old row (`dbt_valid_to` set to change date) and inserts a new row. Historical fact rows retain their original `product_key` and therefore their original category — history is preserved without touching the fact table.

> Note: BigQuery Sandbox does not permit DML. Live simulation of a category change was not possible without enabling billing. The snapshot is correctly configured and would capture changes on any subsequent `dbt snapshot` run after a source update.

**Seller city names.** `olist_sellers.seller_city` is dirty — typos, slash-separated values, inconsistent capitalisation. `initcap()` applied in staging. Full canonical lookup table not built in v1. Known limitation: grouping by seller city produces fragmented results.

---

## Data quality findings

| Finding | Impact | Resolution |
|---|---|---|
| 610 products have no category | Grouping by category undercounts revenue | Set to `Unknown` in staging |
| 13 products have untranslatable categories | Same | Set to `Unknown` via LEFT JOIN coalesce |
| Seller city names contain typos and garbage values | City-level analysis is unreliable | `initcap()` applied, full fix deferred |
| `olist_customers_dataset` has inconsistent naming vs other tables | Source naming confusion | Referenced by actual name in `_sources.yml` |
| `olist_order_reviews` fails to load | Review sentiment not available | Free-text comments contain embedded newlines; fixable with "Allow quoted newlines" option |

---

## dbt tests

22 tests passing across all models:

- `unique` and `not_null` on every surrogate and natural key
- `relationships` (referential integrity) on all four fact table foreign keys
- `dbt_expectations.expect_table_row_count_to_be_between` on the fact table
- `dbt_expectations.expect_column_values_to_be_between` on `price` and `freight_value`

---

## Example query

Revenue by category by month, in English:

```sql
select
    d.year,
    d.month_name,
    p.category_name_english,
    sum(f.price)         as revenue,
    sum(f.freight_value) as shipping,
    count(*)             as units_sold
from analytics.fct_order_items f
join analytics.dim_product  p on f.product_key = p.product_key
join analytics.date_dim     d on f.date_key    = d.date_key
group by d.year, d.month_name, p.category_name_english
order by d.year, revenue desc
```

---

## Stack

| Component | Tool |
|---|---|
| Warehouse | BigQuery Sandbox |
| Transformation | dbt Core 1.12 |
| Language | SQL + Jinja |
| Packages | dbt_utils, dbt_expectations |
| Source data | Olist Brazilian E-Commerce (Kaggle) |

---

## Setup

```bash
# clone the repo
git clone https://github.com/madhura1396/dbt_bigquery.git
cd dbt_bigquery

# create venv on Python 3.11+
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install dbt-bigquery

# install packages
dbt deps

# configure credentials
# create ~/.dbt/profiles.yml pointing at your BigQuery project
# see profiles.yml.example for the required structure

# load the date dimension
dbt seed

# run all models
dbt run

# run tests
dbt test

# run snapshot (after any source category change)
dbt snapshot
```

---

## What's next

- **Second product source.** Add an acquired company's product catalogue with conflicting IDs and category names. Forces a real conforming decision and makes the surrogate key design non-trivial.
- **Accumulating snapshot.** Olist has five order timestamps (`purchase`, `approved`, `carrier`, `delivered`, `estimated`). A second fact table at order grain would show pipeline lag metrics.
- **Dashboard.** Connect Looker Studio or Metabase to `analytics` for interactive revenue by category, repeat customer analysis, and delivery time distributions.
- **Enable billing.** Unlocks DML and allows live SCD Type 2 demonstration.
- **Canonical city lookup.** A seed CSV mapping raw seller city strings to canonical names, joined in `stg_sellers`.
