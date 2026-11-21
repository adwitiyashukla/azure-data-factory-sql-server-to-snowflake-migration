# azure-data-factory-sql-server-to-snowflake-migration

Moves a SQL Server database that lives on my laptop into Snowflake through Azure, the way an on-prem to cloud migration runs. Azure Data Factory does the copying through a self-hosted integration runtime installed next to the database, lands Parquet in ADLS Gen2, and Snowflake pulls the files in and merges them. Every Azure resource comes from Terraform, and both the infrastructure and the factory deploy from GitHub Actions. The workflows log in to Azure with OIDC, so there is no cloud credential in the repo or in GitHub. The one GitHub secret is the SQL Server login password that Terraform writes into Key Vault.

## How it works

A control table in a small Azure SQL database lists the source tables, their key column, their watermark column and how many parallel copies each one gets. The parent pipeline reads that table and fans out three tables at a time. For each table the child pipeline looks up the newest watermark on the source, copies only the rows between the old and the new watermark into the lake as Parquet (split into key ranges so big tables copy in parallel), runs COPY INTO a staging table in Snowflake, merges into the core table on the key column, then writes the new watermark and the copy metrics back to the control database. The first run is a full load. Every run after that only moves what changed, and a table with no changes is skipped before any copy starts.

The source is a synthetic retail database (eight tables across sales, catalog and ops schemas) that a T-SQL generator fills to any scale. Rows are built from a hash of their own id, so the same scale always gives the same data, and a second procedure adds a day of new orders and updates so the incremental run has something to move.

## Full load

Scale 20 of the generator: 27,640,200 rows, 2.11 GB of table data in SQL Server 2025 Developer on an 8 GB laptop over home Wi-Fi. The whole parent run took 14 minutes 2 seconds. Measured from the control database and the factory's own activity output.

| Table | Rows | MB read | Copy seconds | MB per second | Parallel copies | Parquet MB written | Snowflake COPY plus MERGE seconds |
|---|---|---|---|---|---|---|---|
| sales.order_items | 10,000,000 | 743.9 | 236 | 3.28 | 4 | 306.1 | 36 |
| ops.inventory_movements | 6,000,000 | 310.1 | 185 | 2.79 | 4 | 247.4 | 34 |
| sales.orders | 4,000,000 | 469.7 | 189 | 2.66 | 4 | 213.5 | 49 |
| sales.payments | 4,000,000 | 333.8 | 191 | 2.97 | 4 | 171.8 | 49 |
| ops.shipments | 3,200,000 | 260.9 | 88 | 3.34 | 4 | 164.7 | 29 |
| sales.customers | 400,000 | 42.4 | 94 | 2.07 | 2 | 17.1 | 34 |
| catalog.products | 40,000 | 4.1 | 29 | 0.21 | 1 | 1.6 | 20 |
| ops.stores | 200 | 0.0 | 28 | 0.00 | 1 | 0.0 | 18 |

The copies ran 734 seconds of wall clock for 2.11 GB, 2.95 MB per second overall, and the laptop's Wi-Fi upload sat at about 4.4 MB per second while three tables were in flight, which is where the ceiling is. Every table came out of the merge with the same row count as the source, 27,640,200 rows inserted and 0 updated in Snowflake's load log.

## Incremental run

`EXEC sim.add_day` added 20,000 orders with their items, payments and shipments, bumped 4,000 customers up a loyalty tier and marked a third of the open shipments delivered: 291,941 changed rows across six tables. The second run of the same pipeline moved exactly those rows in 8 minutes 32 seconds, 24.3 MB read, and Snowflake's load log shows 138,035 rows inserted and 153,906 updated (orders 20,000 new and 42,845 updated, shipments 4,036 new and 107,061 delivered). products and stores had no new watermark and were skipped before any copy started. Most of those 8 minutes is fixed cost per table rather than data: the watermark lookup waits behind the copies already running on the single runtime node, and a Snowflake COPY plus MERGE takes 20 to 50 seconds whether it moves 4,000 rows or 10 million.

## Cost

Azure for Students subscription, priced from the Data Factory rate card against the measured run: about 60 activity runs and 0.3 hours of self-hosted data movement for the full load, which is under 10 cents, plus a serverless Azure SQL database that pauses itself after an hour and a Log Analytics workspace capped at 0.5 GB a day. The Snowflake side ran on an extra small warehouse that suspends after 60 seconds.

## Layout

```
infra/bootstrap     resource group, Terraform state storage, the identity GitHub Actions logs in with
infra               lake, factory, Key Vault, control database, Log Analytics, failure alert
adf                 factory definitions in the git format ADF Studio reads and writes
sql                 source schema and data generator, control schema, Snowflake setup, report query
.github/workflows   infra: fmt, validate, checkov, plan, gated apply. adf: validate, ARM export, gated deploy
```

checkov runs on every push. The 21 checks skipped in `.checkov.yaml` are the private endpoint, customer managed key, geo-redundancy and SQL auditing family, which do not fit a 100 dollar student subscription.

## Running it

1. Create the empty GitHub repo first and put its numeric id in `infra/bootstrap/main.tf`, since GitHub's OIDC subject now carries the account and repository ids. Log in with the Azure CLI, set `ARM_SUBSCRIPTION_ID`, and run `terraform apply` in `infra/bootstrap`. Copy the outputs into repository variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ADMIN_OBJECT_ID`, `CI_PRINCIPAL_ID`), add `ADMIN_LOGIN`, `ADMIN_IP`, `ALERT_EMAIL`, and the `ONPREM_SQL_PASSWORD` secret.
2. `terraform apply` in `infra`, locally or from the infra workflow with apply checked. The student subscription only allows a handful of regions and refused Azure SQL in West US 2, which is why the control server has its own `control_location` variable.
3. Run `sql/onprem_schema.sql` (it takes the reader password as a sqlcmd variable) and `sql/onprem_sim.sql` on the local SQL Server, then `EXEC sim.load_initial @scale = 20`.
4. Install the self-hosted integration runtime and a 64 bit JDK on the same machine (Parquet needs Java), and register the runtime with the key from `az datafactory integration-runtime list-auth-key`.
5. Run `sql/control_schema.sql` against the control database over Entra authentication, passing the factory's client id as `adf_client_id`. The script maps the managed identity to a database user by SID, so the server needs no Directory Readers role.
6. Run `sql/snowflake_setup.sql` in Snowflake with the public key from `terraform output snowflake_public_key` and a user delegation SAS for the lake container from `az storage container generate-sas --as-user`. Keys stay disabled on the storage account, and a user delegation SAS lives at most seven days, so it gets rotated with `ALTER STAGE`. A storage integration would be cleaner, but a student in a university tenant cannot grant the admin consent it needs.
7. Push, run the adf workflow with deploy checked, then trigger `pl_migrate_all`. Run `EXEC sim.add_day` on the source and trigger it again to see an incremental load.

`sql/report.sql` prints rows, megabytes, seconds and throughput per table and per run from the control database.
