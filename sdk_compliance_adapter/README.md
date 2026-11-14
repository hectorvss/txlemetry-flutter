# Txlemetry Flutter SDK compliance adapter

HTTP adapter used by the Txlemetry SDK compliance harness.

The adapter exposes `/health`, `/init`, `/capture`, `/flush`, `/state`, and `/reset` on port `8080`.

Run locally:

```sh
docker compose -f sdk_compliance_adapter/docker-compose.yml up --build --abort-on-container-exit --exit-code-from test-harness
```
