###############################################################################
# Script Name     : veeam_report.ps1                                          #
#                                                                             #
# Author          : Cristian Malita                                           #
#                                                                             #
# Version         : 1.05                                                      #
#                                                                             #
# Date            : 11.05.2023                                                #
#                                                                             #
# Description     : The following script gathers data from Veeam backup       #
#                   and replication jobs.                                     #
#                                                                             #
###############################################################################

param(
    [Parameter(HelpMessage="For environments with Veeam v10")]
    [switch]$v10 = $False
)
#For Veeam v10
if ($v10) {
    Add-PSSnapin VeeamPSSnapin
    Write-Output "Running for Veeam v10"
}
# Configure these variables to suit your environment

# How many days should the report cover
$days = 30

# Location where the report is going to be saved
$output = "c:\temp" 

# Set to 1 if you want to send report by mail
$mailReport = 0

# SMTP credentials if smtp server requires authentication
$smtpUser = ""
$smtpPassword = ""

# SMTP server
$smtpServer = "smtp.example.com"

# Email address from which the report will be sent
$from = "john.doe@example.com"

# Email address(es) to which the report will be sent. Multiple addresses can be separated by commas. 
$to = "jane.smith@example.com"


#Function to get data for each vm

function getObjectDetails {

    param($session)

    $tasks = $session.GetTaskSessions() | Where {($_.Status -eq "Success") -or ($_.Status -eq "Warning")}

    $backups = @()


    foreach($task in $tasks) {

        $backups += [pscustomobject]@{

            vbrServer = $VBRSERVER

            backupDate = $task.Progress.StartTimeUTC.toString('dd-MM-yyyy')

            name = $task.Name
            
            jobName = $task.Name

            jobType = $session.JobType

            platform = $task.objectPlatform

            usedSizeGB = [math]::Round(($task.Progress.ProcessedUsedSize / $GB), 2)

            readSizeGB = [math]::Round(($task.Progress.ReadSize / $GB), 2)

            }

    }



    return $backups


}

function getAgentDetails {
    param($job)
    
        $agentBackups = @()

        $sessions = Get-VBRComputerBackupJobSession -Name "$($job.Name)?*" | Where {($_.endTime.Date -gt $cutoff)} | Where {($_.Result -eq "Success") -or ($_.Result -eq "Warning")}

        foreach ($session in $sessions) {

            $task = Get-VBRTaskSession -Session $session | Select-Object -Property @{n='vbrServer';e={$($VBRSERVER)}},
                                                                        @{n='backupDate';e={$_.Progress.StartTimeUTC.toString('dd-MM-yyyy')}}, 
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



# DO NOT TOUCH any of these variables


$GB = 1024 * 1024 * 1024
$vbrServer = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
$month = (Get-Culture).DateTimeFormat.GetMonthName((get-date).Month)
$reportLocation = "$OUTPUT\veeam-$VBRSERVER-REPORT-" + (get-date).ToString('yyyyMM') + ".csv"
$subject = "Veeam gather data for $vbrServer"
$body = "Hello, `nPlease check attached report."

$backups = @()
$agentBackups = @()
$wu=@()


# Determine cutoff date
$cutoff = (get-date).AddDays(-$DAYS).Date



# Get all successful jobs since $cutoff and order them by newest to oldest
$sessions = Get-VBRBackupSession | Where {($_.endTime.Date -gt $cutoff)}
$sessions_ordered = $sessions | Sort-Object -Property StartTimeUTC -Descending

$agentJobs = Get-VBRComputerBackupJob

foreach ($job in $agentJobs) {

   $agentBackups += getAgentDetails($job)
}

$backups += $agentBackups

# For each job session get the details of the objects inside 
foreach($session in $sessions_ordered){
    $backups += getObjectDetails($session)
}

$backups = $backups | Sort-Object -Property name

# Calculate the sum of readSize for each object to calculate WU
$sums = ($backups | group-object name | select-object name, @{ n='readSizeGB'; e={($_.Group | Measure-Object readSizeGB -Sum).Sum}})

foreach ($sum in $sums) {
    $obj =  ($backups | ? {$_.name -eq $sum.name})[0]
    $wu += [pscustomobject]@{
        vbrServer = $obj.vbrServer
        name = $obj.name
        platform = $obj.platform
        readSizeGB = $sum.readSizeGB
    }

}


#Generate CSV files for FET and WU
$wu | Export-Csv -path $reportLocation -NoTypeInformation



# Send report by mail

if ($mailReport) {
    if ([string]::IsNullOrWhitespace($smtpUser)) {
        Send-MailMessage -From $from -To $to -Subject $subject -Body $body -Attachments $reportLocation -SmtpServer $smtp
    } else {
        $securePassword = ConvertTo-SecureString $smtpPassword -AsPlainText -Force
        $smtpCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $smtpUser, $securePassword
        Send-MailMessage -From $from -To $to -Subject $subject -Body $body -Attachments $reportLocation -SmtpServer $smtp -Credential $smtpCred
    }
}
