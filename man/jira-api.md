# jira api

Make direct HTTP requests to Jira API, similar to glab api.

## Usage

```bash
jira api <endpoint> [options]
```

## Options

| Option | Value | Description |
|---------|--------|-------------|
| --method METHOD | GET, POST, PUT (default: GET, changes to POST if there are fields) | HTTP method |
| --field key=value | | Add parameter with type inference (true/false/null/@file) |
| --raw-field key=value | | Add parameter as string (no type inference) |
| --header KEY:VALUE | | Add additional HTTP header |
| --input FILE|JSON | | File or JSON for request body (use - for stdin) |
| --output FORMAT | json, csv, table, yaml, md | Output format |
| -h, --help | | Show this help |

## Type Inference for --field

| Input | Converted to |
|-------|--------------|
| true, false, null | Corresponding JSON types |
| numbers (123) | JSON numbers |
| @filename | Reads file content |

## Examples

```bash
# Simple GET request
jira api /issue/ABC-123

# GET request with output format
jira api /issue/ABC-123 --output table

# POST request with fields
jira api /issue --method POST --field summary="New Issue" --field project="ABC"

# POST with file input
jira api /issue --method POST --input issue.json

# POST with raw fields (no type inference)
jira api /issue --method POST --raw-field customField="raw string value"

# Request with custom headers
jira api /issue/ABC-123 --header Authorization:"Bearer token"

# Complex request with multiple fields
jira api /issue --method POST \
  --field summary="Bug in login" \
  --field project="ABC" \
  --field issuetype="Bug" \
  --field priority="High"

# Request from stdin
echo '{"summary":"Test"}' | jira api /issue --method POST --input -

# Read JSON from file
jira api /issue/ABC-123 --input payload.json

# CSV output
jira api /search --output csv --field jql="project=ABC"
```

## Notes

- Supports GET, POST, PUT methods with automatic payload construction
- Method defaults to GET, changes to POST if fields are provided
- --field performs automatic type inference for JSON compatibility
- --raw-field treats values as literal strings
- Use --input - to read from stdin
- Headers can be added for authentication or custom requirements
- Output formats support different use cases (json for scripting, table for viewing)
