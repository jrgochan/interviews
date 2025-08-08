#!/usr/bin/env zsh
set -euo pipefail

# =========================
# Helpers & Defaults
# =========================
info() { print -P "%F{cyan}==>%f $*"; }
ok()   { print -P "%F{green}✔%f $*"; }
err()  { print -P "%F{red}ERROR:%f $*" >&2; }

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing '$1'. Please install it and re-run."
    case "$1" in
      podman)  print "  macOS: brew install podman" ;;
      oc)      print "  macOS: brew install openshift-cli" ;;
      crc)     print "  macOS: brew install crc   # optional; for OpenShift Local" ;;
      skopeo)  print "  macOS: brew install skopeo # optional but recommended" ;;
      kustomize) print "  macOS: brew install kustomize # only needed if using kustomization.yaml" ;;
      envsubst) print "  macOS: brew install gettext # provides envsubst" ;;
    esac
    exit 1
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Defaults (override with env or flags)
: "${NAMESPACE:=demo}"
: "${MANIFESTS:=./openshift}"
: "${APP_NAME:=app}"
: "${APP_PORT:=8080}"
: "${BUILD_IMAGE:=false}"
: "${CONTAINERFILE:=./Containerfile}"
: "${IMAGE_TAG:=local}"
: "${REGISTRY_ROUTE:=}"            # auto-detect if empty
: "${ENSURE_REGISTRY_ROUTE:=true}" # enable defaultRoute if missing

usage() {
  cat <<'EOF'
Usage: ./deploy-local-ocp.zsh [options]

Options (env var overrides in parentheses):
  -n <namespace>      Target namespace/project (NAMESPACE) [default: demo]
  -m <path>           Manifests dir/file (MANIFESTS) [default: ./openshift]
  -a <app-name>       App/imagestream name (APP_NAME) [default: app]
  -p <port>           App container port (APP_PORT) [default: 8080]
  --build             Build & push image (BUILD_IMAGE=true)
  -f <Containerfile>  Containerfile path (CONTAINERFILE) [default: ./Containerfile]
  -t <tag>            Image tag (IMAGE_TAG) [default: local]
  -r <registry-host>  Registry route host (REGISTRY_ROUTE) [auto-detect if empty]
  --no-ensure-route   Do not try to enable the default image registry route
  -h                  Show help
EOF
}

# =========================
# Parse args
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) NAMESPACE="$2"; shift 2;;
    -m) MANIFESTS="$2"; shift 2;;
    -a) APP_NAME="$2"; shift 2;;
    -p) APP_PORT="$2"; shift 2;;
    --build) BUILD_IMAGE=true; shift;;
    -f) CONTAINERFILE="$2"; shift 2;;
    -t) IMAGE_TAG="$2"; shift 2;;
    -r) REGISTRY_ROUTE="$2"; shift 2;;
    --no-ensure-route) ENSURE_REGISTRY_ROUTE=false; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown arg: $1"; usage; exit 2;;
  esac
done

# =========================
# Preflight
# =========================
need podman
need oc
have gettext || need envsubst   # envsubst check

# Ensure Podman machine is reachable (macOS/Windows)
if podman info >/dev/null 2>&1; then
  ok "Podman daemon reachable."
else
  info "Podman not reachable. Ensuring podman machine is running..."
  if podman machine list 2>/dev/null | grep -q 'Running'; then
    ok "Podman machine is running."
  else
    if podman machine list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -q .; then
      DEFAULT_MACHINE=$(podman machine list | awk 'NR==2 {print $1}')
      info "Starting podman machine '$DEFAULT_MACHINE'..."
      podman machine start "$DEFAULT_MACHINE"
    else
      info "No podman machine found. Initializing and starting default machine..."
      podman machine init
      podman machine start
    fi
    ok "Podman machine started."
  fi
fi

# CRC (OpenShift Local)
CRC_AVAILABLE=false
if have crc; then
  CRC_AVAILABLE=true
  if crc status 2>/dev/null | grep -q "OpenShift: .*Running"; then
    ok "OpenShift Local is running."
  else
    info "Starting OpenShift Local (this can take several minutes)..."
    crc start
    ok "OpenShift Local started."
  fi
  if crc oc-env >/dev/null 2>&1; then
    info "Evaluating 'crc oc-env' to wire oc and KUBECONFIG..."
    eval "$(crc oc-env)"
  fi
fi

# Login check
if oc whoami >/dev/null 2>&1; then
  ok "Already logged into: $(oc whoami --show-server)"
else
  info "Please login to your cluster:"
  oc login --insecure-skip-tls-verify
  ok "Logged in as $(oc whoami)."
fi

# Namespace
if oc get ns "${NAMESPACE}" >/dev/null 2>&1; then
  info "Namespace '${NAMESPACE}' exists; switching..."
else
  info "Creating namespace '${NAMESPACE}'..."
  oc new-project "${NAMESPACE}" >/dev/null
fi
oc project "${NAMESPACE}" >/dev/null
ok "Using namespace: ${NAMESPACE}"

# =========================
# Registry route detection
# =========================
get_registry_route() {
  oc -n openshift-image-registry get route default-route -o jsonpath='{.spec.host}' 2>/dev/null || true
}

if [[ -z "${REGISTRY_ROUTE}" ]]; then
  REGISTRY_ROUTE="$(get_registry_route)"
  if [[ -z "${REGISTRY_ROUTE}" && "${ENSURE_REGISTRY_ROUTE}" == "true" ]]; then
    info "Enabling default route for internal registry..."
    oc patch configs.imageregistry.operator.openshift.io/cluster \
      --type=merge -p '{"spec":{"defaultRoute":true}}' >/dev/null || true
    for i in {1..30}; do
      sleep 2
      REGISTRY_ROUTE="$(get_registry_route)"
      [[ -n "${REGISTRY_ROUTE}" ]] && break
    done
  fi
fi

if [[ -z "${REGISTRY_ROUTE}" ]]; then
  err "Could not determine registry route host. Use -r <host> or ensure the default route exists."
  exit 1
fi
ok "Using registry route: ${REGISTRY_ROUTE}"

# =========================
# Build & Push
# =========================
if [[ "${BUILD_IMAGE}" == "true" ]]; then
  # Find a Containerfile if needed
  if [[ ! -f "${CONTAINERFILE}" ]]; then
    for cand in ./Containerfile ./Dockerfile Containerfile Dockerfile; do
      [[ -f "$cand" ]] && { info "Auto-detected container build file: $cand"; CONTAINERFILE="$cand"; break; }
    done
  fi
  [[ -f "${CONTAINERFILE}" ]] || { err "No Containerfile/Dockerfile found. Use -f <path> or create one."; exit 1; }

  # Heads up for Node users
  if grep -qE 'node:|npm ' "${CONTAINERFILE}" 2>/dev/null && [[ ! -f package-lock.json && -f package.json ]]; then
    info "Note: package-lock.json not found; if your Containerfile uses 'npm ci', it may fail. Consider 'npm install' fallback."
  fi

  LOCAL_IMG="${APP_NAME}:${IMAGE_TAG}"
  info "Building image with podman from ${CONTAINERFILE}..."
  podman build -f "${CONTAINERFILE}" -t "${LOCAL_IMG}" .

  # Login (HTTPS)
  TOKEN=$(oc whoami -t)
  [[ -z "${TOKEN}" ]] && { err "Could not obtain an oc token for registry login."; exit 1; }
  info "Logging into internal registry at https://${REGISTRY_ROUTE}..."
  podman login --tls-verify=false -u kubeadmin -p "${TOKEN}" "https://${REGISTRY_ROUTE}"

  # Ensure ImageStream exists
  oc get is "${APP_NAME}" >/dev/null 2>&1 || oc create is "${APP_NAME}" >/dev/null

  DEST_REF="${REGISTRY_ROUTE}/${NAMESPACE}/${APP_NAME}:${IMAGE_TAG}"
  info "Pushing image to ${DEST_REF}..."
  push_ok=false

  # Prefer skopeo via docker-archive (works across Podman VM boundary)
  if have skopeo; then
    TMP_TAR="$(mktemp -t ${APP_NAME}-${IMAGE_TAG}-XXXX).tar"
    info "Saving image to archive ${TMP_TAR} for skopeo copy..."
    podman save --format docker-archive -o "${TMP_TAR}" "${LOCAL_IMG}"
    if skopeo copy \
      --insecure-policy \
      --src-tls-verify=false \
      --dest-tls-verify=false \
      --dest-creds "kubeadmin:${TOKEN}" \
      "docker-archive:${TMP_TAR}" \
      "docker://${DEST_REF}"; then
      push_ok=true
      rm -f "${TMP_TAR}" || true
    else
      info "skopeo copy via archive failed; will try registry port-forward fallback..."
      rm -f "${TMP_TAR}" || true
    fi
  else
    info "skopeo not found; using registry port-forward fallback..."
  fi

  # Fallback: port-forward service/image-registry -> localhost:5000 and push there
  if [[ "${push_ok}" != true ]]; then
    info "Starting temporary port-forward to image-registry on localhost:5000 ..."
    PF_LOG="$(mktemp -t oc-pf-XXXX.log)"
    oc -n openshift-image-registry port-forward service/image-registry 5000:5000 >"$PF_LOG" 2>&1 &
    PF_PID=$!

    cleanup_pf() {
      [[ -n "${PF_PID:-}" ]] && kill "${PF_PID}" >/dev/null 2>&1 || true
      [[ -f "${PF_LOG}" ]] && rm -f "${PF_LOG}" || true
    }
    trap cleanup_pf EXIT

    # Wait up to ~10s for the port-forward to be ready
    ready=false
    if have nc; then
      for i in {1..20}; do
        if nc -z localhost 5000 2>/dev/null; then ready=true; break; fi
        sleep 0.5
      done
    else
      sleep 2; ready=true
    fi
    [[ "${ready}" == true ]] || { err "Port-forward to localhost:5000 did not become ready."; cleanup_pf; trap - EXIT; exit 1; }

    podman login --tls-verify=false -u kubeadmin -p "${TOKEN}" "http://localhost:5000"
    LOCAL_DEST="localhost:5000/${NAMESPACE}/${APP_NAME}:${IMAGE_TAG}"
    podman tag "${LOCAL_IMG}" "${LOCAL_DEST}"
    podman push --tls-verify=false "docker://${LOCAL_DEST}"

    push_ok=true
    info "Pushed via localhost:5000 using port-forward."
    cleanup_pf
    trap - EXIT
  fi

  [[ "${push_ok}" == true ]] || { err "Image push failed."; exit 1; }
  ok "Image pushed to internal registry."
fi

# =========================
# Apply manifests (normalize ${VAR:-default} then envsubst; supports kustomize or plain YAMLs)
# =========================
export APP_NAME APP_PORT NAMESPACE IMAGE_TAG

# helper to strip default expansions like ${FOO:-bar} -> ${FOO}
normalize_defaults() {
  sed -E 's/\$\{([A-Za-z_][A-Za-z0-9_]*)[:-][^}]*\}/\${\1}/g'
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

if [[ -d "${MANIFESTS}" && -f "${MANIFESTS}/kustomization.yaml" ]]; then
  need kustomize
  info "Applying Kustomize at ${MANIFESTS} with variable substitution..."
  # kustomize -> strip ${VAR:-...} -> envsubst -> apply
  kustomize build "${MANIFESTS}" \
    | normalize_defaults \
    | envsubst \
    > "${tmpdir}/rendered.yaml"
  oc apply -f "${tmpdir}/rendered.yaml"
elif [[ -d "${MANIFESTS}" ]]; then
  info "Applying all YAMLs under ${MANIFESTS} with variable substitution..."
  mapfile -t files < <(find "${MANIFESTS}" -type f \( -name '*.yaml' -o -name '*.yml' \))
  if [[ "${#files[@]}" -eq 0 ]]; then
    err "No YAML files found under ${MANIFESTS}."
    exit 1
  fi
  for f in "${files[@]}"; do
    normalize_defaults < "$f" | envsubst > "${tmpdir}/$(basename "$f")"
  done
  oc apply -f "${tmpdir}"
elif [[ -f "${MANIFESTS}" ]]; then
  info "Applying ${MANIFESTS} with variable substitution..."
  normalize_defaults < "${MANIFESTS}" | envsubst > "${tmpdir}/rendered.yaml"
  oc apply -f "${tmpdir}/rendered.yaml"
else
  err "MANIFESTS path '${MANIFESTS}' not found."
  exit 1
fi

ok "Deployment applied."

# Status hints
info "Pods in ${NAMESPACE}:"
oc get pods -n "${NAMESPACE}" || true

if oc -n "${NAMESPACE}" get deploy "${APP_NAME}" >/dev/null 2>&1; then
  info "Waiting for rollout of deploy/${APP_NAME}..."
  oc -n "${NAMESPACE}" rollout status "deploy/${APP_NAME}" || true
fi

if oc -n "${NAMESPACE}" get route "${APP_NAME}" >/dev/null 2>&1; then
  APP_HOST=$(oc -n "${NAMESPACE}" get route "${APP_NAME}" -o jsonpath='{.spec.host}')
  ok "App route: http://${APP_HOST}"
else
  info "No Route named '${APP_NAME}' detected. Ensure your manifests define one if you need external access."
fi

ok "Done."

