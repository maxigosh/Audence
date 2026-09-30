# Audence

Тестирование лендингов на симулированной аудитории через [MiroFish](mirofish/) (вендор-копия [amadad/mirofish](https://github.com/amadad/mirofish)).

## Запуск на сервере

Нужно: Linux/macOS, `git`, `curl`, [uv](https://docs.astral.sh/uv/), Node.js 18+ и залогиненный Claude Code CLI.

```bash
# 1. Инструменты (если ещё нет)
curl -LsSf https://astral.sh/uv/install.sh | sh
npm install -g @anthropic-ai/claude-code
claude            # один раз залогиниться, затем выйти (/exit)

# 2. Репозиторий
git clone -b add-mirofish https://github.com/maxigosh/audence.git
cd audence

# 3. Проверить, что текст лендингов вытаскивается нормально
FETCH_ONLY=1 ./run_landings.sh
less landings/watbot.ru.md

# 4. Полный прогон (долго — запускайте в tmux/screen)
./run_landings.sh                    # watbot.ru и watbot.org
./run_landings.sh some-other.site    # любые домены
MAX_ROUNDS=20 ./run_landings.sh      # больше раундов
MAX_PAGES=0 ./run_landings.sh        # только главная, без внутренних страниц
```

Скрипт берёт главную и до 15 внутренних страниц сайта (без блога, справки, кабинета) и склеивает их в `landings/<домен>.md`. Текст можно поправить руками и запустить с `FETCH=0`.

Результаты — в `results/<домен>/<run_id>/`: сначала `report/verdict.json`, потом `report/summary.json` и `report/report.md`, картинки в `visuals/`. Отчёты MiroFish пишет на английском.
