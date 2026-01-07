import Config

# Hammer rate limiting configuration (required by flowstone)
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       expiry_ms: 60_000 * 60 * 2,
       cleanup_interval_ms: 60_000 * 10
     ]}
