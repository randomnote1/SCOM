<#
    .SYNOPSIS
        Creates output for use in a SCOM PowerShell Grid Widget.

    .DESCRIPTION
        Uses the Server.Pending.Restart management pack to create output for 
        use in a SCOM PowerShell Grid Widget.
#>

# Create a hashtable to translate between HealthState and alphabetical characters for sorting
$sortTable = @{
    0 = 'd'
    1 = 'c'
    2 = 'b'
    3 = 'a'
}

# Get the reboot required monitor object
$rebootRequiredMonitor = Get-SCOMMonitor -DisplayName 'Server Pending Restart Monitor'

# Get the class which is targeted by the reboot required monitor
$operatingSystemClass = Get-SCOMClass -Id $rebootRequiredMonitor.Target.Id

# Get all instances of the class (operating system)
$operatingSystems = Get-SCOMClassInstance -Class $operatingSystemClass

# Build the collection to use when searching for the monitor state
$monitors = New-Object -TypeName 'System.Collections.Generic.List[Microsoft.EnterpriseManagement.Configuration.ManagementPackMonitor]'
$monitors.Add($rebootRequiredMonitor)

foreach ( $operatingSystem in $operatingSystems )
{
    # Find the state of the monitor for the current computer
    $rebootState = $operatingSystem.GetMonitoringStates($monitors)[0]

    # Translate the context XML into an object
    [xml]$context = $rebootState.GetStateChangeEvents()[-1].Context

    # Get the PendingFileRenameOperations property
    $pendingFileRenameOperations = $context.DataItem.Property | Where-Object -FilterScript { $_.Name -eq 'PendingFileRenameOperations' } | Select-Object -ExpandProperty '#text'

    if ( $pendingFileRenameOperations -eq 'true' )
    {
        # Get the files which need renamed. Note the carriage return at the end of the line.
        $pendingFileRenames = ($context.DataItem.Property | Where-Object -FilterScript { $_.Name -eq 'PendingFileRenameOperationsValue' } | Select-Object -ExpandProperty '#text') -replace '  ','
'
    }
    else
    {
        # Set the PendingFileRenames field to an empty string
        $pendingFileRenames = $null
    }

    # Create a data object using a dummy schema and
    $dataObject = $ScriptContext.CreateInstance('xsd://foo!bar/baz')

    <#
        Create an ID using the health state and OS object ID.
         - Must be a string value
         - Used to sort the grid
         - Translate the HealthState value to a letter so it will work with the string sort
    #>
    $dataObject['Id'] = "$($sortTable[$rebootState[0].HealthState.value__]) $($operatingSystem.Id.ToString())"

    # Add the rest of the desired properties
    $dataObject['Health State'] = $ScriptContext.CreateWellKnownType('xsd://Microsoft.SystemCenter.Visualization.Library!Microsoft.SystemCenter.Visualization.OperationalDataTypes/MonitoringObjectHealthStateType',$rebootState[0].HealthState.value__)
    $dataObject['Maintenance Mode'] = $ScriptContext.CreateWellKnownType('xsd://Microsoft.SystemCenter.Visualization.Library!Microsoft.SystemCenter.Visualization.OperationalDataTypes/MonitoringObjectInMaintenanceModeType',$operatingSystem.InMaintenanceMode)
    $dataObject['Computer'] = [System.String]($operatingSystem.'[Microsoft.Windows.Computer].PrincipalName'.Value)
    $dataObject['Last BootUp Time'] = $context.DataItem.Property | Where-Object -FilterScript { $_.Name -eq 'LastBootUpTime' } | Select-Object -ExpandProperty '#text'
    $dataObject['Windows Update'] = $context.DataItem.Property | Where-Object -FilterScript { $_.Name -eq 'WindowsUpdateAutoUpdate' } | Select-Object -ExpandProperty '#text'
    $dataObject['Component Based Servicing'] = $context.DataItem.Property | Where-Object -FilterScript { $_.Name -eq 'ComponentBasedServicing' } | Select-Object -ExpandProperty '#text'
    $dataObject['Pending File Rename Operations'] = $pendingFileRenameOperations
    $dataObject['Pending File Renames'] = $pendingFileRenames

    # Add the data object to what is displayed in the dashboard
    $ScriptContext.ReturnCollection.Add($dataObject)
}