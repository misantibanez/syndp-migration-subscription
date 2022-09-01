$TenantId = ‘<tenant-id>’

#source
$SourceSubscriptionId = ‘<source-subscription-id>’
$SourceResourceGroupName = "<source-rg-name>"
$SourceServerName = "sql-hubdatos-corp-prod"
$SourceDatabaseName = "<source-db-name>"
$SourceLocation = "<source-location>"
$SourceStorage = "<source-storage-name>"
$SourceStorgeSAS = "<source-SAS-token>"
$SourceStorageAccountKey = "<source-storage-account-key>"

#destination
$DestinationSubscriptionId = ‘<target-subscription-id>’
$DestinationLocation = "<target-location>"
$TargetResourceGroupName = "<target-rg-name>"
$TargetWorkspaceName = "<target-ws-name>"
$TargetStorageName = "<target-storage-name>"
$TargetStorageSAS = "<target-SAS-token>"
$TargetStorageAccountKey = "<target-storage-account-key>"

#generales
$AdminLogin = "<admin-user-name>"
$Password = "<admin-user-pwd>"
$Startip = "0.0.0.0"
$Endip = "255.255.255.255"
$ContainerName = "<container-name>"

Connect-AzAccount -TenantId $TenantId

Set-AzContext -SubscriptionId $DestinationSubscriptionId
New-AzResourceGroup -Name $TargetResourceGroupName -Location $DestinationLocation

$password = ConvertTo-SecureString $Password -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ($AdminLogin, $password)

#crear storage account
New-AzStorageAccount -ResourceGroupName $TargetResourceGroupName `
  -Name $TargetStorageName `
  -Location $DestinationLocation `
  -SkuName Standard_LRS `
  -Kind StorageV2 `
  -EnableHierarchicalNamespace $True

$ctx = New-AzStorageContext -StorageAccountName $TargetStorageName -StorageAccountKey $TargetStorageAccountKey

azcopy cp $SourceStorgeSAS $TargetStorageSAS --recursive --log-level=INFO;

#crear synapse workspace
New-AzSynapseWorkspace -ResourceGroupName $TargetResourceGroupName `
    -Name $TargetWorkspaceName  `
    -Location $DestinationLocation `
    -DefaultDataLakeStorageAccountName $TargetStorageName `
    -DefaultDataLakeStorageFilesystem $ContainerName `
    -SqlAdministratorLoginCredential $creds 

#mover datos del storage anterior al nuevo

Set-AzContext -SubscriptionId $SourceSubscriptionId

New-AzSqlDatabaseRestorePoint -ResourceGroupName $SourceResourceGroupName -ServerName $SourceServerName `
    -DatabaseName $SourceDatabaseName -RestorePointLabel "UserDefined-01"

#Mover recurso a otra subscription (se requiere modificar en parámetros los datos del recurso)
Invoke-AzResourceAction -Action validateMoveResources `
-ResourceId "/subscriptions/$SourceSubscriptionId/resourceGroups/$SourceResourceGroupName" `
-Parameters @{ resources= @("/subscriptions/$SourceSubscriptionId/resourceGroups/$SourceResourceGroupName/providers/Microsoft.Sql/servers/$SourceServerName");targetResourceGroup = "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>"}

$server = Get-AzResource -ResourceGroupName $SourceResourceGroupName -ResourceName $SourceServerName -ResourceType 'Microsoft.Sql/servers'
Move-AzResource -DestinationSubscriptionId $DestinationSubscriptionId -DestinationResourceGroupName $TargetResourceGroupName -ResourceId $server.ResourceId