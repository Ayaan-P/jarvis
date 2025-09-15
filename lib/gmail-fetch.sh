#!/bin/bash
# Gmail API wrapper script for ccOS agents
# Usage: ./gmail-fetch.sh <command> [options]

set -e

COMMAND="$1"
shift  # Remove first argument, pass rest to Python script

if [[ -z "$COMMAND" ]]; then
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  setup-check              - Verify Gmail API setup"
    echo "  unread [--limit N]       - Get unread emails"  
    echo "  customer-support         - Find customer support emails"
    echo "  investor-emails          - Find investor-related emails"
    echo "  send --to EMAIL --subject SUBJECT --body BODY"
    echo "  mark-read --message-id ID"
    echo "  filter --filter QUERY --days N"
    echo "  profile                  - Get account info"
    echo ""
    echo "Examples:"
    echo "  $0 setup-check"
    echo "  $0 unread --limit 5"
    echo "  $0 customer-support --days 3"
    echo "  $0 send --to 'user@example.com' --subject 'Hello' --body 'Test message'"
    exit 1
fi

# Find the Python script
SCRIPT_PATHS=(
    "$(dirname "$0")/gmail-fetch.py"
    "./lib/gmail-fetch.py"
    "../Claude-Agentic-Files/lib/gmail-fetch.py"
    "/home/ayaan/Projects/Claude-Agentic-Fileslib/gmail-fetch.py"
)

PYTHON_SCRIPT=""
for script_path in "${SCRIPT_PATHS[@]}"; do
    if [[ -f "$script_path" ]]; then
        PYTHON_SCRIPT="$script_path"
        break
    fi
done

if [[ -z "$PYTHON_SCRIPT" ]]; then
    echo "Error: Gmail Python script not found"
    exit 1
fi

# Execute the Python script with all arguments
python3 "$PYTHON_SCRIPT" "$COMMAND" "$@"