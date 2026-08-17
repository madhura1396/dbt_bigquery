select
    {{ dbt_utils.generate_surrogate_key(['seller_id']) }} as seller_key,
    seller_id,
    seller_city,
    seller_state,
    seller_zip_code_prefix
from {{ ref('stg_sellers') }}
