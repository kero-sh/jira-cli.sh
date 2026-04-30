# jira profile

Get information about the currently authenticated user's profile.

## Usage

```bash
jira profile [options]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --output FORMAT | json, csv, table, yaml, md | Output format |
| -h, --help | | Show this help |

## Examples

```bash
# Get user profile (default output)
jira profile

# Get profile in table format
jira profile --output table

# Get profile in JSON format
jira profile --output json

# Get profile in CSV format
jira profile --output csv

# Get profile in YAML format
jira profile --output yaml

# Get profile in Markdown format
jira profile --output md
```

## Returned Information

- **accountId**: Unique Atlassian account ID
- **displayName**: User's visible name
- **emailAddress**: User's email address
- **active**: Account status (active/inactive)
- **timeZone**: User's timezone
- **locale**: User's locale settings
- **groups**: User groups (if accessible)

## Notes

- Uses the `/myself` endpoint of the Jira API
- Returns details based on the provided authentication token
- No additional parameters required - uses current authenticated context
- Output formats support different use cases:
  - `json`: For scripting and API integration
  - `csv`: For spreadsheet analysis
  - `table`: For terminal viewing
  - `yaml`: For configuration files
  - `md`: For documentation
- Information available depends on Jira permissions and API version
