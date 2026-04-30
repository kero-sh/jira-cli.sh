# jira create

Create a new Jira issue with various output options.

## Usage

```bash
jira create [OPTIONS]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --data | '{json}' or FILE | Uses JIRA_DEFAULT_DATA if not specified. |
| --project | KEY | Uses JIRA_DEFAULT_PROJECT first, then JIRA_PROJECT. |
| --summary | TEXT | Issue title/summary. |
| --description | TEXT | Issue description. |
| --type | NAME | Issue type (e.g., Task, Bug, Story). (default: Task) |
| --assignee | USERNAME | Assign issue to user. |
| --reporter | USERNAME | Set issue reporter. |
| --priority | NAME | Issue priority (e.g., High, Medium, Low). |
| --epic | KEY | Link to epic (customfield_10100). |
| --link-issue | KEY | Create 'Relates to' link to another issue. |
| --template | FILE | Base JSON template file. |

## Output Options

| Option | Value | Description |
|---------|--------|-------------|
| -O|--output | FORMAT [FILE] | Save payload to file (json, yaml, text, csv). |
| --only-* | | Show payload in stdout without creating issue in any format json, yaml, text, csv. |
| --dry-run | | Print curl command instead of executing. |
| -h, --help | | Show this help. |

## Examples

### Basic issue creation
```bash
jira create --project ABC --summary "Fix login bug" --type Bug
```

### With environment variables
```bash
JIRA_DEFAULT_PROJECT=ABC jira create --summary "New feature" --type Story
```

### Using JSON data
```bash
jira create --data '{"fields":{"project":{"key":"ABC"},"summary":"Test","issuetype":{"name":"Task"}}}'
```

### Save payload without creating
```bash
jira create --only-json --project ABC --summary "Preview issue"
```

### Save to file
```bash
jira create --output json /tmp/payload.json --project ABC --summary "Issue"
```

### Using default data
```bash
JIRA_DEFAULT_DATA=./template.json jira create --summary "Custom title"
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| JIRA_DEFAULT_PROJECT | Default project key (highest priority) |
| JIRA_PROJECT | Default project key (fallback) |
| JIRA_DEFAULT_DATA | Default JSON data/template |
| JIRA_HOST | Jira instance URL |
| JIRA_TOKEN | Authentication token |

## Notes

- **Priority order**: --project > JIRA_DEFAULT_PROJECT > JIRA_PROJECT.
- **Data priority**: --data > JIRA_DEFAULT_DATA > --template.
- **CSV format exports**: [project, summary, type].
