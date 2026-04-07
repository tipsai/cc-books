#!/bin/bash
# generate.sh - Извлечение журнала сессий Claude Code за день и генерация FlipBook HTML
#
# Использование: ./generate.sh [YYYY-MM-DD]
# Если дата не указана, используется сегодняшняя.
#
# Вывод: /tmp/claude/daily-flipbook/YYYY-MM-DD.html

set -euo pipefail

DATE="${1:-$(date +%Y-%m-%d)}"
YEAR=$(echo "$DATE" | cut -d'-' -f1)
MONTH=$(echo "$DATE" | cut -d'-' -f2)
DAY=$(echo "$DATE" | cut -d'-' -f3)
DISPLAY_DATE="${DAY}.${MONTH}.${YEAR}"

OUTPUT_DIR="/tmp/claude/daily-flipbook"
OUTPUT_FILE="$OUTPUT_DIR/$DATE.html"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/template.html"

mkdir -p "$OUTPUT_DIR"

# ── Сбор журнала сессий из обоих путей ──
SEARCH_PATHS=(
  "$HOME/.claude/projects"
  "$HOME/claude-data/projects"
)

touch -t "${YEAR}${MONTH}${DAY}0000" /tmp/flipbook_date_marker 2>/dev/null || true

SESSIONS_JSON="[]"
SESSION_COUNT=0

for search_path in "${SEARCH_PATHS[@]}"; do
  if [ ! -d "$search_path" ]; then
    continue
  fi

  # Поиск JSONL-файлов, обновлённых сегодня (без логов субагентов)
  while IFS= read -r logfile; do
    [ -z "$logfile" ] && continue

    # Извлечение имени проекта из пути
    project_dir=$(basename "$(dirname "$logfile")")

    # Разбор сообщений пользователя и использования инструментов ассистента
    if command -v jq &>/dev/null; then
      # Извлечение сводки: сообщения пользователя (первые 200 символов каждого)
      user_msgs=$(jq -r '
        select(.type == "user")
        | .message
        | if type == "array" then
            map(select(.type == "text") | .text) | join(" ")
          elif type == "string" then .
          else empty
          end
        | .[0:200]
      ' "$logfile" 2>/dev/null | head -20)

      # Извлечение использованных инструментов (запись файлов, редактирование, команды)
      tool_actions=$(jq -r '
        select(.type == "assistant")
        | .message[]?
        | select(.type == "tool_use")
        | "\(.name): \(.input.file_path // .input.command // .input.pattern // "" | .[0:100])"
      ' "$logfile" 2>/dev/null | head -30)

      if [ -n "$user_msgs" ]; then
        SESSION_COUNT=$((SESSION_COUNT + 1))
        echo "--- Сессия $SESSION_COUNT: $project_dir ---" >> /tmp/flipbook_sessions_$DATE.txt
        echo "$user_msgs" >> /tmp/flipbook_sessions_$DATE.txt
        echo "" >> /tmp/flipbook_sessions_$DATE.txt
        if [ -n "$tool_actions" ]; then
          echo "Использованные инструменты:" >> /tmp/flipbook_sessions_$DATE.txt
          echo "$tool_actions" >> /tmp/flipbook_sessions_$DATE.txt
          echo "" >> /tmp/flipbook_sessions_$DATE.txt
        fi
      fi
    fi
  done < <(find "$search_path" -name "*.jsonl" -newer /tmp/flipbook_date_marker -not -path "*/subagents/*" 2>/dev/null)
done

# ── Вывод результатов ──
SESSIONS_FILE="/tmp/flipbook_sessions_$DATE.txt"

if [ ! -f "$SESSIONS_FILE" ] || [ ! -s "$SESSIONS_FILE" ]; then
  echo "Журнал сессий за $DATE не найден"
  echo "Проверенные пути:"
  for p in "${SEARCH_PATHS[@]}"; do
    echo "  - $p"
  done
  exit 1
fi

echo "Найдено сессий за $DATE: $SESSION_COUNT"
echo "Данные сессий сохранены в: $SESSIONS_FILE"
echo ""
echo "Для генерации FlipBook выполните в Claude Code:"
echo ""
echo "  /daily-flipbook"
echo ""
echo "Или попросите Claude Code:"
echo "  \"Прочитай $SESSIONS_FILE и сгенерируй FlipBook на основе template.html\""
echo ""
echo "Шаблон: $TEMPLATE"
echo "Файл будет сохранён в: $OUTPUT_FILE"
