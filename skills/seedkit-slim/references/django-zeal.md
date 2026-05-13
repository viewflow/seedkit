# django-zeal

N+1 detection middleware. In zeal 2.x the middleware is a lowercase function, not a class.

```python
# settings (local.py or DEBUG-gated single file)
INSTALLED_APPS += ["zeal"]
MIDDLEWARE += ["zeal.middleware.zeal_middleware"]
ZEAL_RAISE_ON_VIOLATION = True
```
