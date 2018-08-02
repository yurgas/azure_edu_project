#!/usr/bin/env bash

# Requirements: jq

set -euo pipefail
IFS=$'\n\t'

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

usage() { echo "Usage: $0 -i <subscriptionId> -g <resourceGroupName> -n <deploymentName> -l <resourceGroupLocation>" 1>&2; exit 1; }

declare subscriptionId="Free Trial"
declare resourceGroupName="wordpress-resource-group"
declare deploymentName="wordpress"
declare resourceGroupLocation="eastus"

declare shareName="wpstatic"
declare shareQuote="1"

declare vmssName="wordpress"

# Initialize parameters specified from command line
while getopts ":i:g:n:l:" arg; do
	case "${arg}" in
		i)
			subscriptionId=${OPTARG}
			;;
		g)
			resourceGroupName=${OPTARG}
			;;
		n)
			deploymentName=${OPTARG}
			;;
		l)
			resourceGroupLocation=${OPTARG}
			;;
	esac
done
shift $((OPTIND-1))

#Prompt for parameters is some required parameters are missing
if [[ -z "$subscriptionId" ]]; then
	echo "Your subscription ID can be looked up with the CLI using: az account show --out json "
	echo "Enter your subscription ID:"
	read subscriptionId
	[[ "${subscriptionId:?}" ]]
fi

if [[ -z "$resourceGroupName" ]]; then
	echo "This script will look for an existing resource group, otherwise a new one will be created "
	echo "You can create new resource groups with the CLI using: az group create "
	echo "Enter a resource group name"
	read resourceGroupName
	[[ "${resourceGroupName:?}" ]]
fi

if [[ -z "$deploymentName" ]]; then
	echo "Enter a name for this deployment:"
	read deploymentName
fi

if [[ -z "$resourceGroupLocation" ]]; then
	echo "If creating a *new* resource group, you need to set a location "
	echo "You can lookup locations with the CLI using: az account list-locations "

	echo "Enter resource group location:"
	read resourceGroupLocation
fi

#templateFile Path - template file to be used
templateFilePath="azuredeploy.json"

if [ ! -f "$templateFilePath" ]; then
	echo "$templateFilePath not found"
	exit 1
fi

#parameter file path
parametersFilePath="azuredeploy.parameters.json"

if [ ! -f "$parametersFilePath" ]; then
	echo "$parametersFilePath not found"
	exit 1
fi

if [ -z "$subscriptionId" ] || [ -z "$resourceGroupName" ] || [ -z "$deploymentName" ]; then
	echo "Either one of subscriptionId, resourceGroupName, deploymentName is empty"
	usage
fi

# Create tmp directory if not exist
[[ -d tmp ]] || mkdir tmp

#login to azure using your credentials
az account show 1> /dev/null

if [ $? != 0 ];
then
	az login
fi

#set the default subscription id
az account set --subscription $subscriptionId

set +e

# Check for existing RG
GROUP_CHECK=`az group exists --name $resourceGroupName`

if [ "$GROUP_CHECK" != "true" ]; then
	echo "Resource group with name" $resourceGroupName "could not be found. Creating new resource group.."
	set -e
	(
		set -x
		az group create --name $resourceGroupName --location $resourceGroupLocation 1> /dev/null
	)
	else
	echo "Using existing resource group..."
fi

# Generate certificates
CERT_SERVER_NAME="${vmssName}-scale-set.${resourceGroupLocation}.cloudapp.azure.com"
./gen_cert.sh $CERT_SERVER_NAME

# Read application gateway certificate
AG_CERT=`cat "tmp/$CERT_SERVER_NAME.pfx.base64"`

# Read root certificate for vpn gateway
ROOT_CA=`cat tmp/CAcert.crt | egrep -v "^[-]{5}" | tr -d '\n'`

# Generate ssh key
if [ ! -f tmp/id_rsa ]; then
	echo "Generating ssh keys ..."
	ssh-keygen -t rsa -b 2048 -N '' -q -f tmp/id_rsa
fi
SSH_KEY=`cat tmp/id_rsa.pub`

# Create storage account for static file share
export AZURE_STORAGE_ACCOUNT="${vmssName}staticshare"

az storage account create \
    --location "${resourceGroupLocation}" \
    --name "${AZURE_STORAGE_ACCOUNT}" \
    --resource-group "$resourceGroupName" \
    --sku Standard_LRS

export AZURE_STORAGE_ACCESS_KEY=`az storage account keys list --resource-group "$resourceGroupName" --account-name ${AZURE_STORAGE_ACCOUNT} | jq '.[0].value' | tr -d '"'`

az storage share create --name ${shareName} --quota ${shareQuote}

# Start deployment
echo "Starting deployment..."
(
	set -x
	az group deployment create --mode Incremental --name "$deploymentName" \
		--resource-group "$resourceGroupName" \
		--template-file "$templateFilePath" \
		--parameters "@${parametersFilePath}" \
		--parameters vmssName="${vmssName}" sshKeyData="${SSH_KEY}" certData="${AG_CERT}" certPassword="12345" CAcertData="${ROOT_CA}" Share=${shareName} ShareAccount=${AZURE_STORAGE_ACCOUNT} SharePassword=${AZURE_STORAGE_ACCESS_KEY}
)

if [ $? == 0 ];
 then
	echo "Template has been successfully deployed"
fi

# Get vpn server name
[ -d tmp/vpn ] && rm -rf tmp/vpn.zip tmp/vpn
VPN_URL=`az network vnet-gateway vpn-client generate --resource-group "$resourceGroupName" --name "${vmssName}vpngw" | sed -e 's/"//g'`
curl "${VPN_URL}" -o tmp/vpn.zip
unzip tmp/vpn.zip -d tmp/vpn
VPN_SERVER=`cat tmp/vpn/Generic/VpnSettings.xml | grep VpnServer | sed -ne 's/.*<VpnServer>\(.*\)<\/VpnServer>.*/\1/p'`
echo
echo "Vpn endpoint  : ${VPN_SERVER}"
echo
echo "Site endpoint : http://${CERT_SERVER_NAME}"
