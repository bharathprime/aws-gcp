
project_id="gcp-project-id"
gcp_vpc=""
gcp_region=""
# Define PreSharedKeys
PSK1="S_Ap9ZkLmXyT38xxxxxxxxxxxxxxxx"
PSK2="V_Mq7WrJtKcXp9xxxxxxxxxxxxxxxx"
PSK3="T_Hd5XwVrLqMp8xxxxxxxxxxxxxxxx"
PSK4="R_Kf6BnVpLzXt3xxxxxxxxxxxxxxxx"

#----------------------------------- List all GCP regions and select one ---------------------------

# Get list of regions
REGIONS=$(gcloud compute regions list --format="value(name)")

# Convert into array
mapfile -t REGION_LIST < <(echo "$REGIONS")

# Display numbered menu
echo "Available GCP Regions:"
i=1
for region in "${REGION_LIST[@]}"; do
  echo " $i) $region"
  ((i++))
done

# Prompt user to select
read -p "Select a region number: " choice

# Validate selection
if [[ "$choice" -lt 1 || "$choice" -gt ${#REGION_LIST[@]} ]]; then
  echo "❌ Invalid choice"
  exit 1
fi

# Store selected region in variable
gcp_region="${REGION_LIST[$((choice-1))]}"

echo "✅ You selected GCP Region: $gcp_region"

#----------------------------------- Get gcp vpc ------------------------------------
# Get list of VPC network names
VPCS=$(gcloud compute networks list --format="value(name)")

# Convert into array
mapfile -t VPC_LIST < <(echo "$VPCS")

# Display numbered menu
echo "Available GCP VPCs:"
i=1
for vpc in "${VPC_LIST[@]}"; do
  echo " $i) $vpc"
  ((i++))
done

# Prompt user to select
read -p "Select a VPC number: " choice

# Validate selection
if [[ "$choice" -lt 1 || "$choice" -gt ${#VPC_LIST[@]} ]]; then
  echo "❌ Invalid choice"
  exit 1
fi

# Store selected VPC name in variable
gcp_vpc="${VPC_LIST[$((choice-1))]}"

echo "✅ You selected GCP VPC: $gcp_vpc"

#---------------check PSC----------------

PEERING=$(gcloud services vpc-peerings list \
  --network=$gcp_vpc \
  --format="value(peering)")

if [[ "$PEERING" == "servicenetworking-googleapis-com" ]]; then
    echo "✅   Peering exists: $PEERING"
    # Continue with your logic here
else
    echo "❌   Peering not found, exiting..."
    exit 1
fi

echo "Enabling Custom routes for servicenetworking-googleapis-com in $gcp_vpc"
gcloud compute networks peerings update servicenetworking-googleapis-com \
  --network=$gcp_vpc \
  --export-custom-routes \
  --import-custom-routes

#------------------------get aws vpc ----------------------
#!/bin/bash
# List all VPCs with Name, VPC ID, and CIDR and select one

# Get VPCs: Name, ID, and CIDR
VPCS=$(aws ec2 describe-vpcs \
  --query "Vpcs[].{Name:Tags[?Key=='Name']|[0].Value,ID:VpcId,CIDR:CidrBlock}" \
  --output text)

# Convert into an array
mapfile -t VPC_LIST < <(echo "$VPCS")

# Display numbered menu
echo "Available VPCs:"
i=1
for vpc in "${VPC_LIST[@]}"; do
  # Split fields
  VPC_NAME=$(echo "$vpc" | awk '{print $1}')
  VPC_ID=$(echo "$vpc" | awk '{print $2}')
  VPC_CIDR=$(echo "$vpc" | awk '{print $3}')

  # If Name is empty or None, set to NoName
  if [[ -z "$VPC_NAME" || "$VPC_NAME" == "None" ]]; then
    VPC_NAME="NoName"
  fi

  echo " $i) $VPC_NAME  |  $VPC_ID  |  $VPC_CIDR"
  ((i++))
done

# Prompt user to select
read -p "Select a VPC number: " choice

# Validate selection
if [[ "$choice" -lt 1 || "$choice" -gt ${#VPC_LIST[@]} ]]; then
  echo "❌ Invalid choice"
  exit 1
fi

# Extract selected VPC info
SELECTED_VPC=$(echo "${VPC_LIST[$((choice-1))]}")
VPC_NAME=$(echo "$SELECTED_VPC" | awk '{print $1}')
VPC_ID=$(echo "$SELECTED_VPC" | awk '{print $2}')
VPC_CIDR=$(echo "$SELECTED_VPC" | awk '{print $3}')

# Fix Name if empty
if [[ -z "$VPC_NAME" || "$VPC_NAME" == "None" ]]; then
  VPC_NAME="NoName"
fi

echo "✅ You selected VPC: $VPC_NAME  |  $VPC_ID  |  $VPC_CIDR"

#--- vpc ip get end ---
aws_vpc=$VPC_ID

gcloud config set project $project_id
gcloud compute vpn-gateways create havpn \
    --network $gcp_vpc \
    --region $gcp_region

psc_ranges=$(gcloud compute addresses list \
  --global \
  --filter="purpose=VPC_PEERING" \
  --format="value(address, prefixLength)" \
  | awk '{print $1"/"$2}' \
  | paste -sd, -)

if [[ -z "$psc_ranges" ]]; then
  echo "❌ No PSC allocated ranges found. Exiting..."
  exit 1
fi

echo "✅ Found PSC ranges: $psc_ranges"

gcloud compute routers create migrationcr \
  --region=$gcp_region \
  --network=$gcp_vpc \
  --asn=65534 \
  --advertisement-mode=custom \
  --set-advertisement-groups=all_subnets \
  --set-advertisement-ranges=$psc_ranges


# Get VPN interface IPs
gcpif1=$(gcloud compute vpn-gateways describe havpn \
  --region=$gcp_region \
  --format="value(vpnInterfaces[0].ipAddress)")

gcpif2=$(gcloud compute vpn-gateways describe havpn \
  --region=$gcp_region \
  --format="value(vpnInterfaces[1].ipAddress)")

echo "First VPN interface IP: $gcpif1"
echo "Second VPN interface IP: $gcpif2"


# Create Customer Gateway for GCP Interface 1
CGW1_ID=$(aws ec2 create-customer-gateway \
    --type ipsec.1 \
    --public-ip $gcpif1 \
    --bgp-asn 65534 \
    --query 'CustomerGateway.CustomerGatewayId' \
    --output text)

echo "Customer Gateway 1 ID: $CGW1_ID"

# Create Customer Gateway for GCP Interface 2
CGW2_ID=$(aws ec2 create-customer-gateway \
    --type ipsec.1 \
    --public-ip $gcpif2 \
    --bgp-asn 65534 \
    --query 'CustomerGateway.CustomerGatewayId' \
    --output text)

echo "Customer Gateway 2 ID: $CGW2_ID"


#aws ec2 create-vpn-gateway --type ipsec.1 --amazon-side-asn 65001

# Create the VPN Gateway
VGW_ID=$(aws ec2 create-vpn-gateway \
    --type ipsec.1 \
    --amazon-side-asn 65001 \
    --query 'VpnGateway.VpnGatewayId' \
    --output text)

# Print the stored Gateway ID
echo $VGW_ID


# Wait until VGW is available
echo "Waiting for VGW $VGW_ID to become available..."
#aws ec2 wait vpn-gateway-available --vpn-gateway-ids $VGW_ID
sleep 5
aws ec2 attach-vpn-gateway --vpn-gateway-id $VGW_ID --vpc-id $aws_vpc

echo "Waiting for VGW $VGW_ID to be attached to VPC $VPC_ID..."
while true; do
    STATE=$(aws ec2 describe-vpn-gateways \
        --vpn-gateway-ids $VGW_ID \
        --query 'VpnGateways[0].VpcAttachments[0].State' \
        --output text)

    echo "VGW state: $STATE"
    if [ "$STATE" == "attached" ]; then
        break
    fi
    sleep 10
done

# Example for CGW1
VPN1_ID=$(aws ec2 create-vpn-connection \
    --type ipsec.1 \
    --customer-gateway-id $CGW1_ID \
    --vpn-gateway-id $VGW_ID \
    --options TunnelOptions="[{TunnelInsideCidr=169.254.10.0/30,PreSharedKey=$PSK1},{TunnelInsideCidr=169.254.11.0/30,PreSharedKey=$PSK2}]" \
    --query 'VpnConnection.VpnConnectionId' \
    --output text)

echo "Waiting for VPN connection $VPN1_ID to become available..."
#aws ec2 wait vpn-connection-available --vpn-connection-ids $VPN1_ID
sleep 5
# Example for CGW2
VPN2_ID=$(aws ec2 create-vpn-connection \
    --type ipsec.1 \
    --customer-gateway-id $CGW2_ID \
    --vpn-gateway-id $VGW_ID \
    --options TunnelOptions="[{TunnelInsideCidr=169.254.12.0/30,PreSharedKey=$PSK3},{TunnelInsideCidr=169.254.13.0/30,PreSharedKey=$PSK4}]" \
    --query 'VpnConnection.VpnConnectionId' \
    --output text)

echo "Waiting for VPN connection $VPN2_ID to become available..."
#aws ec2 wait vpn-connection-available --vpn-connection-ids $VPN2_ID
sleep 5
# For VPN1
AWS_GW_IP_1=$(aws ec2 describe-vpn-connections \
    --vpn-connection-ids $VPN1_ID \
    --query 'VpnConnections[0].Options.TunnelOptions[0].OutsideIpAddress' \
    --output text)

AWS_GW_IP_2=$(aws ec2 describe-vpn-connections \
    --vpn-connection-ids $VPN1_ID \
    --query 'VpnConnections[0].Options.TunnelOptions[1].OutsideIpAddress' \
    --output text)

# For VPN2
AWS_GW_IP_3=$(aws ec2 describe-vpn-connections \
    --vpn-connection-ids $VPN2_ID \
    --query 'VpnConnections[0].Options.TunnelOptions[0].OutsideIpAddress' \
    --output text)

AWS_GW_IP_4=$(aws ec2 describe-vpn-connections \
    --vpn-connection-ids $VPN2_ID \
    --query 'VpnConnections[0].Options.TunnelOptions[1].OutsideIpAddress' \
    --output text)

gcloud compute external-vpn-gateways create aws-peer-gw \
  --interfaces 0=$AWS_GW_IP_1,1=$AWS_GW_IP_2,2=$AWS_GW_IP_3,3=$AWS_GW_IP_4

gcloud compute vpn-tunnels create tunnel-1 \
    --peer-external-gateway aws-peer-gw \
    --peer-external-gateway-interface 0 \
    --region $gcp_region \
    --ike-version 2 \
    --shared-secret $PSK1 \
    --router migrationcr \
    --vpn-gateway havpn \
    --interface 0

gcloud compute vpn-tunnels create tunnel-2 \
    --peer-external-gateway aws-peer-gw \
    --peer-external-gateway-interface 1 \
    --region $gcp_region \
    --ike-version 2 \
    --shared-secret $PSK2 \
    --router migrationcr \
    --vpn-gateway havpn \
    --interface 0

gcloud compute vpn-tunnels create tunnel-3 \
    --peer-external-gateway aws-peer-gw \
    --peer-external-gateway-interface 2 \
    --region $gcp_region \
    --ike-version 2 \
    --shared-secret $PSK3 \
    --router migrationcr \
    --vpn-gateway havpn \
    --interface 1

gcloud compute vpn-tunnels create tunnel-4 \
    --peer-external-gateway aws-peer-gw \
    --peer-external-gateway-interface 3 \
    --region $gcp_region \
    --ike-version 2 \
    --shared-secret $PSK4 \
    --router migrationcr \
    --vpn-gateway havpn \
    --interface 1
sleep 30
# cloud router
gcloud compute routers add-interface migrationcr \
    --interface-name int-1 \
    --vpn-tunnel tunnel-1 \
    --ip-address 169.254.10.2 \
    --mask-length 30 \
    --region $gcp_region

gcloud compute routers add-interface migrationcr \
    --interface-name int-2 \
    --vpn-tunnel tunnel-2 \
    --ip-address 169.254.11.2 \
    --mask-length 30 \
    --region $gcp_region

gcloud compute routers add-interface migrationcr \
    --interface-name int-3 \
    --vpn-tunnel tunnel-3 \
    --ip-address 169.254.12.2 \
    --mask-length 30 \
    --region $gcp_region

gcloud compute routers add-interface migrationcr \
    --interface-name int-4 \
    --vpn-tunnel tunnel-4 \
    --ip-address 169.254.13.2 \
    --mask-length 30 \
    --region $gcp_region

gcloud compute routers add-bgp-peer migrationcr \
    --peer-name aws-conn1-tunn1 \
    --peer-asn 65001 \
    --interface int-1 \
    --peer-ip-address 169.254.10.1 \
    --region $gcp_region

gcloud compute routers add-bgp-peer migrationcr \
    --peer-name aws-conn1-tunn2 \
    --peer-asn 65001 \
    --interface int-2 \
    --peer-ip-address 169.254.11.1 \
    --region $gcp_region

gcloud compute routers add-bgp-peer migrationcr \
    --peer-name aws-conn2-tunn1 \
    --peer-asn 65001 \
    --interface int-3 \
    --peer-ip-address 169.254.12.1 \
    --region $gcp_region

gcloud compute routers add-bgp-peer migrationcr \
    --peer-name aws-conn2-tunn2 \
    --peer-asn 65001 \
    --interface int-4 \
    --peer-ip-address 169.254.13.1 \
    --region $gcp_region

gcloud compute routers get-status migrationcr \
    --region $gcp_region \
    --format='flattened(result.bgpPeerStatus[].name, result.bgpPeerStatus[].ipAddress, result.bgpPeerStatus[].peerIpAddress)'
gcloud compute vpn-tunnels list
gcloud compute vpn-tunnels describe tunnel-1 \
     --region $gcp_region \
     --format='flattened(status,detailedStatus)'

gcloud compute routers get-status migrationcr \
    --region $gcp_region \
    --format="flattened(result.bestRoutes)"

# Get the VPN Gateway ID attached to the VPC
VGW_ID=$(aws ec2 describe-vpn-gateways \
  --filters "Name=attachment.vpc-id,Values=$aws_vpc" \
  --query "VpnGateways[0].VpnGatewayId" \
  --output text)

if [[ "$VGW_ID" == "None" || -z "$VGW_ID" ]]; then
  echo "❌ No VPN Gateway found attached to VPC $aws_vpc"
  exit 1
fi

echo "✅ Found VPN Gateway: $VGW_ID attached to VPC $aws_vpc"

# Get all Route Table IDs in the VPC
RTB_IDS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$aws_vpc" \
  --query "RouteTables[*].RouteTableId" \
  --output text)

# Loop through and enable route propagation
for RTB_ID in $RTB_IDS; do
  echo "🔄 Enabling route propagation on Route Table: $RTB_ID"
  aws ec2 enable-vgw-route-propagation \
    --route-table-id $RTB_ID \
    --gateway-id $VGW_ID
done

echo "Route propagation enabled for all Route Tables in VPC $aws_vpc"

