$jobs = Get-VBRComputerBackupJob 
$vbrServer = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
$GB = 1024 * 1024 * 1024

$output = "c:\temp"
$reportLocation = "$OUTPUT\veeam-$VBRSERVER-AGENT-" + (get-date).ToString('yyyyMMHHmm') + ".csv"

$DAYS = 30
$cutoff = (get-date).AddDays(-$DAYS).Date

$backups = @()

function getAgentDetails {

    param($job)
    
    $agentBackups = @()

    $sessions = Get-VBRComputerBackupJobSession -Name "$($job.Name)?*" | Where {($_.endTime.Date -gt $cutoff)}

    foreach ($session in $sessions) {

        $task = Get-VBRTaskSession -Session $session | Select-Object -Property @{n='vbrServer';e={$($VBRSERVER)}},
                                                                       @{n='backupDate';e={$_.Progress.StartTimeUTC.toString('dd-MM-yyyy HH:mm')}},
                                                                       status, 
                                                                       @{n='name';e={$($_.Name)}},
                                                                       @{n='jobName';e={$($job.Name)}},
                                                                       @{n='jobType';e={$($job.Type)}},
                                                                       @{n='platform';e={$($_.objectPlatform)}},
                                                                       @{n='usedSizeGB';e={[math]::Round(($_.Progress.ProcessedUsedSize / $GB), 2)}}, 
                                                                       @{n='readSizeGB';e={[math]::Round(($_.Progress.ReadSize / $GB), 2)}}
        $agentBackups += $task
           
    }

    return $agentBackups
}

foreach ($job in $jobs) {

    $backups += getAgentDetails($job)
    
}

if($backups) {
    Write-Output "Exporting CSV"
    $backups |  Where {$_} |Export-Csv $reportLocation -NoTypeInformation
}
