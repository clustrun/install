#!/bin/sh
set -eu

REGISTRY="ghcr.io"
REPO="clustrun/clust-cli"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

detect_platform() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  case "$os" in
    linux)  os="linux" ;;
    darwin) os="darwin" ;;
    *) echo "Unsupported OS: $os" >&2; exit 1 ;;
  esac

  case "$arch" in
    x86_64|amd64)   arch="amd64" ;;
    aarch64|arm64)   arch="arm64" ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
  esac

  # darwin only ships arm64
  if [ "$os" = "darwin" ] && [ "$arch" = "amd64" ]; then
    echo "clust does not support darwin/amd64 — requires Apple Silicon (arm64)" >&2
    exit 1
  fi

  echo "${os}-${arch}"
}

resolve_tag() {
  version="${1:-latest}"
  platform="$2"
  echo "${version}-${platform}"
}

# Fetch the OCI manifest, extract the blob digest, download and extract
fetch_binary() {
  tag="$1"
  image="https://${REGISTRY}/v2/${REPO}"

  # Get an anonymous token for the public package
  token=$(curl -sf "https://${REGISTRY}/token?scope=repository:${REPO}:pull" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

  if [ -z "$token" ]; then
    echo "Failed to get registry token. Is the package public?" >&2
    exit 1
  fi

  auth="Authorization: Bearer ${token}"

  # Resolve the manifest for the tag
  manifest=$(curl -sf -H "$auth" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "${image}/manifests/${tag}")

  if [ -z "$manifest" ]; then
    echo "Failed to fetch manifest for tag: ${tag}" >&2
    exit 1
  fi

  # Extract the first layer's digest (the tarball)
  digest=$(echo "$manifest" | sed -n 's/.*"layers":\[{"mediaType":"application\/gzip","digest":"\([^"]*\)".*/\1/p')

  if [ -z "$digest" ]; then
    echo "Failed to parse blob digest from manifest" >&2
    exit 1
  fi

  # Download and extract
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  curl -sfL -H "$auth" "${image}/blobs/${digest}" | tar xz -C "$tmpdir"

  # Find the binary
  binary=$(find "$tmpdir" -name 'clust-*' -type f | head -1)
  if [ -z "$binary" ]; then
    echo "Binary not found in archive" >&2
    exit 1
  fi

  chmod +x "$binary"

  # Install
  if [ -w "$INSTALL_DIR" ]; then
    mv "$binary" "${INSTALL_DIR}/clust"
  else
    echo "Installing to ${INSTALL_DIR} (requires sudo)"
    sudo mv "$binary" "${INSTALL_DIR}/clust"
  fi

  echo "clust installed to ${INSTALL_DIR}/clust"
}

main() {
  platform=$(detect_platform)
  version="${1:-latest}"
  tag=$(resolve_tag "$version" "$platform")

  echo "Installing clust (${version}, ${platform})..."
  fetch_binary "$tag"
  echo "Done. Run 'clust --help' to get started."
}

main "$@"
