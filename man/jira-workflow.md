# jira workflow

List all available workflows or get specific workflow details.

## Usage

```bash
jira workflow [id] [options]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --output FORMAT | json, csv, table, yaml, md | Output format |
| -h, --help | | Show this help |

## Examples

```bash
# List all workflows (default output)
jira workflow

# List workflows in table format
jira workflow --output table

# List workflows in JSON format
jira workflow --output json

# Get specific workflow by ID
jira workflow WORKFLOW-123

# Get specific workflow with output format
jira workflow WORKFLOW-123 --output table

# List workflows in CSV format
jira workflow --output csv

# List workflows in YAML format
jira workflow --output yaml

# List workflows in Markdown format
jira workflow --output md
```

## Notes

- Without ID, lists all available workflows
- With ID, gets specific workflow details
- For workflows by project and issue type, use: `jira project statuses <PROJECT>`
- Output formats support different use cases:
  - `json`: For scripting and API integration
  - `csv`: For spreadsheet analysis
  - `table`: For terminal viewing
  - `yaml`: For configuration files
  - `md`: For documentation
- Workflow IDs and names may vary by Jira configuration
