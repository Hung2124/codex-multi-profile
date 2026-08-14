# Codex Multi-Profile

<p align="center">
  <strong>Hai tài khoản ChatGPT trên Codex Desktop Windows.<br>Một workspace dùng chung.</strong>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="docs/recipes.md">Recipes</a> ·
  <a href="docs/troubleshooting.md">Troubleshooting</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" alt="Codex Multi-Profile — MAIN và CODEX1 qua AuthSwap" width="920">
</p>

> Không chính thức, không liên kết OpenAI. Cần [Codex Desktop](https://chatgpt.com/codex) từ Microsoft Store.

---

## Vấn đề

`CODEX_HOME` thứ hai thường **không** đổi acc — app vẫn đọc `~\.codex\auth.json`.

Repo này dùng **AuthSwap**: lúc mở profile thì chép token acc phụ vào đúng file app đọc; lúc đóng thì restore acc chính. Session / skill / MCP vẫn dùng chung.

<p align="center">
  <img src="docs/images/flow.png" alt="Luồng AuthSwap" width="920">
</p>

---

## Cài

1. Cài Codex Desktop, đăng nhập acc **chính** một lần, rồi đóng app.
2. PowerShell:

```powershell
git clone https://github.com/Hung2124/codex-multi-profile.git
cd codex-multi-profile
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexMultiProfile.ps1
```

3. Shortcut:
   - **Codex1** — acc phụ (lần đầu sẽ kêu đăng nhập)
   - **Codex Main** — restore acc gốc rồi mở Store Codex
   - **Codex Profiles** — list / tạo profile khác

Không mở hai cửa sổ cùng lúc.

### Kiểm tra sau khi cài

```powershell
$m = "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action status
```

`status` / `doctor` che email (ví dụ `al***@gmail.com`).

---

## Gỡ

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-CodexMultiProfile.ps1
```

Không xóa `~\.codex`.

---

## Tài liệu

- [Architecture](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting.md)
- [FAQ](docs/faq.md)
- [Recipes](docs/recipes.md)
- [Changelog](CHANGELOG.md)
