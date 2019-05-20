cp -a templates/library/{ami,vpc}.template "$TEMPLATE_OUTPUT_DIR/"
printf '{ "Parameters": {} }\n' > "$TEMPLATE_OUTPUT_DIR/vpc.parameters"
