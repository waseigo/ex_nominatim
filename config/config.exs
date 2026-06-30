# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

# This file is responsible for configuring ExNominatim defaults.
# See ExNominatim.get_config/0 for the full list of default values.

# Caching defaults (when using ExNominatim.CachexCache):
#
#   config :ex_nominatim, :cache_name, :ex_nominatim  # Cachex cache name (default: :ex_nominatim)
#   config :ex_nominatim, :cache_ttl, 86_400_000       # TTL in ms (default: 24 hours)

# Rate-limiting defaults:
#
#   config :ex_nominatim, ExNominatim,
#     all: [rate_limit: :auto]  # :auto | true | false | <int>
#
#   :auto  — 1 req/s for nominatim.openstreetmap.org, no limit for other servers (default)
#   true   — 1 req/s for all servers
#   false  — no rate limiting
#   <int>  — N req/s for all servers (e.g. rate_limit: 5)
#
# Retry on rate limit:
#   config :ex_nominatim, ExNominatim,
#     all: [rate_limit_retry: true]  # true | false | <int max retries>

# Geohash:
#   config :ex_nominatim, ExNominatim,
#     all: [geohash: true]  # true | false | <int precision>

# Custom Req opts (headers, timeouts, etc.):
#   config :ex_nominatim, ExNominatim,
#     search: [req_opts: [headers: [accept: "application/json"]]]

import Config
