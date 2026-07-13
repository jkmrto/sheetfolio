# Sheetfolio

## End-of-task routine
When a task that changed code is complete and verified, always finish by:

1. Making exactly one git commit for the task (don't batch unrelated tasks into it).
2. Running `fly deploy` and checking production stays healthy.

This is standing authorization — don't ask for confirmation. Pushing to GitHub still requires an explicit request.

A Stop hook in `.claude/settings.json` blocks ending the turn while the working tree is dirty.

## Quality gate
`mix credo` must stay clean before committing (also enforced in CI).
