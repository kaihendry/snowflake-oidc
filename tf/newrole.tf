# New provider that will use USERADMIN to create users, roles, and grants
provider "snowflake" {
  organization_name = local.organization_name
  account_name      = local.account_name
  user              = "TERRAFORM_SVC"
  role              = "USERADMIN"
  alias             = "useradmin"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(local.private_key_path)
}

# Create a new role using USERADMIN
resource "snowflake_account_role" "tf_role" {
  provider = snowflake.useradmin
  name     = "TF_DEMO_ROLE"
  comment  = "My Terraform role"
}

# Grant the new role to SYSADMIN (best practice)
resource "snowflake_grant_account_role" "grant_tf_role_to_sysadmin" {
  provider         = snowflake.useradmin
  role_name        = snowflake_account_role.tf_role.name
  parent_role_name = "SYSADMIN"
}

# Create a service user with OIDC authentication using SQL
# This must be done via SQL because the snowflake_user resource doesn't support TYPE=SERVICE with WORKLOAD_IDENTITY
resource "snowflake_execute" "create_service_user" {
  provider = snowflake.useradmin

  execute = <<-SQL
    CREATE OR REPLACE USER TF_DEMO_USER
    TYPE = SERVICE
    DEFAULT_WAREHOUSE = '${snowflake_warehouse.tf_warehouse.name}'
    DEFAULT_ROLE = '${snowflake_account_role.tf_role.name}'
    DEFAULT_NAMESPACE = '${snowflake_database.tf_db.name}.${snowflake_schema.tf_db_tf_schema.name}'
    WORKLOAD_IDENTITY = (
      TYPE = OIDC,
      ISSUER = 'https://token.actions.githubusercontent.com',
      SUBJECT = 'repo:kaihendry/snowflake-oidc:environment:test-env'
    )
  SQL

  revert = <<-SQL
    DROP USER IF EXISTS TF_DEMO_USER
  SQL

  depends_on = [
    snowflake_warehouse.tf_warehouse,
    snowflake_account_role.tf_role,
    snowflake_database.tf_db,
    snowflake_schema.tf_db_tf_schema
  ]
}

# Grant the new role to the new user
resource "snowflake_grant_account_role" "grants" {
  provider  = snowflake.useradmin
  role_name = snowflake_account_role.tf_role.name
  user_name = "TF_DEMO_USER"

  depends_on = [snowflake_execute.create_service_user]
}


# Grant usage on the warehouse
resource "snowflake_grant_privileges_to_account_role" "grant_usage_warehouse_to_tf_role" {
  provider          = snowflake.useradmin
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.tf_role.name
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.tf_warehouse.name
  }
}

# Grant usage on the database
resource "snowflake_grant_privileges_to_account_role" "grant_usage_tf_db_to_tf_role" {
  provider          = snowflake.useradmin
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.tf_role.name
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.tf_db.name
  }
}

# Grant usage on the schema
resource "snowflake_grant_privileges_to_account_role" "grant_usage_tf_db_tf_schema_to_tf_role" {
  provider          = snowflake.useradmin
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.tf_role.name
  on_schema {
    schema_name = snowflake_schema.tf_db_tf_schema.fully_qualified_name
  }
}

# Grant select on all tables in the schema (even if the schema is empty)
resource "snowflake_grant_privileges_to_account_role" "grant_all_tables" {
  provider          = snowflake.useradmin
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.tf_role.name
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.tf_db_tf_schema.fully_qualified_name
    }
  }
}

# Grant select on the future tables in the schema
resource "snowflake_grant_privileges_to_account_role" "grant_future_tables" {
  provider          = snowflake.useradmin
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.tf_role.name
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.tf_db_tf_schema.fully_qualified_name
    }
  }
}

# Output the OIDC configuration details for reference
output "oidc_issuer" {
  value = "https://token.actions.githubusercontent.com"
}

output "oidc_subject" {
  value       = "repo:kaihendry/snowman:environment:test-env"
  description = "GitHub OIDC subject for the service user. Update this to match your repository and environment."
}
