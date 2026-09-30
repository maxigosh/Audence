#!/usr/bin/env bash
# Скачивает лендинги и прогоняет каждый через MiroFish.
#
#   ./run_landings.sh                      # watbot.ru и watbot.org
#   ./run_landings.sh example.com foo.ru   # любые другие домены
#
# Настройки через переменные окружения:
#   MAX_ROUNDS=10    число раундов симуляции
#   REQUIREMENT=...  свой вопрос к симуляции вместо стандартного
#   FETCH_ONLY=1     только скачать и показать текст лендингов, без симуляции
#
# Нужно: git, curl, uv, залогиненный Claude Code CLI (`claude`).
# Результаты: results/<домен>/<run_id>/ (report/verdict.json, report/report.md, visuals/*.svg)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MIRO="$ROOT/mirofish"
LANDINGS="$ROOT/landings"
RESULTS="$ROOT/results"
MAX_ROUNDS="${MAX_ROUNDS:-10}"

if [ "$#" -gt 0 ]; then DOMAINS=("$@"); else DOMAINS=(watbot.ru watbot.org); fi

for bin in curl uv claude; do
  command -v "$bin" >/dev/null || { echo "Не найден '$bin' в PATH" >&2; exit 1; }
done

cd "$MIRO"
[ -f .env ] || cp .env.example .env
uv sync --quiet
uv run mirofish doctor

mkdir -p "$LANDINGS" "$RESULTS"

for domain in "${DOMAINS[@]}"; do
  echo "=== $domain: скачиваю лендинг ===" >&2
  html="$LANDINGS/$domain.html"
  txt="$LANDINGS/$domain.md"
  curl -fsSL -m 60 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36" \
    -o "$html" "https://$domain/"

  # HTML -> текст: заголовки, абзацы, кнопки, ссылки; без скриптов и стилей.
  uv run python - "$html" "$txt" "$domain" <<'PY'
import re, sys
from html.parser import HTMLParser

src, dst, domain = sys.argv[1:4]

class Extract(HTMLParser):
    SKIP = {"script", "style", "noscript", "svg", "template"}
    BLOCK = {"p", "div", "section", "li", "br", "tr", "article", "header", "footer",
             "h1", "h2", "h3", "h4", "h5", "h6", "button", "a", "td", "label"}

    def __init__(self):
        super().__init__()
        self.out, self.skip, self.title, self.meta = [], 0, "", []
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in self.SKIP:
            self.skip += 1
        elif tag == "title":
            self._in_title = True
        elif tag == "meta" and a.get("content") and (a.get("name") or a.get("property") or "").lower() in (
            "description", "og:title", "og:description", "keywords"):
            self.meta.append(f"{a.get('name') or a.get('property')}: {a['content']}")
        if tag in self.BLOCK:
            self.out.append("\n")
        if tag in ("h1", "h2", "h3"):
            self.out.append("#" * int(tag[1]) + " ")
        if tag == "li":
            self.out.append("- ")

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip:
            self.skip -= 1
        elif tag == "title":
            self._in_title = False
        if tag in self.BLOCK:
            self.out.append("\n")

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        elif not self.skip:
            self.out.append(data)

p = Extract()
p.feed(open(src, encoding="utf-8", errors="replace").read())
body = "".join(p.out)
body = re.sub(r"[ \t\xa0]+", " ", body)
lines, seen = [], set()
for line in (l.strip() for l in body.splitlines()):
    if line and line not in seen:  # лендинги часто дублируют блоки под мобильную/десктопную версии
        seen.add(line)
        lines.append(line)
text = f"# Лендинг https://{domain}/\n\nTitle: {p.title.strip()}\n" + "\n".join(p.meta) + "\n\n" + "\n".join(lines) + "\n"
open(dst, "w", encoding="utf-8").write(text)
print(f"{domain}: {len(text)} символов текста -> {dst}", file=sys.stderr)
if len(text) < 800:
    print(f"ВНИМАНИЕ: у {domain} очень мало текста — возможно, лендинг рендерится JavaScript'ом. "
          f"Сохраните текст страницы вручную в {dst} и перезапустите.", file=sys.stderr)
PY

  if [ "${FETCH_ONLY:-0}" = 1 ]; then continue; fi

  requirement="${REQUIREMENT:-Это текст лендинга https://$domain/ (сервис Watbot — конструктор чат-ботов с ИИ для бизнеса). \
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
