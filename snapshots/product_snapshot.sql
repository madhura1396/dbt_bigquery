{% snapshot product_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='product_id',
        strategy='check',
        check_cols=['product_category_name_pt'],
    )
}}

select
    product_id,
    coalesce(product_category_name_pt, 'Unknown') as product_category_name_pt,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
from {{ ref('stg_products') }}

{% endsnapshot %}
