# JIRA CLI Tools

Complete suite of command-line tools to interact with Jira.

## Table of Contents

- [Installation](#installation)
  - [Quick Installation](#quick-installation)
  - [Using Make](#using-make)
  - [Manual Installation](#manual-installation)
- [Configuration](#configuration)
  - [Basic Authentication](#basic-authentication-recommended-for-jira-cloud)
  - [OAuth/Bearer Authentication](#oauthbearer-authentication)
  - [Multiple Jira Instances](#multiple-jira-instances)
- [Dependencies](#dependencies)
  - [Required Dependencies](#required-dependencies)
  - [Optional Dependencies](#optional-dependencies)
  - [Installing Dependencies](#installing-dependencies)
- [Available Commands](#available-commands)
- [Usage with JSON Files](#usage-with-json-files)
- [Output Formats](#output-formats)
- [Autocompletion](#autocompletion)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)

## Installation

### Quick Installation

#### Option 1: Add to PATH (Recommended for development)

```bash
# In your ~/.bashrc or ~/.zshrc
export PATH="/path/to/jira-cli.sh/bin:$PATH"

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

#### Option 2: Installation with Make (Recommended for permanent use)

```bash
cd /path/to/jira-cli.sh

# Install to ~/.local/bin (standard user location)
make install

# Or install to custom location
make install PREFIX=/usr/local

# Ensure ~/.local/bin is in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

#### Option 3: Manual Symbolic Links

```bash
# Create links in a directory already in your PATH
cd /path/to/jira-cli.sh/bin
for script in *; do
    sudo ln -sf "$(pwd)/$script" /usr/local/bin/"$script"
done
```

### Using Make

```bash
make install         # Install to ~/.local/bin
make install PREFIX=/usr/local  # Install to /usr/local/bin
make uninstall       # Remove installed files
make check-scripts   # Verify syntax
```

## Configuration

Configure the following environment variables:

### Basic Authentication (Recommended for Jira Cloud)

Use this method with Personal Access Tokens (PAT) or API Tokens from Atlassian. **Both `JIRA_EMAIL` and `JIRA_API_TOKEN` are required**.

```bash
export JIRA_HOST="https://your-instance.atlassian.net"
export JIRA_EMAIL="your-email@example.com"
export JIRA_API_TOKEN="your-api-token"
```

**Important**: Atlassian Personal Access Tokens (starting with `ATATT`) must use Basic Authentication. Make sure to set both `JIRA_EMAIL` and `JIRA_API_TOKEN` variables.

#### How to Get Jira API Token

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Give it a descriptive name (e.g., "jira-cli")
4. Copy the generated token
5. Use it as `JIRA_API_TOKEN` (remember to also set `JIRA_EMAIL`)

### OAuth/Bearer Authentication

Use this method only for OAuth tokens (not for PAT):

```bash
export JIRA_HOST="https://your-instance.atlassian.net"
export JIRA_TOKEN="your-oauth-token"
```

### Additional Variables

```bash
export JIRA_PROJECT="PROJECT-KEY"  # Default project for creating issues
export JIRA_API_VERSION="3"        # 3 for Cloud (default), 2 for Server/DC
export JIRA_AUTH="basic"           # basic or bearer (auto-detects if not specified)
export JIRA_EPIC_FIELD="customfield_10014"  # Epic field (varies by instance)
```

### Configuration File

Create a `~/.jirarc` file with your configuration:

```bash
cat > ~/.jirarc << 'EOF'
# Jira Configuration
export JIRA_HOST="https://your-instance.atlassian.net"
export JIRA_EMAIL="your-email@example.com"
export JIRA_API_TOKEN="your-api-token"
export JIRA_PROJECT="PROJECT"  # Optional: default project
EOF

# Make the file private (contains credentials)
chmod 600 ~/.jirarc
```

Then, load this configuration in your shell:

```bash
# Add to ~/.bashrc or ~/.zshrc
[ -f ~/.jirarc ] && source ~/.jirarc
```

### Multiple Jira Instances

If you work with multiple Jira instances, you can create profiles:

```bash
# ~/.jirarc
jira_personal() {
    export JIRA_HOST="https://personal.atlassian.net"
    export JIRA_EMAIL="personal@example.com"
    export JIRA_API_TOKEN="personal-token"
}

jira_work() {
    export JIRA_HOST="https://org.atlassian.net"
    export JIRA_EMAIL="user@org.com"
    export JIRA_API_TOKEN="work-token"
}

# Use work profile by default
jira_work
```

Then you can switch profiles by running:
```bash
jira_personal  # Switch to personal
jira_work      # Switch to work
```

### Useful Aliases

Add these aliases to your `~/.bashrc` or `~/.zshrc`:

```bash
# Aliases for jira-cli
alias jl='jira-issues-pending-for-me'
alias ji='jira-issue'
alias jb='jira-issue-create-branch'
alias jd='jira-issue-transition-done'
alias js='jira-search'
alias jc='jira-create-issue'
```

## Dependencies

### Required Dependencies

These tools are **mandatory** for basic jira-cli functionality:

#### bash (v4.0+)
- **Description**: Unix shell
- **Used by**: All scripts
- **Installation**: Already included in macOS and Linux. macOS users: consider upgrading to bash 5+ with `brew install bash`

#### curl
- **Description**: Command-line HTTP client
- **Used by**: `jira` (main script for all API calls)
- **Installation**:
  ```bash
  # macOS
  brew install curl
  
  # Ubuntu/Debian
  sudo apt-get install curl
  
  # CentOS/RHEL
  sudo yum install curl
  ```

#### jq (v1.5+)
- **Description**: Command-line JSON processor
- **Used by**: All scripts to process JSON responses from the API
- **Installation**:
  ```bash
  # macOS
  brew install jq
  
  # Ubuntu/Debian
  sudo apt-get install jq
  
  # CentOS/RHEL
  sudo yum install jq
  ```
- **URL**: https://stedolan.github.io/jq/

#### git
- **Description**: Version control system
- **Used by**: `jira-issue-create-branch` (to create branches based on issues)
- **Installation**:
  ```bash
  # macOS
  brew install git
  
  # Ubuntu/Debian
  sudo apt-get install git
  
  # CentOS/RHEL
  sudo yum install git
  ```

### Optional Dependencies

These tools enhance functionality but are **not mandatory**:

#### yq (v4.0+)
- **Description**: Command-line YAML processor
- **Used by**: `jira` (for `--output yaml` format)
- **Installation**:
  ```bash
  # macOS
  brew install yq
  
  # Ubuntu/Debian
  sudo snap install yq
  
  # Using pip
  pip3 install yq
  ```
- **URL**: https://github.com/mikefarah/yq

#### column
- **Description**: Utility to format text into columns
- **Used by**: `jira` (for `--output table` format)
- **Installation**: Already included in macOS and most Linux distributions (part of `util-linux` package)

#### iconv
- **Description**: Character encoding converter
- **Used by**: `jira-issue-create-branch` (to transliterate special characters in branch names)
- **Installation**: Already included in macOS and most Linux distributions

#### base64
- **Description**: Base64 encoder/decoder
- **Used by**: `jira` (for Basic authentication with email+API token)
- **Installation**: Already included in macOS and most Linux distributions

### Installing Dependencies

#### macOS
```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install all dependencies
brew install bash curl jq git yq
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y bash curl jq git util-linux
sudo snap install yq
```

#### CentOS/RHEL
```bash
sudo yum install -y bash curl jq git util-linux-ng
# yq requires manual installation or via snap
```

### Dependency Verification

You can verify that all dependencies are installed by running:

```bash
cd /path/to/jira-cli.sh
make test-deps
```

This will check:
- ✓ Required dependencies (bash, curl, jq, git)
- ⚠ Optional dependencies (yq, column)
- ✓ Configured environment variables

### Compatibility Matrix

| Script | bash | curl | jq | git | yq | column | iconv | base64 |
|--------|------|------|----|----|----|----|-------|--------|
| jira | ✓ | ✓ | ✓ | - | ○ | ○ | - | ○ |
| jira-create-issue | ✓ | - | ✓ | - | - | - | - | - |
| jira-issue | ✓ | - | ✓ | - | - | - | - | - |
| jira-issue-create-branch | ✓ | - | ✓ | ✓ | - | - | ✓ | - |
| jira-issue-link | ✓ | - | ✓ | - | - | - | - | - |
| jira-issue-transition-done | ✓ | - | ✓ | - | - | - | - | - |
| jira-issue-transition-redo | ✓ | - | ✓ | - | - | - | - | - |
| jira-issues-pending-for-me | ✓ | - | ✓ | - | - | - | - | - |
| jira-search | ✓ | - | ✓ | - | - | - | - | - |

**Legend:**
- ✓ = Required
- ○ = Optional (extra functionality)
- \- = Not needed

## Available Commands

### jira

Main Jira API client. Supports traditional and simplified syntax.

```bash
# Simplified syntax
jira priority --output table
jira project PROJECT-123
jira project components PROJECT-123
jira project statuses PROJECT-123
jira workflow --output table
jira issue ABC-123
jira search 'project=ABC AND status=Open'
jira create --project ABC --summary "Title" --description "Desc" --type Task

# Traditional syntax
jira GET /priority
jira GET /project/PROJECT-123/statuses
jira GET /workflow
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

Create or update a Jira issue. Supports both command-line arguments and JSON files.

```bash
# Create with command-line arguments
jira-create-issue --project ABC --summary "Title" --description "Description" --type Task

# Update existing issue
jira-create-issue ABC-123 --summary "New title"

# Create from JSON file
jira-create-issue issue.json

# Create from JSON with overrides
jira-create-issue issue.json --type=Bug --priority=High
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
- `chore/` - Maintenance, tech debt, support
- `spike/` - Research, discovery, experiments
- `release/` - Release candidate activities

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

### md2jira

Convert Markdown to Jira formats (Wiki Markup or ADF JSON).

```bash
# Convert to Wiki Markup
md2jira file.md

# Convert to ADF JSON
md2jira --format=adf file.md

# From stdin
echo "# Title" | md2jira
```

## Usage with JSON Files

The `jira-create-issue` script supports reading properties from JSON files. This allows you to prepare issue information in a file and create tickets more conveniently.

### JSON File Format

The JSON file can contain the following properties:

```json
{
  "project": "PROJECT-KEY",
  "type": "Bug",
  "summary": "Issue title",
  "description": "Detailed description of the issue",
  "priority": "High",
  "assignee": "username",
  "reporter": "reporter.name",
  "epic": "EPIC-123",
  "link": "ISSUE-456"
}
```

### Supported Properties

- **project**: Project key in Jira
- **type**: Issue type (Bug, Task, Story, etc.)
- **summary**: Issue title or summary (required)
- **description**: Detailed issue description
- **priority**: Priority (High, Medium, Low, etc.)
- **assignee**: Assigned user
- **reporter**: Reporter user
- **epic**: Epic key to link to
- **link**: Another issue key to create a "Relates to" link

### Usage Examples

#### Create issue from JSON file
```bash
jira-create-issue issue.json
```
Reads all properties from `issue.json` and prompts for missing required fields.

#### Create issue with type override
```bash
jira-create-issue issue.json --type=Support
```
Reads properties from file but uses "Support" as the issue type, ignoring the JSON value.

#### Combine JSON file with other options
```bash
jira-create-issue issue.json --priority=Critical --assignee=other.user
```
Command-line parameters always take precedence over JSON values.

### Behavior

1. **Value Priority**: Command-line parameters always override JSON file values.

2. **Required Fields**: If required fields (project, type, summary) are missing, the script will prompt for them interactively.

3. **Optional Fields**: Optional fields (description, assignee, priority, etc.) are used if present in JSON, but won't be prompted if missing.

### Complete JSON Example

File: `example-issue.json`
```json
{
  "project": "MYPROJECT",
  "type": "Bug",
  "summary": "Login system error",
  "description": "When a user tries to log in, a 500 error appears on the server.\n\nSteps to reproduce:\n1. Go to login page\n2. Enter valid credentials\n3. Click 'Log In'\n\nExpected result: User should be able to access the system\nActual result: A 500 error is displayed",
  "priority": "High",
  "assignee": "john.doe"
}
```

### Jira API Format Compatibility

The script also supports the standard Jira API format:

```json
{
  "fields": {
    "project": { "key": "MYPROJECT" },
    "issuetype": { "name": "Bug" },
    "summary": "Issue title",
    "description": "Description",
    "priority": { "name": "High" },
    "assignee": { "name": "john.doe" }
  }
}
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
source ~/.bashrc
```

### Zsh

```bash
jira --shell zsh > ~/.jira-completion.zsh
echo 'source ~/.jira-completion.zsh' >> ~/.zshrc
source ~/.zshrc
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

### Working with Workflows

```bash
# List all workflows in your Jira instance
jira workflow --output table

# Get workflows/statuses by issue type for a specific project
jira project statuses PROJECT-KEY

# Example: See what statuses are available for each issue type in project ABC
jira project statuses ABC --output json

# This will show you what workflows are configured for each issue type
# (Bug, Task, Story, etc.) in the project, including all available statuses
# and transitions for each issue type
```

### Creating Issues with JSON

```bash
# Create a bug from JSON file
cat > bug.json << 'EOF'
{
  "project": "ABC",
  "type": "Bug",
  "summary": "Critical bug in production",
  "description": "System crashes on startup",
  "priority": "Critical"
}
EOF

jira-create-issue bug.json

# Override priority from command line
jira-create-issue bug.json --priority=Blocker
```

## Testing

This project uses the [shellunittest](https://github.com/caherrera/shellunittest) framework for testing.

### Running Tests

```bash
# Run all tests from project root
shellunittest test/

# Or use the wrapper script
./test/run_all_tests.sh

# Run specific test file
shellunittest test/test_helpers.sh

# Run with different output formats
shellunittest test/ --format=junit > test-results.xml
shellunittest test/ --format=json > test-results.json
```

### Test Structure

- `test_helpers.sh` - Tests for helper functions (logging, colors, formatting)
- `test_md2jira.sh` - Tests for Markdown to Jira converter
- `test_help.sh` - Tests for help flags across all commands (50+ tests)
- `test_project_components.sh` - Tests for project components

### Available Assertions

- `assert_equals "expected" "actual" "message"` - Verify equality
- `assert_contains "haystack" "needle" "message"` - Verify contains
- `assert_success "message"` - Verify exit code 0
- `assert_exit_code expected actual "message"` - Verify specific exit code
- `assert_file_exists "path" "message"` - Verify file exists
- `assert_file_contains "path" "text" "message"` - Verify file content
- `assert_file_not_contains "path" "text" "message"` - Verify text absence

### Adding New Tests

To create a new test file:

1. Create a file `test_*.sh` in the test directory
2. Use the following template:

```bash
#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Source the testing framework
source "/path/to/shellunittest/src/unittest.sh"

initialize_test_framework "$@"

print_test_header "My Test Suite"

print_section "Test Section"

# Your tests here
assert_equals "expected" "actual" "test description"

print_summary
```

3. Make the file executable: `chmod +x test_*.sh`

## Project Structure

This project follows the standard GNU structure:

```
jira-cli.sh/
├── bin/           # Symbolic links to executables (without .sh extension)
├── src/           # Source scripts with .sh extension
├── lib/           # Shared libraries
├── test/          # Test files
├── vendor/        # External dependencies
├── Makefile       # Build and installation scripts
└── README.md      # This file
```

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
- `md2jira.sh` - Markdown to Jira converter

### Libraries (lib/)

- `common.sh` - Common functions and configuration
- `helpers.sh` - Auxiliary functions (logging, colors, etc.)
- `jira.issues.sh` - Issue-related functions
- `jira.output.sh` - Output formatting functions
- `jira.search.sh` - Search-related functions
- `jira.user.sh` - User-related functions
- `markdown_to_adf.sh` - Markdown to ADF conversion
- `markdown.sh` - Markdown processing
- `completion.bash.sh` - Bash completion
- `completion.zsh.sh` - Zsh completion

### Internal Dependencies

These are project scripts that reference each other:

- **helpers.sh** (lib/) - Used by almost all scripts for logging with colors and text formatting
- **jira.sh** (src/) - Main API client used by all other scripts
- **jira-issue.sh** (src/) - Used by `jira-issue-create-branch.sh` and `jira-issue-transition-done.sh`
- **jira-issue-transition-done.sh** (src/) - Used by `jira-issue-transition-redo.sh`

## Troubleshooting

### Error: "command not found: jira"

**Cause**: The bin/ directory is not in your PATH.

**Solution**:
```bash
export PATH="/path/to/jira-cli.sh/bin:$PATH"
```

### Error: "jq: command not found"

**Cause**: jq is not installed.

**Solution**:
```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq
```

### Error: "You must specify the Jira URL"

**Cause**: The `JIRA_HOST` variable is not configured.

**Solution**:
```bash
export JIRA_HOST="https://your-instance.atlassian.net"
```

### Error: "Failed to parse Connect Session Auth Token" or "Issue does not exist or you do not have permission to see it"

**Cause**: Missing `JIRA_EMAIL` when using Personal Access Token (PAT), or incorrect authentication method.

**Solution**: PATs require **both** `JIRA_EMAIL` and `JIRA_API_TOKEN`:
```bash
export JIRA_EMAIL="your-email@example.com"
export JIRA_API_TOKEN="ATATT3xFf..."  # Your PAT token
export JIRA_HOST="https://your-instance.atlassian.net"
```

Do **not** use `JIRA_TOKEN` for PATs - that's only for OAuth Bearer tokens.

### Permission Error

**Cause**: Scripts don't have execution permissions.

**Solution**:
```bash
cd /path/to/jira-cli.sh
chmod +x src/*.sh
```

### Scripts Can't Find helpers.sh

**Cause**: Incorrect directory structure or broken symbolic links.

**Solution**:
```bash
cd /path/to/jira-cli.sh
# Verify structure
ls -la bin/ src/ lib/

# Recreate symbolic links if needed
cd bin
for f in ../src/*.sh; do
    name=$(basename "$f" .sh)
    ln -sf "../src/$name.sh" "$name"
done
```

### Dependency Issues

**Cause**: Missing required dependencies.

**Solution**:
```bash
# Verify all dependencies
make test-deps

# Install missing dependencies (macOS)
brew install bash curl jq git yq

# Install missing dependencies (Ubuntu/Debian)
sudo apt-get install bash curl jq git
sudo snap install yq
```

## Updating

```bash
cd /path/to/jira-cli.sh
git pull  # If in a git repository
make check-scripts  # Verify syntax
```

## Support

For issues or questions:
1. Verify all dependencies are installed
2. Check environment variables are configured correctly
3. Use `--help` on any command to see help
4. Run `make test-deps` to verify your setup

## License

Internal use.
