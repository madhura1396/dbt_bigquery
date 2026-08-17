select
    product_id,
    coalesce(product_category_name, 'Unknown') as product_category_name_pt,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
from {{ source('raw', 'olist_products') }}
