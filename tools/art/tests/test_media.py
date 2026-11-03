# SPDX-License-Identifier: AGPL-3.0-or-later
"""Provenance from a render's stored metadata, and the pinned-model check.

No network: the media API is reachable only from Trevor's network."""

import io
import json
import unittest

from art import media

GRAPH = {
    "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_2512_fp8_e4m3fn.safetensors"}},
    "2": {"class_type": "LoraLoaderModelOnly", "inputs": {"lora_name": "Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors"}},
    "3": {"class_type": "KSampler", "inputs": {"seed": 1234, "steps": 8, "cfg": 1.0}},
    "4": {"class_type": "CLIPTextEncode", "inputs": {"text": "a red panda"}},
}
META = repr({"prompt": "a red panda", "mode": "image", "quality": "best", "shape": "square", "comfy_prompt": GRAPH})


class MediaTest(unittest.TestCase):
    def test_provenance_reads_model_lora_seed(self):
        rec = media.provenance(media.parse_meta(META))
        self.assertEqual(rec["models"], ["Qwen-Image-2512"])
        self.assertEqual(rec["loras"], ["Qwen-Image-2512-Lightning 8-step"])
        self.assertEqual(rec["seed"], 1234)
        self.assertEqual(rec["steps"], 8)
        self.assertEqual(rec["prompt"], "a red panda")
        self.assertEqual(media.check_pinned(rec), [])

    def test_unpinned_model_is_refused(self):
        graph = dict(GRAPH)
        graph["1"] = {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_2.1.safetensors"}}
        rec = media.provenance({"comfy_prompt": graph})
        self.assertIn("model qwen_image_2.1.safetensors is not pinned", media.check_pinned(rec))

    def test_missing_graph_is_refused(self):
        problems = media.check_pinned(media.provenance({"prompt": "x"}))
        self.assertIn("no model found in the render graph", problems)
        self.assertIn("no single seed in the render graph", problems)

    def test_graph_is_read_from_the_png_text_chunk(self):
        from PIL import Image, PngImagePlugin

        info = PngImagePlugin.PngInfo()
        info.add_text("prompt", json.dumps(GRAPH))
        buf = io.BytesIO()
        Image.new("RGB", (4, 4)).save(buf, "PNG", pnginfo=info)
        # The library meta carries only a job id; the PNG carries the graph.
        rec = media.provenance({"prompt": "a red panda", "comfy_prompt": "883d0909"}, media.graph_from_png(buf.getvalue()))
        self.assertEqual(rec["seed"], 1234)
        self.assertEqual(media.check_pinned(rec), [])
        self.assertEqual(media.graph_from_png(b"not a png"), {})

    def test_parse_meta_tolerates_json_and_junk(self):
        self.assertEqual(media.parse_meta('{"a": 1}'), {"a": 1})
        self.assertEqual(media.parse_meta("not a literal ("), {})
        self.assertEqual(media.parse_meta(None), {})

    def test_client_needs_its_environment(self):
        with self.assertRaises(media.MediaError):
            media.Client(url="", key="", user="")


if __name__ == "__main__":
    unittest.main()
