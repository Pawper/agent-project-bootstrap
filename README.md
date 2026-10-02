# agent-project-bootstrap

A Claude Code skill, and the plugin around it, for standing up a project so many coding agents can work in it at once without colliding.

The lesson it comes from: rules written for one agent become pathologies when thirty follow them at once, and the codebase is the one surface every agent must write to, so anything that lives there is something they all collide on. Decide the homes and the enforcement first, then let agents build.

The skill is in `skills/project-bootstrap/SKILL.md`. Copy that folder into `~/.claude/skills/` to use it anywhere, or into a project's `.claude/skills/`.

The plugin files, the hooks that enforce the rules, the issue template with a State label and the CI skeleton, are filled in by the first session that works on this repository; see the issue list.
