#!/bin/bash
# --------------------------------------------------------------------------
# SCRIPT: migrate_media_structured_fixed.sh
# DESCRIPTION: Transfers files from FTP to S3 with exact folder structure
# --------------------------------------------------------------------------

# ============================== CONFIGURATION ==============================
FTP_USER=""
FTP_PASS=""
FTP_HOST=""
FTP_SOURCE_PATH="/www/album"
S3_BUCKET="s3-bucket-name"
S3_PREFIX="audio"
# ==========================================================================

echo "=========================================="
echo "  FTP to S3 Migration (Structure Preserved)"
echo "=========================================="
echo "FTP Source: $FTP_HOST:$FTP_SOURCE_PATH"
echo "S3 Destination: s3://$S3_BUCKET/$S3_PREFIX/"
echo "=========================================="

# ==========================================================================
# STEP 1: Get recursive file list with full paths
# ==========================================================================
echo ""
echo "--- STEP 1: Fetching recursive file list from FTP ---"

# Use 'find' without '-type f' as lftp's find is limited
FILE_LIST=$(lftp -u "$FTP_USER,$FTP_PASS" "$FTP_HOST" <<EOF
set ftp:ssl-protect-data true
set ftp:passive-mode true
set ftp:list-options -a
cd $FTP_SOURCE_PATH
find
bye
EOF
)

if [ -z "$FILE_LIST" ]; then
    echo "ERROR: Could not retrieve file list or directory is empty."
    exit 1
fi

# Filter out directories (they end with /) and clean up
FILE_LIST=$(echo "$FILE_LIST" | grep -v '/$' | grep -v '^[[:space:]]*$')

TOTAL_FILES=$(echo "$FILE_LIST" | wc -l)
echo "✓ Found $TOTAL_FILES files to process"
echo ""

# ==========================================================================
# STEP 2: Process each file
# ==========================================================================
echo "--- STEP 2: Starting file migration ---"
echo ""

UPLOADED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0
ZIP_SKIPPED_COUNT=0

while IFS= read -r FILE_PATH; do
    # Skip empty lines
    [ -z "$FILE_PATH" ] && continue
    
    # Remove leading "./" if present
    CLEAN_PATH="${FILE_PATH#./}"
    
    # Skip if it's just a dot or empty
    [ "$CLEAN_PATH" = "." ] && continue
    [ -z "$CLEAN_PATH" ] && continue
    
    # Extract folder and file name
    FOLDER_NAME=$(dirname "$CLEAN_PATH")
    FILE_NAME=$(basename "$CLEAN_PATH")
    
    # ==========================================
    # CHECK 1: Skip .zip files and folders
    # ==========================================
    if [[ "$FILE_NAME" == *.zip ]]; then
        echo "⊘ SKIPPED (ZIP): \"$CLEAN_PATH\""
        ((ZIP_SKIPPED_COUNT++))
        continue
    fi
    
    # Skip if it looks like a directory (no extension or ends with /)
    if [[ "$CLEAN_PATH" == */ ]] || [[ ! "$FILE_NAME" == *.* ]]; then
        continue
    fi
    
    # ==========================================
    # CHECK 2: Construct S3 path
    # ==========================================
    if [ "$FOLDER_NAME" = "." ]; then
        S3_PATH="s3://$S3_BUCKET/$S3_PREFIX/$FILE_NAME"
    else
        S3_PATH="s3://$S3_BUCKET/$S3_PREFIX/$CLEAN_PATH"
    fi
    
    # ==========================================
    # CHECK 3: Skip if exists in S3
    # ==========================================
    if aws s3 ls "$S3_PATH" >/dev/null 2>&1; then
        echo "↷ SKIPPED (EXISTS): \"$CLEAN_PATH\""
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # ==========================================
    # TRANSFER: Stream file from FTP to S3
    # ==========================================
    echo "→ Uploading: \"$CLEAN_PATH\""
    
    set -o pipefail
    
    # Important: Use full path from FTP_SOURCE_PATH
    (lftp -u "$FTP_USER,$FTP_PASS" "$FTP_HOST" <<FTPEOF
set ftp:ssl-protect-data true
set ftp:passive-mode true
set xfer:clobber true
cd $FTP_SOURCE_PATH
cat "$CLEAN_PATH"
bye
FTPEOF
) | aws s3 cp - "$S3_PATH"
    
    PIPE_STATUS=$?
    
    if [ $PIPE_STATUS -ne 0 ]; then
        echo "✗ FAILED: \"$CLEAN_PATH\" (exit code: $PIPE_STATUS)"
        ((FAILED_COUNT++))
    else
        echo "✓ SUCCESS: \"$CLEAN_PATH\""
        ((UPLOADED_COUNT++))
    fi
    
    echo ""
    
done <<< "$FILE_LIST"

# ==========================================================================
# STEP 3: Summary
# ==========================================================================
echo "=========================================="
echo "  Migration Summary"
echo "=========================================="
echo "Total files processed: $TOTAL_FILES"
echo "Successfully uploaded: $UPLOADED_COUNT"
echo "Already existed:       $SKIPPED_COUNT"
echo "ZIP files skipped:     $ZIP_SKIPPED_COUNT"
echo "Failed transfers:      $FAILED_COUNT"
echo "=========================================="

if [ $FAILED_COUNT -gt 0 ]; then
    echo "⚠ Warning: Some files failed to transfer"
    exit 1
else
    echo "✓ Migration completed successfully!"
    exit 0
fi
