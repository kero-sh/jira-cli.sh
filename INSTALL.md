# Installation Guide - JIRA CLI

## Quick Installation

### Option 1: Add to PATH (Recommended for development)

```bash
# In your ~/.bashrc or ~/.zshrc
export PATH="/Users/carlosherrera/src/scripts/jira-cli/bin:$PATH"

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

### Option 2: Installation with Make (Recommended for permanent use)

```bash
cd /Users/carlosherrera/src/scripts/jira-cli

# Install to ~/.local/bin (standard user location)
make install

# Or install to custom location
make install PREFIX=/usr/local

# Ensure ~/.local/bin is in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

### Option 3: Manual Symbolic Links

```bash
# Create links in a directory already in your PATH
cd /Users/carlosherrera/src/scripts/jira-cli/bin
for script in *; do
    sudo ln -sf "$(pwd)/$script" /usr/local/bin/"$script"
done
```

## Initial Configuration

### 1. Install Dependencies

#### macOS
```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install jq yq git curl
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y jq git curl
sudo snap install yq
```

### 2. Configure Environment Variables

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

**Important**: For Jira Cloud with Personal Access Tokens (PAT), **both `JIRA_EMAIL` and `JIRA_API_TOKEN` are required**. PATs (tokens starting with `ATATT`) use Basic Authentication and need your email to work correctly.

Then, load this configuration in your shell:

```bash
# Add to ~/.bashrc or ~/.zshrc
[ -f ~/.jirarc ] && source ~/.jirarc
```

### 3. Get Jira API Token

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Give it a descriptive name (e.g., "jira-cli")
4. Copy the generated token
5. Use it as `JIRA_API_TOKEN` (remember to also set `JIRA_EMAIL`)

### 4. Verify Installation

```bash
# Verify dependencies
cd /Users/carlosherrera/src/scripts/jira-cli
make test

# Test a simple command
jira priority --output table
```

## Advanced Configuration

### Autocompletion

#### Bash
```bash
jira --shell bash > ~/.jira-completion.bash
echo '[ -f ~/.jira-completion.bash ] && source ~/.jira-completion.bash' >> ~/.bashrc
source ~/.bashrc
```

#### Zsh
```bash
jira --shell zsh > ~/.jira-completion.zsh
echo '[ -f ~/.jira-completion.zsh ] && source ~/.jira-completion.zsh' >> ~/.zshrc
source ~/.zshrc
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

## Troubleshooting

### Error: "command not found: jira"

**Cause**: The bin/ directory is not in your PATH.

**Solution**:
```bash
export PATH="/Users/carlosherrera/src/scripts/jira-cli/bin:$PATH"
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
cd /Users/carlosherrera/src/scripts/jira-cli
chmod +x src/*.sh
```

### Scripts Can't Find helpers.sh

**Cause**: Incorrect directory structure or broken symbolic links.

**Solution**:
```bash
cd /Users/carlosherrera/src/scripts/jira-cli
# Verify structure
ls -la bin/ src/ lib/

# Recreate symbolic links if needed
cd bin
for f in ../src/*.sh; do
    name=$(basename "$f" .sh)
    ln -sf "../src/$name.sh" "$name"
done
```

## Uninstallation

### If you installed with make
```bash
cd /Users/carlosherrera/src/scripts/jira-cli
make uninstall
```

### If you added to PATH
Remove the PATH line from your `~/.bashrc` or `~/.zshrc`:
```bash
# Remove this line:
# export PATH="/Users/carlosherrera/src/scripts/jira-cli/bin:$PATH"
```

### Remove Configuration Files
```bash
rm -f ~/.jirarc
rm -f ~/.jira-completion.bash
rm -f ~/.jira-completion.zsh
```

## Updating

```bash
cd /Users/carlosherrera/src/scripts/jira-cli
git pull  # If in a git repository
make check-scripts  # Verify syntax
```

## Next Step

Read [README.md](README.md) for complete usage documentation.
