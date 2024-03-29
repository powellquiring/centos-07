#!/bin/bash

log_info "${BASH_SOURCE[0]}: Running SSH script $vsi_ssh_init on $vsi_name using IP address $vsi_ipv4_address."

floating_ip=$(jq -r '.vpc[].virtual_server_instances[]? | select(.type == "cockroachdb-admin") | .floating_ip.address' ${configFile})

log_info "Checking if ${vsi_name} is ready for SSH using ${floating_ip} as jump host."
ssh -F "${config_template_file_dir}/ssh-init/ssh.config" -J root@${floating_ip} root@${vsi_ipv4_address} -t 'true'
return_value=$?
[ $return_value -ne 0 ] && log_warning "${BASH_SOURCE[0]}: Error SSH on ${vsi_ipv4_address}." && is_ssh_ready=false
[ $return_value -eq 0 ] && is_ssh_ready=true

until [ "$is_ssh_ready" = true ]; do
  log_warning "${FUNCNAME[0]}: Sleeping for 30 seconds while waiting for ${vsi_name} to be ready for SSH."
  sleep 30
  
  log_info "Checking if ${vsi_name} is ready for SSH using ${floating_ip} as jump host."
  ssh -F "${config_template_file_dir}/ssh-init/ssh.config" -J root@${floating_ip} root@${vsi_ipv4_address} -t 'true'
  return_value=$?
  [ $return_value -ne 0 ] && log_warning "${BASH_SOURCE[0]}: Error SSH on ${vsi_ipv4_address}." && is_ssh_ready=false
  [ $return_value -eq 0 ] && is_ssh_ready=true
done

certs_directory=certs
ca_directory=cas

if [ ! -f "${config_template_file_dir}/local/certs/${vsi_ipv4_address}.node.key" ]; then
  log_info "${BASH_SOURCE[0]}: Copying certs to local directory for ${vsi_ipv4_address} using ${floating_ip} as jump host."
  if [ ! -z ${floating_ip} ]; then
    scp -F "${config_template_file_dir}/ssh-init/ssh.config" -r root@${floating_ip}:/${certs_directory} ${config_template_file_dir}/local/
    return_value=$?
    [ $return_value -ne 0 ] && log_warning "${BASH_SOURCE[0]}: Error copying ${certs_directory} directory from ${floating_ip}." && is_ready=false
    [ $return_value -eq 0 ] && is_ready=true

    until [ "$is_ready" = true ]; do
      log_warning "${FUNCNAME[0]}: Sleeping for 30 seconds while waiting for all cloud-init activities to complete."
      sleep 30
      
      scp -F "${config_template_file_dir}/ssh-init/ssh.config" -r root@${floating_ip}:/${certs_directory} ${config_template_file_dir}/local/
      return_value=$?
      [ $return_value -ne 0 ] && log_warning "${BASH_SOURCE[0]}: Error copying ${certs_directory} directory from ${floating_ip}." && is_ready=false
      [ $return_value -eq 0 ] && is_ready=true
    done    

    scp -F "${config_template_file_dir}/ssh-init/ssh.config" -r root@${floating_ip}:/${ca_directory} ${config_template_file_dir}/local/
    return_value=$?
    [ $return_value -ne 0 ] && log_warning "${BASH_SOURCE[0]}: Error copying ${ca_directory} directory from ${floating_ip}." && is_ready=false
    [ $return_value -eq 0 ] && is_ready=true

    until [ "$is_ready" = true ]; do
      log_warning "${FUNCNAME[0]}: Sleeping for 30 seconds while waiting for all cloud-init activities to complete."
      sleep 30
      
      scp -F "${config_template_file_dir}/ssh-init/ssh.config" -r root@${floating_ip}:/${ca_directory} ${config_template_file_dir}/local/
      return_value=$?
      [ $return_value -ne 0 ] && log_warning "${BASH_SOURCE[0]}: Error copying ${ca_directory} directory from ${floating_ip}." && is_ready=false
      [ $return_value -eq 0 ] && is_ready=true
    done   

  fi
fi

if [ ! -f "${config_template_file_dir}/local/${vsi_ipv4_address}.cockroachdb.service.done" ]; then

    log_info "${BASH_SOURCE[0]}: Getting IP addresses for all cockroachdb nodes."
    vsi_ipv4_addresses=$(jq -r '.vpc[].virtual_server_instances[]? | select(.type == "cockroachdb") | .primary_network_interface.primary_ipv4_address' ${configFile} | tr -d '\r')
    for address in $vsi_ipv4_addresses; do
        join_list_temp=${join_list_temp},${address}
    done

    store_directory="/data/cockroach"
    store_certs_directory="/data/certs"
    join_list=$(echo "${join_list_temp}" | sed 's/,//')

    ExecStart="/usr/local/bin/cockroach start --certs-dir=${store_certs_directory} --store=${store_directory} --listen-addr=${vsi_ipv4_address} --join=${join_list} --cache=.25 --max-sql-memory=.25"

    log_info "${BASH_SOURCE[0]}: Creating cockroachdb service configuration with $ExecStart."

cat > "${config_template_file_dir}/local/${vsi_ipv4_address}.cockroachdb.service" <<- EOF
[Unit]
Description=Cockroach Database cluster node
Requires=network.target
[Service]
Type=notify
WorkingDirectory=/var/lib/cockroach
ExecStart=$ExecStart
TimeoutStopSec=60
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=cockroach
User=cockroach
[Install]
WantedBy=default.target
EOF

    if [ ! -z ${floating_ip} ]; then
        log_info "${BASH_SOURCE[0]}: Copying service configuration to node ${vsi_ipv4_address} using ${floating_ip} as jump host."
        scp -F "${config_template_file_dir}/ssh-init/ssh.config" -r -o "ProxyJump root@${floating_ip}" "${config_template_file_dir}/local/${vsi_ipv4_address}.cockroachdb.service" root@${vsi_ipv4_address}:/etc/systemd/system/cockroachdb.service
        [ $? -ne 0 ] && log_error "${BASH_SOURCE[0]}: Error copying service configuration to node ${vsi_ipv4_address}." && return 1

        log_info "${BASH_SOURCE[0]}: Creating certs directory on node ${vsi_ipv4_address} using ${floating_ip} as jump host."
        ssh -F "${config_template_file_dir}/ssh-init/ssh.config" -J root@${floating_ip} root@${vsi_ipv4_address} -t 'mkdir -p /data/certs'
        [ $? -ne 0 ] && log_warning "${BASH_SOURCE[0]}: cockroachdb service started with a warning on node ${vsi_ipv4_address}."

        log_info "${BASH_SOURCE[0]}: Copying certs to node ${vsi_ipv4_address} using ${floating_ip} as jump host."
        scp -F "${config_template_file_dir}/ssh-init/ssh.config" -r -o "ProxyJump root@${floating_ip}" "${config_template_file_dir}/local/certs/${vsi_ipv4_address}.node.key" root@${vsi_ipv4_address}:${store_certs_directory}/node.key
        [ $? -ne 0 ] && log_error "${BASH_SOURCE[0]}: Error copying node.key to node ${vsi_ipv4_address}." && return 1
        
        scp -F "${config_template_file_dir}/ssh-init/ssh.config" -r -o "ProxyJump root@${floating_ip}" "${config_template_file_dir}/local/certs/${vsi_ipv4_address}.node.crt" root@${vsi_ipv4_address}:${store_certs_directory}/node.crt
        [ $? -ne 0 ] && log_error "${BASH_SOURCE[0]}: Error copying node.crt to node ${vsi_ipv4_address}." && return 1

        scp -F "${config_template_file_dir}/ssh-init/ssh.config" -r -o "ProxyJump root@${floating_ip}" "${config_template_file_dir}/local/certs/ca.crt" root@${vsi_ipv4_address}:${store_certs_directory}/ca.crt
        [ $? -ne 0 ] && log_error "${BASH_SOURCE[0]}: Error copying node.crt to node ${vsi_ipv4_address}." && return 1

        log_info "${BASH_SOURCE[0]}: Setting ownership of files in certs directory to cockroach for node ${vsi_ipv4_address} using ${floating_ip} as jump host."
        ssh -F "${config_template_file_dir}/ssh-init/ssh.config" -J root@${floating_ip} root@${vsi_ipv4_address} -t 'chown -R cockroach /data/certs && chmod 700 /data/certs/*'
        return_value=$?
        [ $return_value -ne 0 ] && log_warning "${BASH_SOURCE[0]}: Error setting permissions for cockroach user on ${vsi_ipv4_address}." && is_ready=false
        [ $return_value -eq 0 ] && is_ready=true

        until [ "$is_ready" = true ]; do
          log_warning "${FUNCNAME[0]}: Sleeping for 30 seconds while waiting for all cloud-init activities to complete."
          sleep 30
          
          log_info "${BASH_SOURCE[0]}: Setting ownership of files in certs directory to cockroach for node ${vsi_ipv4_address} using ${floating_ip} as jump host."
          ssh -F "${config_template_file_dir}/ssh-init/ssh.config" -J root@${floating_ip} root@${vsi_ipv4_address} -t 'chown -R cockroach /data/certs && chmod 700 /data/certs/*'
          return_value=$?
          [ $return_value -ne 0 ] && log_warning "${BASH_SOURCE[0]}: Error setting permissions for cockroach user on ${vsi_ipv4_address}." && is_ready=false
          [ $return_value -eq 0 ] && is_ready=true
        done
        
        log_info "${BASH_SOURCE[0]}: Initiating start of cockroachdb service for node ${vsi_ipv4_address} using ${floating_ip} as jump host."
        ssh -F "${config_template_file_dir}/ssh-init/ssh.config" -J root@${floating_ip} root@${vsi_ipv4_address} -t 'systemctl start cockroachdb'
        [ $? -ne 0 ] && log_warning "${BASH_SOURCE[0]}: cockroachdb service started with a warning on node ${vsi_ipv4_address}."

        sleep 5
        mv "${config_template_file_dir}/local/${vsi_ipv4_address}.cockroachdb.service" "${config_template_file_dir}/local/${vsi_ipv4_address}.cockroachdb.service.done"

        iam_oauth_tokens=$(ibmcloud iam oauth-tokens --output json)
        [ $? -ne 0 ] && log_error "${FUNCNAME[0]}: Error reading iam oauth-tokens ${iam_oauth_tokens}." && return 1

        iam_token=$(echo "$iam_oauth_tokens" | jq -r '.iam_token')

        cm_uri=${region}.certificate-manager.cloud.ibm.com
        cm_crn=$(jq -r '.service_instances[]? | select(.service_name == "cloudcerts") | .crn' ${configFile} | tr -d '\r\n' | curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" | cut -c 3-)

        certificate=$(cat "${config_template_file_dir}/local/certs/${vsi_ipv4_address}.node.crt" | jq -Rsr 'tojson')
        privateKey=$(cat "${config_template_file_dir}/local/certs/${vsi_ipv4_address}.node.key" | jq -Rsr 'tojson')
        intermediate=$(cat "${config_template_file_dir}/local/certs/ca.crt" | jq -Rsr 'tojson')

cat > "${config_template_file_dir}/local/${vsi_ipv4_address}.cert.json" <<- EOF
{ 
  "name": "$vsi_ipv4_address", 
  "description": "", 
  "data": 
  { 
    "content": $certificate, 
    "priv_key": $privateKey, 
    "intermediate": $intermediate 
  } 
}
EOF
        curl -X POST -H "Content-Type: application/json" -H "authorization: ${iam_token}" -d @${config_template_file_dir}/local/${vsi_ipv4_address}.cert.json "https://${cm_uri}/api/v3/${cm_crn}/certificates/import"

    else
        log_error "${BASH_SOURCE[0]}: Error obtaining floating IP for admin server."
        return 1
    fi

    unset join_list_temp
    unset join_list

fi

log_info "${BASH_SOURCE[0]}: Completed SSH script $vsi_ssh_init on $vsi_name using IP address $vsi_ipv4_address."
