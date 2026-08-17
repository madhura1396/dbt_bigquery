select
    string_field_0 as product_category_name,
    string_field_1 as product_category_name_english
from {{ source('raw', 'product_category_name_translation') }}
where string_field_0 != 'product_category_name'
