#Requires -Module OperationsManager

<#
    .SYNOPSIS
        Sets the AssetStatus property on the specified object(s).

    .EXAMPLE
        Set-SCOMAssetStatus -MonitoringObjectDisplayName Server01.contoso.com -Status Undefined

    .EXAMPLE
        Set-SCOMAssetStatus -MonitoringObjectDisplayName HR_Config -Status Deployed

        Set the HR farm as deployed to production.
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $MonitoringObjectDisplayName,

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

if ( $ScomManagementComputer )
{
    # Connect to the SCOM management group
    New-SCOMManagementGroupConnection -ComputerName $ScomManagementComputer
}

# Get the management pack object of the desired management pack
$managementPack = Get-SCOMManagementPack -Name System.Library

# Get the enum
$enum = $managementPack.GetEnumeration("System.ConfigItem.AssetStatusEnum.$Status")

Write-Verbose -Message "The asset status ID for '$Status' is $($enum.Id)"

# Get the monitoring object. Pass it to a gridview so the user can select the correct object
$monitoringObjects = Get-SCOMMonitoringObject -DisplayName $MonitoringObjectDisplayName |
    Out-GridView -PassThru -Title 'Select the monitoring object'

# Ensure objects were selected
if ( ( $monitoringObjects | Measure-Object ).Count -gt 0 )
{
    # Iterate over the monitoring objects
    foreach ( $monitoringObject in $monitoringObjects )
    {
        # Ensure the '[System.ConfigItem].AssetStatus' property exists
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
}
else
{
    Write-Warning -Message "No objects found for $MonitoringObjectDisplayName"
}
