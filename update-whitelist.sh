#!/bin/bash
#
# usage update-whitelist.sh <configuration file>
# eg: update-whitelist.sh /etc/ipset-whitelist/ipset-whitelist.conf
#
if [[ -z "$1" ]]; then
    echo "Error: please specify a configuration file, e.g. $0 /etc/ipset-whitelist/ipset-whitelist.conf"
    exit 1
fi

if ! source "$1"; then
    echo "Error: can't load configuration file $1"
    exit 1
fi

if ! which curl egrep grep ipset iptables sed sort wc &> /dev/null; then
    echo >&2 "Error: searching PATH fails to find executables among: curl egrep grep ipset iptables sed sort wc"
    exit 1
fi

if [[ ! -d $(dirname "$IP_WHITELIST") || ! -d $(dirname "$IP_WHITELIST_RESTORE") ]]; then
    echo >&2 "Error: missing directory(s): $(dirname "$IP_WHITELIST" "$IP_WHITELIST_RESTORE"|sort -u)"
    exit 1
fi

# create the ipset if needed (or abort if does not exists and FORCE=no)
if ! ipset list -n|command grep -q "$IPSET_WHITELIST_NAME"; then
    if [[ ${FORCE:-no} != yes ]]; then
	echo >&2 "Error: ipset does not exist yet, add it using:"
	echo >&2 "# ipset create $IPSET_WHITELIST_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}"
	exit 1
    fi
    if ! ipset create "$IPSET_WHITELIST_NAME" -exist hash:net family inet hashsize "${HASHSIZE:-16384}" maxelem "${MAXELEM:-65536}"; then
	echo >&2 "Error: while creating the initial ipset"
	exit 1
    fi
fi

# create the iptables binding if needed (or abort if does not exists and FORCE=no)
if ! iptables -nvL INPUT|command grep -q "match-set $IPSET_WHITELIST_NAME"; then
    # we may also have assumed that INPUT rule n°1 is about packets statistics (traffic monitoring)
    if [[ ${FORCE:-no} != yes ]]; then
	echo >&2 "Error: iptables does not have the needed ipset INPUT rule, add it using:"
	echo >&2 "# iptables -I INPUT ${IPTABLES_IPSET_RULE_NUMBER:-1} -m set --match-set $IPSET_WHITELIST_NAME src -j ACCEPT"
	exit 1
    fi
    if ! iptables -I INPUT "${IPTABLES_IPSET_RULE_NUMBER:-1}" -m set --match-set "$IPSET_WHITELIST_NAME" src -j ACCEPT; then
	echo >&2 "Error: while adding the --match-set ipset rule to iptables"
	exit 1
    fi
fi

IP_WHITELIST_TMP=$(mktemp)
for i in "${WHITELISTS[@]}"
do
    IP_TMP=$(mktemp)
    let HTTP_RC=`curl -L -A "whitelist-update/script/github" --connect-timeout 10 --max-time 10 -o $IP_TMP -s -w "%{http_code}" "$i"`
    if (( $HTTP_RC == 200 || $HTTP_RC == 302 || $HTTP_RC == 0 )); then # "0" because file:/// returns 000
	command grep -Po '(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?' "$IP_TMP" >> "$IP_WHITELIST_TMP"

	[[ ${VERBOSE:-yes} == yes ]] && echo -n "."
    elif (( $HTTP_RC == 503 )); then
        echo -e "\nUnavailable (${HTTP_RC}): $i"
    else
        echo >&2 -e "\nWarning: curl returned HTTP response code $HTTP_RC for URL $i"
    fi
    rm -f "$IP_TMP"
done

# sort -nu does not work as expected
sed -r -e '/^(0\.0\.0\.0|10\.|127\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|192\.168\.|22[4-9]\.|23[0-9]\.)/d' "$IP_WHITELIST_TMP"|sort -n|sort -mu >| "$IP_WHITELIST"
rm -f "$IP_WHITELIST_TMP"

# family = inet for IPv4 only
cat >| "$IP_WHITELIST_RESTORE" <<EOF
create $IPSET_TMP_WHITELIST_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
create $IPSET_WHITELIST_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
EOF


# can be IPv4 including netmask notation
# IPv6 ? -e "s/^([0-9a-f:./]+).*/add $IPSET_TMP_WHITELIST_NAME \1/p" \ IPv6
sed -rn -e '/^#|^$/d' \
    -e "s/^([0-9./]+).*/add $IPSET_TMP_WHITELIST_NAME \1/p" "$IP_WHITELIST" >> "$IP_WHITELIST_RESTORE"

cat >> "$IP_WHITELIST_RESTORE" <<EOF
swap $IPSET_WHITELIST_NAME $IPSET_TMP_WHITELIST_NAME
destroy $IPSET_TMP_WHITELIST_NAME
EOF

ipset -file  "$IP_WHITELIST_RESTORE" restore

if [[ ${VERBOSE:-no} == yes ]]; then
    echo
    echo "Number of whitelisted IP/networks found: `wc -l $IP_WHITELIST | cut -d' ' -f1`"
fi
