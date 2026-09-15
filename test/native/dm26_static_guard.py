"""Supplementary integration guard; NOT a substitute for the Swift behavior run."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DM26WiringTests(unittest.TestCase):
    def test_no_reusable_id_terminal_cache(self):
        source = (ROOT / 'ios/Runner/DownloadNativeWaitingQueue.swift').read_text()
        self.assertFalse('supportedTerminalStatusesByTaskId' in source, 'reusable-ID status cache remains')
        self.assertIn('terminalObservation.capture(', source)

    def test_atomic_install_and_unavailable_promotion_gate(self):
        source = (ROOT / 'ios/Runner/DownloadNativeWaitingQueue.swift').read_text()
        self.assertFalse('Bundle(for: BDPlugin.self)' in source, 'framework version is not pub version')
        self.assertIn('installation.install(', source)
        self.assertIn('guard nativePromotionAvailable else { return }', source)
        self.assertNotIn('originalComplete != nil ||', source)


if __name__ == '__main__':
    unittest.main()
