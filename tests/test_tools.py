#!/usr/bin/env python3
"""Unit tests for tools/gen_driconf.py and tools/winlator_presets.py (no network, no Mesa tree)."""
import importlib.util, json, pathlib, re, sys, tempfile, unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gen = load("gen_driconf")
presets = load("winlator_presets")

BASE_CONF = """<?xml version="1.0"?>
<driconf>
    <device driver="panvk">
        <engine engine_name_match="ANGLE">
            <option name="pan_enable_vertex_pipeline_stores_atomics" value="true" />
        </engine>
    </device>
</driconf>
"""


class GenDriconf(unittest.TestCase):
    def test_regex_is_case_insensitive_and_anchored(self):
        rx = gen.exe_regex("Hollow Knight Silksong.exe")
        for name in ["Hollow Knight Silksong.exe", "HOLLOW KNIGHT SILKSONG.EXE"]:
            self.assertTrue(re.fullmatch(rx.strip("^$"), name) and re.search(rx, name))
        self.assertIsNone(re.search(rx, "Hollow Knight Silksong.exe.bak"))
        self.assertIsNone(re.search(gen.exe_regex("a.exe"), "abexe"))
        # No backslashes: Mesa embeds the regex in a C string literal on Android.
        self.assertNotIn("\\", gen.exe_regex("a (x+y).exe"))
        self.assertTrue(re.search(gen.exe_regex("a (x+y).exe"), "A (X+Y).exe"))

    def test_output_keeps_base_entries_and_adds_apps(self):
        data = {"groups": [{"id": "g", "title": "t", "options": {"pan_env_defaults": "PANVK_HEAP_MAX_MB=2048"},
                            "apps": [{"name": "A & B", "exe": "a(b).exe"}]}]}
        root = ET.fromstring(gen.generate(BASE_CONF, data))
        dev = root.find("device")
        self.assertEqual(dev.get("driver"), "panvk")
        self.assertIsNotNone(dev.find("engine"))
        app = dev.find("application")
        self.assertEqual(app.get("name"), "A & B")
        self.assertTrue(re.search(app.get("application_name_match"), "A(B).EXE"))
        self.assertEqual(app.find("option").get("value"), "PANVK_HEAP_MAX_MB=2048")

    def test_unknown_option_rejected(self):
        data = {"groups": [{"id": "g", "title": "t", "options": {"bogus": "1"}, "apps": []}]}
        with self.assertRaises(SystemExit):
            gen.generate(BASE_CONF, data)

    def test_committed_profiles_are_valid(self):
        data = json.loads((ROOT / "compat" / "game-profiles.json").read_text())
        ET.fromstring(gen.generate(BASE_CONF, data))
        for g in data["groups"]:
            self.assertTrue(g.get("evidence"), f"{g['id']} needs an evidence line")
            for v in g["options"].get("pan_env_defaults", "").split(";"):
                if v:
                    k = v.split("=", 1)[0]
                    self.assertTrue(k.startswith(("PANVK_", "MESA_")) and k != "PANVK_DEBUG", k)


def cfg(gpu, ts, screen="1600x720", env="WINEESYNC=1 WRAPPER_NO_PATCH_OPCONSTCOMP=1 BCN_TRANSCODE_TO_ASTC=1"):
    return {
        "meta": {"game_name": "Game", "notes": "", "timestamp": ts, "device": {"gpu": gpu}},
        "container": {"graphicsDriver": "wrapper-leegao", "screenSize": screen, "envVars": env,
                      "graphicsDriverConfig": "gpuName=X;version=System;bcnEmulation=full;bcnEnabled=1;maxDeviceMemory=4096",
                      "dxwrapperConfig": "version=2.4.1,vkd3dVersion=2.14.1"},
        "shortcut": {"path": "C:\\\\Games\\\\game.exe",
                     "extraData": {"graphicsDriverConfig": "version=System;bcnEmulation=auto", "screenSize": screen}},
    }


class Presets(unittest.TestCase):
    def run_tool(self, configs):
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            for i, (game, c) in enumerate(configs):
                (d / "configs" / game).mkdir(parents=True, exist_ok=True)
                (d / "configs" / game / f"c{i}.json").write_text(json.dumps(c))
            out = d / "out"
            sys.argv = ["x", "--configs", str(d), "--driver-name", "PKG", "--out", str(out)]
            presets.main()
            return ({p.stem: json.loads(p.read_text()) for p in out.glob("*.json") if p.stem != "index"},
                    json.loads((out / "index.json").read_text()))

    def test_prefers_mc2_and_rewrites_driver_settings(self):
        res, index = self.run_tool([("game", cfg("Mali-G615 MC6", 200)), ("game", cfg("Mali-G615 MC2", 100))])
        c = res["game"]["container"]
        self.assertTrue(index[0]["fromMc2"])
        self.assertEqual(c["screenSize"], "1600x720")          # MC2 config: resolution untouched
        gdc = presets.parse_kv(c["graphicsDriverConfig"], ";")
        self.assertEqual((gdc["version"], gdc["bcnEmulation"], gdc["bcnEnabled"], gdc["maxDeviceMemory"]),
                         ("PKG", "none", "0", "0"))
        self.assertEqual(c["envVars"], "WINEESYNC=1")
        sgdc = presets.parse_kv(res["game"]["shortcut"]["extraData"]["graphicsDriverConfig"], ";")
        self.assertEqual(sgdc["version"], "PKG")

    def test_mc6_config_is_scaled_down(self):
        res, index = self.run_tool([("game", cfg("Mali-G615 MC6", 1, screen="1920x1080"))])
        self.assertFalse(index[0]["fromMc2"])
        self.assertEqual(res["game"]["container"]["screenSize"], "1280x720")
        self.assertEqual(res["game"]["shortcut"]["extraData"]["screenSize"], "1280x720")

    def test_non_g615_ignored(self):
        res, index = self.run_tool([("other", cfg("Mali-G57 MC2", 1)), ("game", cfg("Mali-G615 MC2", 1))])
        self.assertEqual(sorted(res), ["game"])


if __name__ == "__main__":
    unittest.main()
