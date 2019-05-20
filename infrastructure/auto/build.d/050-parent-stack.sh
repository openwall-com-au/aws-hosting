if [ -n "$PARENT_STACK_NAME" ] && [ "$PARENT_STACK_NAME" != "$STACK_NAME" ]; then
	aws cloudformation package --template-file templates/infrastructure.template --output-template-file "$TEMPLATE_OUTPUT_DIR/output.template" --s3-prefix cloudformation --s3-bucket "$S3_BUCKET"
	STACK_PARAMS=$(
		aws cloudformation describe-stacks --stack-name "$PARENT_STACK_NAME" \
			--query 'Stacks[0].Parameters[][ParameterKey,ParameterValue]' \
			--output text \
			| sed -E 's,^([^[:space:]]+)\s+(.*)\s*$,"\1": "\2"\,,;$s,\,,,'
	)
	[ "$STACK_PARAMS" == 'None' ] && STACK_PARAMS= ||:
	printf '%s\n' '{ "Parameters": {'" ${STACK_PARAMS:-} "'} }' > "$TEMPLATE_OUTPUT_DIR/output.parameters"
fi

# The following should be the last line of the script
printf 'CODEBUILD_TIME %d second(s)\n' $(($(date '+%s') - $(date -d "@${CODEBUILD_START_TIME:0:10}" '+%s')))
