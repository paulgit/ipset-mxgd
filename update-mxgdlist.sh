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

# TODO: IPTABLES rule needs to be for a specific port or port range??

# does not have the needed ipset INPUT rule, add it using:"
#     echo >&2 "# iptables -I INPUT ${IPTABLES_IPSET_RULE_NUMBER:-1} -m set --match-set $IPSET_MXGD_NAME src -j DROP"
#     exit 1
#   fi
#   if ! iptables -I INPUT "${IPTABLES_IPSET_RULE_NUMBER:-1}" -m set --match-set "$IPSET_MXGD_NAME" src -j DROP; then
#     echo >&2 "Error: while adding the --match-set ipset rule to iptables"
#     exit 1
#   fi
# fi

IP_MXGD_TMP=$(mktemp)
for i in "${DNSRECORDS[@]}"
do
  IP_TMP=$(mktemp)
  dig +short $DNSRECORD >$IP_TMP
  # TODO: check error from dig
  command grep -Po '^(?:\d{1,3}.){3}\d{1,3}(?:/\d{1,2})?' "$IP_TMP" | sed -r 's/^0*([0-9]+)\.0*([0-9]+)\.0*([0-9]+)\.0*([0-9]+)$/\1.\2.\3.\4/' >> "$IP_MXGD_TMP"
  rm -f "$IP_TMP"
done

# sort -nu does not work as expected
sed -r -e '/^(0\.0\.0\.0|10\.|127\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|192\.168\.|22[4-9]\.|23[0-9]\.)/d' "$IP_MXGD_TMP"|sort -n|sort -mu >| "$IP_MXGD_LIST"
rm -f "$IP_MXGD_TMP"

# TODO: If there are no IPs then we want to bail out at this point because something has gone wrong or dig didn't work. We may want to consider a failsafe and remove
# the iptable rule

# family = inet for IPv4 only
cat >| "$IP_MXGD_RESTORE" <<EOF
create $IPSET_MXGD_TMP_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
create $IPSET_MXGD_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
EOF

# can be IPv4 including netmask notation
# IPv6 ? -e "s/^([0-9a-f:./]+).*/add $IPSET_TMP_BLACKLIST_NAME \1/p" \ IPv6
sed -rn -e '/^#|^$/d' \
  -e "s/^([0-9./]+).*/add $IPSET_MXGD_TMP_NAME \\1/p" "$IP_MXGD_LIST" >> "$IP_MXGD_RESTORE"

cat >> "$IP_MXGD_RESTORE" <<EOF
swap $IPSET_MXGD_NAME $IPSET_MXGD_TMP_NAME
destroy $IPSET_MXGD_TMP_NAME
EOF

ipset -file  "$IP_MXGD_RESTORE" restore

if [[ ${VERBOSE:-no} == yes ]]; then
  echo
  echo "Number of MX Guarddog IPs found: $(wc -l "$IP_MXGD_LIST" | cut -d' ' -f1)"
fi
