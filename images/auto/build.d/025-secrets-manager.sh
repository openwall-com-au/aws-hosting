SETOLD="$-"
[ "${SETOLD//x}" == "$-" ] || set +x
# The following is not a big secret, but still it is better not to expose
# it without need :)
AD_JOIN_USER=Joiner
AD_JOIN_PASS=$(aws secretsmanager get-secret-value \
	--secret-id "$SECRET_AD_JOIN_ARN" \
	--query SecretString \
	--output text \
	| jq -re .password \
)
[ "$SETOLD" == "$-" ] || set -x
