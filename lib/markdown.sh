#!/bin/bash

# Convert Markdown format to Jira ADF (Atlassian Document Format)
markdown_to_adf() {
  local text="$1"
  local content_nodes='[]'
  local in_code_block=false
  local code_lang=""
  local code_content=""
  
  while IFS= read -r line; do
    # Skip empty lines (will be handled as paragraph separators)
    if [ -z "$line" ] && [ "$in_code_block" = false ]; then
      continue
    fi
    
    # Handle code blocks
    if [[ "$line" =~ ^\`\`\`([a-z]*) ]]; then
      if [ "$in_code_block" = false ]; then
        in_code_block=true
        code_lang="${BASH_REMATCH[1]}"
        code_content=""
        continue
      else
        in_code_block=false
        # Add code block node
        local lang_attr=""
        if [ -n "$code_lang" ]; then
          lang_attr=", \"attrs\": {\"language\": \"$code_lang\"}"
        fi
        content_nodes=$(echo "$content_nodes" | jq --arg content "$code_content" --argjson lang_attr "${lang_attr:-null}" \
          '. += [{"type": "codeBlock", "content": [{"type": "text", "text": $content}]} + (if $lang_attr then {"attrs": {"language": $lang_attr}} else {} end)]')
        continue
      fi
    fi
    
    # Collect code block content
    if [ "$in_code_block" = true ]; then
      if [ -n "$code_content" ]; then
        code_content+=$'\n'
      fi
      code_content+="$line"
      continue
    fi
    
    # Handle headings
    local heading_level=0
    if [[ "$line" =~ ^(#{1,6})[[:space:]]+(.+)$ ]]; then
      heading_level=${#BASH_REMATCH[1]}
      local heading_text="${BASH_REMATCH[2]}"
      content_nodes=$(echo "$content_nodes" | jq --arg level "$heading_level" --arg text "$heading_text" \
        '. += [{"type": "heading", "attrs": {"level": ($level | tonumber)}, "content": [{"type": "text", "text": $text}]}]')
      continue
    fi
    
    # Handle checkbox lists
    if [[ "$line" =~ ^[[:space:]]*[\*\-][[:space:]]\[([xX[:space:]])\][[:space:]]+(.+)$ ]]; then
      local checked="${BASH_REMATCH[1]}"
      local list_text="${BASH_REMATCH[2]}"
      local state="TODO"
      if [[ "$checked" =~ [xX] ]]; then
        state="DONE"
      fi
      
      # Parse inline formatting in list text
      local formatted_content=$(parse_inline_formatting "$list_text")
      
      content_nodes=$(echo "$content_nodes" | jq --arg state "$state" --argjson content "$formatted_content" \
        '. += [{"type": "taskList", "content": [{"type": "taskItem", "attrs": {"state": $state}, "content": [{"type": "text", "text": ($content[0].text // "")}]}]}]')
      continue
    fi
    
    # Handle unordered lists
    if [[ "$line" =~ ^[[:space:]]*[\*\-][[:space:]]+(.+)$ ]]; then
      local list_text="${BASH_REMATCH[1]}"
      local formatted_content=$(parse_inline_formatting "$list_text")
      content_nodes=$(echo "$content_nodes" | jq --argjson content "$formatted_content" \
        '. += [{"type": "bulletList", "content": [{"type": "listItem", "content": [{"type": "paragraph", "content": $content}]}]}]')
      continue
    fi
    
    # Handle ordered lists
    if [[ "$line" =~ ^[[:space:]]*[0-9]+\.[[:space:]]+(.+)$ ]]; then
      local list_text="${BASH_REMATCH[1]}"
      local formatted_content=$(parse_inline_formatting "$list_text")
      content_nodes=$(echo "$content_nodes" | jq --argjson content "$formatted_content" \
        '. += [{"type": "orderedList", "content": [{"type": "listItem", "content": [{"type": "paragraph", "content": $content}]}]}]')
      continue
    fi
    
    # Regular paragraph with inline formatting
    local formatted_content=$(parse_inline_formatting "$line")
    content_nodes=$(echo "$content_nodes" | jq --argjson content "$formatted_content" \
      '. += [{"type": "paragraph", "content": $content}]')
    
  done <<< "$text"
  
  # Build final ADF document
  local adf_doc=$(jq -n --argjson content "$content_nodes" \
    '{
      "version": 1,
      "type": "doc",
      "content": $content
    }')
  
  echo "$adf_doc"
}

# Parse inline formatting (bold, italic, code, links)
parse_inline_formatting() {
  local text="$1"
  local result='[]'
  
  # Simple text node for now - can be enhanced to handle bold, italic, code, links
  # For bold: **text** or __text__
  # For code: `code`
  # For links: [text](url)
  
  # TODO: Implement proper inline formatting parsing
  # For now, just return plain text
  result=$(jq -n --arg text "$text" '[{"type": "text", "text": $text}]')
  
  echo "$result"
}

# Convert Markdown format to Jira Wiki format (legacy)
markdown_to_jira() {
  local text="$1"
  local result=""
  local in_code_block=false
  
  while IFS= read -r line; do
    # Handle code blocks
    if [[ "$line" =~ ^\`\`\`([a-z]*) ]]; then
      if [ "$in_code_block" = false ]; then
        in_code_block=true
        lang="${BASH_REMATCH[1]}"
        if [ -n "$lang" ]; then
          result+=$'{code:'"$lang"$'}\n'
        else
          result+=$'{code}\n'
        fi
        continue
      else
        in_code_block=false
        result+=$'{code}\n'
        continue
      fi
    fi
    
    # Don't process lines inside code blocks
    if [ "$in_code_block" = true ]; then
      result+="$line"$'\n'
      continue
    fi
    
    # Convert headings
    if [[ "$line" =~ ^######[[:space:]]+(.+) ]]; then
      line="h6. ${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^#####[[:space:]]+(.+) ]]; then
      line="h5. ${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^####[[:space:]]+(.+) ]]; then
      line="h4. ${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^###[[:space:]]+(.+) ]]; then
      line="h3. ${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^##[[:space:]]+(.+) ]]; then
      line="h2. ${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^#[[:space:]]+(.+) ]]; then
      line="h1. ${BASH_REMATCH[1]}"
    fi
    
    # Convert checkbox lists (before regular lists)
    if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]\[([xX])\][[:space:]]+(.+) ]]; then
      # Checked checkbox
      line="* (/) ${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]\[[[:space:]]\][[:space:]]+(.+) ]]; then
      # Unchecked checkbox
      line="* (x) ${BASH_REMATCH[1]}"
    # Convert unordered lists
    elif [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+(.+) ]]; then
      line="* ${BASH_REMATCH[1]}"
    fi
    
    # Convert ordered lists
    if [[ "$line" =~ ^[[:space:]]*[0-9]+\.[[:space:]]+(.+) ]]; then
      line="# ${BASH_REMATCH[1]}"
    fi
    
    # Convert blockquotes
    if [[ "$line" =~ ^\>[[:space:]]*(.+) ]]; then
      line="bq. ${BASH_REMATCH[1]}"
    fi
    
    # Convert horizontal rules
    if [[ "$line" =~ ^(\*\*\*|---|___)$ ]]; then
      line="----"
    fi
    
    # Convert bold (**text** or __text__ to *text*)
    while [[ "$line" =~ (.*)\*\*([^*]+)\*\*(.*) ]]; do
      line="${BASH_REMATCH[1]}*${BASH_REMATCH[2]}*${BASH_REMATCH[3]}"
    done
    while [[ "$line" =~ (.*)__([^_]+)__(.*) ]]; do
      line="${BASH_REMATCH[1]}*${BASH_REMATCH[2]}*${BASH_REMATCH[3]}"
    done
    
    # Convert inline code (`code` to {{code}})
    while [[ "$line" =~ (.*)\`([^\`]+)\`(.*) ]]; do
      line="${BASH_REMATCH[1]}{{${BASH_REMATCH[2]}}}${BASH_REMATCH[3]}"
    done
    
    # Convert links ([text](url) to [text|url])
    while [[ "$line" =~ (.*)\[([^\]]+)\]\(([^\)]+)\)(.*) ]]; do
      line="${BASH_REMATCH[1]}[${BASH_REMATCH[2]}|${BASH_REMATCH[3]}]${BASH_REMATCH[4]}"
    done
    
    # Convert images (![alt](url) to !url!)
    while [[ "$line" =~ (.*)\!\[([^\]]*)\]\(([^\)]+)\)(.*) ]]; do
      line="${BASH_REMATCH[1]}!${BASH_REMATCH[3]}!${BASH_REMATCH[4]}"
    done
    
    result+="$line"$'\n'
  done <<< "$text"
  
  # Remove trailing newline
  result="${result%$'\n'}"
  
  echo "$result"
}
