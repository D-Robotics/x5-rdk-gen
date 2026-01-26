#!/usr/bin/env bash

CONFIG_FILE=".rdk_config"

echo "Select SoC:"
select soc in x3 x5; do
    [[ -n "$soc" ]] && break
done

cat > "$CONFIG_FILE" <<EOF
RDK_SOC_NAME=$soc
EOF

echo "Saved to $CONFIG_FILE"