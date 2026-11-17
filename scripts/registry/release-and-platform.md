# 05 package, platform, Drive, workspace, and social evidence

Machine source: `automation/idol-script-registry.yaml`.

Prefer dry-run/value-free checks. External capture, credential, upload, or publication actions require the exact current-task permission and hash-bound approval.

Authority boundary: No script authors release copy, infers publication, prints secrets, or silently retries an ambiguous external action.

Route: local dry-run/readiness → hash-bound approval → one permitted external/local action → measured closeout.

## Registered scripts

- `scripts/idol_asset_drive_sync.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_collect_platform_metrics.py` — status: `active`; authority: `founder_approved_read_only_external`.
- `scripts/idol_import_tiktok_studio_exports.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_tiktok_oauth_reauth.py` — status: `active`; authority: `founder_approved_credential_write`.
- `scripts/idol_platform_auth_status.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_platform_draft_upload.py` — status: `active`; authority: `founder_approved_external_write`.
- `scripts/idol_prepare_api_upload_video.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_safe_workspace_cleanup.py` — status: `active`; authority: `founder_scoped_cleanup`.
- `scripts/idol_social_evidence_snapshot.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_social_public_closeout.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_social_release_session.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_social_release_sync.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_vercel_analytics_setup.py` — status: `active`; authority: `mechanical_default`.
- `scripts/idol_x_scheduled_thread.py` — status: `active`; authority: `founder_approved_external_write`.
- `scripts/idol_youtube_oauth_reauth.py` — status: `active`; authority: `founder_approved_credential_write`.
- `scripts/idol_x_oauth_reauth.py` — status: `active`; authority: `founder_approved_credential_write`.
- `scripts/validate_final_delivery_manifest.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_package_readiness.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_publishing_plan.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_signal_deck_traffic.py` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_social_analytics.rb` — status: `active`; authority: `mechanical_default`.
- `scripts/validate_tiktok_studio_exports.py` — status: `active`; authority: `mechanical_default`.

For profiled work, use this guide and the exact dispatch only. Open the full
[`INDEX.md`](../INDEX.md) only for maintenance, rerouting, or unprofiled discovery.
