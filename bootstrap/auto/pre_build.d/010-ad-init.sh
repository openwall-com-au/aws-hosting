AD_DOMAIN=${AD_DOMAIN?This must be provided!}
AD_DOMAIN="${AD_DOMAIN%.}"

export KRB5CCNAME="$(pwd -P)/krb5-ad.ccache"
SETOLD="$-"
[ "${SETOLD//x}" == "$-" ] || set +x
aws secretsmanager get-secret-value --secret-id "$SECRET_AD_ARN" --query SecretString --output text \
	| jq -re .password \
	| kinit -V -l 300 -r 300 -f -P -c "$KRB5CCNAME" Administrator@"${AD_DOMAIN^^}"
[ "$SETOLD" == "$-" ] || set -x
klist -c "$KRB5CCNAME"

RC=0
# Let's try to create an organisational unit in Active Directory ...
ldapmodify -Y GSSAPI -h "$AD_DOMAIN" <<- __EOF__ || RC=$?
	DN: OU=Hosting,DC=${AD_DOMAIN//./,DC=}
	changetype: add
	description: Container for Web Hosting accounts
	objectclass: top
	objectclass: organizationalUnit
	ou: Hosting
__EOF__

# ldapmodify returns code 68 if the record already exists
if [ $RC -ne 68 ]; then
	if [ $RC -ne 0 ]; then
		echo "CRITICAL Could not add the organisational unit to Active Directory! (Error: $RC)" >&2
		exit $RC
	fi
fi

RC=0
adcli create-group -D "$AD_DOMAIN" "--login-ccache=$KRB5CCNAME" -z 'Hosting Administrators' -O "ou=Hosting,dc=${AD_DOMAIN//./,dc=}" admin || RC=$?
# adcli returns code 5 for an existing account
if [ $RC -ne 5 ]; then
	if [ $RC -ne 0 ]; then
		echo "CRITICAL Could not add the admin group to Active Directory! (Error: $RC)" >&2
		exit $RC
	fi
fi

RC=0
adcli create-group -D "$AD_DOMAIN" "--login-ccache=$KRB5CCNAME" -z 'Virtual Web Hosting' -O "ou=Hosting,dc=${AD_DOMAIN//./,dc=}" virtwww || RC=$?
if [ $RC -ne 5 ]; then
	if [ $RC -ne 0 ]; then
		echo "CRITICAL Could not add the virtwww group to Active Directory! (Error: $RC)" >&2
		exit $RC
	fi
fi

# Configure a low-privileged directory joiner account for instance registration
#adcli create-user -y 'Domain Joiner' -D id.next.internal --login-ccache=/root/.users/admin/krb5-ad.ccache Joiner # 5 - already exists
RC=0
adcli create-user -D "$AD_DOMAIN" "--login-ccache=$KRB5CCNAME" -y 'Domain Joiner' Joiner || RC=$?
if [ $RC -ne 5 ]; then
	if [ $RC -ne 0 ]; then
		echo "CRITICAL Could not add the Joiner user to Active Directory! (Error: $RC)" >&2
		exit $RC
	fi
	# Enable the user, so they could authenticate
	ldapmodify -Y GSSAPI -h "$AD_DOMAIN" <<-__EOF__
		DN: CN=Joiner,CN=Users,DC=${AD_DOMAIN//./,DC=}
		changetype: modify
		replace: userAccountControl
		userAccountControl: 512
	__EOF__
fi


[ "${SETOLD//x}" == "$-" ] || set +x
echo "Retrieving AD Joiner password"
if ! JOINER_PASS=$( \
	aws secretsmanager get-secret-value --secret-id "$SECRET_AD_JOIN_ARN" --query SecretString --output text \
		| jq -re .password \
)
then
	echo "CRITICAL Could not retrieve the secret for the Directory joiner account!" >&2
	exit 1
fi
echo "Determining the cannonical name of the PDC Kerberos endpoint"
PDC_DNS=$(host -r -s -t srv "_kerberos._tcp.${AD_DOMAIN}" | sed -n 's,^_kerberos\..*[[:space:]]\([^[:space:]]\+\)\.$,\1,;T;p')
[ -n "$PDC_DNS" ]
echo "Ensuring that AD Joiner password is not empty"
[ -n "$JOINER_PASS" ]
echo "Setting the AD Joiner password in the directory"
rpcclient -s /dev/null --option=security=ads -k -c "setuserinfo2 Joiner 23 $JOINER_PASS" "$PDC_DNS"
unset PDC_DNS

[ "$SETOLD" == "$-" ] || set -x
#adcli add-member -D id.next.internal --login-ccache=/root/.users/admin/krb5-ad.ccache AWSDomainJoiners Joiner # 4 - already exists
RC=0
adcli add-member -D "$AD_DOMAIN" "--login-ccache=$KRB5CCNAME" AWSDomainJoiners Joiner || RC=$?
# adcli returns code 4 if the user is already a member of the group
if [ $RC -ne 4 ]; then
	if [ $RC -ne 0 ]; then
		echo "CRITICAL Could not add the Joiner user to the AWSDomainJoiners group in Active Directory! (Error: $RC)" >&2
		exit $RC
	fi
fi

get_gid_from_ad() {
	local GROUP_NAME="${1?ERROR: get_group_from_ad requires a group name as an argument!}"
	local OBJECT_SID="$( \
		ldapsearch -LLL -Y GSSAPI -h "$AD_DOMAIN" -b "dc=${AD_DOMAIN//./,dc=}" '(&(objectClass=Group)(CN='"$GROUP_NAME"'))' objectSid \
		| sed -rn '/dn:\s*CN='"$GROUP_NAME"',/{n;s/^objectSid::\s*(.*)$/\1/;T;p}' \
	)"
	[ -n "$OBJECT_SID" ] || return
	local GROUP_ID="$(python2 "${BASH_SOURCE%/*}/../../scripts/objectsid2id.py" "$OBJECT_SID")"
	[ -n "$GROUP_ID" ] || return
	printf '%u' "$GROUP_ID"
}

# a sanity check
get_gid_from_ad admin
