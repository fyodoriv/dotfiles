"""Clear only OpenSSL's VERIFY_X509_STRICT flag (dotfiles #349).

Python 3.13 sets VERIFY_X509_STRICT in ssl.create_default_context(). A
TLS-inspection proxy whose root CA marks basicConstraints as non-critical then
fails every HTTPS call. This module clears that one flag. Chain, hostname, and
expiry checks stay on.

Opt-in per venv: `dotfiles-python-tls-relax <venv>` copies this file and a
`.pth` line that imports it into the venv's site-packages.

It also patches urllib3's create_urllib3_context (and the names bound to it
at import) when urllib3 loads, and points httplib2 at SSL_CERT_FILE or
REQUESTS_CA_BUNDLE when one is set.
"""

import importlib.abc
import os
import ssl
import sys

_STRICT = getattr(ssl, "VERIFY_X509_STRICT", 0)


def _relax(ctx):
    if _STRICT and isinstance(ctx, ssl.SSLContext):
        ctx.verify_flags &= ~_STRICT
    return ctx


def _wrap(fn):
    if getattr(fn, "_dotfiles_tls_relax", False):
        return fn

    def wrapped(*args, **kwargs):
        return _relax(fn(*args, **kwargs))

    wrapped._dotfiles_tls_relax = True
    wrapped.__wrapped__ = fn
    return wrapped


ssl.create_default_context = _wrap(ssl.create_default_context)
ssl._create_default_https_context = ssl.create_default_context

# Modules that bind create_urllib3_context at import time.
_URLLIB3_BINDERS = ("urllib3.util.ssl_", "urllib3.util", "urllib3.connection", "urllib3.connectionpool")


def _patch(mod):
    name = mod.__name__
    if name in _URLLIB3_BINDERS and hasattr(mod, "create_urllib3_context"):
        mod.create_urllib3_context = _wrap(mod.create_urllib3_context)
    if name == "httplib2":
        bundle = os.environ.get("SSL_CERT_FILE") or os.environ.get("REQUESTS_CA_BUNDLE")
        if bundle and os.path.isfile(bundle):
            mod.CA_CERTS = bundle


class _Loader(importlib.abc.Loader):
    def __init__(self, inner):
        self._inner = inner

    def create_module(self, spec):
        return self._inner.create_module(spec)

    def exec_module(self, module):
        self._inner.exec_module(module)
        _patch(module)


class _Finder(importlib.abc.MetaPathFinder):
    def find_spec(self, name, path, target=None):
        if name not in _URLLIB3_BINDERS and name != "httplib2":
            return None
        for finder in sys.meta_path:
            if finder is self or not hasattr(finder, "find_spec"):
                continue
            spec = finder.find_spec(name, path, target)
            if spec is not None and spec.loader is not None:
                spec.loader = _Loader(spec.loader)
                return spec
        return None


for _name in _URLLIB3_BINDERS + ("httplib2",):
    if _name in sys.modules:
        _patch(sys.modules[_name])
sys.meta_path.insert(0, _Finder())
