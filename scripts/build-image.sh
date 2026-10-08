#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${PLATFORM:-linux/amd64}"
tag="${IMAGE_TAG:-$(date -u +%Y%m%d%H%M%S)}"
image="shared-expenses:${tag}"
docker_command=(docker)
builder="${BUILDER:-${DOCKER_CONTEXT:-}}"
build_args=(buildx build)

case "$platform" in
  linux/amd64|linux/arm64) ;;
  *) printf 'Unsupported PLATFORM: %s (use linux/amd64 or linux/arm64)\n' "$platform" >&2; exit 1 ;;
esac

if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
  docker_command+=(--context "$DOCKER_CONTEXT")
fi

if [[ -n "$builder" ]]; then
  build_args+=(--builder "$builder")
  builder_info="$("${docker_command[@]}" buildx inspect "$builder")"
else
  builder_info="$("${docker_command[@]}" buildx inspect)"
fi

if [[ "$builder_info" != *"$platform"* ]]; then
  printf 'Docker builder does not support %s. Use PLATFORM=linux/arm64 on an ARM host, or DOCKER_CONTEXT=<amd64-builder> for an amd64 server.\n' "$platform" >&2
  exit 1
fi

"${docker_command[@]}" "${build_args[@]}" --platform "$platform" --load --tag "$image" --file "$project_root/Dockerfile" "$project_root"
if [[ "${SKIP_IMAGE_SAVE:-false}" == "true" ]]; then
  rm -f "$project_root/image.tar"
else
  "${docker_command[@]}" image save --output "$project_root/image.tar" "$image"
fi
printf '%s\n' "$image" > "$project_root/image.tag"
printf '%s\n' "$platform" > "$project_root/image.platform"
if [[ "${SKIP_IMAGE_SAVE:-false}" == "true" ]]; then
  printf 'Built %s (%s) on Docker context %s\n' "$image" "$platform" "${DOCKER_CONTEXT:-current}"
else
  printf 'Saved %s (%s) to %s/image.tar\n' "$image" "$platform" "$project_root"
fi
