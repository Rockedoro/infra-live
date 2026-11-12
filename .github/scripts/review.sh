#!/bin/bash
set -e

# --- Конфигурация ---
MAX_DIFF_LINES=500
MODEL="qwen2.5-coder:1.5b"
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

# --- 2. Формируем промпт безопасно через jq ---
PROMPT=$(jq -n --arg diff "$DIFF" \
  '"Ты — старший DevOps-инженер. Проанализируй этот diff. Найди ошибки безопасности, проблемы с производительностью Docker/Python/Bash и нарушения best practices. Ответь кратко, по пунктам.\n\nDiff:\n```diff\n\($diff)\n```"')

# Убираем внешние кавычки, которые добавляет jq
PROMPT=$(echo "$PROMPT" | sed 's/^"//;s/"$//')

# --- 3. Отправляем в Ollama ---
REQUEST_JSON=$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" \
  '{model: $model, prompt: $prompt, stream: false}')

RESPONSE=$(curl -s -X POST ${OLLAMA_HOST}/api/generate \
  -H "Content-Type: application/json" \
  -d "$REQUEST_JSON" | jq -r '.response')

# --- 4. Публикуем комментарий в PR (безопасно через jq) ---
if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "null" ]; then
  RESPONSE="⚠️ Модель не вернула ответ. Проверьте логи Ollama."
fi

COMMENT_JSON=$(jq -n --arg body "🤖 **AI Review**:\n\n$RESPONSE" '{body: $body}')

curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO_FULL_NAME/issues/$PR_NUMBER/comments" \
  -d "$COMMENT_JSON"

echo "✅ Review posted to PR #$PR_NUMBER"