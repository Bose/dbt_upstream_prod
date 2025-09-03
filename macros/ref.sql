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
    {{ return(adapter.dispatch("ref", "upstream_prod")(
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
    )) }}
{% endmacro %}

{% macro default__ref(
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
) %}
    /***************
    Handle two-argument refs

    For packages, the project name is the name of the package, e.g. model.facebook_ads.facebook_ads__account_report,
    so we can't simply use the user's project name when one isn't supplied. Instead we will match on just the model
    name - not project + model name - when only one arg (the model name) is supplied.
    ***************/
    {% if parent_arg_2 is none %}
        {% set parent_project = None %}
        {% set parent_model = parent_arg_1 %}
        {% set parent_ref = builtins.ref(parent_model, version=version) %}
    {% else %}
        {% set parent_project = parent_arg_1 %}
        {% set parent_model = parent_arg_2 %}
        {% set parent_ref = builtins.ref(parent_project, parent_model, version=version) %}
    {% endif %}
    {% set current_model = this.name if this is defined else "unknown model" %}

    -- Return builtin ref for ephemeral models, during parsing or when disabled
    {% if execute is false
        or enabled is false
        or parent_ref.is_cte
        or target.name in var("upstream_prod_disabled_targets", [])
        or target.name not in var("upstream_prod_enabled_targets", [])
    %}
        {{ return(parent_ref) }}
    {% endif %}

    -- Raise error if at least one required variable is not set
    {{ upstream_prod.check_reqd_vars(prod_database, prod_schema, env_schemas, env_dbs) }}

    {% set selected = upstream_prod.find_selected_nodes(parent_model, parent_project) %}
    -- Use dev relations for models being built during the current run
    {% if parent_model in selected %}
        {{ return(parent_ref) }}
    -- Find prod version of parent ref
    {% else %}
        {% set parent_node = upstream_prod.find_model_node(parent_model, parent_project, version) %}
        
        -- Set prod schema name
        {% if parent_node.resource_type == "snapshot" and parent_node.config.target_schema is not none %}
            -- When target_schema is set the schema name is the same regardless of the environment.
            -- It is optional as of dbt v1.9. If it isn't set, the generate_schema_name macro is used
            -- in the same way as for models.
            {% set parent_schema = parent_node.schema %}
        {% elif env_schemas is true %}
            -- Schema generated with custom macro
            {% set custom_schema_name = parent_node.config.schema %}
            {% set parent_schema = generate_schema_name(custom_schema_name, parent_node, True) | trim %}
        {% elif prod_schema is none %}
            -- No prod_schema = one-DB-per-env setup with same schema structure in all
            {% set parent_schema = parent_ref.schema %}
        {% else %}
            -- Schema structure is <env>[_<level>], e.g. prod, prod_stg or dev_int 
            {% set parent_schema = parent_ref.schema | replace(target.schema, prod_schema) %}
        {% endif %}

        -- Set prod database name
        {% if env_dbs is true %}
            -- Database generated with custom macro
            {% set parent_database = generate_database_name(prod_database, parent_node, True) | trim %}
        {% else %}
            {% set parent_database = prod_database or parent_ref.database %}
        {% endif %}

        /***************
        Check whether the relations have been materialised in both envs
        
        prod_rel_name helps the package find the correct prod relation for projects using a custom 
        generate_alias_name macro. It assumes that custom aliases are only used in dev envs and prod
        relations always have the same name as the model (+ version suffix when needed).
        It's hacky but it seems to work. 
        ***************/
        {% set re = modules.re %}
        {% set prod_rel_name = re.search("\w+(?=\.)", parent_node.path).group() %}
        {% set prod_rel = adapter.get_relation(parent_database, parent_schema, prod_rel_name) %}
        {% set dev_rel = load_relation(parent_ref) %}
        {% set prod_exists = prod_rel is not none %}
        {% set dev_exists = dev_rel is not none %}

        -- Default to returning the prod relation, but override in the circumstances outlined below
        {% set return_rel = prod_rel %}

        {% if prod_exists is true %}
            -- When option enabled, return the mostly recently updated of dev & prod relations
            {% if prefer_recent is true and dev_exists is true %}
                -- Find when dev & prod relations were last updated
                {% set dev_updated = upstream_prod.get_table_update_ts(dev_rel) %}
                {% set prod_updated = upstream_prod.get_table_update_ts(prod_rel) %}
                -- Return dev relation if it exists and is fresher than prod
                {% if dev_updated > prod_updated %}
                    {{ log("[" ~ current_model ~ "] " ~ parent_ref.table ~ " fresher in " ~ target.name ~ " than prod, switching to " ~ target.name ~ " relation", info=True) }}
                    {% set return_rel = dev_rel %}
                {% endif %}
            {% elif dev_exists is true and prefer_current is true %}
                {{ log("[" ~ current_model ~ "] " ~ parent_ref.table ~ " model exists in " ~ target.name ~ ", switching to " ~ target.name ~ " relation", info=True) }}
                {% set return_rel = dev_rel %}
            {% endif %}
        {% elif dev_exists %}
            -- Return dev relation if prod doesn't exist & fallback is enabled
            {% if fallback is true %}
                {{ log("[" ~ current_model ~ "] " ~ parent_ref.table ~ " model exists in " ~ target.name ~ ", switching to " ~ target.name ~ " relation", info=True) }}
                {% set return_rel = dev_rel %}
            {% else %}
                {{ upstream_prod.raise_ref_not_found_error(current_model, parent_ref.database, parent_ref.schema, parent_ref.identifier) }}
            {% endif %}
        {% else %}
            {{ upstream_prod.raise_ref_not_found_error(current_model, parent_database, parent_schema, prod_rel_name) }}
        {% endif %}

        -- Adjust output if --empty flag was used
        {% if flags.EMPTY %}
            {{ return("(select * from " ~ return_rel ~ " where false limit 0)") }}
        {% else %}
            {% set row_count = upstream_prod.get_total_row_count(return_rel, parent_ref.table) %}
            -- Only sample if table is larger than row_count_size_target and target environment is in row_count_limit_targets variable
            {%- if row_count > row_count_size_target and target.name in row_count_limit_targets -%}
                {%- set pct = 100.0 * row_count_size_target / row_count -%}
                {%- set sample_percentage = [pct, 0.001]|max | round(2) -%}
                -- If relation is a view, use Bernoulli sampling because System sampling is not supported by views
                -- 
                {%- if return_rel.is_view -%}
                    {%- set return_rel = "(" ~ return_rel ~ " SAMPLE ROW (" ~ sample_percentage ~ ") SEED(1) )" -%}
                {% else %}
                    {%- set return_rel = "(" ~ return_rel ~ " SAMPLE BLOCK (" ~ sample_percentage ~ ") SEED(1) )" -%}
                {% endif %}
            {% endif %}
            {{ return(return_rel) }}
        {% endif %}

    {% endif %}
{% endmacro %}