# Intro
Syndp-migration-subscription has the intent to automate migration of Synapse SQL Dedicated Pool between subscriptions.

# Scenario
Migrating the SQL Pool service to a new subscription that is in the same tenant is required. Likewise, it is required to create the Synapse Workspace in the new subscription.

# Dependencies
It is required to validate the storage account/container to which the current Synapse Workspace is configured.

# Solution
To do this, the following steps are required:

1. Generate a restore point of the SQL Pool to migrate
2. Create a SQL Server in the new subscription
3. Restore the restore point on the SQL Server created in the new subscription
4. Generate a SQL Server restore point in the new subscription
5. Restore the restore point in the Synapse Workspace that is in the new subscription.

# Architecture

[WIP]

# Proposed Source
In the "source" folder, you will find the script developed to automate the process.
Among the prerequisites we have:

Definition of the nomenclature of services
Firewall rule definitions (default and public rules were considered)
Access Credential Definitions
The script is responsible for performing the relevant validations regarding the existence of the services.

Likewise, the script is responsible for copying the data from the source storage to the destination.

# Reference Links
- https://docs.microsoft.com/en-us/azure/synapse-analytics/backuprestore/restore-sql-pool 
- https://docs.microsoft.com/en-us/powershell/module/az.synapse/test-azsynapseworkspace?view=azps-7.5.0 
