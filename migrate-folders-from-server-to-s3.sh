#!/bin/bash
# --------------------------------------------------------------------------
# SCRIPT: migrate_media_structured.sh
# DESCRIPTION: Transfers files from FTP to S3 with exact folder structure
#              preservation, skipping .zip files
# --------------------------------------------------------------------------

# ============================== CONFIGURATION ==============================
FTP_USER=""
FTP_PASS=""
FTP_HOST=""
FTP_SOURCE_PATH="/path/on/server/where/media/are/found"
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
# STEP 1: Get recursive file list with full relative paths
# ==========================================================================
echo ""
echo "--- STEP 1: Fetching recursive file list from FTP ---"

FILE_LIST=$(lftp -u "$FTP_USER,$FTP_PASS" "$FTP_HOST" <<EOF
set ftp:ssl-protect-data true
set ftp:passive-mode true
cd $FTP_SOURCE_PATH
find . -type f
bye
EOF
)

if [ -z "$FILE_LIST" ]; then
    echo "ERROR: Could not retrieve file list or directory is empty."
    echo "Please verify FTP credentials and path: $FTP_SOURCE_PATH"
    exit 1
fi

# Count total files
TOTAL_FILES=$(echo "$FILE_LIST" | wc -l)
echo "✓ Found $TOTAL_FILES files to process"
echo ""

# ==========================================================================
# STEP 2: Process each file while preserving folder structure
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
    
    # Remove leading "./" from path for cleaner display
    CLEAN_PATH="${FILE_PATH#./}"
    
    # Extract folder name (everything before the last /)
    FOLDER_NAME=$(dirname "$CLEAN_PATH")
    FILE_NAME=$(basename "$CLEAN_PATH")
    
    # ==========================================
    # CHECK 1: Skip .zip files
    # ==========================================
    if [[ "$FILE_NAME" == *.zip ]]; then
        echo "⊘ SKIPPED (ZIP): \"$CLEAN_PATH\""
        ((ZIP_SKIPPED_COUNT++))
        continue
    fi
    
    # ==========================================
    # CHECK 2: Construct S3 path with folder structure
    # ==========================================
    if [ "$FOLDER_NAME" = "." ]; then
        # File is in root directory
        S3_PATH="s3://$S3_BUCKET/$S3_PREFIX/$FILE_NAME"
    else
        # File is in a subfolder - preserve structure
        S3_PATH="s3://$S3_BUCKET/$S3_PREFIX/$FOLDER_NAME/$FILE_NAME"
    fi
    
    # ==========================================
    # CHECK 3: Skip if file already exists in S3
    # ==========================================
    if aws s3 ls "$S3_PATH" >/dev/null 2>&1; then
        echo "↷ SKIPPED (EXISTS): \"$CLEAN_PATH\""
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # ==========================================
    # TRANSFER: Stream file from FTP to S3
    # ==========================================
    if [ "$FOLDER_NAME" = "." ]; then
        echo "→ Uploading: \"$FILE_NAME\""
    else
        echo "→ Uploading: \"$FOLDER_NAME/$FILE_NAME\""
    fi
    
    set -o pipefail
    
    # Stream directly without touching disk
    lftp -u "$FTP_USER,$FTP_PASS" "$FTP_HOST" <<EOF 2>/dev/null | aws s3 cp - "$S3_PATH" 2>/dev/null
set ftp:ssl-protect-data true
set ftp:passive-mode true
set xfer:clobber true
cd $FTP_SOURCE_PATH
cat "$CLEAN_PATH"
bye
EOF
    
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
# STEP 3: Display summary
# ==========================================================================
echo "=========================================="
echo "  Migration Summary"
echo "=========================================="
echo "Total files found:    $TOTAL_FILES"
echo "Successfully uploaded: $UPLOADED_COUNT"
echo "Already existed:      $SKIPPED_COUNT"
echo "ZIP files skipped:    $ZIP_SKIPPED_COUNT"
echo "Failed transfers:     $FAILED_COUNT"
echo "=========================================="

if [ $FAILED_COUNT -gt 0 ]; then
    echo "⚠ Warning: Some files failed to transfer"
    exit 1
else
    echo "✓ Migration completed successfully!"
    exit 0
fi