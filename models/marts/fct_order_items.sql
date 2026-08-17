select
    {{ dbt_utils.generate_surrogate_key(['oi.order_id', 'oi.order_item_id']) }} as order_item_key,
    oi.order_id,
    oi.order_item_id,
    cast(format_date('%Y%m%d', date(o.order_purchase_timestamp)) as int64) as date_key,
    dp.product_key,
    dc.customer_key,
    ds.seller_key,
    cast(oi.price as numeric)          as price,
    cast(oi.freight_value as numeric)  as freight_value
from {{ ref('stg_order_items') }} oi
join {{ ref('stg_orders') }} o
    on oi.order_id = o.order_id
join {{ ref('stg_customers') }} c
    on o.customer_id = c.customer_id
join {{ ref('dim_customer') }} dc
    on c.customer_unique_id = dc.customer_unique_id
join {{ ref('dim_product') }} dp
    on oi.product_id = dp.product_id
join {{ ref('dim_seller') }} ds
    on oi.seller_id = ds.seller_id
