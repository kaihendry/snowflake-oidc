terraform {
  required_providers {
    snowflake = {
      source = "snowflakedb/snowflake"
    }
  }
}

locals {
  organization_name = "xbjfxng"
  account_name      = "qm18685"
  private_key_path  = "../keys/snowflake_tf_snow_key.p8"
}

provider "snowflake" {
  organization_name = local.organization_name
  account_name      = local.account_name
  user              = "TERRAFORM_SVC"
  role              = "SYSADMIN"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(local.private_key_path)
}

resource "snowflake_database" "tf_db" {
  name         = "TF_DEMO_DB"
  is_transient = false
}

resource "snowflake_warehouse" "tf_warehouse" {
  name                      = "TF_DEMO_WH"
  warehouse_type            = "STANDARD"
  warehouse_size            = "SMALL"
  max_cluster_count         = 1
  min_cluster_count         = 1
  auto_suspend              = 60
  auto_resume               = true
  enable_query_acceleration = false
  initially_suspended       = true
}

# Create a new schema in the DB
resource "snowflake_schema" "tf_db_tf_schema" {
  name                = "TF_DEMO_SC"
  database            = snowflake_database.tf_db.name
  with_managed_access = false
}
