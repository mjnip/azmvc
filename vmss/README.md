ARM Template Input Parameters 

Deploy-AzureResourceGroup.ps1 is a deployment script to deploy the referenced ARM template and parameters file to Azure.  It requires access and authentication to an Azure subscription.  The Deploy-AzureResourceGroup.ps1 will:

- Create a storage account specifically for uploading and referencing deployment templates and scripts.
- Create a SAS Token URL in order to securely access blob storage.
- Inject the SAS Token URL and Base Artifacts storage account into the template parameters.
- Provides a mechanism to validate, deploy and clean Azure Resource Group deployments.
  
The vmss-main-parameters.json defines the parameter inputs that are required to deploy the autoscale pattern to Azure.

_artifactsLocation:	(string, required) url of storage path created Deploy-AzureResourceGroup.ps1 and dynamically injected into deployment parameters.
_artifactsLocationSasToken:	(securestring, required) sas token created by Deploy-AzureResourceGroup.ps1 and dynamically injected into deployment parameters.  Required for secure azure storage access.
oms-subid:	(string, required) Subscription ID where Operations Management Suite Log Analytics is deployed.
oms-rg:	(string, required) Resource Group name where Operations Management Suite Log Analytics is deployed.
workspaceName:	(string, required) Operations Management Suite Log Analytics workspace name.
scriptFile:	(string, required) name of the script file to be executed in the custom script extension.  This is required but the script can be empty.
scriptCommandToExecute:	(string, required) The command line to execute the scriptFile on the virtual machine(s).
osType:	(string, required) The OS type, either Windows or Linux, is forced as inputs.
managedImageId:	(string, required) The Azure Resource ID of the managed image used for this deployment.  Example:  /subscriptions/{SubscriptionID}/resourceGroups/{resourceGroupOfImage}/providers/Microsoft.Compute/images/{customImageName}
lbOrNolb:	(string, required)  Deploy a LB or Not.  Forced values of lb or nolb.
vmSize:	(string, required)  The Azure instance size to deploy.  Must be a well formed Azure VM instance reference.  Example:  Standard_A1
vmssName:	(string, required)  The name of the VM scale set.  String of minimum length 3 to maximum length 64
computerNamePrefix:	(string, required)  The computer name prefix of VMs within the scale set.  Minimum 3 to maximum 9 characters.
instanceCount:	(int, required)  The number of instances to deploy in the scale set.  Between 1 and 100.
adminUsername:	(string, required)  The admin user name for the VM.  Minimum string of length 1.
adminPassword:	(securestring, required)  The admin password for the VM(s).
subnetName:	(string, required)  The subnetName within the Virtual Network to deploy into.  
virtualnetworkName:	(string, required)  The virtual network name to deploy into.
virtualnetworkNameRGName:	(string, required)  The resource group name that the virtual network to deploy into resides.
lbPort:	(string, required)  The front end load balanced port.
lbBePort:	(string, required)  The back end load balanced port to forward traffic to.
diskType:	(string, required)  The type of disk.  Must be either Premium_LRS or Standard_LRS.  (Premium_LRS = SSD, Standard_LRS = HDD).
autoscaleEnabled:	(bool, optional, default: false)  Boolean to enable or disable autoscale rules.
scaleByMetric:	(string, optional, default: CPU)  autoscale rule by CPU or Memory.  Allowed values are CPU or MEM.
scaleInByTimeWindow:	(string, optional, default: 10M)  Time metric scale in setting.  Allowed values:  1M, 5M, 10M, 20M, 30M, 45M, 1H, 1H15M, 1H30M, 1H40M
scaleOutByTimeWindow:	(string, optional, default: 10m)  Time metric scale out setting.  Allowed values:  1M, 5M, 10M, 20M, 30M, 45M, 1H, 1H15M, 1H30M, 1H40M
scaleInByStatistic:	(string, optional, default: Average)  Scale in statictic type.  Allowed values: Average, Min, Max
scaleOutByStatistic:	(string, optional, default: Average)  Scale out statictic type.  Allowed values: Average, Min, Max
scaleOutByOperator:	(string, optional, default: GreaterThan)  Scape out operator type.  Allowed values:  GreaterThan, LessThan
scaleInByOperator:		(string, optional, default: GreaterThan)  Scape in operator type.  Allowed values:  GreaterThan, LessThan
scaleOutByThreshold:	(int, optional, default: 70)  Threshold for scale out rule.  This is a percentage from 1 to 10
scaleInByThreshold:	(int, optional, default: 70)  Threshold for scale in rule.  This is a percentage from 1 to 10
scaleInByType:	(string, optional, default: ChangeCount)  Type of scale action for scale in.  Allowed values: ChangeCount, PercentChangeCount, ExactCount.
scaleOutByType:	(string, optional, default: ChangeCount)  Type of scale action for scale out.  Allowed values: ChangeCount, PercentChangeCount, ExactCount.
scaleInByValue:	(int, optional, default: 1)  Instance value for scale in rule.  This is a percentage, exact count, or incremental increase from 1 to 100
scaleOutByValue:	(int, optional, default: 1)  Instance value for scale out rule.  This is a percentage, exact count, or incremental increase from 1 to 100
scaleOutByCooldown:	(string, optional, default: 10M)  Cooldown time for scale out rule.  This is a string representation of time.  Strict values:  1M, 5M, 10M, 20M, 30M, 1H, 1H30M, 2H, 2H30M, 3H, 4H, 5H, 1D, 2D
scaleInByCooldown:	(string, optional, default: 10M)  Cooldown time for scale in rule.  This is a string representation of time.  Strict values:  1M, 5M, 10M, 20M, 30M, 1H, 1H30M, 2H, 2H30M, 3H, 4H, 5H, 1D, 2D