# Runbook — S3 backend state incidents

Two failure modes for the S3 remote state backend (`s3-bucket-devopsjourney`, `eu-north-1`, native `use_lockfile` locking, no DynamoDB): a stuck lock, and a bad/corrupted state file. Different problem, different fix, different blast radius if you run the wrong one. Read "When *not* to run this" before running either command — both are safe in the right situation and destructive in the wrong one.

Applies to both envs — swap the state key: `day3/dev/platform.tfstate` or `day3/staging/platform.tfstate`. Run all commands from inside `envs/dev` or `envs/staging` unless noted otherwise.

## 1. `terraform force-unlock`

**Symptom:** `plan`/`apply`/`destroy` fails immediately with `Error acquiring the state lock` and a `Lock Info` block showing `ID`, `Who`, `Created`, and `Operation`.

**What the lock actually is:** with `use_lockfile = true` (Terraform ≥ 1.10, no DynamoDB table), the S3 backend writes a small lock object next to the state file using a conditional (If-None-Match) write. It is not held by a database row or a TTL — it is held until either the operation that created it finishes and removes it, or someone removes it manually. Nothing expires it automatically.

### Steps

1. **Read the `Lock Info` block from the error.** It tells you `Who` (user@host that took the lock) and `Created` (when). Do not skip this — this is the check that decides whether you should even be considering the next step.
2. **Confirm the lock holder is actually dead**, not just slow. A `terraform apply` on a t3.micro EC2 instance can legitimately run for a couple of minutes. Check:
   - Is `Who` you, on a machine/session you know crashed, lost network, or got killed mid-apply?
   - Or is `Who` a teammate/CI run — if so, **message them first**, don't guess.
   - If there's any real chance the process in `Who` is still running, do not proceed. Wait it out instead.
3. Only once you've confirmed the holder is dead, unlock:
   ```sh
   terraform force-unlock <LOCK_ID>
   ```
   `<LOCK_ID>` is the `ID` value from the `Lock Info` block, not something you invent.
4. Immediately run `terraform plan` before anything else. If a real `apply` was interrupted mid-flight, the plan may show resources in a half-applied state — read it before touching `apply`.

### When *not* to run `force-unlock`

- **When you can't positively confirm the lock holder is dead.** This is the whole failure mode force-unlock exists to protect against, in reverse: if the original process is still applying and you force-unlock and start a second `apply`, you now have two Terraform runs mutating the same real infrastructure and writing to the same state file with no coordination. That's how state gets corrupted and resources get orphaned or double-created — worse than just waiting.
- **When someone else's name is in `Who`.** Ask first. A five-minute Slack message costs less than a broken shared state file.
- **As a reflex for any Terraform error.** `force-unlock` fixes *stuck locks*, not plan errors, provider errors, or auth failures — those look completely different (no `Lock Info` block) and unlocking does nothing for them.

## 2. Restoring a previous state version (S3 bucket versioning)

**Symptom:** the current state file is bad — truncated, hand-edited into a broken shape, overwritten by a mistaken `terraform state push`, or otherwise not a valid reflection of what Terraform itself last wrote. Versioning is enabled on `s3-bucket-devopsjourney` specifically so this is recoverable without S3 backups.

**Critical distinction before you touch this:** state file bad ≠ don't like the last infrastructure change. Restoring an old state version does not undo anything in AWS — it only rewinds Terraform's *record* of what it manages. If real infrastructure changed since that old version (an instance got replaced, a security group rule got added), restoring state doesn't roll any of that back; it just makes Terraform's map wrong relative to reality, and the next `plan` will propose changes based on a stale picture — potentially trying to recreate resources that already exist correctly, or destroy resources it no longer thinks it should own.

### Steps

1. **List the version history** for the state object:
   ```sh
   aws s3api list-object-versions \
     --bucket s3-bucket-devopsjourney \
     --prefix "day3/<env>/platform.tfstate" \
     --query "Versions[].{VersionId:VersionId,LastModified:LastModified,IsLatest:IsLatest,Size:Size}" \
     --output table
   ```
2. **Download and inspect the candidate version before restoring anything** — don't restore blind:
   ```sh
   aws s3api get-object \
     --bucket s3-bucket-devopsjourney \
     --key "day3/<env>/platform.tfstate" \
     --version-id "<VERSION_ID>" \
     ./candidate.tfstate

   cat ./candidate.tfstate | jq '.resources[].type'   # sanity-check it has what you expect
   ```
3. **Restore it as the new current version** by copying that old version onto the key — this does *not* delete the bad version, it just appends a new version on top with the old content, so the bad version stays in history if you need it later:
   ```sh
   aws s3api copy-object \
     --bucket s3-bucket-devopsjourney \
     --copy-source "s3-bucket-devopsjourney/day3/<env>/platform.tfstate?versionId=<VERSION_ID>" \
     --key "day3/<env>/platform.tfstate"
   ```
4. **`terraform plan` immediately, before any `apply`.** This is the step that tells you whether the restored state actually matches reality. A clean/expected diff means you picked the right version. A plan full of surprise replacements means either you picked the wrong version, or real infrastructure has drifted since it — stop and investigate rather than applying to "fix" the diff.
5. Delete `./candidate.tfstate` locally once done — it's a raw copy of state, treat it like the state file itself (may contain data source values), don't leave it lying around or commit it.

### When *not* to restore a previous version

- **When the current state is valid but you simply disagree with a change it recorded.** That's a `terraform plan`/`apply` decision (or `state rm`/`import` for a single resource), not a version-restore. Version-restore is for a *broken* state file, not an *unwanted-but-correct* one.
- **Without running `plan` against the restored version first.** Restoring and then immediately `apply`-ing skips the one check that tells you whether the restore is actually safe relative to current real infrastructure.
- **If you're not sure real infrastructure hasn't changed since the version you're restoring to.** Check what's actually live (`aws ec2 describe-instances`, etc. — same way drift gets caught, see below) before assuming an old state version is still an accurate picture.
- **As a substitute for fixing drift.** If the state is *technically valid* but out of sync with reality (something was changed outside Terraform), that's a drift problem — reconcile it with `terraform plan`/`apply` or `terraform import`, not by rewinding to an older state version that predates the drift and pretending it didn't happen.

## Acceptance criteria for this runbook

- [ ] `force-unlock` command documented with the actual `Lock Info` fields to check first.
- [ ] Explicit "when not to" for `force-unlock` — concurrent-run corruption risk named.
- [ ] Previous-state-version restore documented using this bucket's real versioning (list → inspect → copy-object restore, not delete-and-hope).
- [ ] Explicit "when not to" for state restore — drift vs. corruption distinction named, `plan`-before-`apply` step called out.