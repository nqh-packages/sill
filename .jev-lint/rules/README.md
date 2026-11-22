# Semantic Lint Rules (`.jev-lint/rules/`)

Add one `.md` file per rule with YAML frontmatter (`id`, `kind`, `severity`, `globs`, `threshold`, `fix`, optional `provider`) plus `## Question`, `## Bad`, and `## Good` sections.
Test every rule before committing: `~/.agents/skills/lint/scripts/lint-run test-rule .jev-lint/rules/<id>.md`
