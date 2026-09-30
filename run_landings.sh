#!/usr/bin/env bash
# Скачивает лендинги и прогоняет каждый через MiroFish.
#
#   ./run_landings.sh                      # watbot.ru и watbot.org
#   ./run_landings.sh example.com foo.ru   # любые другие домены
#
# Настройки через переменные окружения:
#   MAX_ROUNDS=10    число раундов симуляции
#   REQUIREMENT=...  свой вопрос к симуляции вместо стандартного
#   MAX_PAGES=15     сколько внутренних страниц сайта брать вместе с главной (0 — только главная)
#   FETCH_ONLY=1     только скачать текст лендингов в landings/, без симуляции
#   FETCH=0          не скачивать, а взять уже лежащий landings/<домен>.md (например, поправленный руками)
#
# Нужно: git, uv (https://astral.sh/uv), залогиненный Claude Code CLI (`claude`).
# Результаты: results/<домен>/<run_id>/ (report/verdict.json, report/report.md, visuals/*.svg)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MIRO="$ROOT/mirofish"
LANDINGS="$ROOT/landings"
RESULTS="$ROOT/results"
MAX_ROUNDS="${MAX_ROUNDS:-10}"
MAX_PAGES="${MAX_PAGES:-15}"

if [ "$#" -gt 0 ]; then DOMAINS=("$@"); else DOMAINS=(watbot.ru watbot.org); fi

# uv и claude часто ставятся в ~/.local/bin, которого может не быть в PATH
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

for bin in uv claude; do
  command -v "$bin" >/dev/null || { echo "Не найден '$bin' в PATH" >&2; exit 1; }
done

cd "$MIRO"
[ -f .env ] || cp .env.example .env
echo "=== Установка зависимостей MiroFish (первый раз ~5 ГБ, может занять 5–15 минут) ===" >&2
uv sync
uv run mirofish doctor

mkdir -p "$LANDINGS" "$RESULTS"

for domain in "${DOMAINS[@]}"; do
  txt="$LANDINGS/$domain.md"
  if [ "${FETCH:-1}" = 1 ]; then
    echo "=== $domain: скачиваю главную и до $MAX_PAGES внутренних страниц ===" >&2
    uv run python "$ROOT/fetch_landing.py" "$domain" "$txt" --max-pages "$MAX_PAGES"
  else
    [ -f "$txt" ] || { echo "Нет файла $txt (FETCH=0 берёт уже сохранённый текст)" >&2; exit 1; }
  fi

  if [ "${FETCH_ONLY:-0}" = 1 ]; then continue; fi

  requirement="${REQUIREMENT:-Это текст лендинга https://$domain/ и его внутренних страниц (сервис Watbot — конструктор чат-ботов с ИИ для бизнеса). \
Смоделируй, как на этот лендинг реагирует его целевая аудитория: владельцы малого и среднего бизнеса, маркетологи, \
SMM-специалисты, фрилансеры-ботоделы и агентства. Что их цепляет, что непонятно, какие возражения и недоверие возникают, \
как они сравнивают предложение с конкурентами, насколько вероятна регистрация или покупка и что именно на странице \
стоит изменить (оффер, заголовки, цены, призывы к действию, доказательства), чтобы поднять конверсию.}"

  echo "=== $domain: запускаю MiroFish (раундов: $MAX_ROUNDS) ===" >&2
  mkdir -p "$RESULTS/$domain"
  uv run mirofish run \
    --files "$txt" \
    --requirement "$requirement" \
    --max-rounds "$MAX_ROUNDS" \
    --output-dir "$RESULTS/$domain" \
    --json | tee "$RESULTS/$domain/last_run.json" \
    || echo "ОШИБКА: прогон $domain упал, лог — в $RESULTS/$domain/*/logs/run.log" >&2
done

echo >&2
echo "Готово. Главное смотреть тут:" >&2
for domain in "${DOMAINS[@]}"; do
  ls -d "$RESULTS/$domain"/*/report/verdict.json 2>/dev/null >&2 || true
done
