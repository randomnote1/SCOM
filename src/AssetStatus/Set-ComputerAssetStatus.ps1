#Requires -Module OperationsManager

<#
    .SYNOPSIS
        Sets the AssetStatus property on the specified computer object.

    .PARAMETER ComputerName
        The name of the computer.

    .PARAMETER Status
        The status which should be applied to the monitoring object.

    .PARAMETER ScomManagementComputer
        The name of a SCOM management server.
    
    .EXAMPLE
        Set-SCOMAssetStatus -ComputerName Server01 -Status Deployed -Verbose
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String[]]
    $ComputerName,

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

# Get the FQDN of the computers
$fqdns = $ComputerName |
    ForEach-Object -Process { Resolve-DnsName -Name $_ } |
    Select-Object -ExpandProperty Name -Unique

# Get the computer monitoring objects
$computerMonitoringObjects = Get-SCOMMonitoringObject -DisplayName $fqdns |
    Where-Object -FilterScript { ( Get-SCOMClass -Id $_.LeastDerivedNonAbstractMonitoringClassId ).Name -eq 'Microsoft.Windows.Computer' }

if ( ( $computerMonitoringObjects | Measure-Object ).Count -gt 0 )
{
    foreach ( $monitoringObject in $computerMonitoringObjects )
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
}
else
{
    Write-Warning -Message "No computer objects found for: $($ComputerName -join ', ')"
}
