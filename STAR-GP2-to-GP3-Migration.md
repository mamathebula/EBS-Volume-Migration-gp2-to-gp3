# EBS Volume Migration (gp2 → gp3) — STAR Method

## Situation

AWS accounts often accumulate EBS volumes provisioned as gp2 (second-generation general purpose SSD), which was the default volume type for years. In December 2020, AWS released gp3 — a newer generation that is 20% cheaper ($0.08/GB vs $0.10/GB) and offers better baseline performance (3,000 IOPS regardless of size, compared to gp2 where a volume needs to be 1 TB to reach 3,000 IOPS).

Despite gp3 being available for years, many accounts still have gp2 volumes because there's no automatic migration path. Migrating manually through the AWS Console means clicking into each volume individually, selecting "Modify Volume", changing the type, and confirming — one at a time. For accounts with dozens or hundreds of volumes across multiple regions, this is impractical and easy to overlook, resulting in ongoing unnecessary costs.

## Task

My goal was to create a tool that migrates all gp2 EBS volumes to gp3 across an AWS account efficiently. The solution needed to:

- Find all gp2 volumes in a region (or all regions at once)
- Show the user exactly what will be migrated before making changes
- Handle large numbers of volumes without hitting AWS API rate limits
- Require no AWS resources to deploy — just run and done
- Be safe to run on production volumes (no downtime, no data loss)

## Action

I built a bash script that automates the entire migration:

- The script queries the EC2 API to discover all gp2 volumes, displaying volume ID, size, state, and which instance each is attached to
- It asks for confirmation before proceeding, giving the user full visibility
- Volumes are migrated in batches of 10 with a 5-second pause between batches to avoid AWS API throttling
- I added an `--all-regions` flag that loops through every AWS region automatically, scanning each for gp2 volumes
- When running across all regions, the user can press `a` at any prompt to auto-approve all remaining regions
- The script calculates and displays potential savings at every level — per volume, per region (monthly and yearly), and a grand total across all regions when using `--all-regions`
- The migration is online — volumes stay attached and usable with zero downtime

I also wrote a comprehensive README covering the cost comparison, savings examples, advantages and disadvantages of gp3, how to check migration status, risks, CloudFormation drift implications, and a link to the official AWS prescriptive guidance documentation.

## Result

What previously required manually modifying each volume through the AWS Console was reduced to a single command. Key outcomes:

- A task that could take hours of clicking is now completed in minutes
- The script shows potential savings before migration — per volume, per region, and grand total across all regions — so the user knows exactly how much money they'll save before confirming
- 20% cost reduction on every migrated volume — for example, an account with 50 volumes totaling 10 TB saves $200/month ($2,400/year)
- Performance improvement on smaller volumes — volumes under 1 TB get a significant IOPS boost (3,000 baseline vs as low as 100 on gp2)
- The `--all-regions` flag ensures no region is missed, eliminating forgotten gp2 volumes in rarely-used regions
- Zero downtime — all migrations happen online with no impact to running workloads
- Reusable for any AWS account — just run the script, no configuration needed
- No AWS resources deployed — nothing to clean up afterwards

## Disclaimer

This tool is provided as-is for educational and operational purposes. Use at your own risk. Always test in a non-production environment first. The author is not responsible for any data loss, service disruption, unexpected costs, or performance changes resulting from volume migrations. Cost savings are estimates based on standard AWS pricing and may vary by region, usage, and provisioned IOPS/throughput. Review the [AWS EBS pricing page](https://aws.amazon.com/ebs/pricing/) and the [AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/optimize-costs-microsoft-workloads/ebs-migrate-gp2-gp3.html) before migrating production workloads.
