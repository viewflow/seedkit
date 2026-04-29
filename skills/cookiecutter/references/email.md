# Email

Console backend in development, SMTP backend in production — controlled by a single `EMAIL_URL` env var parsed by `django-environ`.

## Settings

In `config/settings.py` (or `config/settings/base.py` for split settings):

```python
EMAIL_CONFIG = env.email_url("EMAIL_URL", default="consolemail://")
vars().update(EMAIL_CONFIG)

DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", default="webmaster@localhost")
SERVER_EMAIL = env("SERVER_EMAIL", default=DEFAULT_FROM_EMAIL)
```

`EMAIL_URL` schemes (django-environ):

- `consolemail://` — print to stdout (dev default)
- `smtp://user:pass@host:port` — plain SMTP
- `smtp+tls://user:pass@host:port` — STARTTLS (most providers on port 587)
- `smtp+ssl://user:pass@host:port` — implicit TLS (port 465)
- `dummymail://` — drop silently (useful in tests)

## .env (local development)

```sh
EMAIL_URL=consolemail://
DEFAULT_FROM_EMAIL=webmaster@localhost
```

## .env.prod (VPS)

Pick the URL that matches your provider. Examples:

```sh
# Postmark SMTP
EMAIL_URL=smtp+tls://<server-token>:<server-token>@smtp.postmarkapp.com:587

# SendGrid SMTP
EMAIL_URL=smtp+tls://apikey:<api-key>@smtp.sendgrid.net:587

# Mailgun SMTP
EMAIL_URL=smtp+tls://<smtp-user>:<smtp-password>@smtp.mailgun.org:587

# AWS SES SMTP
EMAIL_URL=smtp+tls://<smtp-user>:<smtp-password>@email-smtp.<region>.amazonaws.com:587

DEFAULT_FROM_EMAIL=no-reply@example.com
```

URL-encode any special characters in the password (`%40` for `@`, `%23` for `#`, etc.).

## Managed platforms

Set `EMAIL_URL` and `DEFAULT_FROM_EMAIL` as environment variables in the platform dashboard.

- **Fly.io**: `fly secrets set EMAIL_URL=... DEFAULT_FROM_EMAIL=...`
- **Railway / Render**: add via project variables UI.

## Sending mail

```python
from django.core.mail import send_mail

send_mail(
    subject="Welcome",
    message="Thanks for signing up.",
    from_email=None,  # uses DEFAULT_FROM_EMAIL
    recipient_list=["user@example.com"],
)
```

Error reports from `ADMINS` use `SERVER_EMAIL`. Application emails use `DEFAULT_FROM_EMAIL`.

---

## Optional: Mailpit for local HTML preview

Add this section only if the user wants a web UI to inspect rendered emails locally.

### Local — docker-compose.yml

```yaml
services:
  mailpit:
    image: axllent/mailpit:latest
    ports:
      - "8025:8025"  # web UI
      - "1025:1025"  # SMTP
    environment:
      MP_MAX_MESSAGES: 5000
      MP_SMTP_AUTH_ACCEPT_ANY: 1
      MP_SMTP_AUTH_ALLOW_INSECURE: 1
```

### .env

Replace the console backend with the mailpit SMTP endpoint:

```sh
EMAIL_URL=smtp://mailpit:1025
```

Open http://localhost:8025 to view captured emails.
