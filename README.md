# Description:
It's a sample project for studying Azure automation, not for production use.
It creates WordPress Scale Set, applicate gateway as L7 balancer, MySQL database,
and VPN point-to-site gateway to access virtual network. It also generates sample
certificates for https and for creating VPN connection.

## Main statements:
1. Ubuntu 16.04 image for VM in a Scale Set
2. File Storage as shared storage for static WordPress files
   (https://docs.microsoft.com/ru-ru/azure/storage/files/storage-how-to-use-files-linux)
3. Azure deployment templates used for creating most of resources
4. Application gateway used to access WordPress, with https only access
5. IKEv2 certificate based VPN connection used to connect to virutal network
6. Create ssh keys for authentication on VM in a scale set

# Installation:
1. Execute ./run_deploy.sh
2. Import tmp/CAcert.crt as trusted CA on client PC
3. Import VPNClient1.pfx as client certificate for vpn on client PC
4. Configure VPN connection using client certficate, using VPN endpoint from the output
5. Connect to WordPress using url endpoint from the output and complete installation

It takes about half an hour to provision configuration on Azure.
