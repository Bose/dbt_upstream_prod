# dbt_upstream_prod
A dbt package for easily using production data in a development environment.

## Setup

> ℹ️ If you need help setting up the package, please send a message to Filipe_Balseiro@bose.com or Marc_Sloope@bose.com

The package relies on a few variables that indicate where prod data is avaiable. The exact requirements depend on your setup; use the questions below to find the correct variables for your project. 

#### 1. Does your project have a custom schema macro?

If you aren't sure, check your `macros` directory for a macro called `generate_schema_name`. The exact filename may differ - [dbt's docs](https://docs.getdbt.com/docs/build/custom-schemas#a-built-in-alternative-pattern-for-generating-schema-names) call it `get_custom_schema.sql` - so you may need to check the file contents.

#### 2. Do your dev & prod environments use the same database?
Your platform may use a different term, such as _catalog_ on Databricks or _project_ on BigQuery.

#### 3. Choose the appropriate setup

|                                   | Custom schema macro | No custom schema macro |
|-----------------------------------|---------------------|------------------------|
| Dev & prod in same database       | Setup A             | Setup B                |
| Dev & prod in different databases | Setup C             | Setup D                |


<!-- START COLLAPSIBLE SECTIONS -->

<!-- A: custom macro & same database -->
<details><summary>Setup A</summary>
<br/>

Your custom schema macro needs two small tweaks to work with the package. As an example, the macro below shows how to adapt the [built-in `generate_schema_name_for_env` macro](https://github.com/dbt-labs/dbt-adapters/blob/6e765f58d1a15f7fcc15e504916543bd55bd62b7/dbt/include/global_project/macros/get_custom_name/get_custom_schema.sql#L47-L60):

```sql
-- 1. Add an is_upstream_prod parameter that defaults to False
{% macro generate_schema_name(custom_schema_name, node, is_upstream_prod=False) -%}

    {%- set default_schema = target.schema -%}
    -- 2. In the clause that generates your prod schema names, add a check that the value is True
    --    **Make sure to enclose the or condition in brackets**
    {%- if (target.name == "prod" or is_upstream_prod is true) and custom_schema_name is not none -%}

        {{ custom_schema_name | trim }}

    {%- else -%}

        {{ default_schema }}

    {%- endif -%}

{%- endmacro %}
```

<br/>

Add the values below to the `vars` section of `dbt_project.yml`. Some optional variables are included to improve your experience:
- `upstream_prod_fallback` tells the package to return your dev relation if the prod version can't be found. This is very useful when creating multiple models at the same time.
- `upstream_prod_prefer_recent` compares when the prod and dev relations were last modified and returns the most recent. **This is only available on Snowflake, Databricks & BigQuery.**
- `upstream_prod_disabled_targets` is used to bypass the package in certain environments. **It is highly recommended to disable the package for prod runs**.

```yml
# dbt_project.yml
vars:
  # Required
  upstream_prod_env_schemas: true
  # Optional, but recommended
  upstream_prod_fallback: true
  upstream_prod_prefer_recent: true
  upstream_prod_disabled_targets:
    - prod
```
</details>

<!-- B: no custom macro & same database -->
<details><summary>Setup B</summary>
<br/>

Add the values below to the `vars` section of `dbt_project.yml`. Some optional variables are included to improve your experience:
- `upstream_prod_fallback` tells the package to return your dev relation if the prod version can't be found. This is very useful when creating multiple models at the same time.
- `upstream_prod_prefer_recent` compares when the prod and dev relations were last modified and returns the most recent. **This is only available on Snowflake, Databricks & BigQuery.**
- `upstream_prod_disabled_targets` is used to bypass the package in certain environments. **It is highly recommended to disable the package for prod runs**.

```yml
# dbt_project.yml
vars:
  # Required
  upstream_prod_schema: <prod_schema_name/prefix>
  # Optional, but recommended
  upstream_prod_fallback: true
  upstream_prod_prefer_recent: true
  upstream_prod_disabled_targets:
    - prod
```
</details>

<!-- C: custom macro & different databases -->
<details><summary>Setup C</summary>
<br/>

Your custom schema macro needs two small tweaks to work with the package. As an example, the macro below shows how to adapt the [built-in `generate_schema_name_for_env` macro](https://github.com/dbt-labs/dbt-adapters/blob/6e765f58d1a15f7fcc15e504916543bd55bd62b7/dbt/include/global_project/macros/get_custom_name/get_custom_schema.sql#L47-L60):

```sql
-- 1. Add an is_upstream_prod parameter that defaults to False
{% macro generate_schema_name(custom_schema_name, node, is_upstream_prod=False) -%}

    {%- set default_schema = target.schema -%}
    -- 2. In the clause that generates your prod schema names, add a check that the value is True
    --    **Make sure to enclose the or condition in brackets**
    {%- if (target.name == "prod" or is_upstream_prod is true) and custom_schema_name is not none -%}

        {{ custom_schema_name | trim }}

    {%- else -%}

        {{ default_schema }}

    {%- endif -%}

{%- endmacro %}
```

<br/>

Add the values below to the `vars` section of `dbt_project.yml`. Some optional variables are included to improve your experience:
- `upstream_prod_fallback` tells the package to return your dev relation if the prod version can't be found. This is very useful when creating multiple models at the same time.
- `upstream_prod_prefer_recent` compares when the prod and dev relations were last modified and returns the most recent. **This is only available on Snowflake, Databricks & BigQuery.**
- `upstream_prod_disabled_targets` is used to bypass the package in certain environments. **It is highly recommended to disable the package for prod runs**.
- `upstream_prod_enabled_targets` is used to restrict the package to certain environments (if it is easier to identify the environments to enable instead).
- `upstream_prod_prefer_current_target` is used to always return current target environment relation no matter if the production version is fresher (as long as the target environment relation exists)
- `upstream_prod_row_count_limit_targets` is used to specify the list of environments to apply row count size limits
- `upstream_prod_row_count_size_target` is used to define the target size threshold to apply row count limit and retrieve a sample of the dataset.

```yml
# dbt_project.yml
vars:
  # Required
  upstream_prod_database: <prod_database_name>
  upstream_prod_env_schemas: true
  # Optional, but recommended
  upstream_prod_fallback: true
  upstream_prod_prefer_recent: true
  upstream_prod_disabled_targets:
    - prod
  upstream_prod_enabled_targets:
    - dev
    - ci
  upstream_prod_prefer_current_target: true
  upstream_prod_row_count_size_target: 100000
```

<details><summary><b>Using a custom database macro?</b></summary>
<br/>

There are two more steps if your project has a custom `generate_database_name` macro.

First, add `upstream_prod_env_dbs: true` to `dbt_project.yml`.

Then update your custom database macro in exactly the same way as your schema macro. For example:

```sql
-- 1. Add an is_upstream_prod parameter that defaults to False
{% macro generate_database_name(custom_database_name=none, node=none, is_upstream_prod=False) -%}

    {%- set default_database = target.database -%}
    -- 2. In the clause that generates your prod database names, add a check that the value is True
    --    **Make sure to enclose the or condition in brackets**
    {%- if (target.name == "prod" or is_upstream_prod is true) and custom_database_name is not none -%}

        {{ custom_database_name | trim }}

    {%- else -%}

        {{ default_database }}

    {%- endif -%}

{%- endmacro %}
```

</details>

</details>

<!-- D: no custom macro & different databases -->
<details><summary>Setup D</summary>
<br/>

Add the values below to the `vars` section of `dbt_project.yml`. Some optional variables are included to improve your experience:
- `upstream_prod_fallback` tells the package to return your dev relation if the prod version can't be found. This is very useful when creating multiple models at the same time.
- `upstream_prod_prefer_recent` compares when the prod and dev relations were last modified and returns the most recent. **This is only available on Snowflake, Databricks & BigQuery.**
- `upstream_prod_disabled_targets` is used to bypass the package in certain environments. **It is highly recommended to disable the package for prod runs**.

```yml
# dbt_project.yml
vars:
  # Required
  upstream_prod_database: <prod_database_name>
  upstream_prod_schema: <prod_schema_name/prefix>
  # Optional, but recommended
  upstream_prod_fallback: true
  upstream_prod_prefer_recent: true
  upstream_prod_disabled_targets:
    - prod
```

<details><summary><b>Using a custom database macro?</b></summary>
<br/>

There are two more steps if your project has a custom `generate_database_name` macro.

First, add `upstream_prod_env_dbs: true` to `dbt_project.yml`.

Your custom database macro now needs two small tweaks to work with the package, as shown in the example below:

```sql
-- 1. Add an is_upstream_prod parameter that defaults to False
{% macro generate_database_name(custom_database_name=none, node=none, is_upstream_prod=False) -%}

    {%- set default_database = target.database -%}
    -- 2. In the clause that generates your prod database names, add a check that the value is True
    --    **Make sure to enclose the or condition in brackets**
    {%- if (target.name == "prod" or is_upstream_prod is true) and custom_database_name is not none -%}

        {{ custom_database_name | trim }}

    {%- else -%}

        {{ default_database }}

    {%- endif -%}

{%- endmacro %}
```

</details>

</details>
<!-- END COLLAPSIBLE SECTIONS -->

### 4. Create a custom `ref()` macro

In your `macros` directory, create a file called `ref.sql` with the following contents:
```sql
{% macro ref(
    parent_arg_1,
    parent_arg_2=None, 
    prod_database=var("upstream_prod_database", None), 
    prod_schema=var("upstream_prod_schema", None),
    enabled=var("upstream_prod_enabled", True),
    fallback=var("upstream_prod_fallback", False),
    env_schemas=var("upstream_prod_env_schemas", False),
    version=None,
    prefer_recent=var("upstream_prod_prefer_recent", False),
    env_dbs=var("upstream_prod_env_dbs", False),
    prefer_current=var("upstream_prod_prefer_current_target", False),
    row_count_size_target=var("upstream_prod_row_count_size_target", 0),
    row_count_limit_targets=var("upstream_prod_row_count_limit_targets", None)
) %}

    {% do return(upstream_prod.ref(
        parent_arg_1, 
        parent_arg_2, 
        prod_database, 
        prod_schema, 
        enabled, 
        fallback, 
        env_schemas, 
        version, 
        prefer_recent, 
        env_dbs,
        prefer_current,
        row_count_size_target,
        row_count_limit_targets
    )) %}

{% endmacro %}
```

Alternatively, you can find any instances of `{{ ref() }}` in your project and replace them with `{{ upstream_prod.ref() }}`. This is suitable for testing the package but is not recommended for general use.

## How it works

Assume your project has an `events` model that depends on intermediate and staging layers. The simplified DAGs looks like this:

```mermaid
  graph LR
      source[(Source)]
      source -.-> prod_stg[stg_events]
      source ==> dev_stg[stg_events]
      
      subgraph prod
      prod_stg -.-> prod_int[int_events] -.-> prod_mart[events]
      end
      
      subgraph dev
      dev_stg ==> dev_int[int_events] ==> dev_mart[events]
      end
```

You want to change `int_events`, so you need a copy of `stg_events` in dev. This could be expensive and time-consuming to create from scratch, and it could slow down your development process considerably. Perhaps this model already exists from previous work, but is it up-to-date? If the model definition or underlying data has changed, your dev model may break in prod.

`upstream-prod` sovles this problem by intelligently redirecting `ref`s based on the selected models for the current run. Running `dbt build -s int_events+` would:

1. Create `dev.int_events` using data from `prod.stg_events`
2. Create `dev.events` on top of `dev.int_events`, since the package recognises that `int_events` has been selected
3. Run tests against `dev.int_events` and `dev.events`

Now that your dev models are using prod data, you DAG would look like this:
```mermaid
  graph LR
      source[(Source)]
      source ==> prod_stg[stg_events]
      source -.-> dev_stg[stg_events]
      
      subgraph prod
      prod_stg -.-> prod_int[int_events] -.-> prod_mart[events]
      end
      
      subgraph dev
      dev_stg ~~~ dev_int
      prod_stg ==> dev_int[int_events] ==> dev_mart[events]
      end
```

## Compatibility
`upstream-prod` is built and tested on Snowflake.
