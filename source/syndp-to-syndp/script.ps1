$TenantId = ‘<tenant-id>’

#source
$SourceSubscriptionId = ‘<source-subscription-id>’
$SourceResourceGroupName = "<source-rg-name>"
$SourceWorkspaceName = "<source-ws-name>"
$SourceDatabaseName = "<source-db-name>"
$SourceLocation = "<source-location>"
$SourceStorage = "<source-storage-name>"
$SourceStorageURL = 'https://'+$SourceStorage+'.dfs.core.windows.net/'

#destination
$DestinationSubscriptionId = ‘<target-subscription-id>’
$DestinationLocation = "<target-location>"
$TargetResourceGroupName = "<target-rg-name>"
$TargetWorkspaceName = "<target-ws-name>"
$TargetDatabaseName = "<target-db-name>"
$TargetStorageName = "<target-storage-name>"
$TargetServerName = "<target-server-name>"
$TargetStorageURL = 'https://'+$TargetStorageName+'.dfs.core.windows.net/'


#generales
$AdminLogin = "<admin-user-name>"
$Password = "<admin-user-pwd>"
$Startip = "0.0.0.0"
$Endip = "255.255.255.255"
$ContainerName = "<container-name>"
$RestorePointLabel = "<restore-point-name>"
$ServiceObjectiveName = "<service-level>"

Connect-AzAccount -TenantId $TenantId
Set-AzContext -SubscriptionId $SourceSubscriptionId

$password = ConvertTo-SecureString $Password -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ($AdminLogin, $password)

#Crear un punto de restauracion del SQL Pool Dedicado
New-AzSynapseSqlPoolRestorePoint -WorkspaceName $SourceWorkspaceName -Name $SourceDatabaseName `
    -RestorePointLabel $RestorePointLabel
    
$Database = Get-AzSynapseSqlPool -ResourceGroupName $SourceResourceGroupName -WorkspaceName $SourceWorkspaceName `
    -Name $SourceDatabaseName

$RestorePoint = $Database | Get-AzSynapseSqlPoolRestorePoint | Select -Last 1

#Instancia la suscripcion donde se requiere migrar
Set-AzContext -SubscriptionId $DestinationSubscriptionId

#Crear el grupo de recursos definido

$validateRG = Get-AzResourceGroup -Name $TargetResourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue

if (!$validateRG)
{
    New-AzResourceGroup -Name $TargetResourceGroupName -Location $DestinationLocation
}else
{
    Write-Host "$TargetResourceGroupName already exist"
}

#Crear SQL Server para restaurar el SQL Pool a migrar

$validateSQLServer = Get-AzureRmSqlServer -ServerName $TargetServerName -ResourceGroupName $TargetResourceGroupName -ErrorAction SilentlyContinue

if (!$validateSQLServer)
{
New-AzSqlServer -ResourceGroupName $TargetResourceGroupName `
    -ServerName $TargetServerName `
    -Location $DestinationLocation `
    -SqlAdministratorCredentials $(New-Object -TypeName System.Management.Automation.PSCredential `
    -ArgumentList $AdminLogin, $(ConvertTo-SecureString -String $Password -AsPlainText -Force))

New-AzSqlServerFirewallRule -ResourceGroupName $TargetResourceGroupName `
    -ServerName $TargetServerName `
    -FirewallRuleName "AllowSome" -StartIpAddress $Startip -EndIpAddress $Endip
}else
{
    Write-Host "$TargetServerName already exist"
}

#Realizar la restauracion en el Server
$PointInTime = $RestorePoint.RestorePointCreationDate  

$DatabaseID = $Database.Id -replace "Microsoft.Synapse", "Microsoft.Sql" `
	-replace "workspaces", "servers" `
	-replace "sqlPools", "databases"

$RestoredDatabase = Restore-AzSqlDatabase -FromPointInTimeBackup -PointInTime $PointInTime `
    -ResourceGroupName $TargetResourceGroupName `
    -ServerName $TargetServerName -TargetDatabaseName $TargetDatabaseName `
    -ResourceId $DatabaseID -Edition "DataWarehouse" `
    -ServiceObjectiveName $ServiceObjectiveName

#Crear un punto de restauracion de la base de datos en el Server
New-AzSqlDatabaseRestorePoint -ResourceGroupName $RestoredDatabase.ResourceGroupName -ServerName $RestoredDatabase.ServerName `
    -DatabaseName $RestoredDatabase.DatabaseName -RestorePointLabel $RestorePointLabel

$RestorePoint = Get-AzSqlDatabaseRestorePoint -ResourceGroupName $RestoredDatabase.ResourceGroupName -ServerName $RestoredDatabase.ServerName `
    -DatabaseName $RestoredDatabase.DatabaseName | Select -Last 1

#Crear el Storage Account en la suscripcion donde se va a migrar SQL Pool
$validateStorage = Get-AzStorageAccount -Name $TargetStorageName -ResourceGroupName $TargetResourceGroupName -ErrorAction SilentlyContinue

if(!$validateStorage)
{
    New-AzStorageAccount -ResourceGroupName $TargetResourceGroupName `
    -Name $TargetStorageName `
    -Location $DestinationLocation `
    -SkuName Standard_LRS `
    -Kind StorageV2 `
    -EnableHierarchicalNamespace $True

    $SourceContext = (Get-AzStorageAccount -ResourceGroupName $SourceResourceGroupName -AccountName $SourceStorage).context
    $TargetContext = (Get-AzStorageAccount -ResourceGroupName $TargetResourceGroupName -AccountName $TargetStorageName).context
    $SourceStorageSAS = $SourceStorageURL+(New-AzStorageAccountSASToken -Context $SourceContext -Service Blob,File,Table,Queue -ResourceType Service,Container,Object -Permission racwdlup)
    $TargetStorageSAS = $TargetStorageURL+(New-AzStorageAccountSASToken -Context $TargetContext -Service Blob,File,Table,Queue -ResourceType Service,Container,Object -Permission racwdlup)

    azcopy cp $SourceStorageSAS $TargetStorageSAS --recursive --log-level=INFO;

}else{
    Write-Host "$TargetStorageName already exist"
}

#Crear el Synapse Workspace en la suscripcion donde se va a migrar SQL Pool
$validateSynapseWorkspace = Test-AzSynapseWorkspace -Name $TargetWorkspaceName
if (!$validateSynapseWorkspace)
{
   #crear synapse workspace
   New-AzSynapseWorkspace -ResourceGroupName $TargetResourceGroupName `
    -Name $TargetWorkspaceName  `
    -Location $DestinationLocation `
    -DefaultDataLakeStorageAccountName $TargetStorageName `
    -DefaultDataLakeStorageFilesystem $ContainerName `
    -SqlAdministratorLoginCredential $creds 
}else{
    Write-Host "$TargetWorkspaceName already exist"
}

#Realizar la restauracion en el Synapse Workspace
$FinalRestore = Restore-AzSynapseSqlPool –FromRestorePoint -RestorePoint $RestorePoint.RestorePointCreationDate -ResourceGroupName $TargetResourceGroupName `
    -WorkspaceName $TargetWorkspaceName -TargetSqlPoolName $TargetDatabaseName –ResourceId $RestoredDatabase.ResourceID -PerformanceLevel DW100c

echo "Migracion Finalizada"