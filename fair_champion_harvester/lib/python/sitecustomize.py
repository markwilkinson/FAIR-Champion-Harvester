# Loaded automatically by Python at start-up when this directory is on
# PYTHONPATH (see FAIRChampionHarvester::Extruct.python_env). Makes the
# `extruct` CLI identify itself with the harvester's User-Agent instead of
# "python-requests/x.y.z". A no-op unless EXTRUCT_USER_AGENT is set.
import os

_ua = os.environ.get("EXTRUCT_USER_AGENT")
if _ua:
    try:
        import requests.utils

        requests.utils.default_user_agent = lambda name="python-requests": _ua
    except Exception:  # never let the shim break the real tool
        pass
