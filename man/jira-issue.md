# jira issue

Get issue information, add comments, and move issues between projects.

## Usage

```bash
jira issue [key] [options]
jira issue comment [key] -m "message" [options]
jira issue comment [key] -m "@file" [options]
jira [key] --move PROJ  # Move (clone) issue to another project
jira move [key] --to-project PROJ [options]
```

## Commands

### comment
Add a comment to the specified issue.

```bash
jira issue comment [key] -m "message"
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --transitions | | Show available transitions |
| --to ID | ID of transition to apply (requires --transitions) |
| --transition SPEC | Apply transition by ID, transition name, or destination status name |
| --assign [me|email|user|none] | Assign issue to a user |
| --unassign | | Unassign issue (alias for --assign none) |
| --move PROJ | | Clone issue in project PROJ (move between projects) |
| --components A,B | | Component list for destination issue (overwrites source) |
| --yes | | Non-interactive mode: don't prompt for type or component creation |
| -m, --message | | Comment message (required for comment) |
| --comment-scan-max NUM | | Comment scan limit (default: $JIRA_ACTIVITY_COMMENT_SCAN_MAX or 100) |
| --output FORMAT | json, csv, table, yaml, md | Output format |
| -h, --help | | Show this help |

## Examples

```bash
# List issues assigned to you
jira issue

# Get specific issue
jira issue ABC-123

# Clone issue to another project
jira issue ABC-123 --move PROJ2

# Short form for move
jira ABC-123 --move PROJ2

# Move with components and non-interactive mode
jira move ABC-123 --to-project PROJ2 --components Frontend,Backend --yes

# Assign to current user
jira issue ABC-123 --assign me

# Assign to specific user
jira issue ABC-123 --assign user@example.com

# Unassign issue
jira issue ABC-123 --assign none

# Unassign using alias
jira issue ABC-123 --unassign

# Add comment
jira issue comment ABC-123 -m "Comment here"

# Add comment from file
jira issue comment ABC-123 -m "@message.txt"

# Add comment from pipe
echo "message" | jira issue comment ABC-123 -m -

# Show available transitions
jira issue ABC-123 --transitions

# Apply transition
jira issue ABC-123 --transition "In Progress"
```

## Notes

- Without key, lists issues assigned to you
- With --transitions, shows available transitions
- With 'comment', adds a comment to the issue
- With --move PROJ, clones the issue in project PROJ (creates components/labels if missing, links to original)
- Move operation is for moving between projects (not within same project)
- Component list overwrites source components when moving
- Non-interactive mode skips prompts for type and component creation
