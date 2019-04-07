<#
    Sample script to configure a new vCenter, create a datacenter, create a cluster, 
    add ESXi hosts, and configure vSAN. 
    
    Modify the variables below to the desired settings.
#>


$vcenterName = "vmindevvctr01.nghs.com"
#$vcenterName = "vc1.lab.local"
$datacenterName = "Atlanta"
$clusterName = "Lab-1"
$vmhostNames = ("vmindevesx01.nghs.com","vmindevesx02.nghs.com","vmindevesx03.nghs.com")
#$vmhostNames = ("esx1.lab.local","esx2.lab.local","esx3.lab.local")
$enableDrs = $true
$enableHa = $true
$enableVsan = $true
$vsanCacheDiskSizeGB = 4
$vsanDataDiskSizeGB = 8
$vcenterSettings = @{
    "mail.sender" = "vcenter@lab.local";
    "mail.smtp.server" = "smtp.lab.local";
    #"mail.smtp.username" = "";
    #"mail.smtp.password" = "";
    #"mail.smtp.port" = "25";
    #"snmp.receiver.1.name" = "localhost";
    #"snmp.receiver.1.enabled" = "True";
    #"snmp.receiver.1.port" = "162";
    #"snmp.receiver.1.community" = "public";
    #"event.maxAge" = "30";
    #"event.maxAgeEnabled" = "True";
    #"task.maxAge" = "30";
    #"task.maxAgeEnabled" = "True";
    #"log.level" = "info";
}



# Prompt for ESXi host credentails
$hostCredentials = Get-Credential -UserName "root" -Message "Enter the ESXi host credentials to be used for adding hosts to vCenter"


# Connect to vCenter
$vcenter = Connect-VIServer -Server $vcenterName


# Configure vCenter settings
Foreach ($key in $vcenterSettings.keys) {

    # Get the current advanced setting
    $advSetting = Get-AdvancedSetting -Entity $vcenter -Name $key

    # Set the new value if it is different
    If ($advSetting.Value -ne $vcenterSettings[$key]) {
        Set-AdvancedSetting -AdvancedSetting $advSetting -Value $vcenterSettings[$key] -Confirm:$false
    }

}


# Create Datacenter
$datacenter = Get-Datacenter | Where-Object Name -eq $datacenterName
If ($null -eq $datacenter) {
    Write-Host "Creating Datacenter $datacenterName"
    $datacenter = New-Datacenter -Name $datacenterName -Location (Get-Folder -NoRecursion)
}


# Create Cluster
$cluster = Get-Cluster | Where-Object Name -eq $clusterName
If ($null -eq $cluster) {
    Write-Host "Creating Cluster $clusterName"
    $cluster = New-Cluster -Name $clusterName -Location $datacenter
}


# Add Hosts
$newVMHosts = $vmhostNames | Where-Object {$_ -NotIn (Get-VMHost).Name}
Foreach ($newVMHost in $newVMHosts) {
    Write-Host "Adding host $newVMHost"
    Add-VMHost -Name $newVMhost -Location $cluster -Credential $hostCredentials -Force
}


# Enable cluster features
Set-Cluster -Cluster $cluster -DrsEnabled $enableDrs -HaEnabled $enableHa -VsanEnabled $enableVsan -Confirm:$false


# Configure vSAN
If ($enableVsan) {

    # Create vSAN disk group on each host
    Foreach ($vmhost in (Get-VMHost -Location $cluster)) {
        $vsanDisks = Get-VMHostHba -VMHost $vmhost | Get-ScsiLun | Where-Object {$_.VsanStatus -eq “Eligible”}
        $cacheDisk =  $vsanDisks | Where-Object {$_.IsSsd -eq $true -and $_.CapacityGB -eq $vsanCacheDiskSizeGB}
        $dataDisk = $vsanDisks | Where-Object {$_.CapacityGB -eq $vsanDataDiskSizeGB}

        New-VsanDiskGroup -VMHost $vmhost -SsdCanonicalName $cacheDisk -DataDiskCanonicalName $dataDisk
    }

    # Enable vSAN Performance Service
    Get-VsanClusterConfiguration -Cluster $cluster | Set-VsanClusterConfiguration -PerformanceServiceEnabled $true

}
