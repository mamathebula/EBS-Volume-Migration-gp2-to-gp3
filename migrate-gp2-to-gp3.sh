#!/bin/bash
# Migrate EBS volumes from gp2 to gp3
# gp3 is 20% cheaper and has better baseline performance
#
# Usage:
#   ./migrate-gp2-to-gp3.sh              # current region only
#   ./migrate-gp2-to-gp3.sh --all-regions # all AWS regions
#
# To skip a volume, tag it with: skip-migration = true

set -e

# Configuration
OLD_TYPE="gp2"
NEW_TYPE="gp3"
BATCH_SIZE=10
SKIP_TAG="skip-migration"
# Prices in cents to avoid decimals (gp2=10 cents/GB, gp3=8 cents/GB)
GP2_CENTS=10
GP3_CENTS=8

GRAND_TOTAL_GB=0
GRAND_TOTAL_SAVINGS_CENTS=0

# Convert cents to dollar string (e.g., 1234 → $12.34)
cents_to_dollars() {
  local cents=$1
  local dollars=$((cents / 100))
  local remainder=$((cents % 100))
  printf "\$%d.%02d" "$dollars" "$remainder"
}

migrate_region() {
  local region=$1
  echo ""
  echo "=========================================="
  echo "  Region: $region"
  echo "=========================================="

  # Get all gp2 volumes with their tags
  ALL_VOLUMES=$(aws ec2 describe-volumes \
    --region "$region" \
    --filters "Name=volume-type,Values=$OLD_TYPE" \
    --query "Volumes[*].[VolumeId,Size,State,Attachments[0].InstanceId,Tags[?Key=='${SKIP_TAG}'].Value|[0],Tags[?Key=='Name'].Value|[0]]" \
    --output text)

  if [ -z "$ALL_VOLUMES" ]; then
    echo "No $OLD_TYPE volumes found. Skipping."
    return
  fi

  # Filter out skipped volumes
  SKIPPED=""
  VOLUMES=""
  while read -r vid size state instance skip_tag name; do
    if [[ "$skip_tag" == "true" || "$skip_tag" == "True" || "$skip_tag" == "TRUE" ]]; then
      SKIPPED="${SKIPPED}${vid} ${size} ${name:-N/A}\n"
    else
      VOLUMES="${VOLUMES}${vid} ${size} ${state} ${instance}\n"
    fi
  done <<< "$ALL_VOLUMES"

  # Remove trailing newline
  VOLUMES=$(echo -e "$VOLUMES" | sed '/^$/d')

  # Show skipped volumes
  if [ -n "$(echo -e "$SKIPPED" | sed '/^$/d')" ]; then
    SKIP_COUNT=$(echo -e "$SKIPPED" | sed '/^$/d' | wc -l | tr -d ' ')
    echo ""
    echo "Skipped $SKIP_COUNT volumes (tagged with $SKIP_TAG=true):"
    echo -e "$SKIPPED" | sed '/^$/d' | while read -r vid size name; do
      echo "  $vid ($size GB) - $name"
    done
  fi

  if [ -z "$VOLUMES" ]; then
    echo "No eligible $OLD_TYPE volumes to migrate (all skipped)."
    return
  fi

  TOTAL=$(echo "$VOLUMES" | wc -l | tr -d ' ')
  TOTAL_GB=0
  while read -r vid size state instance; do
    TOTAL_GB=$((TOTAL_GB + size))
  done <<< "$VOLUMES"

  GP2_COST_CENTS=$((TOTAL_GB * GP2_CENTS))
  GP3_COST_CENTS=$((TOTAL_GB * GP3_CENTS))
  SAVINGS_CENTS=$((GP2_COST_CENTS - GP3_COST_CENTS))
  YEARLY_CENTS=$((SAVINGS_CENTS * 12))

  echo ""
  echo "Found $TOTAL eligible $OLD_TYPE volumes ($TOTAL_GB GB total) to migrate → $NEW_TYPE:"
  echo ""
  echo "  Current cost (gp2):     $(cents_to_dollars $GP2_COST_CENTS)/month"
  echo "  After migration (gp3):  $(cents_to_dollars $GP3_COST_CENTS)/month"
  echo "  Monthly savings:        $(cents_to_dollars $SAVINGS_CENTS)/month"
  echo "  Yearly savings:         $(cents_to_dollars $YEARLY_CENTS)/year"
  echo ""
  printf "%-22s %-10s %-12s %-15s %-20s\n" "Volume ID" "Size (GB)" "State" "Savings/mo" "Attached To"
  echo "---------------------------------------------------------------------------------"
  echo "$VOLUMES" | while read -r vid size state instance; do
    instance=${instance:-"(not attached)"}
    vol_savings_cents=$((size * (GP2_CENTS - GP3_CENTS)))
    printf "%-22s %-10s %-12s %-15s %-20s\n" "$vid" "$size" "$state" "$(cents_to_dollars $vol_savings_cents)" "$instance"
  done

  echo ""
  if [ "$AUTO_APPROVE" = true ]; then
    echo "Auto-approved."
  else
    read -p "Migrate $TOTAL volumes in $region? (y/n/a=all remaining): " confirm
    if [[ "$confirm" == "a" || "$confirm" == "A" ]]; then
      AUTO_APPROVE=true
    elif [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "Skipped $region."
      return
    fi
  fi

  echo ""
  echo "Migrating in batches of $BATCH_SIZE..."
  echo ""

  count=0
  echo "$VOLUMES" | while read -r vid size state instance; do
    count=$((count + 1))

    echo "[$count/$TOTAL] Migrating $vid ($size GB) → $NEW_TYPE..."
    if aws ec2 modify-volume --region "$region" --volume-id "$vid" --volume-type "$NEW_TYPE" --output text > /dev/null 2>&1; then
      echo "  ✓ $vid migration started"
    else
      echo "  ✗ $vid failed"
    fi

    # Batch throttle
    if [ $((count % BATCH_SIZE)) -eq 0 ] && [ "$count" -lt "$TOTAL" ]; then
      echo ""
      echo "Batch complete. Waiting 5 seconds to avoid throttling..."
      sleep 5
      echo ""
    fi
  done

  # Track grand totals
  GRAND_TOTAL_GB=$((GRAND_TOTAL_GB + TOTAL_GB))
  GRAND_TOTAL_SAVINGS_CENTS=$((GRAND_TOTAL_SAVINGS_CENTS + SAVINGS_CENTS))

  echo ""
  echo "Done with $region. Migrated $TOTAL volumes. Saving $(cents_to_dollars $SAVINGS_CENTS)/month."
}

# Main
AUTO_APPROVE=false

if [[ "$1" == "--all-regions" ]]; then
  echo "Fetching all AWS regions..."
  echo "Volumes tagged with '$SKIP_TAG=true' will be skipped."
  REGIONS=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)
  REGION_COUNT=$(echo "$REGIONS" | wc -w | tr -d ' ')
  echo "Found $REGION_COUNT regions. Scanning each for $OLD_TYPE volumes..."

  for region in $REGIONS; do
    migrate_region "$region"
  done

  GRAND_YEARLY_CENTS=$((GRAND_TOTAL_SAVINGS_CENTS * 12))
  echo ""
  echo "=========================================="
  echo "  All regions complete."
  echo "  Total: ${GRAND_TOTAL_GB} GB migrated"
  echo "  Savings: $(cents_to_dollars $GRAND_TOTAL_SAVINGS_CENTS)/month ($(cents_to_dollars $GRAND_YEARLY_CENTS)/year)"
  echo "=========================================="
else
  CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "${AWS_REGION:-us-east-1}")
  echo "Running in region: $CURRENT_REGION"
  echo "Volumes tagged with '$SKIP_TAG=true' will be skipped."
  echo "(Use --all-regions to migrate across all AWS regions)"
  migrate_region "$CURRENT_REGION"
fi

echo ""
echo "Migrations happen in the background. Check status with:"
echo ""
echo "  aws ec2 describe-volumes-modifications --filters Name=modification-state,Values=modifying"
