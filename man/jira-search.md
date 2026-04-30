# jira search

Search issues using JQL (Jira Query Language).

## Usage

```bash
jira search [jql] [options]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --output FORMAT | json, csv, table, yaml, md | Output format |
| --csv-export TYPE | all|current | CSV export mode |
| --paginate | | Automatically paginate through all result pages |
| -h, --help | | Show this help |

## Examples

```bash
# Search issues assigned to current user (default behavior)
jira search

# Search with JQL query
jira search 'project=ABC AND status=Open'

# Search with JQL and output format
jira search 'assignee=currentUser()' --output md

# Search with pagination (gets all results)
jira search 'project=ABC' --paginate

# Search with CSV export
jira search 'project=ABC' --output csv --csv-export all

# Search for specific issue types
jira search 'project=ABC AND issuetype in (Bug, Story)'

# Search with date range
jira search 'project=ABC AND created >= 2024-01-01'

# Complex JQL search
jira search 'project=ABC AND status in ("In Progress", "Testing") AND priority = High'
```

## Notes

- Without JQL, searches for issues assigned to current user
- Use --paginate to automatically retrieve all pages of results
- CSV export modes:
  - `all`: Export all matching issues
  - `current`: Export only current page of results
- JQL syntax follows standard Jira Query Language
- Output formats support different use cases:
  - `json`: For scripting and API integration
  - `csv`: For spreadsheet analysis
  - `table`: For terminal viewing
  - `yaml`: For configuration files
  - `md`: For documentation
