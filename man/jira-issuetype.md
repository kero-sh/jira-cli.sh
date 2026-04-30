# jira issuetype

List all available issue types in Jira.

## Usage

```bash
jira issuetype [options]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --output FORMAT | json, csv, table, yaml, md | Output format |
| -h, --help | | Show this help |

## Examples

```bash
# List all issue types (default output)
jira issuetype

# List issue types in table format
jira issuetype --output table

# List issue types in JSON format
jira issuetype --output json

# List issue types in CSV format
jira issuetype --output csv

# List issue types in YAML format
jira issuetype --output yaml

# List issue types in Markdown format
jira issuetype --output md
```

## Notes

- Lists all issue types configured in your Jira instance
- Common issue types include: Task, Bug, Story, Epic, Sub-task
- Issue types may vary by Jira project configuration
- Output formats support different use cases:
  - `json`: For scripting and API integration
  - `csv`: For spreadsheet analysis
  - `table`: For terminal viewing
  - `yaml`: For configuration files
  - `md`: For documentation
- Some issue types may be project-specific
