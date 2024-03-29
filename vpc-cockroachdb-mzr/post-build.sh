#!/bin/bash

log_info "${BASH_SOURCE[0]}: Running post-build script. started."

floating_ip=$(jq -r '.vpc[].virtual_server_instances[]? | select(.type == "cockroachdb-admin") | .floating_ip.address' ${configFile})

log_info ""

log_success "You can access the admin instance using the following SSH command:"
log_warning "    ssh -F vpc-cockroachdb-mzr/ssh-init/ssh.config root@${floating_ip}"
log_success ""

for vsi_list in $(jq -c '.vpc[]?.virtual_server_instances[]? | select(.type == "cockroachdb")' ${configFile}); do
    vsi_name_temp=$(echo ${vsi_list} | jq -r '.name | select (.!=null)')
    primary_ipv4_address=$(echo ${vsi_list} | jq -r '.primary_network_interface.primary_ipv4_address | select (.!=null)')

    vsi_name=${resources_prefix}-${vsi_name_temp}
    for x_use_resources_prefix_key in "${x_use_resources_prefix_keys[@]}"; do
        if [ "${x_use_resources_prefix_key}" = "virtual_server_instances" ]; then
            vsi_name=${vsi_name_temp}
        fi
    done    

    log_success "You can access the cockroachdb node ${vsi_name} using the following SSH command:"
    log_warning "    ssh -F vpc-cockroachdb-mzr/ssh-init/ssh.config -J root@${floating_ip} root@${primary_ipv4_address}"
    log_success ""

    log_success "You can access the CockroachDB Web Admin UI on node ${vsi_name}, using the following SSH command:"
    log_warning "    ssh -F vpc-cockroachdb-mzr/ssh-init/ssh.config -L 8080:${primary_ipv4_address}:8080 root@${floating_ip}"
    log_success ""
    log_success " and by pointing your browser to:"
    log_warning "    http://localhost:8080" 
    log_success ""    
done

for vsi_list in $(jq -c '.vpc[]?.virtual_server_instances[]? | select(.type == "app")' ${configFile}); do
    vsi_name_temp=$(echo ${vsi_list} | jq -r '.name | select (.!=null)')
    primary_ipv4_address=$(echo ${vsi_list} | jq -r '.primary_network_interface.primary_ipv4_address | select (.!=null)')

    vsi_name=${resources_prefix}-${vsi_name_temp}
    for x_use_resources_prefix_key in "${x_use_resources_prefix_keys[@]}"; do
        if [ "${x_use_resources_prefix_key}" = "virtual_server_instances" ]; then
            vsi_name=${vsi_name_temp}
        fi
    done 

    log_success "You can access the app node ${vsi_name} using the following SSH command:"
    log_warning "    ssh -F vpc-cockroachdb-mzr/ssh-init/ssh.config -J root@${floating_ip} root@${primary_ipv4_address}"
    log_success ""   

done

for load_balancer in $(jq -c '.vpc[]?.load_balancers[]?' ${configFile} | tr -d '\r'); do
    load_balancer_name_temp=$(echo ${load_balancer} | jq -r '.name | select (.!=null)')
    load_balancer_hostname=$(echo ${load_balancer} | jq -r '.hostname | select (.!=null)')
    load_balancer_type=$(echo ${load_balancer} | jq -r '.type | select (.!=null)')
    load_balancer_listeners=$(echo ${load_balancer} | jq -c '.listeners[]? | select (.!=null)')

    if [ ! -z ${load_balancer_name_temp} ]; then
        load_balancer_name=${resources_prefix}-${load_balancer_name_temp}
        for x_use_resources_prefix_key in "${x_use_resources_prefix_keys[@]}"; do
            if [ "${x_use_resources_prefix_key}" = "load_balancers" ]; then
                load_balancer_name=${load_balancer_name_temp}
            fi
        done

        log_success "The ${load_balancer_type} load balancer ${load_balancer_name} is available using the following address:"
        log_warning "    ${load_balancer_hostname}"
        
        for load_balancer_listener in ${load_balancer_listeners}; do
            listener_protocol=$(echo ${load_balancer_listener} | jq -r '.protocol | select (.!=null)')
            listener_port=$(echo ${load_balancer_listener} | jq -r '.port | select (.!=null)')

            log_success " on ${listener_protocol} port:"
            log_warning "    ${listener_port}"
            log_success "" 
        done

    fi
done

log_success "After having created the database and table as per the instructions found here:"
log_warning "    https://github.com/IBM-Cloud/vpc-tutorials/tree/master/vpc-cockroachdb-mzr#test-the-cluster-taken-from-the-cockroachdb-documentation"

log_success "you may access a sample NodeJS app that interacts with the database:"
log_warning "    http://${load_balancer_hostname}/api/bank"

log_info "${BASH_SOURCE[0]}: Running post-build script. done."