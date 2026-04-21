# UniqueDing Kitchen

Flutter Web ordering app with markdown-driven menu and recommendation content.

- Chinese version: [README.zh-CN.md](./README.zh-CN.md)

## Screenshots

<table>
  <tr>
    <td align="center"><strong>Day Theme</strong></td>
    <td align="center"><strong>Dark Theme</strong></td>
  </tr>
  <tr>
    <td><img src="./docs/screenshots/app-dark-theme.png" alt="Day Theme" /></td>
    <td><img src="./docs/screenshots/app-day-theme.png" alt="Dark Theme" /></td>
  </tr>
</table>

## Key Directories

- `lib/`: app UI and runtime config loader
- `web/public/`: editable markdown data source (`menu.md`, `recommend.md`)
- `scripts/`: runtime/ops scripts used by the app lifecycle
- `tools/branding/`: one-off branding/logo generation helpers
- `docker/`: container entrypoint scripts
- `deploy/`: deployment examples (`docker-compose.example.yaml`)
- `.github/workflows/`: CI workflow for Docker publishing

## Common Commands

- Local verify: `flutter analyze && flutter test`
- Run locally in Chrome: `flutter run -d chrome`
- Build web: `flutter build web --wasm --no-source-maps --no-web-resources-cdn --no-wasm-dry-run`
- Generate recommendation markdown: `python3 scripts/generate_recommendation.py`

## Script vs Tooling

- `scripts/generate_recommendation.py`: production-facing helper used by Docker startup/cron to refresh `recommend.md`
- `tools/branding/generate_logo_candidates_v4.py`: one-off logo candidate generator, not used by runtime or deploy flow

`generate_recommendation.py` path behavior:

- `PUBLIC_DIR` controls base directory (supports relative path; default prefers `public`, then `web/public`)
- output defaults to `${PUBLIC_DIR}/recommend.md`
- can override output via `RECOMMEND_FILE`
- script writes to a temporary file first, then atomically replaces target

`generate_recommendation.py` menu source behavior:

- `MENU_SOURCE=local` reads `${PUBLIC_DIR}/menu.md`
- `MENU_SOURCE=trillium` fetches and parses `TRILLIUM_URL` (uses `TRILLIUM_TITLE`)
- generated recommendation format is markdown table (`| 名称 | 描述 | 口味 | 小料 |`)

`generate_recommendation.py` OpenAI env behavior:

- URL supports `OPENAI_BASE_URL` / `OPENAI_URL` / `API_URL` / `BASE_URL`
- API key supports `OPENAI_API_KEY` / `API_KEY`
- model supports `OPENAI_MODEL` / `MODEL`
- URL can be either base (for example `https://api.openai.com/v1`) or full endpoint (for example `https://api.openai.com/v1/chat/completions`)

## Docker Compose Example

Use `deploy/docker-compose.example.yaml` as a template:

`docker compose -f deploy/docker-compose.example.yaml up -d`

If you host behind a reverse proxy subpath (for example `/cook/`), set:

- `WEB_BASE_HREF=/cook/`

The value must start and end with `/`.

## Trillium Menu Source

Runtime config supports switching menu source via env vars:

- `MENU_SOURCE`: `local` (default) or `trillium`
- `TRILLIUM_URL`: HTML article URL, for example `https://note.uniqueding.xyz/share/cooklist`
- `TRILLIUM_TITLE`: article title marker used to locate the content section, for example `cooklist`

## Recommend Scheduler

- `RECOMMEND_CRON_SCHEDULE`: cron expression for daily recommendation generation, default `0 0 * * *`
