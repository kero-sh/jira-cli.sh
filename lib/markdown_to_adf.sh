#!/bin/bash

# Convert Markdown to Atlassian Document Format (ADF)
# This is a simplified converter that handles the most common cases

markdown_to_adf() {
  local markdown_text="$1"
  
  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required for ADF conversion" >&2
    return 1
  fi
  
  local content='[]'
  local line_buffer=""
  local in_code_block=false
  local code_lang=""
  local code_lines=()
  local list_items=()
  local list_type=""
  
  while IFS= read -r line || [ -n "$line" ]; do
    
    # Handle code blocks
    if [[ "$line" =~ ^\`\`\`([a-z0-9]*) ]]; then
      # Flush any pending content
      if [ -n "$line_buffer" ]; then
        content=$(add_paragraph "$content" "$line_buffer")
        line_buffer=""
      fi
      
      if [ "$in_code_block" = false ]; then
        # Start code block
        in_code_block=true
        code_lang="${BASH_REMATCH[1]}"
        code_lines=()
      else
        # End code block
        in_code_block=false
        local code_text=$(IFS=$'\n'; echo "${code_lines[*]}")
        content=$(add_code_block "$content" "$code_text" "$code_lang")
        code_lang=""
      fi
      continue
    fi
    
    # Collect code block lines
    if [ "$in_code_block" = true ]; then
      code_lines+=("$line")
      continue
    fi
    
    # Handle headings
    if [[ "$line" =~ ^(#{1,6})[[:space:]]+(.+)$ ]]; then
      # Flush line buffer
      if [ -n "$line_buffer" ]; then
        content=$(add_paragraph "$content" "$line_buffer")
        line_buffer=""
      fi
      
      local level=${#BASH_REMATCH[1]}
      local heading_text="${BASH_REMATCH[2]}"
      content=$(add_heading "$content" "$level" "$heading_text")
      continue
    fi
    
    # Handle task list items (checkboxes)
    if [[ "$line" =~ ^[[:space:]]*[\*\-][[:space:]]\[([xX[:space:]])\][[:space:]]+(.+)$ ]]; then
      # Flush line buffer
      if [ -n "$line_buffer" ]; then
        content=$(add_paragraph "$content" "$line_buffer")
        line_buffer=""
      fi
      
      local checked="${BASH_REMATCH[1]}"
      local task_text="${BASH_REMATCH[2]}"
      local state="TODO"
      [[ "$checked" =~ [xX] ]] && state="DONE"
      
      content=$(add_task_item "$content" "$state" "$task_text")
      continue
    fi
    
    # Handle bullet lists
    if [[ "$line" =~ ^[[:space:]]*[\*\-][[:space:]]+(.+)$ ]]; then
      # Flush line buffer
      if [ -n "$line_buffer" ]; then
        content=$(add_paragraph "$content" "$line_buffer")
        line_buffer=""
      fi
      
      local item_text="${BASH_REMATCH[1]}"
      content=$(add_bullet_item "$content" "$item_text")
      continue
    fi
    
    # Handle numbered lists  
    if [[ "$line" =~ ^[[:space:]]*[0-9]+\.[[:space:]]+(.+)$ ]]; then
      # Flush line buffer
      if [ -n "$line_buffer" ]; then
        content=$(add_paragraph "$content" "$line_buffer")
        line_buffer=""
      fi
      
      local item_text="${BASH_REMATCH[1]}"
      content=$(add_numbered_item "$content" "$item_text")
      continue
    fi
    
    # Empty line - paragraph separator
    if [ -z "$line" ]; then
      if [ -n "$line_buffer" ]; then
        content=$(add_paragraph "$content" "$line_buffer")
        line_buffer=""
      fi
      continue
    fi
    
    # Regular text - accumulate in buffer
    if [ -n "$line_buffer" ]; then
      line_buffer+=" "
    fi
    line_buffer+="$line"
    
  done <<< "$markdown_text"
  
  # Flush remaining buffer
  if [ -n "$line_buffer" ]; then
    content=$(add_paragraph "$content" "$line_buffer")
  fi
  
  # Build final ADF document
  jq -n --argjson content "$content" '{
    "version": 1,
    "type": "doc",
    "content": $content
  }'
}

# Helper functions for building ADF nodes

add_paragraph() {
  local content="$1"
  local text="$2"
  
  # Process inline formatting
  local inline_content=$(process_inline_formatting "$text")
  
  echo "$content" | jq --argjson inline "$inline_content" \
    '. += [{"type": "paragraph", "content": $inline}]'
}

add_heading() {
  local content="$1"
  local level="$2"
  local text="$3"
  
  local inline_content=$(process_inline_formatting "$text")
  
  echo "$content" | jq --arg level "$level" --argjson inline "$inline_content" \
    '. += [{"type": "heading", "attrs": {"level": ($level | tonumber)}, "content": $inline}]'
}

add_code_block() {
  local content="$1"
  local code="$2"
  local lang="$3"
  
  if [ -n "$lang" ]; then
    echo "$content" | jq --arg code "$code" --arg lang "$lang" \
      '. += [{"type": "codeBlock", "attrs": {"language": $lang}, "content": [{"type": "text", "text": $code}]}]'
  else
    echo "$content" | jq --arg code "$code" \
      '. += [{"type": "codeBlock", "content": [{"type": "text", "text": $code}]}]'
  fi
}

add_task_item() {
  local content="$1"
  local state="$2"
  local text="$3"
  
  local inline_content=$(process_inline_formatting "$text")
  
  echo "$content" | jq --arg state "$state" --argjson inline "$inline_content" \
    '. += [{"type": "taskList", "content": [{"type": "taskItem", "attrs": {"state": $state}, "content": [{"type": "paragraph", "content": $inline}]}]}]'
}

add_bullet_item() {
  local content="$1"
  local text="$2"
  
  local inline_content=$(process_inline_formatting "$text")
  
  echo "$content" | jq --argjson inline "$inline_content" \
    '. += [{"type": "bulletList", "content": [{"type": "listItem", "content": [{"type": "paragraph", "content": $inline}]}]}]'
}

add_numbered_item() {
  local content="$1"
  local text="$2"
  
  local inline_content=$(process_inline_formatting "$text")
  
  echo "$content" | jq --argjson inline "$inline_content" \
    '. += [{"type": "orderedList", "content": [{"type": "listItem", "content": [{"type": "paragraph", "content": $inline}]}]}]'
}

# Process inline formatting: **bold**, `code`, [link](url)
process_inline_formatting() {
  local text="$1"
  local result='[]'
  
  # For simplicity, create a single text node
  # TODO: Parse and handle **bold**, *italic*, `code`, [links](url), etc.
  
  # Handle bold **text**
  while [[ "$text" =~ (.*)\*\*([^*]+)\*\*(.*) ]]; do
    text="${BASH_REMATCH[1]}*${BASH_REMATCH[2]}*${BASH_REMATCH[3]}"
  done
  
  # Handle inline code `code` -> {{code}}
  while [[ "$text" =~ (.*)\`([^\`]+)\`(.*) ]]; do
    text="${BASH_REMATCH[1]}{{${BASH_REMATCH[2]}}}${BASH_REMATCH[3]}"
  done
  
  # For now, return simple text node
  result=$(jq -n --arg text "$text" '[{"type": "text", "text": $text}]')
  
  echo "$result"
}
