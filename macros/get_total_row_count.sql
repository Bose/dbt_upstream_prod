{% macro get_total_row_count(relation, model) %}
    {{ return(adapter.dispatch("get_total_row_count", "upstream_prod")(relation, model)) }}
{% endmacro %}

{% macro default__get_total_row_count(relation, model) %}

    -- Calculate total rows in the table
    {%- set total_rows_query -%}
        SELECT COUNT(*) AS total_records
        FROM {{ relation }}
    {%- endset -%}
    {%- set total_records = dbt_utils.get_single_value(total_rows_query) -%}
    {{ return(total_records) }}

{% endmacro %}