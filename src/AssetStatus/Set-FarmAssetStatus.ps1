#Requires -Module OperationsManager

<#
    .SYNOPSIS
        Set the asset status on a SharePoint farm.

    .DESCRIPTION
        Set the asset status on a SharePoint farm including the SQL Server(s)
        and related cluster objects. This is used to move monitoring objects
        into and out of production.

    .PARAMETER FarmConfigDatabaseName
        The name of the SharePoint farm configuration database.

    .PARAMETER Status
        The status to apply to the farm. A status of "Deployed" puts it into
        production. Any other status pulls it out of production.

    .PARAMETER ScomManagementComputer
        The name of a SCOM management server.

    .EXAMPLE
        .\Set-FarmAssetStatus.ps1 -FarmConfigDatabaseName HR_Config -Status Deployed -Verbose

        Mark the HR farm as Deployed which will place it into production.
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $FarmConfigDatabaseName,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'Deployed',
        'DeploymentRequested',
        'Disposed',
        'Purchased',
        'PurchaseRequested',
        'Retired',
        'Undefined'
    )]
    [System.String]
    $Status,

    [Parameter()]
    [System.String]
    $ScomManagementComputer
)

<#
    Define an array which maps SQL versions to SharePoint versions

    - SQL 2008 and SP 2010
    - SQL 2012 and SP 2013
    - SQL 2014 and SP 2013
    - SQL 2016 and SP 2016
    - SQL 2017 and SP 2016
    - SQL 2017 and SP 2019
    - SQL 2019 and SP ?
#>
$sqlToSharePointVersionMap = @()
$sqlToSharePointVersionMap += New-Object -TypeName PSObject -Property @{ SqlVersion = 10; SharePointVersion = 2010 }
$sqlToSharePointVersionMap += New-Object -TypeName PSObject -Property @{ SqlVersion = 11; SharePointVersion = 2013 }
$sqlToSharePointVersionMap += New-Object -TypeName PSObject -Property @{ SqlVersion = 12; SharePointVersion = 2013 }
$sqlToSharePointVersionMap += New-Object -TypeName PSObject -Property @{ SqlVersion = 13; SharePointVersion = 2016 }
$sqlToSharePointVersionMap += New-Object -TypeName PSObject -Property @{ SqlVersion = 14; SharePointVersion = 2016 }
$sqlToSharePointVersionMap += New-Object -TypeName PSObject -Property @{ SqlVersion = 14; SharePointVersion = 2019 }
$sqlToSharePointVersionMap += New-Object -TypeName PSObject -Property @{ SqlVersion = 15; SharePointVersion = $null }

# Create an array to store the monitoring objects
$monitoringObjects = @()

if ( $scomManagementComputer )
{
    # Connect to the SCOM management group
    New-SCOMManagementGroupConnection -ComputerName $ScomManagementComputer
}

# Get the management pack object of the desired management pack
$managementPack = Get-SCOMManagementPack -Name System.Library

# Get the enum
$enum = $managementPack.GetEnumeration("System.ConfigItem.AssetStatusEnum.$Status")

Write-Verbose -Message "The asset status ID for '$Status' is $($enum.Id)"

#region SharePointFarm

# Define the sharepoint farm classes
$sharepointClassNames = @(
    'Microsoft.SharePoint.Foundation.2010.SPFarm'    # SharePoint 2010
    'Microsoft.SharePoint.2013.SPFarm'               # SharePoint 2013
    'Microsoft.SharePoint.Library.SPFarm'            # SharePoint 2016 and 2019
)

# Get the SharePoint farm monitoring objects
$farms = Get-SCOMClass -Name $sharepointClassNames |
    Get-SCOMClassInstance |
    Where-Object -FilterScript { $_.DisplayName -eq $FarmConfigDatabaseName }

# If no farms were found
if ( ( $farms | Measure-Object ).Count -eq 0 )
{
    throw "No farms found with the database name '$FarmConfigDatabaseName'"
}

# If multiple farms are found with the same name
if ( ( $farms | Measure-Object ).Count -gt 1 )
{
    Write-Verbose -Message 'Multiple farms were found with the specified name.'
    
    # Prompt the user to select a farm
    $selectedfarm = $farms |
        Select-Object -Property DisplayName,@{n='Version';e={ ( Get-SCOMClass -Id $_.LeastDerivedNonAbstractManagementPackClassId.Guid ).DisplayName }},Id |
        Out-GridView -Title 'Select the desired farm' -OutputMode Single

    if ( ( $selectedfarm | Measure-Object ).Count -eq 0 )
    {
        throw 'No farms were selected.'
    }

    # Get the farm object from the selected farm
    $farms = $farms | Where-Object -FilterScript { $_.Id.Guid -eq $selectedfarm.Id.Guid }
}

# Add the farm monitoring object to the monitoring objects array
$monitoringObjects += $farms

# Get the class of the farm object
$spFarmClass = Get-SCOMClass -Id $farms.LeastDerivedNonAbstractManagementPackClassId.Guid

#endregion SharePointFarm

#region SharePointServers

# Generate the SPServer class name
$spServerClassName = $spFarmClass.Name.Replace('SPFarm','SPServer')

# Get the SPServer class object
$spServerClass = Get-SCOMClass -Name $spServerClassName

# Get the SPServer objects
$spServerObjects = $farms.GetRelatedMonitoringObjects($spServerClass,'Recursive')

# Get the related windows computer objects
$spComputerObjects = $spServerObjects |
    ForEach-Object -Process { $_.GetParentMonitoringObjects() } |
    Where-Object -FilterScript { ( Get-SCOMClass -Id $_.LeastDerivedNonAbstractManagementPackClassId ).Name -eq 'Microsoft.Windows.Computer' }

# Add the windows computer objects to the monitoring objects array
$monitoringObjects += Get-SCOMMonitoringObject -Name $spComputerObjects.Name

#endregion SharePointServers

#region WebApplicationTransactionMonitoring

# Get the related web application objects
$webApplicationTransactionMonitoringObjects = $spComputerObjects |
    ForEach-Object -Process { $_.GetRelatedMonitoringObjects() } |
    Where-Object -FilterScript { $_.FullName -match '^WebApplication_' }

# Add the web application transaction monitoring objects to the monitoring objects array
$monitoringObjects += Get-SCOMMonitoringObject -Id $webApplicationTransactionMonitoringObjects.Id

#endregion WebApplicationTransactionMonitoring

#region SQLServers

# Define the SQL Server DBEngine classes
$sqlDbEngineClassNames = @(
    'Microsoft.SQLServer.DBEngine'            # Old management packs
    'Microsoft.SQLServer.Windows.DBEngine'    # Version-agnostic management pack
)

# Define the SQL Server Database classes
$sqlDatabaseClassNames = @(
    'Microsoft.SQLServer.Database'            # Old management packs
    'Microsoft.SQLServer.Windows.Database'    # Version-agnostic management pack
)

# Generate the SPConfiguration class name
$spConfigurationClassName = $spFarmClass.Name.Replace('SPFarm','SPConfiguration')

# Get the SPConfiguration class object
$spConfigurationClass = Get-SCOMClass -Name $spConfigurationClassName

# Get the SPConfiguration object
$spConfigurationObject = $farms.GetRelatedMonitoringObjects($spConfigurationClass)

<#
    Get the server name where the database is hosted.
    SharePoint can use aliases on the SharePoint servers, so the server or
    instance name may not be exactly the same.
#>
$configServer = $spConfigurationObject.Values |
    Where-Object -FilterScript { $_.Type.Name -eq 'Server' } |
    Select-Object -ExpandProperty Value

# Get the database engine object
$dbEngineObject = Get-SCOMClass -Name $sqlDbEngineClassNames |
    Get-SCOMClassInstance | 
    Where-Object -FilterScript { $_.DisplayName -match $configServer }

# If nothing was found
if ( $dbEngineObject.Count -eq 0 )
{
    # Determine the version of the SharePoint farm
    if ( $spFarmClass.DisplayName -match '^SharePoint ([\d]*) Farm$' )
    {
        $farmVersion = [System.Int32]::Parse($Matches[1])
    }
    else
    {
        $farmVersion = 2010
    }

    # Get the database objects
    $databaseObjects = Get-SCOMClass -Name $sqlDatabaseClassNames |
        Get-SCOMClassInstance |
        Where-Object -FilterScript { $_.DisplayName -eq $farms.DisplayName }
  
    foreach ( $databaseObject in $databaseObjects )
    {
        # Get the database engine object the config database is part of
        $dbEngineObject = $databaseObject.GetParentMonitoringObjects() |
            Where-Object -FilterScript { ( Get-SCOMClass -Id $_.LeastDerivedNonAbstractManagementPackClassId.Guid ).Name -in $sqlDbEngineClassNames }

        # Get the version of the database engine
        $dbEngineMajorVersion = $dbEngineObject.Values |
            Where-Object -FilterScript { $_.Type.Name -eq 'Version' } |
            ForEach-Object -Process { [System.Int32]::Parse($_.Value.Split('.')[0]) }
        
        # Determine what the correct SQL and SharePoint version mapping is
        $dbVersionMatch = $sqlToSharePointVersionMap |
            Where-Object -FilterScript { $_.SqlVersion -eq $dbEngineMajorVersion } |
            Where-Object -FilterScript { $_.SharePointVersion -eq $farmVersion }

        # If a match was found
        if ( $dbVersionMatch )
        {
            break
        }
    }
}

# Get the related windows computer objects
$dbComputerObjects = $dbEngineObject |
    ForEach-Object -Process { $_.GetParentMonitoringObjects() } |
    Where-Object -FilterScript { ( Get-SCOMClass -Id $_.LeastDerivedNonAbstractManagementPackClassId ).Name -eq 'Microsoft.Windows.Computer' }

# Add the windows computer objects to the monitoring objects array
$monitoringObjects += Get-SCOMMonitoringObject -Name $dbComputerObjects

# Get the cluster shared volume monitoring class
$clusterSharedVolumeClass = Get-SCOMClass -Name Microsoft.Windows.Server.ClusterSharedVolumeMonitoring.Cluster

# Find related objects which indicate this instance is part of a Failover Cluster
$clusterSharedVolumeMonitoringObject = $dbComputerObjects.GetRelatedMonitoringObjects($clusterSharedVolumeClass)

if ( $clusterSharedVolumeMonitoringObject )
{
    # Get the name of the cluster
    $clusterName = $clusterSharedVolumeMonitoringObject.Values |
        Where-Object -FilterScript { $_.Type.Name -eq 'ClusterName' } |
        Select-Object -ExpandProperty Value
    
    # Get the Windows computer class
    $windowsComputerClass = Get-SCOMClass -Name Microsoft.Windows.Computer

    # Get the cluster computer object and add it to the monitoring objects
    $clusterComputerObject = $windowsComputerClass |
        Get-SCOMClassInstance |
        Where-Object -FilterScript { $_.DisplayName -match $clusterName }

    # Add the cluster computer object to the monitoring objects array
    $monitoringObjects += Get-SCOMMonitoringObject -Name $clusterComputerObject.Name

    # Get the cluster monitoring object
    $clusterMonitoringObject = Get-SCOMMonitoringObject -DisplayName $clusterName

    # Get the cluster nodes
    $clusterNodes = $clusterMonitoringObject.GetRelatedMonitoringObjects($windowsComputerClass,'Recursive')

    # Add the cluster nodes to the monitoring objects
    $monitoringObjects += Get-SCOMMonitoringObject -Name $clusterNodes.Name
}

#endregion SQLServers

#region SetAssetStatus

foreach ( $monitoringObject in $monitoringObjects )
{
    if ( $monitoringObject.'[System.ConfigItem].AssetStatus' )
    {
        Write-Verbose -Message "Setting the asset status '$Status' on '$($monitoringObject.DisplayName)'"
            
        # Set the Asset Status
        $monitoringObject.'[System.ConfigItem].AssetStatus'.Value = $enum

        # Save the changes
        $monitoringObject.Overwrite()
    }
    else
    {
        Write-Warning -Message "The monitoring object '$($monitoringObject.DisplayName)' does not have the 'AssetStatus' property."
    }
}

#endregion SetAssetStatus

