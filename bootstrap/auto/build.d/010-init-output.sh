TEMPLATE_OUTPUT_DIR="${BASH_SOURCE%/*}/../../out"
mkdir -p -m700 "$TEMPLATE_OUTPUT_DIR"
TEMPLATE_OUTPUT_DIR="$(cd $TEMPLATE_OUTPUT_DIR && pwd -P)"
export TEMPLATE_OUTPUT_DIR
