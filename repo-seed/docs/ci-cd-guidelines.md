# CI/CD Guidelines

**Version**: 1.25  
**Status**: Active  
**Last Updated**: 2026-06-19

Use this document when creating or changing CI/CD workflows, build pipelines, release automation, or deployment automation.

## Core Rule

Do not modify CI/CD unless the task explicitly asks for CI/CD work.

CI/CD changes can affect releases, deployments, secrets, permissions, infrastructure, and production behavior. Keep changes small, reviewable, and easy to rollback.

## Safe Default Pipeline

For a new or small project, start with validation only:

1. checkout
2. restore/install dependencies
3. build
4. run tests
5. run lint/format checks if configured

Do not add deployment, package publishing, release creation, or secret-dependent jobs until the project actually needs them.

## Change Rules

- Preserve the existing CI/CD provider and workflow structure.
- Prefer modifying the narrowest relevant workflow/job/step.
- Do not rename workflows, jobs, environments, or secrets unless the task requires it.
- Do not weaken branch filters, required checks, approvals, permissions, or test gates.
- Do not add broad permissions such as write-all unless the task explicitly requires it and the reason is documented.
- Do not add deployment or publishing jobs without documented target, trigger, credentials, rollback, and validation plan.
- Do not print or expose secret values.
- Do not guess secret names. Use only names already documented in the repository/task.

## Branch and PR Expectations

CI/CD changes follow the same strict Git Flow rules as code changes.

Normal CI/CD work uses:

```text
feature/update-ci-validation
```

Emergency production pipeline fixes use:

```text
hotfix/fix-release-workflow
```

All CI/CD changes should go through PR review. Never auto-merge CI/CD changes.

## Validation

Before finishing a CI/CD task:

- Check YAML/syntax validity when possible.
- Run equivalent local commands when practical.
- Verify changed paths, triggers, environment names, and permissions.
- Confirm the workflow still targets the expected branches.
- State which parts can only be verified by the hosted CI system.

## Documentation

Update repository documentation when CI/CD changes affect:

- build/test commands
- release process
- deployment process
- required secrets or environment variables
- supported branches or triggers
- required manual approval steps

Do not invent deployment instructions, secret names, hosted environment names, or release guarantees.
