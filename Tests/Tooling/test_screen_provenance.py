import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "provenance", Path(__file__).resolve().parents[2] / "bin/lib/screen-provenance.py")
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)


class ScreenProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        original = provenance.ROOT
        self.addCleanup(setattr, provenance, "ROOT", original)
        provenance.ROOT = Path(self.directory.name)
        self.files = ["Preferans/View.swift", "Preferans/Resources/Localizable.xcstrings",
                      "Sources/PreferansEngine/Rules.swift", "PreferansUITests/Flow.swift",
                      "Preferans.xcodeproj/project.pbxproj", "Package.swift", "Package.resolved"]
        for name in self.files:
            p = provenance.ROOT / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("original")
        self.record = provenance.ROOT / "capture.json"
        self.record.write_text(json.dumps(provenance.source_manifest()))

    def check(self):
        with contextlib.redirect_stderr(io.StringIO()):
            return provenance.check(self.record)

    def testEachInputInvalidatesCaptureEvenWithPreservedModificationTime(self):
        for name in self.files:
            with self.subTest(name=name):
                p = provenance.ROOT / name
                old = p.stat()
                p.write_text("changed")
                os.utime(p, ns=(old.st_atime_ns, old.st_mtime_ns))
                self.assertFalse(self.check())
                p.write_text("original")
                self.assertTrue(self.check())

    def testNewOrRemovedSourceInvalidatesCapture(self):
        p = provenance.ROOT / "Preferans/NewScreen.swift"
        p.write_text("new")
        self.assertFalse(self.check())
        p.unlink()
        self.assertTrue(self.check())
        (provenance.ROOT / self.files[0]).unlink()
        self.assertFalse(self.check())

    def testFreshTimestampsAloneCannotChangeProvenance(self):
        for name in self.files:
            os.utime(provenance.ROOT / name, None)
        self.assertTrue(self.check())
        self.record.unlink()
        self.assertFalse(self.check())


if __name__ == "__main__":
    unittest.main()
