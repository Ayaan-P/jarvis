#!/bin/bash
# Claude Business OS - One-click installer

echo "✨ Claude Business OS Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Claude Code installation
if ! command -v claude &> /dev/null; then
    echo "❌ Claude Code not found. Please install first:"
    echo "   curl -sSL https://get.claude.ai | bash"
    exit 1
fi

echo "🔍 Found Claude Code ✓"

# Install business agents
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"
mkdir -p "$CLAUDE_AGENTS_DIR"

echo "🤖 Installing business agents..."

# Copy agents
cp agents/*.md "$CLAUDE_AGENTS_DIR/"

# Install automation scripts
CLAUDE_LIB_DIR="$HOME/Projects/Claude-Agentic-Files/lib"
mkdir -p "$CLAUDE_LIB_DIR"
cp -r lib/* "$CLAUDE_LIB_DIR/"

# Set up environment
if [ ! -f "$HOME/Projects/Claude-Agentic-Files/.env" ]; then
    cp .env.template "$HOME/Projects/Claude-Agentic-Files/.env"
    echo "📝 Environment template created at $HOME/Projects/Claude-Agentic-Files/.env"
    echo "   Edit this file with your API keys"
fi

echo "🎉 Installation complete!"
echo ""
echo "Your business agents are ready in Claude Code"