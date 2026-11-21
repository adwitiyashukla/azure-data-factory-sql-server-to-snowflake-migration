variable "suffix" {
  type    = string
  default = "as"
}

variable "location" {
  type    = string
  default = "westus2"
}

variable "control_location" {
  type    = string
  default = "canadacentral"
}

variable "github_owner" {
  type    = string
  default = "adwitiyashukla"
}

variable "github_repo" {
  type    = string
  default = "azure-data-factory-sql-server-to-snowflake-migration"
}

variable "admin_object_id" {
  type = string
}

variable "admin_login" {
  type = string
}

variable "admin_ip" {
  type    = string
  default = ""
}

variable "alert_email" {
  type = string
}

variable "ci_principal_id" {
  type = string
}

variable "onprem_sql_password" {
  type      = string
  sensitive = true
}

variable "control_sku" {
  type    = string
  default = "GP_S_Gen5_1"
}

variable "log_daily_quota_gb" {
  type    = number
  default = 0.5
}

variable "secret_expiry" {
  type    = string
  default = "2027-09-30T00:00:00Z"
}
