"""Publication guard regressions use generated canaries, never live keys."""
import importlib.util
import struct
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('audit_public', Path(__file__).resolve().parents[1] / 'scripts/audit_public.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class PublicationTests(unittest.TestCase):
    def categories(self, path, data, mode='100644'):
        return {r['category'] for r in audit.scan(path, data, mode)}

    def test_credential_canary_is_redacted(self):
        canary = ('gh' + 'p_' + 'a1B2' * 10).encode()
        rows = audit.scan('Sources/accidental.txt', canary)
        self.assertIn('github-token', {r['category'] for r in rows})
        self.assertNotIn(canary.decode(), str(rows))

    def test_private_files_and_symlinks(self):
        for path in ['.env', 'Engine/Default/data', 'build/App.app/file', 'raw.xcresult/data', 'signing.p12']:
            self.assertIn('private-file-class', self.categories(path, b''))
        self.assertIn('symlink-or-non-file', self.categories('link', b'', '120000'))

    def test_paths_and_emails(self):
        self.assertIn('personal-path', self.categories('note.txt', ('/' + 'Users/' + 'person/document').encode()))
        self.assertIn('non-example-email', self.categories('note.txt', ('person' + '@' + 'private.invalid').encode()))
        self.assertEqual(set(), self.categories('note.txt', b'user@example.com'))

    def test_only_exact_synthetic_url_fixture_allowed(self):
        sample = b'https://' + b'user:secret@' + b'example.com/private'
        self.assertNotIn('embedded-url-credential', self.categories('Tests/WorkspaceTests.swift', sample))
        self.assertIn('embedded-url-credential', self.categories('Sources/example.swift', sample))
        other = b'https://' + b'other:canary@' + b'example.com/'
        self.assertIn('embedded-url-credential', self.categories('Tests/WorkspaceTests.swift', other))

    def test_image_metadata_and_unknown_binary(self):
        def chunk(kind, body=b''):
            return struct.pack('>I', len(body)) + kind + body + b'\0' * 4
        image = b'\x89PNG\r\n\x1a\n' + chunk(b'tEXt', b'Author=canary') + chunk(b'IEND')
        self.assertIn('image-metadata-or-unknown-chunk', self.categories('icon.png', image))
        self.assertIn('unreviewed-binary', self.categories('unknown.bin', b'\xff\xfe'))


if __name__ == '__main__':
    unittest.main()
