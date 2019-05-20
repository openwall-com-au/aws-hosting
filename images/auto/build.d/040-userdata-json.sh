echo '{' > "$TEMPLATE_OUTPUT_DIR/build-output.json"
OUTPUT=
for f in "$TEMPLATE_OUTPUT_DIR"/*.userdata
do
	OUTPUT="${OUTPUT:+$OUTPUT,$'\n'}$(<$f)"
done
echo "$OUTPUT" >> "$TEMPLATE_OUTPUT_DIR/build-output.json"
echo "}" >> "$TEMPLATE_OUTPUT_DIR/build-output.json"
cat "$TEMPLATE_OUTPUT_DIR/build-output.json"
echo =========
jq . "$TEMPLATE_OUTPUT_DIR/build-output.json"
