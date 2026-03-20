# EBS Volume Migration: gp2 → gp3

Bash script that finds all gp2 EBS volumes in your AWS account and migrates them to gp3 in batches.

## Why Migrate?

| | gp2 | gp3 |
|---|---|---|
| Price | $0.10/GB/month | $0.08/GB/month |
| Baseline IOPS | 100 IOPS per GB (up to 16,000) | 3,000 IOPS (free, regardless of size) |
| Baseline Throughput | 128–250 MB/s (depends on size) | 125 MB/s (free) |
| Max IOPS | 16,000 | 16,000 |
| Max Throughput | 250 MB/s | 1,000 MB/s |

gp3 is 20% cheaper and gives you 3,000 IOPS baseline on every volume — even a 1 GB volume. With gp2, a 1 GB volume only gets 100 IOPS.

### Example Savings

| Volume Size | gp2 Cost | gp3 Cost | Monthly Savings |
|-------------|----------|----------|-----------------|
| 100 GB | $10.00 | $8.00 | $2.00 |
| 500 GB | $50.00 | $40.00 | $10.00 |
| 1 TB | $100.00 | $80.00 | $20.00 |
| 10 x 100 GB | $100.00 | $80.00 | $20.00 |

## Usage

| Command | What It Does |
|---------|-------------|
| `./migrate-gp2-to-gp3.sh` | Migrates gp2 volumes in your current configured region only |
| `./migrate-gp2-to-gp3.sh --all-regions` | Loops through every AWS region and migrates gp2 volumes in each |
| `export AWS_REGION=us-west-1 && ./migrate-gp2-to-gp3.sh` | Migrates gp2 volumes in a specific region |

## How to Skip Volumes

Tag any volume with `skip-migration` = `true` and the script will leave it alone.

### AWS Console

1. Go to EC2 → Volumes
2. Select the volume
3. Click Tags tab → Manage tags
4. Add tag: Key = `skip-migration`, Value = `true`
5. Save

### AWS CLI

```bash
aws ec2 create-tags \
  --resources vol-0abc123 \
  --tags Key=skip-migration,Value=true
```

The script will show skipped volumes separately so you know what was excluded.

## Prerequisites

- AWS CLI installed and configured (`aws configure`)
- Permissions: `ec2:DescribeVolumes` and `ec2:ModifyVolume`

## Run

### Option 1: Local Terminal

**Step 1: Set up AWS credentials** (skip if already configured)

```bash
aws configure
```

**Step 2: Verify credentials**

```bash
aws sts get-caller-identity
```

**Step 3: Run the script**

Single region (current region):

```bash
chmod +x migrate-gp2-to-gp3.sh
./migrate-gp2-to-gp3.sh
```

All regions:

```bash
chmod +x migrate-gp2-to-gp3.sh
./migrate-gp2-to-gp3.sh --all-regions
```

### Option 2: AWS CloudShell

1. Log into the AWS Console
2. Open CloudShell (terminal icon, top right)
3. Make sure you're in the correct region
4. Click Actions → Upload file → select `migrate-gp2-to-gp3.sh`
5. If re-uploading, delete the old file first:

```bash
rm migrate-gp2-to-gp3.sh
```

6. Run:

Single region:

```bash
chmod +x migrate-gp2-to-gp3.sh
./migrate-gp2-to-gp3.sh
```

All regions:

```bash
chmod +x migrate-gp2-to-gp3.sh
./migrate-gp2-to-gp3.sh --all-regions
```

## What Happens

1. Script finds all gp2 volumes in the current region (or all regions with `--all-regions`)
2. Shows you a list with volume ID, size, state, savings per volume, and what instance it's attached to
3. Displays total potential savings — current gp2 cost, gp3 cost, monthly and yearly savings
4. Asks for confirmation before proceeding (per region)
   - `y` — yes, migrate the volumes in this region
   - `n` — no, skip this region and move to the next one
   - `a` — yes, migrate this region AND auto-approve all remaining regions without asking again (only useful with `--all-regions`)
5. Migrates in batches of 10 (5-second pause between batches to avoid throttling)
6. Migrations happen in the background — the volume stays online during migration
7. When using `--all-regions`, shows a grand total of GB migrated and total savings at the end

## Example Output

```
==========================================
  Region: us-west-1
==========================================

Found 3 gp2 volumes (350 GB total) to migrate → gp3:

  Current cost (gp2):  $35.00/month
  After migration (gp3): $28.00/month
  Monthly savings:     $7.00/month
  Yearly savings:      $84.00/year

Volume ID              Size (GB)  State        Savings/mo      Attached To
---------------------------------------------------------------------------------
vol-0abc123            100        in-use       $2.00           i-0abc123
vol-0def456            200        in-use       $4.00           i-0def456
vol-0ghi789            50         available    $1.00           (not attached)

Migrate 3 volumes in us-west-1? (y/n/a=all remaining): y

Migrating in batches of 10...

[1/3] Migrating vol-0abc123 (100 GB) → gp3...
  ✓ vol-0abc123 migration started
[2/3] Migrating vol-0def456 (200 GB) → gp3...
  ✓ vol-0def456 migration started
[3/3] Migrating vol-0ghi789 (50 GB) → gp3...
  ✓ vol-0ghi789 migration started

Done with us-west-1. Migrated 3 volumes. Saving $7.00/month.
```

## Check Migration Status

After running the script, check progress with:

```bash
aws ec2 describe-volumes-modifications \
  --filters Name=modification-state,Values=modifying \
  --query "VolumesModifications[*].[VolumeId,OriginalVolumeType,TargetVolumeType,Progress]" \
  --output table
```

Check completed migrations:

```bash
aws ec2 describe-volumes-modifications \
  --filters Name=modification-state,Values=completed \
  --query "VolumesModifications[*].[VolumeId,OriginalVolumeType,TargetVolumeType]" \
  --output table
```

## Important Notes

- Migration is online — no downtime, no detach required. Volumes stay attached and usable
- Migration typically takes a few minutes to a few hours depending on volume size
- You can only modify a volume once every 6 hours. If a volume was recently modified, it will fail and the script will show an error for that volume
- If a volume is managed by CloudFormation, this will cause stack drift (same as the Lambda runtime updater). Update the template afterwards to match
- The script only targets the current region. Run it again with a different `AWS_REGION` for multi-region accounts
- There is no cost for the migration itself — you only pay the new gp3 price going forward

## Advantages of gp3 over gp2

- 20% cheaper — $0.08/GB vs $0.10/GB, same storage, lower price
- 3,000 IOPS baseline on every volume regardless of size (gp2 needs 1 TB to reach 3,000 IOPS)
- Performance is independent from capacity — you can provision IOPS and throughput separately without increasing volume size
- Higher max IOPS — gp3 supports up to 80,000 IOPS per volume vs 16,000 on gp2
- Higher max throughput — gp3 supports up to 2,000 MB/s vs 250 MB/s on gp2
- Larger max volume size — gp3 supports up to 64 TiB vs 16 TiB on gp2
- Online migration — no downtime, no detach, volume stays usable during conversion
- No migration cost — you only pay the new gp3 price going forward

## Disadvantages / Things to Watch

- If you have gp2 volumes larger than 5.3 TB, they get more than 16,000 IOPS from the 3 IOPS/GB formula. On gp3, you'd need to provision additional IOPS ($0.005/IOPS-month) to match — this could cost more
- Extra IOPS above 3,000 costs $0.005 per provisioned IOPS-month
- Extra throughput above 125 MB/s costs $0.04 per provisioned MB/s-month
- If your workload relies on gp2 burst credits (small volumes bursting to 3,000 IOPS), gp3 gives you 3,000 IOPS baseline instead — same performance, but no burst above that without provisioning
- Volumes can only be modified once every 6 hours — if a migration fails, you have to wait before retrying
- If volumes are managed by CloudFormation, this causes stack drift (update the template afterwards)
- The script migrates with default gp3 settings (3,000 IOPS, 125 MB/s throughput). If you need higher performance, adjust IOPS/throughput after migration
- Migrations run in batches of 10 with a 5-second pause between batches to avoid AWS API throttling. If you have hundreds or thousands of volumes, the script handles it automatically — it just takes longer (e.g., 1,000 volumes = 100 batches ≈ 8–10 minutes of API calls, plus background migration time)

For full details, see the [AWS Prescriptive Guidance: Migrate EBS volumes from gp2 to gp3](https://docs.aws.amazon.com/prescriptive-guidance/latest/optimize-costs-microsoft-workloads/ebs-migrate-gp2-gp3.html).

## Is It Cost Effective to Migrate?

Yes, almost always. The migration itself is free — AWS doesn't charge for changing volume type, and the script deploys nothing.

### For most volumes (under 1 TB): Pure win

gp3 is 20% cheaper with better baseline performance. No extra costs.

| Volume Size | gp2 IOPS | gp3 IOPS (free) | Storage Savings | Extra IOPS Cost | Net Savings |
|-------------|----------|------------------|-----------------|-----------------|-------------|
| 50 GB | 150 | 3,000 | $1.00/mo | $0 | $1.00/mo |
| 100 GB | 300 | 3,000 | $2.00/mo | $0 | $2.00/mo |
| 500 GB | 1,500 | 3,000 | $10.00/mo | $0 | $10.00/mo |
| 1 TB | 3,000 | 3,000 | $20.00/mo | $0 | $20.00/mo |

### For large volumes (over 1 TB): Still cheaper, but check IOPS needs

gp2 gives 3 IOPS per GB, so large volumes get high IOPS automatically. On gp3, IOPS above 3,000 costs $0.005/IOPS-month.

| Volume Size | gp2 IOPS | gp3 Extra IOPS Needed | Storage Savings | Extra IOPS Cost | Net Savings |
|-------------|----------|-----------------------|-----------------|-----------------|-------------|
| 2 TB | 6,000 | 3,000 | $40.00/mo | $15.00/mo | $25.00/mo |
| 5 TB | 15,000 | 12,000 | $100.00/mo | $60.00/mo | $40.00/mo |
| 5.3 TB+ | 16,000 | 13,000 | $106.00/mo | $65.00/mo | $41.00/mo |

Even at 5 TB, you save $40/month. The break-even point where gp3 could cost more than gp2 doesn't exist for storage alone — the 20% storage discount always outweighs the IOPS cost.

The only exception: if you provision IOPS significantly above what gp2 would give (e.g., you want 16,000 IOPS on a 100 GB volume), the extra IOPS cost ($65/mo) would exceed the storage savings ($2/mo). But in that case, you should be using io2 volumes, not gp3.

### Bottom line

| Scenario | Cost Effective? |
|----------|----------------|
| Volumes under 1 TB | Always — cheaper and faster |
| Volumes 1–5 TB | Always — storage savings exceed IOPS costs |
| Volumes over 5 TB needing max IOPS | Still yes — but verify with the pricing table above |
| Volumes needing more than 16,000 IOPS | Use io2 instead of gp3 |

## Risks

Low risk. This is a safe migration:

- No downtime — volume stays online
- No data loss — it's a type change, not a copy
- Performance is equal or better (3,000 IOPS baseline vs potentially less on small gp2 volumes)
- If you need more than 3,000 IOPS or 125 MB/s throughput on gp3, you can provision extra (at additional cost)

The only edge case: if you have a gp2 volume larger than 5.3 TB, it gets more than 16,000 IOPS on gp2 (3 IOPS/GB). On gp3, you'd need to provision additional IOPS to match. This is rare.

## What Gets Deployed

Nothing. This is a standalone bash script. It does not create any AWS resources — it only calls the EC2 API to modify existing volumes.

## Multi-Region

Run with `--all-regions` to scan and migrate across every AWS region:

```bash
./migrate-gp2-to-gp3.sh --all-regions
```

The script will loop through all regions, show you gp2 volumes in each, and ask for confirmation per region. Press `a` at any prompt to auto-approve all remaining regions.

To run for a specific region without `--all-regions`:

```bash
export AWS_REGION=eu-west-1
./migrate-gp2-to-gp3.sh
```

## Why Do gp2 Volumes Still Exist?

There is no technical advantage to staying on gp2. gp3 is cheaper and equal or better in every metric. The reasons gp2 volumes still exist in most accounts:

| Reason | Explanation |
|--------|-------------|
| Legacy defaults | gp2 was the default volume type for years. Many accounts, AMIs, and launch templates still create gp2 volumes automatically |
| Hardcoded in templates | Older CloudFormation templates, Terraform configs, and CDK stacks still specify `gp2` and were never updated |
| No urgency | AWS hasn't deprecated gp2, so teams don't prioritize the migration |
| Change management | Some organizations require approval processes even for simple, zero-risk changes |
| Lack of awareness | Many teams don't realize gp3 exists or that migration is free and online |

AWS themselves recommend migrating all gp2 volumes to gp3. There is no scenario where gp2 outperforms gp3 at a lower cost.

## Disclaimer

This tool is provided as-is for educational and operational purposes. Use at your own risk. Always test in a non-production environment first. The author is not responsible for any data loss, service disruption, unexpected costs, or performance changes resulting from volume migrations. Cost savings are estimates based on standard AWS pricing and may vary by region, usage, and provisioned IOPS/throughput. Review the [AWS EBS pricing page](https://aws.amazon.com/ebs/pricing/) and the [AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/optimize-costs-microsoft-workloads/ebs-migrate-gp2-gp3.html) before migrating production workloads.
