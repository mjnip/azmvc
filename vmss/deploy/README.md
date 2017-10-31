ARM Template Input Parameters 

Deploy-AzureResourceGroup.ps1 is a deployment script to deploy the referenced ARM template and parameters file to Azure.  It requires access and authentication to an Azure subscription.  The Deploy-AzureResourceGroup.ps1 will:

- Create a storage account specifically for uploading and referencing deployment templates and scripts.
- Create a SAS Token URL in order to securely access blob storage.
- Inject the SAS Token URL and Base Artifacts storage account into the template parameters.
- Provides a mechanism to validate, deploy and clean Azure Resource Group deployments.
- If switch CleanUpDeploymentStorage is called, note that the deploy script will remove the deployment storage account and resource group.  This will result in an added removal operation to complete before the script returning. 


Usage Examples:

#validate
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus2' `
-ResourceGroupName 'td-vmss' `
-UploadArtifacts `
-TemplateParametersFile '..\templates\vmss-main.parameters.json' `
-TemplateFile '..\templates\vmss-main.json' `
-StorageAccountName 'tdmvcdeploy' `
-StorageContainerName 'tdmvc' `
-ArtifactStagingDirectory '..\templates' `
-ScriptStagingDirectory '..\scripts' `
-ValidateOnly


#deploy
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus2' `
-ResourceGroupName 'td-vmss' `
-UploadArtifacts `
-TemplateParametersFile '..\templates\vmss-main-autoscale.parameters.json' `
-TemplateFile '..\templates\vmss-main.json' `
-StorageAccountName 'tdmvcdeploy' `
-StorageContainerName 'tdmvc' `
-ArtifactStagingDirectory '..\templates' `
-ScriptStagingDirectory '..\scripts' `
-CleanUpDeploymentStorage

#Clean
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus2' `
-ResourceGroupName 'td-vmss' `
-UploadArtifacts `
-TemplateParametersFile '..\templates\vmss-main-autoscale.parameters.json' `
-TemplateFile '..\templates\vmss-main.json' `
-StorageAccountName 'tdmvcdeploy' `
-StorageContainerName 'tdmvc' `
-ArtifactStagingDirectory '..\templates' `
-ScriptStagingDirectory '..\scripts' `
-CleanUp
