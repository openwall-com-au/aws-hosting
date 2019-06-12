VPC_PUBLIC_CIDR="${VPC_PUBLIC_CIDR:-10.0.0.0/22}"

upload_bootstrap_snippet()
{
	SNIPPET="${BASH_SOURCE[0]%/*}/../../scripts/$1"
	[ -s "$SNIPPET" ]
	SETOLD="$-"
	[ "${SETOLD//x}" == "$-" ] || set +x
	AD_JOIN_PASS_SAFE="${AD_JOIN_PASS//\"/\\\"}"
	AD_JOIN_PASS_SAFE="${AD_JOIN_PASS_SAFE//|/\\|}"
	AD_JOIN_PASS_SAFE="${AD_JOIN_PASS_SAFE//&/\\&}"
	sed -i "
		s|@@AD_DOMAIN@@|$AD_DOMAIN|g
		s|@@AD_JOIN_USER@@|$AD_JOIN_USER|g
		s|@@AD_JOIN_PASS@@|$AD_JOIN_PASS_SAFE|g
		s|@@LDAP_BASE@@|DC=${AD_DOMAIN//\./,DC=}|g
		s|@@EFS_DNS@@|$EFS_DNS|g
		s|@@PHP_DNS@@|$PHP_DNS|g
		s|@@PHP_PORT@@|$PHP_PORT|g
		s|@@VPC_PUBLIC_CIDR@@|$VPC_PUBLIC_CIDR|g
	" "$SNIPPET"
	[ "$SETOLD" == "$-" ] || set -x
	OUTPUT="s3://$S3_BUCKET/bootstrap/$(sha1sum "$SNIPPET" | cut -f1 -d' ').bootstrap"
	aws s3 cp "$SNIPPET" "$OUTPUT" >&2
	printf '%s\n' "$OUTPUT"
}
