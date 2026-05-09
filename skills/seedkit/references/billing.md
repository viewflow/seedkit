# Billing — Stripe

Two options. Ask the user which one.

- **`stripe` (raw SDK)** — the official Stripe Python client, no Django ORM sync. You store the Stripe customer ID on the User model and call the Stripe API directly. Stripe-hosted Checkout and the Customer Portal handle the subscription UI so you write almost no billing UI yourself. Pick for simple cases: one-time payments, or subscriptions where Stripe manages the plan-switching / cancellation UI.
- **`dj-stripe`** — syncs Stripe objects (Customer, Subscription, Price, Product, Invoice) into local Django models. Lets you query billing state with the ORM, filter users by plan, and react to billing events via Django signals. Pick when you need to display subscription status in your own UI, gate features by plan in Python code, or run billing queries in the DB.

---

## Option A — raw `stripe` SDK

### Install

```sh
uv add stripe
```

### Settings

```python
# config/settings/base.py
import stripe as _stripe

STRIPE_PUBLISHABLE_KEY = env("STRIPE_PUBLISHABLE_KEY", default="")
STRIPE_SECRET_KEY = env("STRIPE_SECRET_KEY", default="")
STRIPE_WEBHOOK_SECRET = env("STRIPE_WEBHOOK_SECRET", default="")

_stripe.api_key = STRIPE_SECRET_KEY
```

### .env.example

```
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

### Store the customer ID on the User model

Add a nullable field to whatever model represents a user (or a `Profile`):

```python
stripe_customer_id = models.CharField(max_length=255, blank=True, default="")
```

Create or retrieve the Stripe customer on first checkout:

```python
import stripe
from django.conf import settings

def get_or_create_customer(user):
    if user.stripe_customer_id:
        return user.stripe_customer_id
    # Stripe's idempotency key turns concurrent first-checkout requests for
    # the same user into a no-op upsert: the second call returns the same
    # customer instead of creating a duplicate. No DB row lock is held
    # across the network round-trip — that pattern stalls workers and risks
    # deadlocks if the Stripe call is slow.
    customer = stripe.Customer.create(
        email=user.email,
        idempotency_key=f"customer:user:{user.pk}",
    )
    user.stripe_customer_id = customer.id
    user.save(update_fields=["stripe_customer_id"])
    return customer.id
```

### Checkout session

```python
# billing/views.py
import stripe
from django.conf import settings
from django.contrib.auth.decorators import login_required
from django.shortcuts import redirect

@login_required
def create_checkout_session(request):
    customer_id = get_or_create_customer(request.user)
    session = stripe.checkout.Session.create(
        customer=customer_id,
        payment_method_types=["card"],
        line_items=[{"price": request.POST["price_id"], "quantity": 1}],
        mode="subscription",
        success_url=request.build_absolute_uri("/billing/success/"),
        cancel_url=request.build_absolute_uri("/billing/cancel/"),
    )
    return redirect(session.url)
```

### Customer portal (plan changes, cancellation)

```python
@login_required
def customer_portal(request):
    session = stripe.billing_portal.Session.create(
        customer=request.user.stripe_customer_id,
        return_url=request.build_absolute_uri("/billing/"),
    )
    return redirect(session.url)
```

### Webhook

Stripe sends events to a URL you register in the dashboard. The view must read the raw request body **before** any JSON parsing — use `@csrf_exempt` and avoid body-consuming middleware.

```python
# billing/views.py
import stripe
from django.conf import settings
from django.http import HttpResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST

@csrf_exempt
@require_POST
def stripe_webhook(request):
    payload = request.body
    sig_header = request.META.get("HTTP_STRIPE_SIGNATURE", "")
    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.STRIPE_WEBHOOK_SECRET
        )
    except (ValueError, stripe.SignatureVerificationError):
        # `stripe.error.SignatureVerificationError` is a deprecated compat shim
        # in stripe-python ≥7. Use the top-level name.
        return HttpResponse(status=400)

    if event["type"] == "customer.subscription.created":
        _handle_subscription_created(event["data"]["object"])
    elif event["type"] == "customer.subscription.deleted":
        _handle_subscription_deleted(event["data"]["object"])
    # add more event types as needed

    return HttpResponse(status=200)


def _handle_subscription_created(subscription):
    from django.contrib.auth import get_user_model
    User = get_user_model()
    try:
        user = User.objects.get(stripe_customer_id=subscription["customer"])
    except User.DoesNotExist:
        return
    user.is_subscribed = True   # or whatever field tracks subscription state
    user.save(update_fields=["is_subscribed"])


def _handle_subscription_deleted(subscription):
    from django.contrib.auth import get_user_model
    User = get_user_model()
    try:
        user = User.objects.get(stripe_customer_id=subscription["customer"])
    except User.DoesNotExist:
        return
    user.is_subscribed = False
    user.save(update_fields=["is_subscribed"])
```

### URLs

```python
# config/urls.py
from billing import views as billing_views

urlpatterns += [
    path("billing/checkout/", billing_views.create_checkout_session, name="billing-checkout"),
    path("billing/portal/", billing_views.customer_portal, name="billing-portal"),
    path("billing/webhook/", billing_views.stripe_webhook, name="stripe-webhook"),
]
```

Register `https://yourdomain.com/billing/webhook/` in Stripe Dashboard → Developers → Webhooks. For local dev use the Stripe CLI:

```sh
stripe listen --forward-to localhost:8000/billing/webhook/
```

The CLI prints a webhook signing secret (`whsec_...`) — use it as `STRIPE_WEBHOOK_SECRET` in `.env` during development.

---

## Option B — `dj-stripe`

### Install

```sh
uv add dj-stripe
```

### Settings

```python
# config/settings/base.py
INSTALLED_APPS = [
    ...
    "djstripe",
]

STRIPE_LIVE_MODE = env.bool("STRIPE_LIVE_MODE", default=False)
STRIPE_TEST_SECRET_KEY = env("STRIPE_TEST_SECRET_KEY", default="")
STRIPE_LIVE_SECRET_KEY = env("STRIPE_LIVE_SECRET_KEY", default="")
DJSTRIPE_WEBHOOK_SECRET = env("DJSTRIPE_WEBHOOK_SECRET", default="")
DJSTRIPE_FOREIGN_KEY_TO_FIELD = "id"   # use Stripe IDs as FK targets, not Django PKs
```

### .env.example

```
STRIPE_LIVE_MODE=False
STRIPE_TEST_SECRET_KEY=sk_test_...
STRIPE_LIVE_SECRET_KEY=sk_live_...
DJSTRIPE_WEBHOOK_SECRET=whsec_...
```

### Migrate

```sh
uv run manage.py migrate
```

dj-stripe ships ~30 migrations that create local mirror tables for all Stripe objects.

### Sync existing Stripe data

After connecting to an account for the first time, pull existing objects into the local DB:

```sh
uv run manage.py djstripe_sync_models
```

### URLs (webhook)

```python
# config/urls.py
import djstripe.urls

urlpatterns += [
    path("stripe/", include("djstripe.urls", namespace="djstripe")),
]
```

dj-stripe handles `POST /stripe/webhook/` automatically. Register `https://yourdomain.com/stripe/webhook/` in the Stripe Dashboard.

### Querying subscription state

```python
from djstripe.models import Subscription

def user_is_subscribed(user):
    return Subscription.objects.filter(
        customer__subscriber=user,
        status__in=["active", "trialing"],
    ).exists()
```

Gate a view:

```python
from django.contrib.auth.decorators import login_required
from django.shortcuts import redirect

def subscription_required(view_func):
    @login_required
    def wrapper(request, *args, **kwargs):
        if not user_is_subscribed(request.user):
            return redirect("billing-upgrade")
        return view_func(request, *args, **kwargs)
    return wrapper
```

### Checkout session (dj-stripe still uses Stripe-hosted Checkout)

```python
import stripe
from django.conf import settings
from django.contrib.auth.decorators import login_required
from django.shortcuts import redirect
from djstripe.models import Customer

@login_required
def create_checkout_session(request):
    customer, _ = Customer.get_or_create(subscriber=request.user)
    session = stripe.checkout.Session.create(
        customer=customer.id,
        payment_method_types=["card"],
        line_items=[{"price": request.POST["price_id"], "quantity": 1}],
        mode="subscription",
        success_url=request.build_absolute_uri("/billing/success/"),
        cancel_url=request.build_absolute_uri("/billing/cancel/"),
    )
    return redirect(session.url)
```

### Reacting to billing events

dj-stripe fires Django signals after syncing incoming webhook events:

```python
# billing/signals.py
from djstripe.signals import WEBHOOK_SIGNALS

@WEBHOOK_SIGNALS["customer.subscription.created"].connect
def on_subscription_created(sender, event, **kwargs):
    subscription = event.data["object"]
    # subscription is a Stripe dict; also available as djstripe.models.Subscription
    ...
```

Connect signals in `billing/apps.py`:

```python
from django.apps import AppConfig

class BillingConfig(AppConfig):
    name = "billing"

    def ready(self):
        import billing.signals  # noqa: F401
```

### Local dev

```sh
stripe listen --forward-to localhost:8000/stripe/webhook/
```

Use the printed `whsec_...` as `DJSTRIPE_WEBHOOK_SECRET` in `.env`.
