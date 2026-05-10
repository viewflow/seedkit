# Email

Stock Django wires email backend / host / port / user / pass / tls one setting at a time. `django-environ`'s `email_url` parser collapses that into a single `EMAIL_URL` env var (`consolemail://`, `smtp+tls://user:pass@host:port`, …). Same shape as `DATABASE_URL`; swap providers without touching code.

## Settings

In `config/settings.py` (or `config/settings/base.py`):

```python
# Gated default keeps dev zero-config but fails fast in prod (where DEBUG
# is unset). Use `env.NOTSET` for the prod branch — `default=None` would
# pass None into env.email_url() / env(), which then crashes with TypeError
# on URL parsing or silently propagates as `DEFAULT_FROM_EMAIL = None`.
# `env.NOTSET` raises ImproperlyConfigured cleanly at startup naming the
# missing variable.
globals().update(env.email_url(
    "EMAIL_URL",
    default="consolemail://" if DEBUG else env.NOTSET,
))

DEFAULT_FROM_EMAIL = env(
    "DEFAULT_FROM_EMAIL",
    default="webmaster@localhost" if DEBUG else env.NOTSET,
)
SERVER_EMAIL = env("SERVER_EMAIL", default=DEFAULT_FROM_EMAIL)

ADMINS = [(email.split("@")[0], email) for email in env.list("DJANGO_ADMINS", default=[])]
MANAGERS = ADMINS
```

`.env` must exist before the first `manage.py` invocation. Some
django-environ versions raise `ImproperlyConfigured` on a missing `.env`
file rather than falling through to the gated defaults — `cp .env.example
.env` is the safest first step in the README.

`ADMINS` receive 500-error emails (when `DEBUG=False`) and any `mail_admins()` call. Leave empty in dev — console backend prints to stdout anyway.

If allauth is configured with `ACCOUNT_EMAIL_VERIFICATION = "mandatory"` in production, the gated default is what saves you: console backend would block every signup because the verification link only goes to stdout. Production must set `EMAIL_URL` to a real SMTP URL.

`EMAIL_URL` schemes:

- `consolemail://` — print to stdout (dev default)
- `smtp://user:pass@host:port` — plain SMTP
- `smtp+tls://user:pass@host:port` — STARTTLS (port 587)
- `smtp+ssl://user:pass@host:port` — implicit TLS (port 465)
- `dummymail://` — drop silently (tests)

## .env (local)

```sh
EMAIL_URL=consolemail://
DEFAULT_FROM_EMAIL=webmaster@localhost
```

Also append to `.env.example` so the var is discoverable:

```sh
EMAIL_URL=consolemail://
# DEFAULT_FROM_EMAIL=webmaster@localhost
# SERVER_EMAIL=root@example.com
# DJANGO_ADMINS=admin@example.com,ops@example.com
```

## .env.prod (VPS)

Pick the URL matching your provider:

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
SERVER_EMAIL=django@example.com
DJANGO_ADMINS=ops@example.com,alerts@example.com
```

URL-encode special characters in the password (`%40` for `@`, `%23` for `#`).

---

## Provider HTTP APIs (django-anymail)

SMTP works everywhere but is slower than provider HTTP APIs and exposes none of the provider's features (templated emails, click tracking, event webhooks). `django-anymail` ships per-provider `EmailBackend` classes that talk the provider's HTTP API instead.

Pick this over SMTP when:

- The provider charges per-message and you want delivery-event webhooks (delivered / bounced / complained / opened).
- You want to use server-stored templates with merge variables instead of rendering MIME locally.
- The platform blocks outbound port 587 (some serverless / managed runtimes do).

### Install

Pick the provider extra at install time:

```sh
uv add 'django-anymail[postmark]'      # or [amazon-ses], [sendgrid], [mailgun], [mandrill], [sparkpost], [brevo]
```

### Settings

Anymail's `EMAIL_BACKEND` overrides whatever `EMAIL_URL` parsed, so the `globals().update(env.email_url(...))` line above is fine to keep — it remains the dev fallback when `EMAIL_BACKEND` isn't set.

```python
INSTALLED_APPS += ["anymail"]

# Use provider API in prod; consolemail in dev. Same gating shape as
# the rest of the foundation.
if not DEBUG:
    EMAIL_BACKEND = "anymail.backends.postmark.EmailBackend"

ANYMAIL = {
    "POSTMARK_SERVER_TOKEN": env("POSTMARK_SERVER_TOKEN", default="" if DEBUG else env.NOTSET),
    # Provider-specific keys — see anymail.readthedocs.io for the full list.
    # SES: "AMAZON_SES_CLIENT_PARAMS", or use boto3's standard env vars.
    # SendGrid: "SENDGRID_API_KEY".
    # Mailgun: "MAILGUN_API_KEY", "MAILGUN_SENDER_DOMAIN".
}
```

### .env.prod

```sh
POSTMARK_SERVER_TOKEN=<token>
DEFAULT_FROM_EMAIL=no-reply@example.com
SERVER_EMAIL=django@example.com
```

`EMAIL_URL` is no longer needed in prod with this setup — `EMAIL_BACKEND` wins.

### Webhooks (optional)

Provider event webhooks (delivered / bounced / opened / clicked) need a Django URL exposed:

```python
# config/urls.py
urlpatterns = [
    ...
    path("anymail/", include("anymail.urls")),
]
```

```python
# settings — protect against forged webhook calls
ANYMAIL["WEBHOOK_SECRET"] = env("ANYMAIL_WEBHOOK_SECRET", default="" if DEBUG else env.NOTSET)
```

The provider needs configuring with `ANYMAIL_WEBHOOK_SECRET` as HTTP basic auth (`https://<secret>@example.com/anymail/<provider>/tracking/`). Connect signals to react to events:

```python
from anymail.signals import tracking

def handle_event(sender, event, esp_name, **kwargs):
    # event.event_type: "delivered", "bounced", "opened", ...
    ...

tracking.connect(handle_event)
```

---

## Managed platforms

Set `EMAIL_URL` and `DEFAULT_FROM_EMAIL` as platform env vars.

- **Fly.io**: `fly secrets set EMAIL_URL=... DEFAULT_FROM_EMAIL=...`
- **Railway / Render**: project-variables UI.

## Sending

```python
from django.core.mail import send_mail

send_mail(
    subject="Welcome",
    message="Thanks for signing up.",
    from_email=None,  # uses DEFAULT_FROM_EMAIL
    recipient_list=["user@example.com"],
)
```

Application mail uses `DEFAULT_FROM_EMAIL`; error reports to `ADMINS` use `SERVER_EMAIL`.

For multi-recipient broadcasts (newsletters, daily digests) **never** pass the full address list as `recipient_list=` — every recipient sees every other recipient's address in the `To:` header. Loop and send one message per user, or build an `EmailMessage` with `bcc=` set:

```python
for email in addresses:
    send_mail("Daily digest", body, None, [email])     # one per user

# or, single-shot via BCC:
EmailMessage(
    subject="Daily digest",
    body=body,
    to=["no-reply@example.com"],
    bcc=addresses,
).send()
```

---

## Optional — Mailpit for local HTML preview

Apply only if the user wants a web UI to inspect rendered emails locally.

### docker-compose.yml

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

uv-on-host (Django runs on the host, talks to Mailpit via the published port):

```sh
EMAIL_URL=smtp://localhost:1025
```

docker-compose dev (Django runs in a service that shares the compose network):

```sh
EMAIL_URL=smtp://mailpit:1025
```

Open <http://localhost:8025> in either case to view captured emails.

---

## HTML email templates (short)

Auth flows (allauth, mail-auth, password resets) and ad-hoc transactional mail send better-looking HTML than plain text. Stock Django gives you the wiring (`EmailMultiAlternatives`); the templates are project work.

### Layout

```
templates/email/
  base.html        # shared shell — header, footer, brand colours
  base.txt         # plain-text shell (mandatory companion to every HTML email)
  password_reset.html
  password_reset.txt
  account_confirmation.html
  account_confirmation.txt
```

Always ship a `.txt` companion. Spam filters score HTML-only mail aggressively; `EmailMultiAlternatives` requires a plain-text body anyway.

### Send

```python
from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string

def send_password_reset(user, reset_url):
    ctx = {"user": user, "reset_url": reset_url}
    msg = EmailMultiAlternatives(
        subject="Reset your password",
        body=render_to_string("email/password_reset.txt", ctx),
        to=[user.email],
    )
    msg.attach_alternative(render_to_string("email/password_reset.html", ctx), "text/html")
    msg.send()
```

### Allauth override

`django-allauth` looks up its templates by name first in the project, then falls back to its own. Drop the override into `templates/account/email/`:

```
templates/account/email/
  email_confirmation_message.html   # allauth-specific name
  email_confirmation_message.txt
  password_reset_key_message.html
  password_reset_key_message.txt
```

### Pitfalls

- Inline every CSS rule. Gmail / Outlook strip `<style>` blocks. Tools like `premailer` can do this at build time; for a starter, write inline styles by hand and keep the palette small.
- Don't reference Tailwind classes in email HTML. Tailwind output is purged against templates `@source`'d in `source.css` — email templates would either bloat the bundle (if added to `@source`) or miss styles (if not). Write the small inline subset you need.
- Test with a real client. Litmus / Email on Acid render previews; or just send to one Gmail and one Outlook account before declaring a template done.
