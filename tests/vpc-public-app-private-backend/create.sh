#!/bin/bash
set -e
set -o pipefail
source $(dirname "$0")/common.sh

# deploy to first zone in the selected region
ZONE=$(ibmcloud is zones --json | jq -r .[].name | sort | head -1)
echo "Region is $REGION, zone is $ZONE"

# create the VPC that will be reused by the following scripts
ibmcloud is vpc-create $TEST_VPC_NAME --resource-group-name $RESOURCE_GROUP
export REUSE_VPC=$TEST_VPC_NAME

# provision resources
bash ./vpc-public-app-private-backend/vpc-pubpriv-create-with-bastion.sh $ZONE $KEYS at$JOB_ID- $RESOURCE_GROUP resources.sh

# verify software installed
source resources.sh
test_curl $FRONT_IP_ADDRESS '' 'I am the frontend server'

# ssh is not working.  The private ssh key matching the key in the bastion and frontend are likely not in the test environment
# These two are for debugging
# ssh -F ./scripts/ssh.notstrict.config -o ProxyJump=root@$BASTION_IP_ADDRESS root@$FRONT_NIC_IP uname -a
# ssh -F ./scripts/ssh.notstrict.config -o ProxyJump=root@$BASTION_IP_ADDRESS root@$FRONT_NIC_IP curl $BACK_NIC_IP
# test_curl $BACK_NIC_IP "ssh -F ./scripts/ssh.notstrict.config -o ProxyJump=root@$BASTION_IP_ADDRESS root@$FRONT_NIC_IP" 'I am the backend server'
