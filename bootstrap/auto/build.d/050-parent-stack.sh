if [ -n "$PARENT_STACK_NAME" ] && [ "$PARENT_STACK_NAME" != "$STACK_NAME" ]; then
	# Some of the following may fail if there is no corresponding SSM parameter defined
	BASTION_AMI=$(aws ssm get-parameter --name "/$PARENT_STACK_NAME/config/ami/bastion" --query 'Parameter.Value' --output text) ||:
	APP_AMI=$(aws ssm get-parameter --name "/$PARENT_STACK_NAME/config/ami/app" --query 'Parameter.Value' --output text) ||:
	WEB_AMI=$(aws ssm get-parameter --name "/$PARENT_STACK_NAME/config/ami/web" --query 'Parameter.Value' --output text) ||:

	# If the retrieved value is 'undefined' it means that we are still in the bootstrapping mode
	[ "$BASTION_AMI" != undefined ] || BASTION_AMI=
	[ "$APP_AMI" != undefined ] || APP_AMI=
	[ "$WEB_AMI" != undefined ] || WEB_AMI=

	aws cloudformation package --template-file infrastructure/templates/infrastructure.template --output-template-file "$TEMPLATE_OUTPUT_DIR/output.template" --s3-prefix cloudformation --s3-bucket "$S3_BUCKET"
	STACK_PARAMS=$(
		aws cloudformation describe-stacks --stack-name "$PARENT_STACK_NAME" \
			--query 'Stacks[0].Parameters[][ParameterKey,ParameterValue]' \
			--output text \
			| sed -E "
				s,^(BastionImageId\t).*\$,\1${BASTION_AMI:-},
				s,^(AppImageId\t).*\$,\1${APP_AMI:-},
				s,^(WebImageId\t).*\$,\1${WEB_AMI:-},
				" \
			| sed -E 's,^([^[:space:]]+)\s+(.*)\s*$,"\1": "\2"\,,;$s,\,,,'
	)
	[ "$STACK_PARAMS" == 'None' ] && STACK_PARAMS= ||:
	printf '%s\n' '{ "Parameters": {'" ${STACK_PARAMS:-} "'} }' > "$TEMPLATE_OUTPUT_DIR/output.parameters"
fi

# The following should be the last line of the script
printf 'CODEBUILD_TIME %d second(s)\n' $(($(date '+%s') - $(date -d "@${CODEBUILD_START_TIME:0:10}" '+%s')))
