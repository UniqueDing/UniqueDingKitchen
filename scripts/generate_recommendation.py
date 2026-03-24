#!/usr/bin/env python3
"""Generate recommend.md with an OpenAI-compatible model.

Environment variables:
- OPENAI_BASE_URL or OPENAI_URL or API_URL or BASE_URL
- OPENAI_API_KEY or API_KEY
- OPENAI_MODEL or MODEL
- MENU_SOURCE: local (default) or trillium
- TRILLIUM_URL / TRILLIUM_TITLE when MENU_SOURCE=trillium
- PUBLIC_DIR: defaults to relative ./public (or ./web/public if present)

Usage:
  python scripts/generate_recommendation.py
  python scripts/generate_recommendation.py --menu web/public/menu.md --out web/public/recommend.md
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def _env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return default


def _read_file(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def _default_public_dir() -> Path:
    env_public_dir = os.getenv("PUBLIC_DIR", "").strip()
    if env_public_dir:
        return Path(env_public_dir)
    if Path("public").exists():
        return Path("public")
    if Path("web/public").exists():
        return Path("web/public")
    return Path("public")


def _build_prompt(menu_md: str, last_recommendation_md: str) -> str:
    return f"""
你是餐饮推荐助手。请基于给定菜单，生成今天的推荐 markdown。

要求：
1) 输出必须是 markdown，且仅输出 markdown 内容。
2) 顶部分类标题固定为：## AI今日推荐
3) 推荐 3 道菜。
4) 必须使用 markdown 表格，列固定为：名称 | 描述 | 口味 | 小料
5) 表格表头必须为：| 名称 | 描述 | 口味 | 小料 |
6) 表格分隔行必须为：| --- | --- | --- | --- |
7) 推荐理由简短，不要超过 20 个汉字。
8) 口味列可为空，小料列可为空；若为空保留空单元格。
9) 尽量避免与最近推荐完全重复。
10) 优先推荐主菜、炖菜、主食相关菜，火锅，烤串等类别直接推荐火锅，烤肉，不要推荐配菜例如牛肉，羊肉这样。

[完整菜单]
{menu_md}

[最近推荐]
{last_recommendation_md}
""".strip()


def _resolve_chat_endpoint(url: str) -> str:
    cleaned = url.strip().rstrip("/")
    if cleaned.endswith("/chat/completions"):
        return cleaned
    if cleaned.endswith("/v1"):
        return cleaned + "/chat/completions"
    return cleaned + "/chat/completions"


def _post_chat_completion(base_url: str, api_key: str, model: str, prompt: str) -> str:
    endpoint = _resolve_chat_endpoint(base_url)
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You generate strict markdown outputs."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.4,
    }

    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    timeout_seconds = float(_env("OPENAI_TIMEOUT_SECONDS", default="45") or "45")
    retries = int(_env("OPENAI_MAX_RETRIES", default="2") or "2")
    last_error: Exception | None = None
    body: str | None = None

    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
                body = response.read().decode("utf-8")
            break
        except urllib.error.HTTPError as err:
            detail = err.read().decode("utf-8", errors="ignore")
            raise RuntimeError(f"HTTP {err.code}: {detail}") from err
        except (TimeoutError, socket.timeout) as err:
            last_error = err
            if attempt >= retries:
                raise RuntimeError(
                    f"OpenAI request timed out after {timeout_seconds:.0f}s (retries={retries})."
                ) from err
            time.sleep(0.8 * (attempt + 1))
            continue
        except urllib.error.URLError as err:
            last_error = err
            if attempt >= retries:
                raise RuntimeError(f"Request failed: {err}") from err
            time.sleep(0.8 * (attempt + 1))
            continue

    if body is None:
        raise RuntimeError(f"Request failed: {last_error}")

    data = json.loads(body)
    try:
        content = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as err:
        raise RuntimeError(f"Unexpected response shape: {data}") from err

    if not isinstance(content, str) or not content.strip():
        raise RuntimeError("Model returned empty content")
    return content.strip()


def _fetch_text(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={"cache-control": "no-cache", "user-agent": "unique-ding-kitchen/1.0"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as response:
            if response.status != 200:
                raise RuntimeError(f"HTTP {response.status} while fetching {url}")
            return response.read().decode("utf-8", errors="ignore")
    except urllib.error.HTTPError as err:
        detail = err.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"HTTP {err.code}: {detail}") from err
    except urllib.error.URLError as err:
        raise RuntimeError(f"Request failed: {err}") from err


def _strip_tags(value: str) -> str:
    return re.sub(r"<[^>]+>", "", value).strip()


def _decode_html(value: str) -> str:
    return (
        value.replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", '"')
        .replace("&#39;", "'")
        .replace("\u00a0", " ")
        .strip()
    )


def _slugify(input_text: str) -> str:
    text = input_text.lower()
    text = re.sub(r"[^a-z0-9\u4e00-\u9fa5]+", "-", text)
    text = re.sub(r"-+", "-", text)
    return re.sub(r"(^-|-$)", "", text)


def _is_header_row(cells: list[str]) -> bool:
    normalized = [cell.replace(" ", "").strip().lower() for cell in cells]
    return (
        "名称" in normalized
        or "菜名" in normalized
        or "description" in normalized
        or "口味" in normalized
    )


def _extract_markdown_from_trillium_html(html: str, article_title: str) -> str:
    snippet = html
    title = article_title.strip()
    if title:
        markers = [f'<h1 id="{title}"', f'<h1 id="{_slugify(title)}"', f'>{title}<']
        for marker in markers:
            idx = snippet.find(marker)
            if idx >= 0:
                snippet = snippet[idx:]
                break

    h2_matches = list(re.finditer(r"<h2[^>]*>(.*?)<a[^>]*>", snippet, flags=re.S))
    if not h2_matches:
        return ""

    out: list[str] = []
    for idx, match in enumerate(h2_matches):
        heading = _decode_html(_strip_tags(match.group(1) or ""))
        if not heading:
            continue
        section_start = match.end()
        section_end = h2_matches[idx + 1].start() if idx + 1 < len(h2_matches) else len(snippet)
        chunk = snippet[section_start:section_end]

        rows: list[list[str]] = []
        for tr in re.finditer(r"<tr[^>]*>(.*?)</tr>", chunk, flags=re.S):
            row_html = tr.group(1) or ""
            cells = [
                _decode_html(_strip_tags(m.group(1) or ""))
                for m in re.finditer(r"<t[dh][^>]*>(.*?)</t[dh]>", row_html, flags=re.S)
            ]
            if not cells:
                continue
            if _is_header_row(cells):
                continue
            if not cells[0]:
                continue
            while len(cells) < 4:
                cells.append("")
            rows.append(cells[:4])

        if not rows:
            continue

        out.append(f"## {heading}")
        out.append("| 名称 | 描述 | 口味 | 小料 |")
        out.append("| --- | --- | --- | --- |")
        for row in rows:
            out.append(f"| {row[0]} | {row[1]} | {row[2]} | {row[3]} |")
        out.append("")

    return "\n".join(out).strip()


def _load_menu_markdown(menu_path: Path, menu_source: str, trillium_url: str, trillium_title: str) -> str:
    source = menu_source.strip().lower()
    if source == "markdown":
        source = "local"
    if source == "trillium":
        if not trillium_url.strip():
            raise RuntimeError("MENU_SOURCE=trillium but TRILLIUM_URL is empty")
        html = _fetch_text(trillium_url.strip())
        markdown = _extract_markdown_from_trillium_html(html, article_title=trillium_title)
        if not markdown.strip():
            raise RuntimeError("Failed to extract menu from Trillium HTML")
        return markdown

    return _read_file(menu_path)


def _normalize_markdown(md: str) -> str:
    text = md.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z0-9_-]*\n", "", text)
        text = re.sub(r"\n```$", "", text).strip()

    lines = [line.rstrip() for line in text.splitlines()]
    table_lines = [line for line in lines if line.strip().startswith("|")]

    if not table_lines:
        rows: list[list[str]] = []
        for line in lines:
            raw = line.strip()
            if not raw.startswith("-"):
                continue
            payload = raw[1:].strip()
            parts = [part.strip() for part in payload.split("|")]
            if len(parts) < 4:
                continue
            rows.append(parts[:4])
        if not rows:
            raise RuntimeError("Model output is not a valid table or list recommendation format")
        out_lines = [
            "## AI今日推荐",
            "| 名称 | 描述 | 口味 | 小料 |",
            "| --- | --- | --- | --- |",
        ]
        out_lines.extend(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} |" for r in rows[:3])
        return "\n".join(out_lines).strip()

    out = ["## AI今日推荐", "| 名称 | 描述 | 口味 | 小料 |", "| --- | --- | --- | --- |"]
    for line in table_lines:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 4:
            continue
        if _is_header_row(cells):
            continue
        if all(set(cell) <= {"-", ":"} for cell in cells):
            continue
        out.append(f"| {cells[0]} | {cells[1]} | {cells[2]} | {cells[3]} |")

    if len(out) <= 3:
        raise RuntimeError("Model output table has no valid recommendation rows")
    return "\n".join(out[:6]).strip()


def main() -> int:
    default_public_dir = _default_public_dir()
    default_menu = str(default_public_dir / "menu.md")
    default_out = os.getenv("RECOMMEND_FILE", str(default_public_dir / "recommend.md"))

    parser = argparse.ArgumentParser()
    parser.add_argument("--menu", default=default_menu)
    parser.add_argument("--out", default=default_out)
    args = parser.parse_args()

    menu_path = Path(args.menu)
    out_path = Path(args.out)

    menu_source = _env("MENU_SOURCE", default="local")
    trillium_url = _env("TRILLIUM_URL")
    trillium_title = _env("TRILLIUM_TITLE", default="cooklist")

    base_url = _env(
        "OPENAI_BASE_URL",
        "OPENAI_URL",
        "API_URL",
        "BASE_URL",
        default="https://api.openai.com/v1",
    )
    api_key = _env("OPENAI_API_KEY", "API_KEY")
    model = _env("OPENAI_MODEL", "MODEL", default="gpt-4o-mini")

    if not api_key:
        print("Missing API key. Set OPENAI_API_KEY or API_KEY.", file=sys.stderr)
        return 2

    menu_md = _load_menu_markdown(
        menu_path,
        menu_source=menu_source,
        trillium_url=trillium_url,
        trillium_title=trillium_title,
    )
    if not menu_md.strip():
        print(f"Menu source is empty: {menu_path}", file=sys.stderr)
        return 2

    last_recommendation_md = _read_file(out_path)
    prompt = _build_prompt(menu_md, last_recommendation_md)

    try:
        generated = _post_chat_completion(base_url, api_key, model, prompt)
    except Exception as error:
        print(f"Failed to generate recommendation: {error}", file=sys.stderr)
        return 1
    normalized = _normalize_markdown(generated)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
    tmp_path.write_text(normalized + "\n", encoding="utf-8")
    tmp_path.replace(out_path)

    print(f"Generated recommendation markdown -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
