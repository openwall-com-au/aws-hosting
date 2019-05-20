USERDATA_SCRIPT=$(upload_bootstrap_snippet bastion.userdata)

printf '"BastionUserData": "aws s3 cp \\\"%s\\\" \\\"/root/%s\\\" && /bin/bash -ex \\\"/root/%s\\\" && rm -f \\\"%s\\\""\n' \
	"$USERDATA_SCRIPT" "${USERDATA_SCRIPT##*/}" "${USERDATA_SCRIPT##*/}" "${USERDATA_SCRIPT##*/}" \
	> "$TEMPLATE_OUTPUT_DIR/bastion.userdata"
printf '{ "Parameters": {} }\n' > "$TEMPLATE_OUTPUT_DIR/bastion-ami.parameters"
