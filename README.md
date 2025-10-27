# JIRA CLI Tools

Complete suite of command-line tools to interact with Jira.

## Project Structure

This project follows the standard GNU structure:

```
jira-cli/
├── bin/           # Symbolic links to executables (without .sh extension)
├── src/           # Source scripts with .sh extension
├── lib/           # Shared libraries
└── doc/           # Documentation
```

## Installation

### Manual Installation

Add the `bin/` directory to your PATH:

```bash
export PATH="/Users/carlosherrera/src/scripts/jira-cli/bin:$PATH"
```

Add this to your `~/.bashrc` or `~/.zshrc` to make it permanent.

### Using make

```bash
make install         # Install to ~/.local/bin
make install PREFIX=/usr/local  # Install to /usr/local/bin
```

## Configuration

Configure the following environment variables:

### Basic Authentication (Jira Cloud with API Token)

```bash
export JIRA_HOST="https://your-instance.atlassian.net"
export JIRA_EMAIL="your-email@example.com"
export JIRA_API_TOKEN="your-api-token"
```

### OAuth/Bearer Authentication

```bash
export JIRA_HOST="https://your-instance.atlassian.net"
export JIRA_TOKEN="your-oauth-token"
```

### Additional Variables

```bash
export JIRA_PROJECT="PROJECT-KEY"  # Default project for creating issues
export JIRA_API_VERSION="3"        # 3 for Cloud (default), 2 for Server/DC
```

## Available Commands

### jira

Main Jira API client. Supports traditional and simplified syntax.

```bash
# Simplified syntax
jira priority --output table
jira project PROJECT-123
jira issue ABC-123
jira search 'project=ABC AND status=Open'
jira create --project ABC --summary "Title" --description "Desc" --type Task

# Traditional syntax
jira GET /priority
jira POST /issue --data payload.json
```

### jira-issue

Get information about a specific issue.

```bash
jira-issue ABC-123
jira-issue ABC-123 --fields '{"key":.key,"summary":.fields.summary}'
jira-issue ABC-123 --full
```

### jira-create-issue

Create or update a Jira issue.

```bash
jira-create-issue --project ABC --summary "Title" --description "Description" --type Task
jira-create-issue ABC-123 --summary "New title"  # Update
```

### jira-issue-create-branch

Create a Git branch based on a Jira issue. The branch prefix is automatically determined based on the issue type and priority.

```bash
jira-issue-create-branch ABC-123
# Creates: feature/ABC-123-issue-title
```

Generated branch types:
- `hotfix/` - Critical bugs and incidents
- `bugfix/` - Normal bugs
- `feature/` - Stories, improvements, epics
- `task/` - Tasks
- `chore/` - Maintenance

### jira-search

Search issues using JQL.

```bash
jira-search 'project=ABC AND status=Open'
jira-search 'assignee=currentUser() AND priority=High'
```

### jira-issues-pending-for-me

List issues assigned to you that are not in Done status.

```bash
jira-issues-pending-for-me
```

### jira-issue-link

Create a link between two issues.

```bash
jira-issue-link ABC-123 DEF-456 --type Relates
```

### jira-issue-transition-done

Execute a sequence of transitions to move an issue to Done status.

```bash
jira-issue-transition-done ABC-123
```

### jira-issue-transition-redo

Revert an issue and move it back to Done status.

```bash
jira-issue-transition-redo ABC-123
```

 

## Dependencies

### Required

- **bash** - Unix shell
- **curl** - HTTP client
- **jq** - Command-line JSON processor
- **git** - For `jira-issue-create-branch`

### Optional

- **yq** - For YAML output format (`--output yaml`)
- **column** - For table output format (`--output table`)

### Installing Dependencies

#### macOS

```bash
brew install jq yq
```

#### Ubuntu/Debian

```bash
sudo apt-get install jq
sudo snap install yq
```

#### CentOS/RHEL

```bash
sudo yum install jq
```

## Output Formats

The main `jira` command supports multiple output formats:

```bash
jira priority --output json   # Formatted JSON (default)
jira priority --output csv    # CSV
jira priority --output table  # Table with columns
jira priority --output yaml   # YAML
jira priority --output md     # Markdown table
```

## Autocompletion

Generate autocompletion scripts for your shell:

### Bash

```bash
jira --shell bash > ~/.jira-completion.bash
echo 'source ~/.jira-completion.bash' >> ~/.bashrc
```

### Zsh

```bash
jira --shell zsh > ~/.jira-completion.zsh
echo 'source ~/.jira-completion.zsh' >> ~/.zshrc
```

## Usage Examples

### Complete Workflow

```bash
# 1. Search pending issues
jira-issues-pending-for-me

# 2. View issue details
jira-issue ABC-123

# 3. Create branch to work on
jira-issue-create-branch ABC-123

# 4. ... make changes and commit ...

# 5. Update the issue
jira-issue-transition-done ABC-123

# 6. Create a new issue
jira-create-issue --project ABC \
  --summary "New feature" \
  --description "Detailed description" \
  --type Story \
  --priority High
```

### Complex Searches

```bash
# Issues from last sprint
jira search 'sprint in openSprints() AND project=ABC'

# Issues with specific label
jira search 'labels=backend AND status="In Progress"'

# Issues updated this week
jira search 'updated >= -1w AND assignee=currentUser()'
```

## File Structure

### Executable Scripts (bin/)

All available commands as symbolic links without `.sh` extension.

### Source Scripts (src/)

Original files with `.sh` extension:
- `jira.sh` - Main API client
- `jira-create-issue.sh` - Issue creator
- `jira-issue.sh` - Issue query
- `jira-issue-create-branch.sh` - Branch creator
- `jira-issue-link.sh` - Issue linker
- `jira-issue-transition-done.sh` - Transition to Done
- `jira-issue-transition-redo.sh` - Re-transition
- `jira-issues-pending-for-me.sh` - Pending issues lister
- `jira-search.sh` - JQL searcher

### Libraries (lib/)

- `helpers.sh` - Auxiliary functions (logging, colors, etc.)

## Support

For issues or questions:
1. Verify all dependencies are installed
2. Check environment variables are configured correctly
3. Use `--help` on any command to see help

## License

Internal use.
