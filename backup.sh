#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# ENV
if [ -f "$SCRIPT_DIR/.env" ]; then
	set -a
	source "$SCRIPT_DIR/.env"
	set +a
else
	echo "Error: .env file not found at $SCRIPT_DIR/.env"
	exit 1
fi

# VALIDATION
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
if [ -z "$PROJECT_PATH" ]; then
	echo "Error: PROJECT_PATH is not set in .env"
	exit 1
fi

# CLEANING
declare -i DAYS_TO_KEEP
PREFIXES=("filesystem/${ALIAS}/" "databases/${ALIAS}/")
LOCK_DAYS=$((DAYS_TO_KEEP - 1))
LOCK_DATE=$(date -d "$LOCK_DAYS days ago" +%d-%m-%Y)
THRESHOLD_DATE=$(date -d "$DAYS_TO_KEEP days ago" --utc +%Y-%m-%dT%H:%M:%SZ)

for CURRENT_PREFIX in "${PREFIXES[@]}"; do
	LOCK_KEY="${CURRENT_PREFIX}${LOCK_DATE}_${ALIAS}.zip"

	echo "~~~ Processing: $CURRENT_PREFIX"

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

# NAMES
CURRENT_DATE=$(date +%d-%m-%Y)
DEST="${CURRENT_DATE}_${ALIAS}.zip"
DEST_FS_KEY="filesystem/${ALIAS}/${DEST}"
DEST_DB_KEY="databases/${ALIAS}/${DEST}"
LOCAL_FS="$SCRIPT_DIR/fs.zip"
LOCAL_DB="$SCRIPT_DIR/db.zip"

# FILESYSTEM
echo "~~~ Zip filesystem"
cd "$PROJECT_PATH" && zip -r "$SCRIPT_DIR/fs.zip" . \
	-x ".git/*" \
	-x "storage/framework/cache/*" \
	-x "storage/framework/sessions/*" \
	-x "storage/framework/debugbar/*" \
	-x "storage/framework/views/*" \
	-x "storage/logs/*"

if [ -n "$SSL_PATH" ]; then
  echo "Zip SSL certificates"
  zip -rg "$SCRIPT_DIR/fs.zip" "$SSL_PATH"
fi

echo "Uploading $DEST_FS_KEY to s3"
if aws s3 cp "$LOCAL_FS" "s3://$BUCKET/$DEST_FS_KEY"; then
	echo "Upload successful."
	rm "$LOCAL_FS"
	echo "Local archive removed."
else
	echo "Error: Failed to upload archive to S3."
fi

# DATABASES
echo "~~~ Dump databases"
if [ -n "$DB_LIST" ]; then
  if ls "$SCRIPT_DIR"/*.sql 1> /dev/null 2>&1; then
    rm "$SCRIPT_DIR"/*.sql
  fi

  IFS=',' read -ra DBS <<< "$DB_LIST"

  if [ ${#DBS[@]} -eq 0 ]; then
  	echo "No valid database entries found in DB_LIST."
  	exit
  fi

  TIMESTAMP=$(date +%Y-%m-%d_%H-%M)

  for ENTRY in "${DBS[@]}"; do
    [ -z "$ENTRY" ] && continue

  	IFS=':' read -r DB_NAME DB_HOST DB_USER DB_PASS <<< "$ENTRY"

  	echo "Dumping $DB_NAME..."
  	mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" 2>/dev/null > "${SCRIPT_DIR}/${DB_NAME}_${TIMESTAMP}.sql"

    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
      echo "Successfully dumped $DB_NAME"
    else
      echo "Error: Failed to dump $DB_NAME"
    fi
  done

  if ls "$SCRIPT_DIR"/*.sql 1> /dev/null 2>&1; then
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M)

  	DB_ZIP="${SCRIPT_DIR}/db.zip"
  	zip -j "$DB_ZIP" "$SCRIPT_DIR"/*.sql
    rm "$SCRIPT_DIR"/*.sql

  	echo "Combined archive created: $DB_ZIP"
  else
  	echo "No SQL files found to archive."
  fi
fi

echo "Uploading $DEST_DB_KEY to s3"
if aws s3 cp "$LOCAL_DB" "s3://$BUCKET/$DEST_DB_KEY"; then
	echo "Upload successful."
	rm "$LOCAL_DB"
	echo "Local archive removed."
else
	echo "Error: Failed to upload archive to S3."
fi



