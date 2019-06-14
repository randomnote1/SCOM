#Requires -Module OperationsManager

<#
    .SYNOPSIS
        Get performance data for the specified SCOM object.

    .PARAMETER MonitoringObject
        The monitoring object to get performance counter data from.

    .PARAMETER CounterName
        The name of the counter from which to return performance data.

    .PARAMETER StartTime
        The start of the time range to return.

    .PARAMETER EndTime
        The end of the time range to return.

    .EXAMPLE
        Get-SCOMPerfData -ManagmentServer Server01 -MonitoringObject $logicalDisk -CounterName 'Free Megabytes'
#>

function Get-SCOMPerfData
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [Microsoft.EnterpriseManagement.Monitoring.MonitoringObject]
        $MonitoringObject,
        
        [Parameter()]
        [System.String]
        $CounterName,
         
        [Parameter()]
        [System.Datetime]
        $StartTime = (Get-Date).Addhours(-12).ToUniversalTime(), 
        
        [Parameter()]
        [System.Datetime]
        $EndTime = (Get-Date).ToUniversalTime()
    ) 
 
    <#
        .SYNOPSIS
            Adds a clause to the criteria string.
    #>
    function Add-Criteria() 
    { 
        param
        (
            [Parameter(Mandatory = $true)]
            [System.Object]
            $Clause
        )
     
        # If nothing has been added to the criteria string
        if ( [System.String]::IsNullOrEmpty($script:criteria) )
        {
            # Add the first criteria to the string
            $script:criteria = $Clause
        } 
        else 
        {
            # Append the criteria to the string
            $script:criteria += " AND $Clause"
        }
    }

    # Verify a connection exists to the SCOM management group
    if ( -not ( Get-SCOMManagementGroupConnection ) )
    {
        try
        {
            # If a connection doesn't exist, try to connect
            New-SCOMManagementGroupConnection -ErrorAction Stop
        }
        catch
        {
            throw 'No connection exists to the SCOM Management Group. Run New-SCOMManagementGroupConnection and try again.'
        }
    }
    
    # Get the management group object
    $managementGroup = Get-SCOMManagementGroup

    # Create an array to gather all the parameters
    [System.String] $script:criteria = ''

    # Add the object full name to the criteria array
    if ( $PSBoundParameters.ContainsKey('MonitoringObject') )
    {
        Add-Criteria -Clause "MonitoringObjectFullName = '$($MonitoringObject.FullName)'"
    }

    # Add the counter name to the criteria array
    if ( $PSBoundParameters.ContainsKey('CounterName') )
    {
        Add-Criteria -Clause "CounterName = '$CounterName'"
    }
 
    # Set up the reader based on the criteria 
    $reader = $managementGroup.GetMonitoringPerformanceDataReader($script:criteria) 

    while ( $reader.Read() )
    { 
        # Create the performance data object and then get values in the date/time range 
        $perfData = $reader.GetMonitoringPerformanceData() 
        $valueReader = $perfData.GetValueReader($StartTime,$EndTime) 
        $val = @()
 
        # Retrieve the values
        while ( $valueReader.Read() )
        { 
            $perfValue = $valueReader.GetMonitoringPerformanceDataValue()
            $val += $perfvalue.SampleValue
            $LastValue = $perfValue.SampleValue
        }

        # Get the value statistics
        $data = $val | Measure-Object -Maximum -Minimum -Average

        # Build the formatted object
        $outputObject = New-Object -TypeName PSObject -Property @{
            Rule = $perfdata.RuleDisplayName
            Path = $perfData.MonitoringObjectPath
            ObjectName = $perfData.ObjectName
            CounterName = $perfData.countername
            Instance = $perfdata.InstanceName
            MaxValue = $data.Maximum
            MinValue = $data.Minimum
            AvgValue = $data.Average
            LastValue = $lastValue
            Count = $data.Count
        }

        # Finally, return the object
        $outputObject
    }
}