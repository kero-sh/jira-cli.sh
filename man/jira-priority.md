# jira priority

List all available priorities in Jira.

## Usage

```bash
jira priority [options]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --output FORMAT | json, csv, table, yaml, md | Output format |
| -h, --help | | Show this help |

## Examples

```bash
# List all priorities (default output)
jira priority

# List priorities in table format
jira priority --output table

# List priorities in JSON format
jira priority --output json

# List priorities in CSV format
jira priority --output csv

# List priorities in YAML format
jira priority --output yaml

# List priorities in Markdown format
jira priority --output md
```

## Notes

- Lists all priority levels configured in your Jira instance
- Output formats support different use cases:
  - `json`: For scripting and API integration
  - `csv`: For spreadsheet analysis
  - `table`: For terminal viewing
  - `yaml`: For configuration files
  - `md`: For documentation
- Priority names and IDs may vary by Jira configuration
