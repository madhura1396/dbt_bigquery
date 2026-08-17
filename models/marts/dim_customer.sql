with customer_base as (
    select
        customer_unique_id,
        customer_city,
        customer_state,
        row_number() over (
            partition by customer_unique_id
            order by customer_unique_id
        ) as rn
    from {{ ref('stg_customers') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['customer_unique_id']) }} as customer_key,
    customer_unique_id,
    customer_city,
    customer_state
from customer_base
where rn = 1
