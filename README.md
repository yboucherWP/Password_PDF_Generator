# Password PDF Generator

WiFi/password PDF webhook service for Ubuntu or Debian.

This repo now installs into one fixed service root:

```text
/opt/services/password-pdf-generator/
```

The goal is a layout that stays the same no matter where you run install or update commands.

## Installed Layout

After install, the important paths are:

```text
/opt/services/password-pdf-generator/
/opt/services/password-pdf-generator/app/
/opt/services/password-pdf-generator/.venv/
/opt/services/password-pdf-generator/config/
/opt/services/password-pdf-generator/config/brand_settings.json
/opt/services/password-pdf-generator/config/password-pdf-generator.env
/opt/services/password-pdf-generator/data/
/opt/services/password-pdf-generator/logs/
/etc/systemd/system/password-pdf-generator.service
/etc/caddy/conf.d/webhooks.caddy
/etc/caddy/conf.d/webhooks.routes/
/etc/caddy/conf.d/webhooks.routes/password-pdf-generator.caddy
```

The PDF app keeps its own code, venv, config, data, and logs together under one folder.

## Install

Run this on the target machine:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/yboucherWP/Password_PDF_Generator/main/install.sh)
```

The installer:

- installs system packages
- clones or updates the repo into `/opt/services/password-pdf-generator/app`
- creates `/opt/services/password-pdf-generator/.venv`
- stores config in `/opt/services/password-pdf-generator/config`
- stores generated files in `/opt/services/password-pdf-generator/data`
- stores logs in `/opt/services/password-pdf-generator/logs`
- creates `password-pdf-generator.service`
- writes or updates the shared Caddy host file at `/etc/caddy/conf.d/webhooks.caddy`
- writes its own route snippet at `/etc/caddy/conf.d/webhooks.routes/password-pdf-generator.caddy`
- uses port `8000` by default, or the next free local port if `8000` is already in use
- generates `WIFI_PDF_API_KEY` automatically if missing and prints it once so you can copy it
- preserves the existing `WIFI_PDF_API_KEY` on later installs or updates unless you explicitly pass a new one
- writes the expected WorkDrive env keys even when they are still blank, so you can fill them in directly
- expects the webhook payload to provide `workdrive_folder_id` for WorkDrive uploads
- uses refresh-token OAuth only for Zoho auth

## Update

On the target machine:

```bash
sudo /opt/services/password-pdf-generator/app/update.sh
```

That keeps the same paths, refreshes the repo, rebuilds the venv, reapplies the service config, and rewrites the shared Caddy file.

## Shared Caddy Layout

This installer now assumes the PDF webhook and the quote geolocation webhook live on the same VM and same hostname.

The shared Caddy host file imports every per-app route snippet from:

```text
/etc/caddy/conf.d/webhooks.routes/*.caddy
```

This service contributes only its own route snippet. It does not need to know how the quote geolocation app is installed.

The PDF route snippet exposes:

- `/pdf/*` to the PDF service on `127.0.0.1:8000`
- `/webhooks/zoho/wifi-pdfs*` to the PDF service on `127.0.0.1:8000`

So the preferred public paths are:

- PDF health: `https://api01.wifiplex.ca/pdf/health`
- PDF webhook: `https://api01.wifiplex.ca/pdf/webhooks/zoho/wifi-pdfs`

The older direct PDF webhook path still works:

- `https://api01.wifiplex.ca/webhooks/zoho/wifi-pdfs`

## Runtime

Local service:

- app module: `wifi_pdf.api:app`
- local health: `http://127.0.0.1:8000/health`
- local webhook: `http://127.0.0.1:8000/webhooks/zoho/wifi-pdfs`

Public paths through the shared Caddy site:

- `GET /pdf/health`
- `POST /pdf/webhooks/zoho/wifi-pdfs`

## Key Installer Variables

- `PASSWORD_PDF_HOST`
- `PASSWORD_PDF_API_KEY`
- `PASSWORD_PDF_ENABLE_WORKDRIVE`
- `PASSWORD_PDF_ZOHO_REGION`
- `PASSWORD_PDF_PORT`
- `PASSWORD_PDF_CADDY_FILE`
- `PASSWORD_PDF_CADDY_ROUTES_DIR`
- `PASSWORD_PDF_CADDY_ROUTE_FILE`
- `ZOHO_WORKDRIVE_CLIENT_ID`
- `ZOHO_WORKDRIVE_CLIENT_SECRET`
- `ZOHO_WORKDRIVE_REFRESH_TOKEN`

## Logs And Data

- PDFs, manifests, exports, and jobs are written under:
  `/opt/services/password-pdf-generator/data/output/pdf/wifi`
- logs are written under:
  `/opt/services/password-pdf-generator/logs`
- main rotating log file:
  `/opt/services/password-pdf-generator/logs/wifi_pdf.log`

## Future Apps

If you add a third webhook app later, the same pattern should be reused:

- `/opt/services/<app-name>/app`
- `/opt/services/<app-name>/.venv`
- `/opt/services/<app-name>/config`
- `/opt/services/<app-name>/data`
- `/opt/services/<app-name>/logs`
- one systemd unit under `/etc/systemd/system`
- one per-app Caddy route snippet under `/etc/caddy/conf.d/webhooks.routes`

Each installer should choose its own local port, then add only its own route snippet. That keeps the repos separate and avoids one app overwriting another app's reverse-proxy config.

## WorkDrive Behavior

When WorkDrive upload is enabled:

- the webhook payload must include `workdrive_folder_id`
- that ID is treated as the parent folder
- the app searches inside that parent for the child folder named `Document locataire`
- the app uploads into that child folder

The app no longer uses a default parent folder ID from env or config.

## Docs

- app details: [wifi_pdf/README.md](./wifi_pdf/README.md)
- deployment notes: [docs/wifi-pdf-ubuntu-esxi.md](./docs/wifi-pdf-ubuntu-esxi.md)
