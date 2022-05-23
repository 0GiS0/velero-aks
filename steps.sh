# Variables
RESOURCE_GROUP="velero-demo"
LOCATION="westeurope"
AKS_NAME="velero-demo-aks"

# Create a resource group.
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create an AKS cluster.
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_NAME \
  --generate-ssh-keys

# Get the cluster credentials.
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME

# Install Velero locally
brew install velero

# Create a demo with azure disk
kubectl create ns tour-of-heroes-azure-disk
kubectl apply -n tour-of-heroes-azure-disk -f tour-of-heroes-demos/azure-disk --recursive

k get all -n tour-of-heroes-azure-disk

# Create a demo with azure file with nfs protocol
kubectl create ns tour-of-heroes-azure-files-nfs
kubectl apply -n tour-of-heroes-azure-files-nfs -f tour-of-heroes-demos/azure-files-nfs --recursive

k get all -n tour-of-heroes-azure-files-nfs

# Add some heroes via API (use client.http)

##################################################
# Use Velero to create a workload cluster backup #
##################################################

# Create an storage account
STORAGE_NAME="k8svelerobackupg"
az storage account create \
   --name $STORAGE_NAME \
   --resource-group $RESOURCE_GROUP \
   --sku Standard_GRS \
   --encryption-services blob \
   --https-only true \
   --kind BlobStorage \
   --access-tier Hot

# Create a container
BLOB_CONTAINER=backups
az storage container create \
-n $BLOB_CONTAINER \
--public-access off \
--account-name $STORAGE_NAME

# Set permissions for velero
AZURE_SUBSCRIPTION_ID=`az account list --query '[?isDefault].id' -o tsv`
AZURE_TENANT_ID=`az account list --query '[?isDefault].tenantId' -o tsv`

AZURE_CLIENT_SECRET=$(az ad sp create-for-rbac --name "velero" --role "Contributor" --scopes /subscriptions/$AZURE_SUBSCRIPTION_ID --query 'password' -o tsv)
AZURE_CLIENT_ID=`az ad sp list --display-name "velero" --query '[0].appId' -o tsv`

#the resource group that contains your cluster's virtual machines/disks.
AKS_NODE_RESOURCE_GROUP=$(az aks show --resource-group $RESOURCE_GROUP --name $AKS_NAME --query nodeResourceGroup -o tsv)

cat << EOF  > ./credentials-velero
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AKS_NODE_RESOURCE_GROUP}
AZURE_CLOUD_NAME=AzurePublicCloud
EOF

# Install and start Velero
velero install \
--provider azure \
--plugins velero/velero-plugin-for-microsoft-azure:v1.4.1 \
--bucket $BLOB_CONTAINER \
--secret-file ./credentials-velero \
--backup-location-config resourceGroup=$RESOURCE_GROUP,storageAccount=$STORAGE_NAME,subscriptionId=$AZURE_SUBSCRIPTION_ID \
--snapshot-location-config resourceGroup=$RESOURCE_GROUP,subscriptionId=$AZURE_SUBSCRIPTION_ID \
--use-restic

# Velero is installed! ⛵ Use 'kubectl logs deployment/velero -n velero' to view the status.
kubectl logs deployment/velero -n velero

# Check that everthing is up and running
kubectl -n velero get pods

# To run a basic on-demand backup of your cluster with azure disk pv
velero backup create azure-disk-backup --default-volumes-to-restic --include-namespaces tour-of-heroes-azure-disk
velero backup describe azure-disk-backup --details

# To run a basic on-demand backup of your cluster with azure files (NFS protocol) pv
velero backup create azure-files-nfs-backup --default-volumes-to-restic --include-namespaces tour-of-heroes-azure-files-nfs
velero backup describe azure-files-nfs-backup --details

# Check all backups with velero
velero get backups

# Create a new cluster
az group create --name $RESOURCE_GROUP-restore --location $LOCATION

# Create a new resource group
az aks create \
  --resource-group $RESOURCE_GROUP-restore \
  --name $AKS_NAME-restore \
  --generate-ssh-keys 

# Get the cluster credentials
az aks get-credentials --resource-group $RESOURCE_GROUP-restore --name $AKS_NAME-restore

# Deploy and configure velero here
velero install \
--provider azure \
--plugins velero/velero-plugin-for-microsoft-azure:v1.4.1 \
--bucket $BLOB_CONTAINER \
--secret-file ./credentials-velero \
--backup-location-config resourceGroup=$RESOURCE_GROUP,storageAccount=$STORAGE_NAME,subscriptionId=$AZURE_SUBSCRIPTION_ID \
--snapshot-location-config resourceGroup=$RESOURCE_GROUP,subscriptionId=$AZURE_SUBSCRIPTION_ID \
--use-restic

# Check the pods for velero
kubectl -n velero get pods

# Check the logs
kubectl logs deployment/velero -n velero

# Check that you can see the backups (It takes a few minutes)
velero get backups

# Nothing here
k get pods -n tour-of-heroes-azure-disk
k get pods -n tour-of-heroes-azure-files-nfs

# Restore backup
velero restore create --from-backup azure-disk-backup
velero restore create --from-backup azure-files-nfs-backup

# See details
velero restore describe azure-disk-backup-XXXXXXXXXX --details
velero restore describe azure-files-nfs-backup-XXXXXXX --details

# Now tour-of-heroes is restored!
k get all -n tour-of-heroes-azure-disk
k get all -n tour-of-heroes-azure-files-nfs
