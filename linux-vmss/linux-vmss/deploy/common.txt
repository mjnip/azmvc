#validate
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus2' `
-ResourceGroupName 'td-linuxvmss' `
-StorageResourceGroupName 'td-mvc-deploy' `
-UploadArtifacts `
-StorageAccountName 'tdmvcdeploy' `
-StorageContainerName 'tdmvc' `
-ValidateOnly

#deploy
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus2' `
-ResourceGroupName 'td-linuxvmss' `
-StorageResourceGroupName 'td-mvc-deploy' `
-UploadArtifacts `
-StorageAccountName 'tdmvcdeploy' `
-StorageContainerName 'tdmvc'

#clean
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus2' `
-ResourceGroupName 'td-linuxvmss' `
-StorageResourceGroupName 'td-mvc-deploy' `
-UploadArtifacts `
-StorageAccountName 'tdmvcdeploy' `
-StorageContainerName 'tdmvc' `
-CleanUp