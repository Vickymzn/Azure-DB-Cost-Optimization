
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-billing-opt"
  location = "East US"
}

resource "random_string" "rand" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "archive_sa" {
  name                     = "archivestor${random_string.rand.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "archive_container" {
  name                  = "archived-records"
  storage_account_name  = azurerm_storage_account.archive_sa.name
  container_access_type = "private"
}

resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "billing-cosmos-${random_string.rand.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  consistency_policy {
    consistency_level = "Session"
  }
  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "billing_db" {
  name                = "billing"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

resource "azurerm_cosmosdb_sql_container" "billing_container" {
  name                = "records"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.billing_db.name
  partition_key_path  = "/id"
}

resource "azurerm_app_service_plan" "func_plan" {
  name                = "billing-func-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "FunctionApp"
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_linux_function_app" "archive_func" {
  name                       = "archive-func-${random_string.rand.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_app_service_plan.func_plan.id
  storage_account_name       = azurerm_storage_account.archive_sa.name
  storage_account_access_key = azurerm_storage_account.archive_sa.primary_access_key
  functions_extension_version = "~4"
  site_config {
    application_stack {
      python_version = "3.11"
    }
  }
  app_settings = {
    COSMOS_URI        = azurerm_cosmosdb_account.cosmos.endpoint
    COSMOS_KEY        = azurerm_cosmosdb_account.cosmos.primary_key
    COSMOS_DB_NAME    = azurerm_cosmosdb_sql_database.billing_db.name
    COSMOS_CONTAINER  = azurerm_cosmosdb_sql_container.billing_container.name
    BLOB_CONTAINER    = azurerm_storage_container.archive_container.name
    BLOB_ACCOUNT_NAME = azurerm_storage_account.archive_sa.name
    ARCHIVE_DAYS      = "90"
  }
}
