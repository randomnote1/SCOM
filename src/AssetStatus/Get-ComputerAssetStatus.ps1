#Requires -Module OperationsManager

<#
    .SYNOPSIS
        Gets the AssetStatus property on the specified computer object.

    .PARAMETER ComputerName
        The name(s) of the computer(s) to get the asset status for.

    .PARAMETER ScomManagementComputer
        The name of a SCOM management server.
    
    .EXAMPLE
        Get-ComputerAssetStatus -ComputerName Server01

    .EXAMPLE
        Get-ComputerAssetStatus
#>

[CmdletBinding()]
param
(
    [Parameter()]
    [System.String[]]
    $ComputerName,

    [Parameter()]
    [System.String]
    $ScomManagementComputer
)

if ( $ScomManagementComputer )
{
    # Connect to the SCOM management group
    New-SCOMManagementGroupConnection -ComputerName $ScomManagementComputer
}

if ( $ComputerName )
{
    # Get the FQDN of the specified computers
    $fqdns = $ComputerName |
        ForEach-Object -Process { Resolve-DnsName -Name $_ } |
        Select-Object -ExpandProperty Name -Unique

    # Get the computer monitoring objects
    $computerMonitoringObjects = Get-SCOMMonitoringObject -DisplayName $fqdns |
        Where-Object -FilterScript { ( Get-SCOMClass -Id $_.LeastDerivedNonAbstractMonitoringClassId ).Name -eq 'Microsoft.Windows.Computer' }
}
else
{
    # Get all of the computer monitoring objects
    $computerMonitoringObjects = Get-SCOMClass -Name Microsoft.Windows.Computer | Get-SCOMMonitoringObject
}

if ( ( $computerMonitoringObjects | Measure-Object ).Count -gt 0 )
{
    foreach ( $monitoringObject in $computerMonitoringObjects )
    {
        if ( $monitoringObject.'[System.ConfigItem].AssetStatus' )
        {
            $monitoringObject | Select-Object -Property DisplayName,@{n='AssetStatus';e={$_.'[System.ConfigItem].AssetStatus'.Value.DisplayName}}
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
