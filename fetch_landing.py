"""Скачивает лендинг и его внутренние страницы и сохраняет их текст одним markdown-файлом.

    python fetch_landing.py watbot.ru landings/watbot.ru.md [--max-pages 15] [--max-chars 45000]

Обходит только ссылки с главной страницы на тот же домен и пропускает блог, справку,
личный кабинет, языковые версии и файлы. Строки, повторяющиеся на разных страницах
(шапка, подвал, меню), попадают в текст один раз.
"""
import argparse
import re
import sys
import urllib.request
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urlunsplit

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"

# Разделы, которые не относятся к самому лендингу.
SKIP_PATH = re.compile(
    r"^/(blog|news|articles?|help|docs?|faq|support|account|cabinet|lk|login|signin|sign-in|signup|sign-up|"
    r"register|auth|admin|api|cdn|static|assets|wp-|tag|category|search|cart|checkout)(/|$)"
    r"|^/(ru|en|de|es|fr|it|pt|kk|kz|uz|uk|ua|tr|pl|zh)(/|$)",
    re.I,
)
SKIP_EXT = re.compile(r"\.(pdf|jpe?g|png|gif|webp|svg|ico|zip|rar|mp4|mp3|xml|json|txt|css|js)$", re.I)


class Extract(HTMLParser):
    SKIP = {"script", "style", "noscript", "svg", "template"}
    BLOCK = {"p", "div", "section", "li", "br", "tr", "article", "header", "footer",
             "h1", "h2", "h3", "h4", "h5", "h6", "button", "a", "td", "label"}

    def __init__(self):
        super().__init__()
        self.out, self.skip, self.title, self.meta, self.links = [], 0, "", [], []
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in self.SKIP:
            self.skip += 1
        elif tag == "title":
            self._in_title = True
        elif tag == "a" and a.get("href"):
            self.links.append(a["href"])
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


def fetch(url: str) -> tuple[str, str]:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "ru,en;q=0.8"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        if "html" not in resp.headers.get("Content-Type", "html"):
            raise ValueError("не HTML")
        charset = resp.headers.get_content_charset() or "utf-8"
        return resp.geturl(), resp.read().decode(charset, errors="replace")


def parse(html: str) -> Extract:
    p = Extract()
    p.feed(html)
    return p


def internal_links(base_url: str, hrefs: list[str]) -> list[str]:
    host = urlsplit(base_url).hostname
    urls = []
    for href in hrefs:
        u = urlsplit(urljoin(base_url, href.strip()))
        if u.scheme not in ("http", "https") or u.hostname != host:
            continue
        path = re.sub(r"/+$", "", u.path) or "/"
        if path == "/" or SKIP_PATH.search(path) or SKIP_EXT.search(path):
            continue
        url = urlunsplit((u.scheme, u.netloc, path, "", ""))
        if url not in urls:
            urls.append(url)
    return urls


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("domain")
    ap.add_argument("dst")
    ap.add_argument("--max-pages", type=int, default=15, help="сколько внутренних страниц брать (0 — только главная)")
    ap.add_argument("--max-chars", type=int, default=45000, help="общий лимит текста (MiroFish читает ~50 000 знаков)")
    args = ap.parse_args()

    home_url, home_html = fetch(f"https://{args.domain}/")
    home = parse(home_html)
    pages = [(home_url, home)]
    for url in internal_links(home_url, home.links)[: args.max_pages]:
        try:
            pages.append((url, parse(fetch(url)[1])))
        except Exception as exc:  # одна битая страница не должна ронять весь прогон
            print(f"  пропускаю {url}: {exc}", file=sys.stderr)

    seen: set[str] = set()
    parts = [f"# Лендинг https://{args.domain}/\n"]
    total = 0
    for url, p in pages:
        body = re.sub(r"[ \t\xa0]+", " ", "".join(p.out))
        lines = []
        for line in (l.strip() for l in body.splitlines()):
            if line and line not in seen:
                seen.add(line)
                lines.append(line)
        section = f"\n---\n\n## Страница: {url}\n\nTitle: {p.title.strip()}\n" + "\n".join(p.meta) + "\n\n" + "\n".join(lines) + "\n"
        if total + len(section) > args.max_chars and len(parts) > 1:
            print(f"  лимит {args.max_chars} знаков: {url} и дальше не вошли", file=sys.stderr)
            break
        parts.append(section)
        total += len(section)
        print(f"  {url}: {len(lines)} строк", file=sys.stderr)

    text = "".join(parts)
    with open(args.dst, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"{args.domain}: {len(parts) - 1} стр., {len(text)} знаков -> {args.dst}", file=sys.stderr)
    if len(home.out) and len("".join(home.out).strip()) < 800:
        print(f"ВНИМАНИЕ: на главной {args.domain} очень мало текста — возможно, она рендерится JavaScript'ом. "
              f"Сохраните текст вручную в {args.dst} и запустите с FETCH=0.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
