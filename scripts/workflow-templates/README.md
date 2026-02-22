# Release Workflow Templates

These templates bootstrap the GitHub Actions workflows required by `scripts/release_all.sh`.

Included templates:
- `pre-release-ci.yml`
- `pre-release-ci-enterprise-selfhosted.yml`
- `release-notarized.yml`
- `release-notarized-selfhosted.yml`
- `release-dry-run.yml`

Install into a target repository with:

```bash
scripts/setup_release_workflows.sh --target /path/to/repo --commit --push
```

For GitHub Enterprise with self-hosted runners:

```bash
scripts/setup_release_workflows.sh --target /path/to/repo --enterprise-selfhosted --commit --push
```
