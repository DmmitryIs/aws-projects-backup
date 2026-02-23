#!/bin/bash

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

if [ -f "$SCRIPT_DIR/.env" ]; then
	set -a
	source "$SCRIPT_DIR/.env"
	set +a
else
	echo "Error: .env file not found at $SCRIPT_DIR/.env"
	exit 1
fi

if [ -z "$BUCKET" ]; then
	echo "Error: BUCKET is not set in .env"
	exit 1
fi

if [ -z "$ALIAS" ]; then
	echo "Error: ALIAS is not set in .env"
	exit 1
fi

if [ -z "$DAYS_TO_KEEP" ]; then
	echo "Error: DAYS_TO_KEEP is not set in .env"
	exit 1
fi

declare -i DAYS_TO_KEEP

PREFIXES=("filesystem/${ALIAS}/" "databases/${ALIAS}/")

LOCK_DAYS=$((DAYS_TO_KEEP - 1))
LOCK_DATE=$(date -d "$LOCK_DAYS days ago" +%d-%m-%Y)
THRESHOLD_DATE=$(date -d "$DAYS_TO_KEEP days ago" --utc +%Y-%m-%dT%H:%M:%SZ)

for CURRENT_PREFIX in "${PREFIXES[@]}"; do
	LOCK_KEY="${CURRENT_PREFIX}${LOCK_DATE}_${ALIAS}.zip"

	echo "Processing: $CURRENT_PREFIX"

	echo "Checking for lock file: $LOCK_KEY"

	if aws s3api head-object --bucket "$BUCKET" --key "$LOCK_KEY" > /dev/null 2>&1; then
		echo "Lock file found. Cleaning up files older than $DAYS_TO_KEEP days..."

		KEYS_TO_DELETE=$(aws s3api list-objects-v2 \
			--bucket "$BUCKET" \
			--prefix "$CURRENT_PREFIX" \
			--query "Contents[?LastModified < \`$THRESHOLD_DATE\`].Key" \
			--output text)

		if [ "$KEYS_TO_DELETE" != "None" ] && [ -n "$KEYS_TO_DELETE" ]; then
			for key in $KEYS_TO_DELETE; do
				if [ "$key" != "$LOCK_KEY" ]; then
					echo "Deleting: $key"
					aws s3 rm "s3://$BUCKET/$key"
				fi
			done
		else
			echo "No old files found in $CURRENT_PREFIX."
		fi
	else
		echo "Lock file NOT found ($LOCK_KEY). Skipping this directory."
	fi
done

cd /var/www/avd_new && zip -r ~/archive.zip . \
-x ".git/*" \
-x "storage/framework/sessions/*" \
-x "storage/framework/debugbar/*" \
-x "storage/framework/views/*" \
-x "storage/framework/logs/*" \
-x "storage/framework/logs/*"
