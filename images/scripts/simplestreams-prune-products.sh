#!/usr/bin/env bash
set -euo pipefail

IMAGES_JSON="${IMAGES_JSON:-streams/v1/images.json}"
INDEX_JSON="${INDEX_JSON:-streams/v1/index.json}"
IMAGES_DIR="${IMAGES_DIR:-images}"

if [[ ! -f "$IMAGES_JSON" ]]; then
  echo "ERROR: $IMAGES_JSON not found" >&2
  exit 1
fi
if [[ ! -d "$IMAGES_DIR" ]]; then
  echo "ERROR: $IMAGES_DIR not found" >&2
  exit 1
fi

echo "=== Products summary (debug) ==="
jq -r '
  .products
  | to_entries[]
  | [
      .key,
      (.value.os // ""),
      (.value.variant // ""),
      (.value.arch // .value.architecture // ""),
      (((.value.versions // {}) | keys | max) // "")
    ]
  | @tsv
' "$IMAGES_JSON" | sed 's/^/  /'

# keep: newest product per (os, variant, arch). newest decided by max(version-key).
keep_json="$(
  jq -c '
    def gkey($p):
      (($p.value.os // "") + "|" + ($p.value.variant // "") + "|" + ($p.value.arch // $p.value.architecture // ""));

    def maxver($p):
      (((($p.value.versions // {}) | keys | max) // ""));

    reduce (.products | to_entries[]) as $p
      ({};
        (gkey($p)) as $g
        | (maxver($p)) as $v
        | if (.[$g] == null) or ($v > .[$g].maxver) then
            .[$g] = { key: $p.key, maxver: $v }
          else
            .
          end
      )
    | [.[] | .key]
  ' "$IMAGES_JSON"
)"

del_json="$(
  jq -c --argjson keep "$keep_json" '
    ($keep | map({(.): true}) | add) as $K
    | .products | keys | map(select($K[.] | not))
  ' "$IMAGES_JSON"
)"

echo "=== Keep products ==="
jq -r '.[]' <<<"$keep_json" | sed 's/^/  - /'

del_count="$(jq -r 'length' <<<"$del_json")"
if [[ "$del_count" -eq 0 ]]; then
  echo "No old products to delete (nothing to do)."
  exit 0
fi

echo "=== Products to delete (debug) ==="
echo "$del_json" | jq -r '.[]' | sed 's/^/  - /' || true

# Collect file paths referenced by products to delete
tmp_deleted_paths="$(mktemp)"
jq -r --argjson del "$del_json" '
  ($del | map({(.): true}) | add) as $D
  | (.products // {})
  | to_entries[]
  | select($D[.key])
  | (.value.versions // {})
  | to_entries[]
  | (.value.items // {})
  | to_entries[]
  | .value.path
' "$IMAGES_JSON" | sort -u > "$tmp_deleted_paths"

# Rewrite images.json to keep only keep_json products
tmp_images="$(mktemp)"
jq --argjson keep "$keep_json" '
  ($keep | map({(.): true}) | add) as $K
  | .products |= with_entries(select($K[.key]))
' "$IMAGES_JSON" > "$tmp_images"
mv "$tmp_images" "$IMAGES_JSON"

# Delete files for deleted products (only under images/)
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  if [[ "$p" == "$IMAGES_DIR/"* ]]; then
    rm -f -- "$p"
  else
    echo "WARN: Skip deleting non-$IMAGES_DIR path: $p" >&2
  fi
done < "$tmp_deleted_paths"
rm -f "$tmp_deleted_paths"

# Delete orphaned files under images/ not referenced by images.json
tmp_preserve="$(mktemp)"
jq -r '
  .products
  | to_entries[]
  | .value.versions
  | to_entries[]
  | .value.items
  | to_entries[]
  | .value.path
' "$IMAGES_JSON" | sort -u > "$tmp_preserve"

while IFS= read -r f; do
  if ! grep -Fxq "$f" "$tmp_preserve"; then
    rm -f -- "$f"
  fi
done < <(find "$IMAGES_DIR" -type f -print | sort -u)

rm -f "$tmp_preserve"

# Update index.json products list
products_keys="$(jq -c '.products | keys' "$IMAGES_JSON")"
mkdir -p "$(dirname "$INDEX_JSON")"

if [[ -f "$INDEX_JSON" ]]; then
  tmp_index="$(mktemp)"
  jq --argjson products "$products_keys" '
    .index.images.products = $products
  ' "$INDEX_JSON" > "$tmp_index"
  mv "$tmp_index" "$INDEX_JSON"
else
  cat > "$INDEX_JSON" <<EOF
{"index":{"images":{"datatype":"image-downloads","path":"streams/v1/images.json","products":$products_keys,"format":"products:1.0"}},"format":"index:1.0"}
EOF
fi

echo "=== Done. Kept products ==="
jq -r '.products | keys[]' "$IMAGES_JSON" | sed 's/^/  - /'
