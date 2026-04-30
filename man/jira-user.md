# jira user

Get user information, search users, and view user activity.

## Usage

```bash
jira user [command] [options]
```

## Commands

### get
Get user profile information.

```bash
jira user get <email|username|accountId>
```

### search  
Search for users by text.

```bash
jira user search <text>
```

### activity
Get user activity summary.

```bash
jira user activity [term]
```

## Options

### Activity Options

| Option | Value | Description |
|---------|--------|-------------|
| --jql | | Print JQL queries by category instead of counting |
| --from-date | YYYY-MM-DD | Start date (range); default last 30d |
| --to-date | YYYY-MM-DD | End date (range); default last 30d |
| --lookback | Nd | Alternative to --from-date/--to-date; e.g. 30d |
| --states | | Group only states by created/assigned (To Do, In Progress, Done) |
| --list | | In addition to counting, return lists by category (key fields) |
| --list-only | | Return only flat list (for --output table) |
| --limit | N | Maximum issues per list (default 100) |

## Examples

```bash
# Get user by email
jira user get carlos@example.com

# Get user by username
jira user get carlos.herrera

# Get user by account ID
jira user get 5f3a1b2c3d4e5f6789012345

# Search for users
jira user search jimy

# Get activity for user
jira user activity jimy

# Get activity with date range
jira user activity jimy --from-date 2024-01-01 --to-date 2024-01-31

# Get activity with lookback
jira user activity jimy --lookback 60d

# Get activity with states grouping
jira user activity jimy --states

# Get activity with JQL output
jira user activity jimy --jql
```

## Aliases

```bash
jira user <text>  # Equivalent to 'jira user search <text>'
```

## Notes

- In API v3 (Cloud) uses accountId; for 'get' with email/username, a search is performed to resolve the accountId.
- In API v2 (Server/DC) uses username; 'get' resolves username via search.
- For 'activity', default range is last 30 days (configurable with --lookback or --from-date/--to-date).
- 'activity' without term uses your current user (endpoint /myself).
- With --jql, JQL queries are printed by group (reported and assigned) and by status category (To Do, In Progress, Done), including date range.
- With --states/--list, grouping is by statusCategory (grey/blue/green).
- Lists include: key, project, summary, statusCategory, labels, components and epic (if in customfield_10014).
