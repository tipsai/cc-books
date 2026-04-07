#!/bin/bash
# daily-cron.sh - Ежедневная автоматическая генерация FlipBook за день
#
# Использование:
#   ./daily-cron.sh              # Генерация за сегодня
#   ./daily-cron.sh 2026-04-05   # Генерация за указанную дату
#
# Setup (launchd):
#   cp skill/com.cc-books.daily.plist ~/Library/LaunchAgents/
#   launchctl load ~/Library/LaunchAgents/com.cc-books.daily.plist
#
# Setup (cron):
#   crontab -e
#   55 23 * * * /path/to/cc-books/skill/daily-cron.sh

set -euo pipefail

DATE="${1:-$(date +%Y-%m-%d)}"
OUTPUT_DIR="/tmp/claude/daily-flipbook"
OUTPUT_FILE="$OUTPUT_DIR/$DATE.html"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Пропустить, если уже сгенерировано сегодня
if [ -f "$OUTPUT_FILE" ]; then
  echo "Уже сгенерировано: $OUTPUT_FILE"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

# Поиск сессий за сегодня
SEARCH_PATHS=(
  "$HOME/.claude/projects"
  "$HOME/claude-data/projects"
)

touch -t "$(echo "$DATE" | tr -d '-')0000" /tmp/ccbooks_date_marker 2>/dev/null || true

SESSION_COUNT=0
SESSION_DATA=""

for search_path in "${SEARCH_PATHS[@]}"; do
  [ ! -d "$search_path" ] && continue

  while IFS= read -r logfile; do
    [ -z "$logfile" ] && continue

    msgs=$(jq -r 'select(.type == "user") | .message.content | if type == "array" then map(select(.type == "text") | .text) | join(" ") elif type == "string" then . else empty end | .[0:200]' "$logfile" 2>/dev/null | grep -v "^$" | grep -v "^<" | head -8)

    if [ -n "$msgs" ]; then
      SESSION_COUNT=$((SESSION_COUNT + 1))
      SESSION_DATA="$SESSION_DATA
=== Сессия $SESSION_COUNT ===
$msgs
"
    fi
  done < <(find "$search_path" -name "*.jsonl" -newer /tmp/ccbooks_date_marker -not -path "*/subagents/*" 2>/dev/null)
done

if [ "$SESSION_COUNT" -eq 0 ]; then
  echo "Сессии за $DATE не найдены"
  exit 0
fi

# Сохранение данных сессий для обработки Claude
echo "$SESSION_DATA" > "$OUTPUT_DIR/.pending-$DATE.txt"

# Попытка генерации через Claude Code (если доступен)
if command -v claude &>/dev/null; then
  claude -p "$(cat <<EOF
Прочитай $OUTPUT_DIR/.pending-$DATE.txt и сгенерируй FlipBook за $DATE.

Используй шаблон $SCRIPT_DIR/template.html как основу.
Путь вывода: $OUTPUT_FILE

Количество сессий: $SESSION_COUNT
Дата: $DATE

Обобщи содержимое сессий в 3-5 глав, дай каждой главе заголовок
и сгенерируй HTML в виде массива pages для FlipBook.

Также добавь запись об этой книге в $OUTPUT_DIR/books.json.
Если books.json не существует, создай новый.
Если запись с такой же датой уже есть, перезапиши её.
EOF
  )" 2>/dev/null

  if [ -f "$OUTPUT_FILE" ]; then
    rm -f "$OUTPUT_DIR/.pending-$DATE.txt"
    echo "Сгенерировано: $OUTPUT_FILE ($SESSION_COUNT сессий)"

    # Уведомление macOS
    osascript -e "display notification \"Книга за $DATE сгенерирована ($SESSION_COUNT сессий)\" with title \"CC Books\" sound name \"Tink\"" 2>/dev/null || true
  else
    echo "Генерация через Claude не удалась. Данные сессий сохранены в: $OUTPUT_DIR/.pending-$DATE.txt"
    echo "Запустите '/daily-flipbook' вручную в Claude Code для генерации."
  fi
else
  echo "Claude CLI не найден. Данные сессий сохранены в: $OUTPUT_DIR/.pending-$DATE.txt"
  echo "Запустите '/daily-flipbook' вручную в Claude Code для генерации."
fi
