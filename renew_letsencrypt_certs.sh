#!/bin/bash

script_path=$(dirname $0)
log_file=renew_letsencrypt_certs.log

exec 3>&1 4>&2 1>"$script_path/$log_file" 2>&1

# Print header information
echo -e "Shell script to renew certificates wtih Let's Encrypt."

# ------------------------------------------------------------------------------
# Functions
#

# Check and/or update letsencrypt path
check_letsencrypt_paths() {
  if [[ ! $letsencrypt_bin_path ]]; then
    letsencrypt_bin_path=/root/letsencrypt
  fi
  if [[ ! $letsencrypt_cert_path ]]; then
    letsencrypt_cert_path=/etc/letsencrypt
  fi
}

# Check and/or update Plesk Cert path
check_plesk_path() {
  if [[ -z $plesk_cert_path ]]; then
    plesk_cert_path=/usr/local/psa/var/certificates
  fi
}

# Do the actual renewing
call_renew() {
  check_letsencrypt_paths
  check_plesk_path

  echo -e "\nProcessing $name"

  if [[ -z $domains ]]; then
    echo ERROR: \$domain must not be empty
    return
  fi

  # Build Let's encrypt command
  command="./letsencrypt-auto certonly --standalone --renew-by-default"

  for domain in ${domains[*]}
  do
    command="$command -d $domain"
  done

  # Execute command
  cd $letsencrypt_bin_path
  echo "Request new certificate: $command"
  $command

  # Link to existing Plesk certificate
  if [[ -n $plesk_ca ]] && [[ -n $plesk_cert ]]; then
    cert_path="$plesk_cert_path/$name"
    if [ ! -d $cert_path ]; then
      mkdir -p $cert_path
    fi

    cert=cert.$(date +%Y-%m-%d.%H:%M).pem
    ca=ca.$(date +%Y-%m-%d.%H:%M).pem

    echo "Create Plesk certificate file: $cert_path/$cert"
    cat "$letsencrypt_cert_path/live/${domains[0]}/privkey.pem" > "$cert_path/$cert"
    cat "$letsencrypt_cert_path/live/${domains[0]}/fullchain.pem" >> "$cert_path/$cert"

    echo "Create Plesk CA file: $cert_path/$ca"
    cat "$letsencrypt_cert_path/live/${domains[0]}/cert.pem" > "$cert_path/$ca"

    echo "Link Plesk certificate: $cert_path/$plesk_cert to $plesk_cert_path/$plesk_cert"
    rm "$plesk_cert_path/$plesk_cert"
    ln -s "$name/$cert" "$plesk_cert_path/$plesk_cert"

    echo "Link Plesk CA: $cert_path/$plesk_ca to $plesk_cert_path/$plesk_ca"
    rm "$plesk_cert_path/$plesk_ca"
    ln -s "$name/$ca" "$plesk_cert_path/$plesk_ca"
  fi
}


# ------------------------------------------------------------------------------
# Read config file and process
#

/usr/sbin/apachectl stop
sleep 2

while read line
do
  # Skip comments and empty lines
  ([[ $line = \#* ]] || [[ -z $line ]]) && continue

  if [[ "$line" == \[*\] ]]; then
    if [[ $name ]]; then
      call_renew
    fi

    # Reset previous values
    unset domains
    unset plesk_ca
    unset plesk_cert

    name=`expr match "$line" "\[\(.\+\)\]"`

  elif [[ "$line" == *\=* ]]; then
    # Set values
    declare $line

    if [[ $domain ]]; then
      domains[${#domains[@]}]=$domain
      unset domain
    fi
  fi
done < "$script_path/renew_letsencrypt_certs.conf"

call_renew

/usr/sbin/apachectl start

exec 1>&3 2>&4

if [[ $email ]]; then
  echo "$script_path/$log_file"
  cat "$script_path/$log_file"
  mail -s "Renew Let's Encrypt certificates" $email < "$script_path/$log_file"
fi
