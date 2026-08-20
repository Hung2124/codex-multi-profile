# Codex Multi-Profile

<p align="center">
  <strong>Một app Windows để xem và chọn tài khoản ChatGPT trên Codex Desktop.<br>Một workspace dùng chung. Một cửa sổ (AuthSwap).</strong>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="docs/router.md">Router</a> ·
  <a href="docs/recipes.md">Recipes</a> ·
  <a href="docs/troubleshooting.md">Troubleshooting</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" alt="Codex Multi-Profile — MAIN và CODEX1 qua AuthSwap" width="920">
</p>

> Không chính thức, không liên kết OpenAI. Cần [Codex Desktop](https://chatgpt.com/codex) từ Microsoft Store.

## Chọn tài khoản

Sau khi cài, mở **Codex Accounts** trên Desktop. Đó là sản phẩm: danh sách tài khoản (tên, email đã che, lần dùng gần nhất, depleted, sticky). Bấm / Enter để mở profile qua AuthSwap.

Nếu Codex đang mở, app **đóng cửa sổ đó** rồi chuyển sang login đã lưu. Không hỏi mật khẩu khi `auth.json` còn và không bị poison. Đăng nhập lần đầu (profile mới) vẫn nằm trong Codex.

Agent vẫn dùng CLI: `pool` / `stick` / `route` / `depleted`.

## Cài (một lệnh)

```powershell
irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
```

Giống one-liner curl|bash của b-nnett/codex-subscription-router — không vá ChatGPT.exe.

1. Cài Codex Desktop, đăng nhập acc chính một lần, rồi đóng app.
2. Chạy lệnh trên.
3. Shortcut **Codex Accounts** (chính) / Codex1 / Codex Main / Codex Profiles.

## Router

**Người dùng:** mở **Codex Accounts**. **Agent:** `CodexProfile.ps1 -Action route`.

Bảng định tuyến kiểu subscription-router, vẫn một cửa sổ vì AuthSwap chỉ có một ~/.codex/auth.json. Chi tiết: [docs/router.md](docs/router.md).

| Tình huống | Cách xử lý |
|:---|:---|
| Chat / folder mới | Profile non-depleted dùng lâu nhất (LRU) |
| Cùng git repo / workspace | Sticky owner |
| Owner bị đánh dấu depleted | Failover sang profile còn lại |
| Tất cả depleted | Một thông báo gộp (email đã che). Không mở app |
| Đang mở một cửa sổ Codex | App đóng clone rồi chuyển acc. CLI `route` chỉ in lựa chọn |

```powershell
$m = "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action pool
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action stick -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action route
```

Chỉ dùng tài khoản bạn sở hữu / được phép. depleted là cờ local — không phải công cụ vượt quota.

## Mục đích & sử dụng hợp lệ

Repo này là công cụ mã nguồn mở, chạy local trên Windows dành cho developer đã có nhiều tài khoản ChatGPT hợp lệ (ví dụ cá nhân và công ty).

Repo không nhắm tới chia sẻ gói trả phí, vượt quota, scrape, API không chính thức, hoặc trái Điều khoản OpenAI.

## AuthSwap

CODEX_HOME thứ hai thường không đổi acc — app vẫn đọc ~/.codex/auth.json. AuthSwap chép token acc phụ vào đúng file app đọc; lúc đóng thì restore acc chính.

Layer và model ChatGPT Web tắt mặc định (-Action layer / -Action models).

## Gỡ

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-CodexMultiProfile.ps1
```

Không xóa ~/.codex.

## Tài liệu

- [Router](docs/router.md)
- [Architecture](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting.md)
- [FAQ](docs/faq.md)
- [Recipes](docs/recipes.md)
- [Changelog](CHANGELOG.md)
