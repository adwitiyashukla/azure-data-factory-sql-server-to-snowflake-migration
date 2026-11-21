# azure-data-factory-sql-server-to-snowflake-migration

Moves a SQL Server database that lives on my laptop into Snowflake through Azure, the way an on-prem to cloud migration runs. Azure Data Factory does the copying through a self-hosted integration runtime installed next to the database, lands Parquet in ADLS Gen2, and Snowflake pulls the files in and merges them. Every Azure resource comes from Terraform, and both the infrastructure and the factory deploy from GitHub Actions through OIDC, so there is no cloud secret stored in the repo or in GitHub.

## How it works

A control table in a small Azure SQL database lists the source tables, their key column, their watermark column and how many parallel copies each one gets. The parent pipeline reads that table and fans out. For each table the child pipeline looks up the newest watermark on the source, copies only the rows between the old and the new watermark into the lake as Parquet (split into key ranges so big tables copy in parallel), runs COPY INTO a staging table in Snowflake, merges into the core table, then writes the new watermark and the copy metrics back to the control database. The first run is a full load. Every run after that only moves what changed.

## Layout

```
infra/bootstrap     resource group, Terraform state storage, the identity GitHub Actions logs in with
infra               lake, factory, Key Vault, control database, Log Analytics, failure alert
adf                 factory definitions in the git format ADF Studio reads and writes
sql                 source schema and data generator, control schema, Snowflake setup, report query
.github/workflows   infra: fmt, validate, checkov, plan, gated apply. adf: validate, ARM export, gated deploy
```

## Running it

1. Log in with the Azure CLI, set `ARM_SUBSCRIPTION_ID`, and run `terraform apply` in `infra/bootstrap` once. Copy the outputs into GitHub repository variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ADMIN_OBJECT_ID`, `CI_PRINCIPAL_ID`) and add `ADMIN_LOGIN`, `ADMIN_IP`, `ALERT_EMAIL` plus the `ONPREM_SQL_PASSWORD` secret.
2. `terraform apply` in `infra`, locally or from the infra workflow with apply checked.
3. Run `sql/onprem_schema.sql` and `sql/onprem_sim.sql` on the local SQL Server, then `EXEC sim.load_initial @scale = 20`.
4. Install the self-hosted integration runtime and a 64 bit OpenJDK on the same machine and register the runtime with the key from `az datafactory integration-runtime list-auth-key`.
5. Run `sql/control_schema.sql` against the control database with the factory's client id, and `sql/snowflake_setup.sql` in Snowflake with the public key from `terraform output snowflake_public_key`.
6. Put the Snowflake account identifier into `adf/linkedService/ls_snowflake.json`, push, and run the adf workflow with deploy checked.
7. Trigger `pl_migrate_all`. Run `EXEC sim.add_day` on the source and trigger it again to see an incremental load.

`sql/report.sql` prints rows, megabytes, seconds and throughput per table and per run from the control database.
