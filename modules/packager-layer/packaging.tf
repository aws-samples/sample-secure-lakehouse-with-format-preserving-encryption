# =============================================================================
# Packager Layer — Glue Dependency Packager
# =============================================================================
#
# Build-time / deploy-time packaging via a terraform_data + local-exec provisioner.
# During `terraform apply` (on an internet-connected build host) this:
#   1. pip-installs requirements.txt (plus all transitive deps) as Glue-runtime
#      wheels (Linux x86_64 / CPython 3.11), unpacked onto a clean build root so
#      top-level importable packages sit at the archive root.
#   2. Adds ALL shared modules (every *.py in shared_modules_dir except the main
#      job script) at the archive root.
#   3. Zips the build root into requirements.zip (a "fat zip", no raw .whl files).
#   4. Uploads (overwrites) the archive to s3://<assets-bucket>/artifacts/requirements.zip.
#
# The triggers map re-runs the provisioner whenever requirements.txt OR any
# bundled shared .py module changes (content hash) — including adding or removing
# a .py file — so any source change propagates to the archive consumed by the
# Glue job via --extra-py-files.

resource "terraform_data" "dependency_packager" {
  triggers_replace = {
    requirements_hash = filemd5(var.requirements_path)
    archive_key       = local.dependency_archive_key

    # Hash of every bundled shared module. jsonencode of the map changes if any
    # file content changes, or if a .py file is added/removed.
    shared_modules_hash = jsonencode(local.shared_module_hashes)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      BUILD_DIR="${local.build_dir}"
      # Resolve the archive to an absolute path so the `cd` in step 4 does not
      # break the relative path passed to `zip`.
      mkdir -p "$BUILD_DIR"
      ARCHIVE_PATH="$(cd "$BUILD_DIR" && pwd)/${local.dependency_archive_name}"

      # 1. Start from a freshly-cleaned build root (no stale artifacts).
      rm -rf "$BUILD_DIR"
      mkdir -p "$BUILD_DIR/pkg"

      # 2. Download + unpack requirements (and all transitive deps) as Glue-runtime
      #    wheels straight into the package root. --target unpacks wheels so each
      #    importable top-level package lands at the root (sys.path-ready).
      python3 -m pip install \
        --requirement "${var.requirements_path}" \
        --target "$BUILD_DIR/pkg" \
        --platform "${var.glue_platform}" \
        --python-version "${var.glue_python_version}" \
        --implementation cp \
        --only-binary=:all: \
        --upgrade

      # 3. Bundle every shared module at the archive root.
%{for p in local.shared_module_paths~}
      cp "${p}" "$BUILD_DIR/pkg/"
%{endfor~}

      # 4. Produce a single fat zip (no raw .whl files; --target already unpacked).
      ( cd "$BUILD_DIR/pkg" && zip -r -q "$ARCHIVE_PATH" . -x '*.whl' )

      # 5. Upload (overwrite) to the fixed artifacts/ key.
      aws s3 cp "$ARCHIVE_PATH" "${local.dependency_archive_uri}"

      echo "Uploaded dependency archive to ${local.dependency_archive_uri}"
    EOT
  }
}
