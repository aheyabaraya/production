import base64
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "idol_execute_image_generation_request.py"
SPEC = importlib.util.spec_from_file_location("idol_image_execution", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class FakeResponse:
    def __init__(self, body: bytes, url: str):
        self.body = body
        self.url = url

    def __enter__(self):
        return self

    def __exit__(self, _exc_type, _exc_value, _traceback):
        return False

    def read(self, size: int = -1) -> bytes:
        return self.body if size < 0 else self.body[:size]

    def geturl(self) -> str:
        return self.url


class ImageGenerationExecutorTransportTest(unittest.TestCase):
    def orchestration_report(self, *, selection_only=False):
        return {
            "selection_only": selection_only,
            "external_call_performed": False,
        }, {"founder_generation_authority_id": "AUTH-EXACT"}

    def assert_zero_secret_loader_and_transport(self, argv, *, selection_only=False):
        with mock.patch.object(MODULE, "repo_path", return_value=Path("request.yaml")), \
             mock.patch.object(MODULE, "load_mapping", return_value={}), \
             mock.patch.object(MODULE, "safe_preflight", return_value=self.orchestration_report(selection_only=selection_only)), \
             mock.patch.object(MODULE, "load_credential_for_confirmed_execute") as secret_loader, \
             mock.patch.object(MODULE, "perform_openai") as transport, \
             mock.patch.object(MODULE, "perform_xai") as xai_transport, \
             mock.patch.object(MODULE, "open_without_redirect") as xai_io, \
             mock.patch.object(MODULE.urllib.request, "urlopen") as urlopen:
            status = MODULE.main(argv)
        secret_loader.assert_not_called()
        transport.assert_not_called()
        xai_transport.assert_not_called()
        xai_io.assert_not_called()
        urlopen.assert_not_called()
        return status

    def test_nonexecuting_paths_never_load_secret_or_open_transport(self):
        self.assertEqual(0, self.assert_zero_secret_loader_and_transport(["preflight", "request.yaml"]))
        self.assertEqual(
            1,
            self.assert_zero_secret_loader_and_transport(
                ["execute", "request.yaml", "--founder-authority-id", "AUTH-EXACT"]
            ),
        )
        self.assertEqual(
            1,
            self.assert_zero_secret_loader_and_transport(
                [
                    "execute",
                    "request.yaml",
                    "--founder-authority-id",
                    "AUTH-WRONG",
                    "--confirm-external-paid-execution",
                ]
            ),
        )
        self.assertEqual(
            1,
            self.assert_zero_secret_loader_and_transport(
                [
                    "execute",
                    "request.yaml",
                    "--founder-authority-id",
                    "AUTH-EXACT",
                    "--confirm-external-paid-execution",
                ],
                selection_only=True,
            ),
        )

    def test_all_helper_children_drop_provider_credentials(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root = Path(directory)
            env_file = fixture_root / ".env.xai.local"
            env_file.write_text("XAI_API_KEY=fixture-never-loaded\n", encoding="utf-8")
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.dict(
                     MODULE.os.environ,
                     {
                         "XAI_API_KEY": "mock-xai-only",
                         "OPENAI_API_KEY": "mock-openai-only",
                         "SAFE_FIXTURE": "kept",
                     },
                     clear=True,
                 ), \
                 mock.patch.object(
                     MODULE.subprocess,
                     "run",
                     return_value=mock.Mock(returncode=0),
                ) as child:
                MODULE.allowed_env_file(env_file)
                MODULE.validate_schema(env_file)
                MODULE.validate_document_schema({}, env_file, "fixture")

        self.assertEqual(3, child.call_count)
        for call in child.call_args_list:
            child_env = call.kwargs["env"]
            self.assertNotIn("XAI_API_KEY", child_env)
            self.assertNotIn("OPENAI_API_KEY", child_env)
            self.assertEqual("kept", child_env["SAFE_FIXTURE"])

    def test_xai_explicit_credential_file_is_exact_repository_path(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root = Path(directory)
            exact = fixture_root / ".env.xai.local"
            other = fixture_root / ".env.other.local"
            exact.write_text("XAI_API_KEY=fixture-only\n", encoding="utf-8")
            other.write_text("XAI_API_KEY=fixture-other\n", encoding="utf-8")
            defaults = {
                "openai": (fixture_root / ".env.local",),
                "xai_api": (exact,),
            }
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.object(MODULE, "DEFAULT_ENV_FILES", defaults):
                self.assertEqual((exact,), MODULE.credential_file_candidates("xai_api", str(exact)))
                with self.assertRaisesRegex(MODULE.ExecutionError, "must be the ignored repository"):
                    MODULE.credential_file_candidates("xai_api", str(other))

    def test_xai_credential_file_uses_same_private_contract_as_native_manager(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root = Path(directory)
            exact = fixture_root / ".env.xai.local"
            exact.write_text("XAI_API_KEY=fixture_xai_key_1234567890\n", encoding="utf-8")
            exact.chmod(0o600)
            defaults = {"openai": (), "xai_api": (exact,)}
            ignored = mock.Mock(returncode=0)
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.object(MODULE, "DEFAULT_ENV_FILES", defaults), \
                 mock.patch.object(MODULE.subprocess, "run", return_value=ignored), \
                 mock.patch.dict(MODULE.os.environ, {}, clear=True):
                self.assertEqual(
                    ".env.xai.local",
                    MODULE.credential_presence("xai_api", None),
                )
                self.assertEqual(
                    "fixture_xai_key_1234567890",
                    MODULE.load_credential_for_confirmed_execute("xai_api", None),
                )

                exact.chmod(0o640)
                with self.assertRaisesRegex(MODULE.ExecutionError, "0600 or stricter"):
                    MODULE.credential_presence("xai_api", None)

                exact.chmod(0o600)
                exact.write_text(
                    "XAI_API_KEY=fixture_xai_key_1234567890\n"
                    "XAI_API_KEY=fixture_xai_key_abcdefghij\n",
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(MODULE.ExecutionError, "duplicate XAI_API_KEY"):
                    MODULE.credential_presence("xai_api", None)

                exact.write_text("XAI_API_KEY=short\n", encoding="utf-8")
                with self.assertRaisesRegex(MODULE.ExecutionError, "invalid private transport shape"):
                    MODULE.credential_presence("xai_api", None)

                exact.write_bytes(b"XAI_API_KEY=" + b"a" * (MODULE.XAI_ENV_FILE_MAX_BYTES + 1))
                with self.assertRaisesRegex(MODULE.ExecutionError, "64 KiB"):
                    MODULE.credential_presence("xai_api", None)

                exact.unlink()
                target = fixture_root / "outside-secret"
                target.write_text("XAI_API_KEY=fixture_xai_key_1234567890\n", encoding="utf-8")
                target.chmod(0o600)
                exact.symlink_to(target)
                with self.assertRaisesRegex(MODULE.ExecutionError, "must not be a symlink"):
                    MODULE.credential_presence("xai_api", None)

    def test_xai_process_environment_uses_private_transport_shape(self):
        with mock.patch.dict(MODULE.os.environ, {"XAI_API_KEY": "short"}, clear=True):
            with self.assertRaisesRegex(MODULE.ExecutionError, "invalid private transport shape"):
                MODULE.credential_presence("xai_api", None, process_env_only=True)

        with mock.patch.dict(
            MODULE.os.environ,
            {"XAI_API_KEY": "fixture_process_xai_key_123456"},
            clear=True,
        ):
            self.assertEqual(
                "process_environment",
                MODULE.credential_presence("xai_api", None, process_env_only=True),
            )

    def test_edit_uses_multipart_image_array_and_exact_model(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            image = Path(directory) / "reference.png"
            image.write_bytes(b"fixture-image-bytes")
            context = {
                "prompt_text": "five exact lines",
                "attachments": [(image, {"order": 1})],
            }
            request = MODULE.openai_http_request({}, context, "mock-only-key")

        self.assertEqual("POST", request.method)
        self.assertEqual("https://api.openai.com/v1/images/edits", request.full_url)
        self.assertTrue(request.headers["Content-type"].startswith("multipart/form-data; boundary="))
        body = request.data
        self.assertIn(b'name="model"', body)
        self.assertIn(b"gpt-image-2", body)
        self.assertIn(b'name="image[]"', body)
        self.assertIn(b"fixture-image-bytes", body)
        self.assertNotIn(b"image_url", body)

    def test_generation_without_attachment_uses_json(self):
        request = MODULE.openai_http_request(
            {},
            {"prompt_text": "five exact lines", "attachments": []},
            "mock-only-key",
        )

        self.assertEqual("https://api.openai.com/v1/images/generations", request.full_url)
        self.assertEqual("application/json", request.headers["Content-type"])
        payload = json.loads(request.data.decode("utf-8"))
        self.assertEqual("gpt-image-2", payload["model"])
        self.assertEqual(1, payload["n"])
        self.assertNotIn("images", payload)

    def test_execution_receipt_contract_rejects_output_hash_tampering(self):
        image_bytes = b"mock-image-bytes-never-sent"
        request = {
            "packet_id": "PKT_BC01_ACTION",
            "mode": "official_branch",
            "cut_pointer": {"cut_id": "BC01_ACTION"},
            "execution": {
                "execution_adapter_id": "openai_api_gpt_image_2",
                "provider": "openai",
                "provider_model_or_tool": "gpt-image-2",
                "selected_native_tool": None,
                "auth_lane": "founder_approved_api",
                "provider_profile_id": "openai_image_api_current",
                "cli_or_api_version": "fixture-v1",
                "provider_profile_sha256": "2" * 64,
                "provider_capability_snapshot_sha256": "3" * 64,
            },
            "prompt": {"full_prompt_sha256": "4" * 64},
            "attachment_order_sha256": "5" * 64,
        }
        receipt = {
            "schema_version": "idol_image_generation_execution_receipt.v3",
            "artifact_type": "image_generation_execution_receipt",
            "status": "generated_pending_pixel_review",
            "external_call_performed": True,
            "request_path": "runs/test-only/request.yaml",
            "request_sha256": "6" * 64,
            "approval_path": "runs/test-only/approval.yaml",
            "approval_sha256": "7" * 64,
            "packet_id": request["packet_id"],
            "mode": request["mode"],
            "cut_id": request["cut_pointer"]["cut_id"],
            "execution_adapter_id": "openai_api_gpt_image_2",
            "provider": "openai",
            "provider_model_or_tool": "gpt-image-2",
            "selected_native_tool": None,
            "auth_lane": "founder_approved_api",
            "provider_profile_id": "openai_image_api_current",
            "runtime_version": "fixture-v1",
            "provider_profile_sha256": request["execution"]["provider_profile_sha256"],
            "provider_capability_snapshot_sha256": request["execution"]["provider_capability_snapshot_sha256"],
            "founder_generation_authority_id": "FOUNDER-GEN-AUTH-001",
            "spend_envelope": "one_image_only",
            "prompt_sha256": request["prompt"]["full_prompt_sha256"],
            "attachment_order_sha256": request["attachment_order_sha256"],
            "endpoint": "/v1/images/generations",
            "transport": "json",
            "response_image_encoding": "base64_json",
            "native_session_binding": None,
            "output_count": 1,
            "output_path": "runs/test-only/receipt-output.png",
            "output_sha256": MODULE.hashlib.sha256(image_bytes).hexdigest(),
            "automatic_fallback": "none",
            "prompt_rewrite_policy": "forbidden",
            "full_size_pixel_review_status": "pending",
            "03v_handoff_allowed": False,
            "secret_values_recorded": False,
        }

        provider = {
            "endpoint": "/v1/images/generations",
            "transport": "json",
            "response_image_encoding": "base64_json",
        }
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root = Path(directory)
            context = {
                "request_path": "runs/test-only/request.yaml",
                "request_sha256": "6" * 64,
                "approval_path": "runs/test-only/approval.yaml",
                "approval_sha256": "7" * 64,
                "founder_generation_authority_id": "FOUNDER-GEN-AUTH-001",
                "spend_envelope": "one_image_only",
                "output_path": fixture_root / "runs" / "test-only" / "receipt-output.png",
            }
            with mock.patch.object(MODULE, "ROOT", fixture_root):
                MODULE.validate_execution_receipt(receipt, request, context, image_bytes, provider)
                receipt["output_sha256"] = "f" * 64
                with self.assertRaisesRegex(MODULE.ExecutionError, "output_sha256 differs"):
                    MODULE.validate_execution_receipt(receipt, request, context, image_bytes, provider)

    def xai_profile_document(self):
        response_contract = {
            "image_encoding": "base64_json",
            "exact_output_count": 1,
            "items_json_pointer": "/data",
            "image_value_json_pointer": "/b64_json",
            "output_url_allowed_hosts": [],
        }
        return {
            "schema_version": "idol-xai-api-media-provider-profiles.v1",
            "status": "active",
            "provider": "xai_api",
            "runtime_surface": "xai_media_api",
            "profile_source_policy": {
                "exact_model_owner": "this_file",
                "exact_endpoint_owner": "this_file",
                "resolved_snapshot_required": True,
                "requested_observed_match_required": True,
                "silent_model_or_auth_fallback": "forbidden",
            },
            "profiles": {
                "xai_fixture_image_current": {
                    "exact_model": "fixture-xai-image-model",
                    "image_adapter_id": "xai_api_media",
                    "auth_lane": "founder_approved_api",
                    "api_version": "fixture-api-v1",
                    "api_base_url": "https://xai-fixture.invalid",
                    "authorization_scheme": "bearer",
                    "capability_status": "active",
                    "harness_status": "active",
                    "default_enabled": False,
                    "automatic_fallback": "none",
                    "unavailable_or_mismatch_action": "hold_and_report",
                    "operations": {
                        "image_gen": {
                            "endpoint_path": "/fixture/v1/images/generations",
                            "transport": "json",
                            "attachment_policy": "forbidden",
                            "request_contract": {
                                "model_field": "model",
                                "prompt_field": "prompt",
                                "output_count_field": "n",
                                "attachment_field": None,
                                "fixed_fields": {"quality": "fixture"},
                            },
                            "response_contract": dict(response_contract),
                        },
                        "image_edit": {
                            "endpoint_path": "/fixture/v1/images/edits",
                            "transport": "json_data_url_array",
                            "attachment_policy": "required_all_ordered",
                            "request_contract": {
                                "model_field": "model",
                                "prompt_field": "prompt",
                                "output_count_field": "n",
                                "attachment_field": "images",
                                "fixed_fields": {"quality": "fixture"},
                            },
                            "response_contract": dict(response_contract),
                        },
                    },
                }
            },
        }

    def registered_xai_fixture(self, directory: str, attachments):
        fixture_root = Path(directory)
        profile_path = fixture_root / "automation" / "providers" / "xai-fixture.json"
        profile_path.parent.mkdir(parents=True)
        profile_path.write_text(json.dumps(self.xai_profile_document()), encoding="utf-8")
        profile_sha256 = hashlib.sha256(profile_path.read_bytes()).hexdigest()
        registry_path = fixture_root / "automation" / "harness-provider-profile-registry.json"
        registry_path.write_text(
            json.dumps(
                {
                    "media_lanes": {
                        "xai_api_media": {
                            "provider": "xai",
                            "auth_lane": "founder_approved_api",
                            "capability_status": "active",
                            "harness_status": "active",
                            "registration_status": "registered_exact",
                            "provider_profile_id": "xai_fixture_image_current",
                            "provider_profile_source": "automation/providers/xai-fixture.json",
                            "provider_profile_source_sha256": profile_sha256,
                            "image_adapter_id": "xai_api_media",
                            "image_output_contract": "exact_expected_output_path_sha256_pixel_review",
                            "default_enabled": False,
                            "selection_only": False,
                            "automatic_fallback": "none",
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        registry_sha256 = hashlib.sha256(registry_path.read_bytes()).hexdigest()
        request = {
            "execution": {
                "execution_adapter_id": "xai_api_media",
                "provider": "xai_api",
                "provider_model_or_tool": "fixture-xai-image-model",
                "selected_native_tool": None,
                "auth_lane": "founder_approved_api",
                "provider_profile_id": "xai_fixture_image_current",
                "provider_profile_sha256": profile_sha256,
                "provider_capability_snapshot_sha256": registry_sha256,
                "cli_or_api_version": "fixture-api-v1",
            }
        }
        context = {"prompt_text": "five exact lines", "attachments": attachments}
        return fixture_root, registry_path, request, context

    def test_openai_existing_registered_lane_stays_exact(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root = Path(directory)
            profile_path = fixture_root / "automation" / "providers" / "openai-image-profiles.json"
            profile_path.parent.mkdir(parents=True)
            profile_path.write_text(
                json.dumps({"profiles": {"openai_image_api_current": {"exact_model": "gpt-image-2"}}}),
                encoding="utf-8",
            )
            profile_sha256 = hashlib.sha256(profile_path.read_bytes()).hexdigest()
            registry_path = fixture_root / "automation" / "harness-provider-profile-registry.json"
            registry_path.write_text(
                json.dumps(
                    {
                        "media_lanes": {
                            "openai_image_api_current": {
                                "image_adapter_id": "openai_api_gpt_image_2",
                                "provider_profile_source_sha256": profile_sha256,
                                "automatic_fallback": "none",
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            registry_sha256 = hashlib.sha256(registry_path.read_bytes()).hexdigest()
            request = {
                "execution": {
                    "execution_adapter_id": "openai_api_gpt_image_2",
                    "provider": "openai",
                    "provider_model_or_tool": "gpt-image-2",
                    "selected_native_tool": None,
                    "auth_lane": "founder_approved_api",
                    "provider_profile_id": "openai_image_api_current",
                    "provider_profile_sha256": profile_sha256,
                    "provider_capability_snapshot_sha256": registry_sha256,
                    "cli_or_api_version": "fixture-openai-v1",
                }
            }
            with mock.patch.object(MODULE, "PROVIDER_REGISTRY", registry_path), \
                 mock.patch.object(MODULE, "OPENAI_PROFILE", profile_path):
                provider = MODULE.validate_provider(request, {"attachments": []})
            self.assertEqual("openai", provider["provider"])
            self.assertEqual("/v1/images/generations", provider["endpoint"])
            self.assertEqual("json", provider["transport"])
            self.assertFalse(provider["selection_only"])

    def test_registered_xai_profile_exact_match_and_mocked_edit_transport(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            image_one = Path(directory) / "reference-one.png"
            image_two = Path(directory) / "reference-two.png"
            image_one.write_bytes(b"fixture-image-one")
            image_two.write_bytes(b"fixture-image-two")
            attachments = [(image_one, {"order": 1}), (image_two, {"order": 2})]
            fixture_root, registry_path, request, context = self.registered_xai_fixture(directory, attachments)
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.object(MODULE, "PROVIDER_REGISTRY", registry_path):
                provider = MODULE.validate_provider(request, context)
                http_request = MODULE.xai_http_request(request, context, "mock-only-key", provider)
                returned_bytes = b"fixture-output-image"
                response_body = json.dumps(
                    {"data": [{"b64_json": base64.b64encode(returned_bytes).decode("ascii")}]}
                ).encode("utf-8")
                with mock.patch.object(
                    MODULE,
                    "open_without_redirect",
                    return_value=FakeResponse(response_body, provider["url"]),
                ) as transport:
                    result = MODULE.perform_xai(request, context, "mock-only-key", provider)

                self.assertEqual("POST", http_request.method)
                self.assertEqual("https://xai-fixture.invalid/fixture/v1/images/edits", http_request.full_url)
                payload = json.loads(http_request.data.decode("utf-8"))
                self.assertEqual("fixture-xai-image-model", payload["model"])
                self.assertEqual(1, payload["n"])
                self.assertEqual(
                    [
                        "data:image/png;base64," + base64.b64encode(b"fixture-image-one").decode("ascii"),
                        "data:image/png;base64," + base64.b64encode(b"fixture-image-two").decode("ascii"),
                    ],
                    payload["images"],
                )
                self.assertEqual(returned_bytes, result)
                transport.assert_called_once()

    def test_registered_xai_profile_mismatch_holds_without_transport(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root, registry_path, request, context = self.registered_xai_fixture(directory, [])
            request["execution"]["provider_model_or_tool"] = "different-fixture-model"
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.object(MODULE, "PROVIDER_REGISTRY", registry_path), \
                 mock.patch.object(MODULE.urllib.request, "urlopen") as urlopen:
                with self.assertRaisesRegex(MODULE.ExecutionError, "differs from the exact registered"):
                    MODULE.validate_provider(request, context)
            urlopen.assert_not_called()

    def test_xai_selection_only_registry_holds_before_transport(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root, registry_path, request, context = self.registered_xai_fixture(directory, [])
            registry_path.write_text(
                json.dumps(
                    {
                        "media_lanes": {
                            "xai_api_media": {
                                "provider": "xai",
                                "auth_lane": "founder_approved_api",
                                "default_enabled": False,
                                "selection_only": True,
                                "automatic_fallback": "none",
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.object(MODULE, "PROVIDER_REGISTRY", registry_path), \
                 mock.patch.object(MODULE, "open_without_redirect") as transport:
                with self.assertRaisesRegex(MODULE.ExecutionError, "activation HOLD"):
                    MODULE.validate_provider(request, context)
            transport.assert_not_called()

    def test_xai_registration_required_registry_holds_before_transport(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root, registry_path, request, context = self.registered_xai_fixture(directory, [])
            registry_path.write_text(
                json.dumps(
                    {
                        "media_lanes": {
                            "xai_api_media": {
                                "provider": "xai",
                                "auth_lane": "founder_approved_api",
                                "capability_status": "registration_required",
                                "harness_status": "hold",
                                "registration_status": "registration_required",
                                "default_enabled": False,
                                "selection_only": False,
                                "automatic_fallback": "none",
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.object(MODULE, "PROVIDER_REGISTRY", registry_path), \
                 mock.patch.object(MODULE, "load_credential_for_confirmed_execute") as secret_loader, \
                 mock.patch.object(MODULE, "open_without_redirect") as transport:
                with self.assertRaisesRegex(MODULE.ExecutionError, "activation HOLD"):
                    MODULE.validate_provider(request, context)
            secret_loader.assert_not_called()
            transport.assert_not_called()

    def test_registered_xai_stale_profile_source_hash_holds_before_transport(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root, registry_path, request, context = self.registered_xai_fixture(directory, [])
            profile_path = fixture_root / "automation" / "providers" / "xai-fixture.json"
            profile_path.write_text(profile_path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.object(MODULE, "PROVIDER_REGISTRY", registry_path), \
                 mock.patch.object(MODULE, "open_without_redirect") as transport:
                with self.assertRaisesRegex(MODULE.ExecutionError, "source SHA-256 is stale"):
                    MODULE.validate_provider(request, context)
            transport.assert_not_called()

    def test_registered_xai_transport_failure_has_no_fallback(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fixture_root, registry_path, request, context = self.registered_xai_fixture(directory, [])
            with mock.patch.object(MODULE, "ROOT", fixture_root), \
                 mock.patch.object(MODULE, "PROVIDER_REGISTRY", registry_path):
                provider = MODULE.validate_provider(request, context)
                with mock.patch.object(
                    MODULE,
                    "open_without_redirect",
                    side_effect=MODULE.urllib.error.URLError("fixture transport unavailable"),
                ) as transport:
                    with self.assertRaisesRegex(MODULE.ExecutionError, "no fallback was attempted"):
                        MODULE.perform_xai(request, context, "mock-only-key", provider)
            transport.assert_called_once()


class ImageGenerationVersionBoundaryTest(unittest.TestCase):
    def load_schema(self, name: str):
        return json.loads((ROOT / "schemas" / name).read_text(encoding="utf-8"))

    def xai_model_rule(self, schema):
        return schema["$defs"]["execution"]["oneOf"][-1]["properties"]["provider_model_or_tool"]

    def test_active_authoring_successors_exclude_selection_only_legacy_shape(self):
        delta = self.load_schema("prompt-packet-delta.schema.json")
        packets = self.load_schema("prompt-packets.schema.json")
        request = self.load_schema("image-generation-request.schema.json")
        receipt = self.load_schema("image-generation-execution-receipt.schema.json")
        correction = self.load_schema("image-render-correction.schema.json")

        self.assertEqual("1.6", delta["properties"]["schema_version"]["const"])
        self.assertEqual("2.6", packets["properties"]["schema_version"]["const"])
        self.assertEqual("idol_image_generation_request.v12", request["properties"]["schema_version"]["const"])
        self.assertEqual("idol_image_generation_execution_receipt.v4", receipt["properties"]["schema_version"]["const"])
        self.assertEqual("idol_image_render_correction.v8", correction["properties"]["schema_version"]["const"])
        self.assertEqual(
            "idol_image_generation_request.v12",
            correction["properties"]["base_request"]["allOf"][1]["properties"]["schema_version"]["const"],
        )
        for schema in (delta, packets, request):
            self.assertEqual(
                "unregistered_selection_only",
                self.xai_model_rule(schema)["not"]["const"],
            )

    def test_legacy_readers_preserve_committed_selection_only_contracts(self):
        delta = self.load_schema("prompt-packet-delta-v1.3-legacy.schema.json")
        packets = self.load_schema("prompt-packets-v2.3-legacy.schema.json")
        request = self.load_schema("image-generation-request-v9-legacy.schema.json")
        receipt = self.load_schema("image-generation-execution-receipt-v1-legacy.schema.json")
        correction = self.load_schema("image-render-correction-v5-legacy.schema.json")

        self.assertEqual("1.3", delta["properties"]["schema_version"]["const"])
        self.assertEqual("2.3", packets["properties"]["schema_version"]["const"])
        self.assertEqual("idol_image_generation_request.v9", request["properties"]["schema_version"]["const"])
        self.assertEqual("idol_image_generation_execution_receipt.v1", receipt["properties"]["schema_version"]["const"])
        self.assertEqual("idol_image_render_correction.v5", correction["properties"]["schema_version"]["const"])
        self.assertEqual(
            "idol_image_generation_request.v9",
            correction["properties"]["base_request"]["allOf"][1]["properties"]["schema_version"]["const"],
        )
        for schema in (delta, packets, request):
            self.assertEqual("unregistered_selection_only", self.xai_model_rule(schema)["const"])
        self.assertEqual("openai_api_gpt_image_2", receipt["properties"]["execution_adapter_id"]["const"])


class ImageGenerationSecurityPolicyTest(unittest.TestCase):
    def test_direct_xai_credential_exception_is_exact_and_no_fallback(self):
        policy = " ".join(
            (ROOT / "policies" / "repository-media-security.md")
            .read_text(encoding="utf-8")
            .split()
        )
        for required in (
            "registered repository xAI API executor may load `XAI_API_KEY`",
            "only after it has revalidated the exact current-job Founder external/paid",
            "authority, request, provider-registry snapshot",
            "provider-owned profile source SHA-256",
            "follows a redirect",
            "falls back to Grok subscription, OpenAI, another xAI profile",
            "both remain separately Founder-gated for the exact job",
        ):
            self.assertIn(required, policy)


if __name__ == "__main__":
    unittest.main()
