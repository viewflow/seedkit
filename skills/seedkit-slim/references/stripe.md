# Stripe (raw SDK)

Use the official `stripe` SDK directly — no `dj-stripe`. Three views: Checkout session, Customer Portal, webhook.

```toml
# pyproject.toml
dependencies = [
    "stripe",
]
```

```python
# config/settings/base.py
import stripe as _stripe

STRIPE_PUBLISHABLE_KEY = env("STRIPE_PUBLISHABLE_KEY", default="")
STRIPE_SECRET_KEY = env("STRIPE_SECRET_KEY", default="")
STRIPE_WEBHOOK_SECRET = env("STRIPE_WEBHOOK_SECRET", default="")

_stripe.api_key = STRIPE_SECRET_KEY  # module-scope: every `import stripe` shares the key
```

```sh
# .env.example
STRIPE_PUBLISHABLE_KEY=pk_test_replace
STRIPE_SECRET_KEY=sk_test_replace
STRIPE_WEBHOOK_SECRET=whsec_replace
```

## Customer link on the user model

```python
# users/models.py
class User(AbstractUser):
    stripe_customer_id = models.CharField(max_length=64, blank=True, default="")
```

Add as a field on the custom user (or a follow-up migration) — webhook handlers look up users by `stripe_customer_id`, so it has to be queryable.

## billing/views.py

```python
import stripe
from django.conf import settings
from django.http import HttpResponse, HttpResponseBadRequest, JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST


def create_checkout_session(request):
    session = stripe.checkout.Session.create(
        mode="payment",
        line_items=[{"price": request.POST["price_id"], "quantity": 1}],
        success_url=request.build_absolute_uri("/billing/success"),
        cancel_url=request.build_absolute_uri("/billing/cancel"),
        customer=request.user.stripe_customer_id or None,
    )
    return JsonResponse({"id": session.id, "url": session.url})


def customer_portal(request):
    portal = stripe.billing_portal.Session.create(
        customer=request.user.stripe_customer_id,
        return_url=request.build_absolute_uri("/"),
    )
    return JsonResponse({"url": portal.url})


@csrf_exempt
@require_POST
def stripe_webhook(request):
    sig_header = request.META.get("HTTP_STRIPE_SIGNATURE", "")
    try:
        event = stripe.Webhook.construct_event(
            request.body, sig_header, settings.STRIPE_WEBHOOK_SECRET,
        )
    except (ValueError, stripe.error.SignatureVerificationError):
        return HttpResponseBadRequest("invalid signature")
    # dispatch on event["type"] — checkout.session.completed, invoice.paid, ...
    return HttpResponse(status=200)
```

`@csrf_exempt` + `@require_POST` together: Stripe posts from outside Django's CSRF, but only POST is valid — leaving GET open invites probe noise. `construct_event` verifies the signature using the raw body, so never read `request.body` before this call.
