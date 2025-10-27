# JIRA CLI Dependencies

## Required Dependencies

These tools are **mandatory** for basic jira-cli functionality:

### 1. bash (v4.0+)
- **Description**: Unix shell
- **Used by**: All scripts
- **Installation**: 
  - Already included in macOS and Linux
  - macOS users: consider upgrading to bash 5+ with `brew install bash`

### 2. curl
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

### 3. jq (v1.5+)
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

### 4. git
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

## Optional Dependencies

These tools enhance functionality but are **not mandatory**:

### 5. yq (v4.0+)
- **Description**: Command-line YAML processor
- **Used by**: `jira` (for `--output yaml` format)
- **Function**: Allows converting JSON responses to YAML
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
- **Note**: If not available, simply don't use `--output yaml`

### 6. column
- **Description**: Utility to format text into columns
- **Used by**: `jira` (for `--output table` format)
- **Function**: Formats tables with aligned columns
- **Installation**:
  - Already included in macOS and most Linux distributions
  - Part of the `util-linux` package on Linux

### 7. iconv
- **Description**: Character encoding converter
- **Used by**: `jira-issue-create-branch` (to transliterate special characters in branch names)
- **Function**: Converts accents and special characters to ASCII
- **Installation**:
  - Already included in macOS and most Linux distributions

### 8. base64
- **Description**: Base64 encoder/decoder
- **Used by**: `jira` (for Basic authentication with email+API token)
- **Function**: Encodes credentials for the Authorization header
- **Installation**:
  - Already included in macOS and most Linux distributions

## System Dependencies

### Environment Variables

For the scripts to work correctly, you need to configure:

#### Jira Cloud Authentication (API Token)
```bash
export JIRA_HOST="https://your-instance.atlassian.net"
export JIRA_EMAIL="your-email@example.com"
export JIRA_API_TOKEN="your-atlassian-api-token"
```

#### OAuth/Bearer Authentication
```bash
export JIRA_HOST="https://your-instance.atlassian.net"
export JIRA_TOKEN="your-oauth-token"
```

#### Optional Variables
```bash
export JIRA_PROJECT="KEY"                    # Default project
export JIRA_API_VERSION="3"                  # 3=Cloud (default), 2=Server/DC
export JIRA_AUTH="basic"                     # basic or bearer (auto-detects if not specified)
export JIRA_EPIC_FIELD="customfield_10014"   # Epic field (varies by instance)
```

## Internal Dependencies

These are project scripts that reference each other:

### helpers.sh (lib/)
- **Description**: Auxiliary functions library
- **Functions**:
  - `info()`, `error()`, `warn()`, `success()` - Logging with colors
  - `echoc()` - Echo with colors
  - Text formatting functions
- **Used by**: Almost all scripts

### jira.sh (src/)
- **Description**: Main Jira API client
- **Used by**: 
  - `jira-create-issue.sh`
  - `jira-issue.sh`
  - `jira-issue-link.sh`
  - `jira-issue-transition-done.sh`
  - `jira-issue-transition-redo.sh`
  - `jira-issues-pending-for-me.sh`
  - `jira-search.sh`

### jira-issue.sh (src/)
- **Description**: Wrapper to get issue information
- **Used by**:
  - `jira-issue-create-branch.sh`
  - `jira-issue-transition-done.sh`

### jira-issue-transition-done.sh (src/)
- **Description**: Issue transition to Done
- **Used by**:
  - `jira-issue-transition-redo.sh`

## Dependency Verification

You can verify that all dependencies are installed by running:

```bash
cd /Users/carlosherrera/src/scripts/jira-cli
make test-deps
```

This will check:
- ✓ Required dependencies (bash, curl, jq, git)
- ⚠ Optional dependencies (yq, column)
- ✓ Configured environment variables

## Compatibility Matrix

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

## Quick Install All Dependencies

### macOS
```bash
brew install bash curl jq git yq
```

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y bash curl jq git util-linux
sudo snap install yq
```

### CentOS/RHEL
```bash
sudo yum install -y bash curl jq git util-linux-ng
# yq requires manual installation or via snap
```

## Additional Notes

1. **jq is critical**: Almost all scripts depend on jq to process JSON. Without it, most scripts will fail.

2. **curl in main jira**: Only the `jira.sh` script makes direct HTTP calls. Other scripts invoke it.

3. **Optional dependencies**: Scripts degrade gracefully. For example, if `yq` is not available, the YAML format simply won't be available.

4. **realpath**: Used in all scripts to get the directory path. Included in GNU coreutils (Linux) and macOS 10.15+.

5. **sed**: Used for basic text manipulation. Included in all Unix systems.
