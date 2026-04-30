# jira project

Get project information, list components, and view workflows.

## Usage

```bash
jira project [id|command] [options]
```

## Commands

### components
List components of a project.

```bash
jira project components <project>
```

### statuses
Get workflows/statuses by issue type in a project.

```bash
jira project statuses <project>
```

### workflow
Show workflow and transitions for a specific issue type.

```bash
jira project <project> --workflow [issuetype]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --output FORMAT | json, csv, table, yaml, md | Output format |
| --workflow [issuetype] | e.g. Task, Bug, Story | Filter workflow by issue type |
| --export | | Export component list to stdout (components only) |
| --import | | Import components from stdin (components only) |
| --format FORMAT | json, csv, yaml, tsv (default: json) | Format for --export/--import |
| -h, --help | | Show this help |

## Examples

```bash
# List all projects
jira project

# Get specific project
jira project CORE

# List projects in table format
jira project --output table

# List components of a project
jira project components PROJ

# Export components to JSON file
jira project components PROJ --export --format json > comps.json

# Import components from JSON file
jira project components PROJ --import --format json < comps.json

# Get workflows/statuses of a project
jira project statuses PROJ

# Show workflow for specific issue type
jira project PROJ --workflow Task

# Show workflow for Story type
jira project PROJ --workflow Story
```

## Notes

- Without ID, lists all available projects
- Components can be exported/imported for backup/restore
- Workflow view shows transitions and status flows
- Issue type filtering applies to workflow display only
