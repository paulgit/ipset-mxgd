#!/bin/bash
#
# usage update-blacklist.sh <configuration file>
# eg: update-blacklist.sh /etc/ipset-blacklist/ipset-blacklist.conf
#
function exists() { command -v "$1" >/dev/null 2>&1 ; }

if [[ -z "$1" ]]; then
  echo "Error: please specify a configuration file, e.g. $0 /etc/ipset-mxgd/ipset-mxgd.conf"
  exit 1
fi

# shellcheck source=ipset-mxgd.conf
if ! source "$1"; then
  echo "Error: can't load configuration file $1"
  exit 1
fi

if ! exists curl && exists egrep && exists grep && exists ipset && exists iptables && exists sed && exists sort && exists wc ; then
  echo >&2 "Error: searching PATH fails to find executables among: curl egrep grep ipset iptables sed sort wc"
  exit 1
fi

if [[ ! -d $(dirname "$IP_MXGD_LIST") || ! -d $(dirname "$IP_MXGD_RESTORE") ]]; then
  echo >&2 "Error: missing directory(s): $(dirname "$IP_MXGD_LIST" "$IP_MXGD_RESTORE"|sort -u)"
  exit 1
fi

# create the ipset if needed (or abort if does not exists and FORCE=no)
if ! ipset list -n|command grep -q "$IPSET_MXGD_NAME"; then
  if [[ ${FORCE:-no} != yes ]]; then
    echo >&2 "Error: ipset does not exist yet, add it using:"
    echo >&2 "# ipset create $IPSET_MXGD_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}"
    exit 1
  fi
  if ! ipset create "$IPSET_MXGD_NAME" -exist hash:net family inet hashsize "${HASHSIZE:-16384}" maxelem "${MAXELEM:-65536}"; then
    echo >&2 "Error: while creating the initial ipset"
    exit 1
  fi
fi

if ! iptables -nvL INPUT|command grep -q "match-set $IPSET_MXGD_NAME"; then
  # we may also have assumed that INPUT rule n°1 is about packets statistics (traffic monitoring)
  if [[ ${FORCE:-no} != yes ]]; then
    echo >&2 "Error: iptables does not have the needed ipset INPUT rule, add it using:"
    echo >&2 "# iptables -A INPUT -m set --match-set $IPSET_MXGD_NAME src -p tcp --dport $IPTABLES_RULE_PORT -j ACCEPT"
    exit 1
  fi
  if ! iptables -A INPUT  -m set --match-set "$IPSET_MXGD_NAME" src -p tcp --dport $IPTABLES_RULE_PORT -j ACCEPT; then
    echo >&2 "Error: while adding the --match-set ipset rule to iptables"
    exit 1
  fi
fi

IP_MXGD_TMP=$(mktemp)

# look up the A DNS record and filter out only valid IP addresses (this should only return valid IP addresses)
dig +short $DNSRECORD A | grep -Po '\b(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\b' >> "$IP_MXGD_TMP"

# Make sure we have some IP addresses
if [ $(wc -l "$IP_MXGD_TMP" | cut -d' ' -f1) == 0 ]; then
  if [[ ${VERBOSE:-no} == yes ]]; then
    echo >&2 "Error: DNS A Record for $DNSRECORD returned no IP addresses"
  fi
  exit 1
fi

cp "$IP_MXGD_TMP" "$IP_MXGD_LIST"
rm -f "$IP_MXGD_TMP"

# Output IP details if Verbose mode is on
if [[ ${VERBOSE:-no} == yes ]]; then
  echo >&2 "DNS A Record for $DNSRECORD returned the following:"
  echo >&2 "$(<$IP_MXGD_LIST)"
fi

# family = inet for IPv4 only
cat >| "$IP_MXGD_RESTORE" <<EOF
create $IPSET_MXGD_TMP_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
create $IPSET_MXGD_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
EOF

# can be IPv4 including netmask notation
# IPv6 ? -e "s/^([0-9a-f:./]+).*/add $IPSET_TMP_BLACKLIST_NAME \1/p" \ IPv6
sed -rn -e "s/^(.+)$/add $IPSET_MXGD_TMP_NAME \\1/p" "$IP_MXGD_LIST" >> "$IP_MXGD_RESTORE"

cat >> "$IP_MXGD_RESTORE" <<EOF
swap $IPSET_MXGD_NAME $IPSET_MXGD_TMP_NAME
destroy $IPSET_MXGD_TMP_NAME
EOF

ipset -file  "$IP_MXGD_RESTORE" restore

exit 0
