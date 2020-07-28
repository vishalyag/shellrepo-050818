# Script Description - This script installs the OMS agent on Azure VMs by going through all the resource groups for a single subscription
#Suppress the warnings
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
#Connect-AzAccount
$sub_id = Read-Host "Provide subscription Id of the Azure environment: -"
Select-AzSubscription $sub_id
#Defining variables
$i=0
$vmStat1 = @()
$workspace_rg = "az-monitor-rg-2"
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspace_rg
$workspaceId = $workspace.CustomerId
$workspaceKey = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $workspace_rg -Name $workspace.Name
$Publicsettings=@{"workspaceId" = $workspaceId}
$Protectedsettings=@{"workspaceKey" = $workspaceKey.primarysharedkey}

# Get the excluded VMs Property and counts of such Vms
$exclude_vms = Import-Csv "E:\vms3.csv"
$exclude_vm_list = $exclude_vms | ForEach-Object {
    foreach ($property in $_.PSObject.Properties) {
        $property.Name
        $property.Value
        #replace = $property.Value
        }
    }
$fl_exclude_vm_list = $exclude_vm_list.length
# Get the resource Groups and export the details to a file
$rgs = Get-AzResourceGroup | Select-Object -Property ResourceGroupName | Export-Csv "E:\rgs.csv"
$file = Import-Csv "E:\rgs.csv"

# Get the Resource Groups Property and counts of such RGs
$filevalues = $file | ForEach-Object {
    foreach ($property in $_.PSObject.Properties) {
        #$property.Name
        $property.Value
        #replace = $property.Value
        }
    }

$fl = $filevalues.length
for ($i=0;$i -lt $fl;$i++) {
    $rg = $filevalues[$i]
    $vms=Get-AzVM -ResourceGroupName $rg
    #Write-Host "Vms are $vms"
    if ($vms -eq $null) {
        Write-Host "No VMs present in the Resource Group $rg"
    }
    else {
        foreach($vm in $vms){
            $vmName=$vm.name
            $vmLocation = $vm.Location
            $vmostype = $vm.StorageProfile.OsDisk.OsType
            $vmStat1= Get-AzVM -ResourceGroupName $rg -VMName $vmName -Status
            $vmStat2= $vmStat1.Statuses[-1].DisplayStatus
            $exc_vm = $exclude_vm_list | Select-String $vmName
            if ( $exc_vm ) {
                Write-Host "VM $vmName present in the Resource Group $rg of OS Type $vmostype needs to be excluded from the Azure monitor Integration"
                }
            else {
                if ($vmStat2 -eq "VM running")  {
                    if ($vmostype -eq "Linux") {
                        $vmextstate = Get-AzVMExtension -ResourceGroupName $rg -VMName $vmName
                        $ext_name = $vmextstate.Name

                        if (!$ext_name) {
                            Write-Host "Linux VM found - OMS Agent Installation is in progress for the VM $vmName present in the Resource Group $rg"
                            Set-AzVMExtension -ExtensionName "OmsAgentForLinux" -ResourceGroupName $rg -VMName $vmName -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "OmsAgentForLinux" -TypeHandlerVersion 1.7 -Settings $PublicSettings -ProtectedSettings $ProtectedSettings -Location $vmLocation
                        }
                        else {
                            $wsp_id_vm = az vm extension show -g $rg --vm-name $vmName -n $ext_name --query settings.workspaceId -o table
                            if ($wsp_id_vm -eq $workspaceId) {
                                Write-Host "Linux VM $vmName present in the Resource Group $rg is already integrated with the workspace "$workspace.Name""
                                }
                            else {
                                Write-Host "Linux VM found - OMS Agent Uninstallation is in progress for the VM $vmName present in the Resource Group $rg"
                                Remove-AzVMExtension -ResourceGroupName $rg -VMName $vmName -Name $ext_name -Force
                                Write-Host "Linux VM found - OMS Agent Installation is in progress for the VM $vmName present in the Resource Group $rg"
                                Set-AzVMExtension -ExtensionName "OmsAgentForLinux" -ResourceGroupName $rg -VMName $vmName -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "OmsAgentForLinux" -TypeHandlerVersion 1.7 -Settings $PublicSettings -ProtectedSettings $ProtectedSettings -Location $vmLocation
                                }
                            }
                        }
                    else {
                        $vmextstate = Get-AzVMExtension -ResourceGroupName $rg -VMName $vmName
                        $ext_name_win = $vmextstate.Name
                        if (!$ext_name_win) {
                            Write-Host "Windows VM found - Monitoring Agent Installation is in progress for the VM $vmName present in the Resource Group $rg"
                            Set-AzVMExtension -ExtensionName "Microsoft.EnterpriseCloud.Monitoring" -ResourceGroupName $rg -VMName $vmName -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "MicrosoftMonitoringAgent" -TypeHandlerVersion 1.0 -Settings $PublicSettings -ProtectedSettings $ProtectedSettings -Location $vmLocation
                        }
                        else {
                            $wsp_id_winvm = az vm extension show -g $rg --vm-name $vmName -n $ext_name_win --query settings.workspaceId -o table
                            if ($wsp_id_winvm -eq $workspaceId) {
                                Write-Host "Windows VM $vmName present in the Resource Group $rg is already integrated with the workspace "$workspace.Name""
                                }
                            else {
                                Write-Host "Wndows VM found - Monitoring Agent Uninstallation is in progress for the VM $vmName present in the Resource Group $rg"
                                Remove-AzVMExtension -ResourceGroupName $rg -VMName $vmName -Name $ext_name_win -Force
                                Write-Host "Windows VM found - Monitoring Agent Installation is in progress for the VM $vmName present in the Resource Group $rg"
                                Set-AzVMExtension -ExtensionName "Microsoft.EnterpriseCloud.Monitoring" -ResourceGroupName $rg -VMName $vmName -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "MicrosoftMonitoringAgent" -TypeHandlerVersion 1.0 -Settings $PublicSettings -ProtectedSettings $ProtectedSettings -Location $vmLocation
                                }
                            }
                        }
                    }
                else {
                    Write-Host "$vmostype VM $vmName present in the Resource Group $rg is in Powered Down State and OMS agent cannot be installed"
                    }
                }
            }
        }
    }