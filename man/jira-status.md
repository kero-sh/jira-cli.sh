# jira status

List all available statuses in Jira.

## Usage

```bash
jira status [options]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --output FORMAT | json, csv, table, yaml, md | Output format |
| -h, --help | | Show this help |

## Examples

```bash
# List all statuses (default output)
jira status

# List statuses in table format
jira status --output table

# List statuses in JSON format
jira status --output json

# List statuses in CSV format
jira status --output csv

# List statuses in YAML format
jira status --output yaml

# List statuses in Markdown format
jira status --output md
```

## Notes

- Lists all status levels configured in your Jira instance
- Output formats support different use cases:
  - `json`: For scripting and API integration
  - `csv`: For spreadsheet analysis
  - `table`: For terminal viewing
  - `yaml`: For configuration files
  - `md`: For documentation
- Status names and categories may vary by Jira workflow configuration
