#!/bin/bash
set -e

# --- Конфигурация ---
MAX_DIFF_LINES=500
MODEL="qwen2.5-coder:7b"
PR_NUMBER=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")
REPO_FULL_NAME=$(jq -r '.repository.full_name' "$GITHUB_EVENT_PATH")

# --- 1. Получаем diff ---
DIFF=$(git diff origin/main...HEAD)
DIFF_LINES=$(echo "$DIFF" | wc -l)

if [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
  echo "❌ Error: Diff is too large ($DIFF_LINES lines). Max allowed: $MAX_DIFF_LINES."
  exit 1
fi

if [ -z "$DIFF" ]; then
  echo "✅ No changes to review."
  exit 0
fi

# --- 2. Формируем промпт ---
PROMPT="Ты — старший DevOps-инженер. Проанализируй этот diff. Найди ошибки безопасности, проблемы с производительностью Docker/Python/Bash и нарушения best practices. Ответь кратко, по пунктам.

Diff:
\`\`\`diff
$DIFF
\`\`\`"

# --- 3. Отправляем в Ollama ---
RESPONSE=$(curl -s -X POST ${OLLAMA_HOST}/api/generate \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"prompt\": \"$PROMPT\",
    \"stream\": false
  }" | jq -r '.response')

# --- 4. Публикуем комментарий в PR ---
COMMENT_BODY="{\"body\": \"🤖 **AI Review**:\\n\\n$RESPONSE\"}"

curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$REPO_FULL_NAME/issues/$PR_NUMBER/comments \
  -d "$COMMENT_BODY"

echo "✅ Review posted to PR #$PR_NUMBER"