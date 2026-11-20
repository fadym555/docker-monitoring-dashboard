#!/usr/bin/env bash
# End-to-end checks against a running stack. Run from the repository root.
set -euo pipefail

PROM=${PROM:-http://127.0.0.1:9090}
GRAFANA=${GRAFANA:-http://127.0.0.1:3000}
PUBLIC=${PUBLIC:-https://localhost}
DASHBOARD=grafana/dashboards/docker-monitoring.json

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; exit 1; }

# retry <seconds> <description> <command...>
retry() {
  local timeout=$1 desc=$2
  shift 2
  local end=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    ((SECONDS < end)) || fail "$desc (timed out after ${timeout}s)"
    sleep 5
  done
  pass "$desc"
}

query() { curl -fsS --get "$PROM/api/v1/query" --data-urlencode "query=$1"; }
expect() { [[ "$(query "$1" | jq -r '.data.result[0].value[1] // empty')" == "$2" ]]; }
status_of() { curl -sk -o /dev/null -w '%{http_code}' "$@"; }

echo "Scrape targets"
for job in prometheus cadvisor node docker; do
  retry 180 "$job target is up" expect "up{job=\"$job\"}" 1
done

echo "Metrics"
retry 120 "cAdvisor sees the demo API container" \
  expect 'count(container_cpu_usage_seconds_total{name="docker-monitoring-demo-api-1"}) > bool 0' 1
retry 60 "Docker engine counts running containers" \
  expect 'engine_daemon_container_states_containers{state="running"} >= bool 7' 1
docker run --name smoke-stopped busybox:1.37 true >/dev/null
retry 60 "a stopped container is counted" \
  expect 'engine_daemon_container_states_containers{state="stopped"} >= bool 1' 1
docker rm smoke-stopped >/dev/null

echo "Dashboard queries"
mapfile -t exprs < <(jq -r '.. | objects | select(has("expr")) | .expr' "$DASHBOARD" | sort -u)
missing=()
all_queries_have_data() {
  missing=()
  local e q n
  for e in "${exprs[@]}"; do
    q=${e//\$container/.+}
    n=$(query "$q" | jq -r '.data.result | length' 2>/dev/null) || n=0
    [[ $n -gt 0 ]] || missing+=("$e")
  done
  [[ ${#missing[@]} -eq 0 ]]
}
end=$((SECONDS + 180))
until all_queries_have_data; do
  if ((SECONDS >= end)); then
    printf '        %s\n' "${missing[@]}"
    fail "dashboard queries without data"
  fi
  sleep 10
done
pass "all ${#exprs[@]} dashboard queries return data"

echo "Grafana"
retry 60 "Grafana is healthy on the admin port" curl -fsS "$GRAFANA/api/health"
retry 60 "public HTTPS endpoint serves Grafana" curl -fsSk "$PUBLIC/api/health"
code=$(status_of "$PUBLIC/api/dashboards/uid/docker-monitoring")
[[ $code == 200 ]] || fail "dashboard returned $code"
pass "dashboard is viewable without logging in"
code=$(status_of "$PUBLIC/login")
[[ $code == 404 ]] || fail "/login returned $code"
pass "login page is not public"
code=$(status_of -X POST -H 'Content-Type: application/json' -d '{"dashboard":{"title":"x"}}' "$PUBLIC/api/dashboards/db")
[[ $code =~ ^40[13]$ ]] || fail "saving a dashboard returned $code"
pass "visitors cannot save dashboards"

echo "Exposure"
for port in 8080 9100; do
  if curl -fsS -m 3 "http://127.0.0.1:$port/" >/dev/null 2>&1; then
    fail "port $port should not be published on the host"
  fi
done
pass "collectors are not published on the host"

echo "All checks passed."
