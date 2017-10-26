ARM Template Input Parameters 

Deploy-AzureResourceGroup.ps1 is a deployment script to deploy the referenced ARM template and parameters file to Azure.  It requires access and authentication to an Azure subscription.  The Deploy-AzureResourceGroup.ps1 will:

- Create a storage account specifically for uploading and referencing deployment templates and scripts.
- Create a SAS Token URL in order to securely access blob storage.
- Inject the SAS Token URL and Base Artifacts storage account into the template parameters.
- Provides a mechanism to validate, deploy and clean Azure Resource Group deployments.
  
The vmss-main-parameters.json defines the parameter inputs that are required to deploy the autoscale pattern to Azure.

_artifactsLocation:	(string, required) url of storage path created Deploy-AzureResourceGroup.ps1 and dynamically injected into deployment parameters.
_artifactsLocationSasToken:	(securestring, required) sas token created by Deploy-AzureResourceGroup.ps1 and dynamically injected into deployment parameters.  Required for secure azure storage access.
keyVaultName:	(string, required) Prefix name of the key vault.  minLength: 1
accessPolicies:	(array, required) Defines the vault access policies for each user/service principal.  Format must be well defined.  Default Value {}.  For details on the key vault permissions, please see: https://docs.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults#property-values 
     keys - encrypt, decrypt, wrapKey, unwrapKey, sign, verify, get, list, create, update, import, delete, backup, restore, recover, purge
	 secrets - get, list, set, delete, backup, restore, recover, purge
	 certificates - get, list, delete, create, import, update, managecontacts, getissuers, listissuers, setissuers, deleteissuers, manageissuers, recover, purge
	 
	 Example:
	 [
        {
          "tenantId": "AAD Tenant ID",
          "objectId": "Object ID of the application or service principal",
          "permissions": {
            "keys": [
              "encrypt",
              "decrypt",
              "wrapKey",
              "unwrapKey",
              "sign",
              "verify",
              "get",
              "list"
            ],
            "secrets": [
              "backup",
              "restore",
              "recover",
              "purge"
            ],
            "certificates": [
              "get",
              "list",
              "delete",
              "create",
              "import",
              "update",
              "managecontacts",
              "getissuers",
              "listissuers",
              "setissuers",
              "deleteissuers",
              "manageissuers",
              "recover",
              "purge"
            ]
          }
        },
        {
          "tenantId": "AAD Tenant ID",
          "objectId": "Object ID of the application or service principal",
          "permissions": {
            "keys": [
              "all"
            ],
            "secrets": [
              "all"
            ],
            "certificates": [
              "all"
            ]
          }
        }
      ]

logsRetentionInDays:	(int, optional, default = 0, min = 0, max = 365)  Specifies the number of days that logs are gonna be kept. If you do not want to apply any retention policy and retain data forever, set value to 0
enableVaultForDeployment:	(bool, optional, defaultValue = false)  Property to specify whether Azure Virtual Machines are permitted to retrieve certificates stored as secrets from the key vault. 
enableVaultForTemplateDeployment:	(bool, optional, defaultValue = false)  Property to specify whether Azure Resource Manager is permitted to retrieve secrets from the key vault.
enableVaultForDiskEncryption:	(bool, optional, defaultValue = false)  Property to specify whether Azure Disk Encryption is permitted to retrieve secrets from the vault and unwrap keys.
vaultSku:	(string, optional, defaultValue = Standard)  Specifies the SKU for the vault.  Allowed values Standard or Premium
vaultSoftDelete:	(string, optional, defaultValue = disabled)  The vault's create mode to indicate whether the vault needs to be soft deleted or not. Allowed values disabled or enabled
protectWithLocks:	(string, optional, defaultValue = disabled)  Specifies if you want cannotDelete locks on vault and storage for vault diagnostics.  Allowed values enabled or disabled.
