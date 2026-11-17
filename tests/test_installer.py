"""Local, non-destructive checks. Real templates are optional private fixtures."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'install.sh').read_text()
HTML_CODE = SOURCE.split('customize_html() {', 1)[1].split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]


def shell(code, env=None):
    return subprocess.run(['bash', '-c', f'source {shlex.quote(str(ROOT / "install.sh"))}\n' + code],
                          text=True, capture_output=True, env=env, check=True)


def customize(path, index, enabled=1, palette=4321):
    # Predictable choices only in the test process; production uses secrets.
    return subprocess.run(['python3', '-c',
        'import secrets\n'
        f'secrets.randbelow=lambda n:{palette}\n' + HTML_CODE,
        str(path), str(index), str(enabled)], text=True, capture_output=True)


class InstallerTests(unittest.TestCase):
    def test_syntax_and_embedded_python(self):
        subprocess.run(['bash', '-n', str(ROOT / 'install.sh')], check=True)
        for code in re.findall(r"<<'([A-Z]+)'\n(.*?)\n\1\n", SOURCE, re.S):
            if code[0] in ('PY', 'PROFILE'):
                compile(code[1], '<embedded>', 'exec')

    def test_acme_install_arguments_and_output_validation(self):
        with tempfile.TemporaryDirectory() as d:
            result = shell("""
ROOT=$TEST_ROOT; TMP=$TEST_ROOT/tmp; mkdir "$TMP"
curl() {
  cat > "$TMP/acme-install.sh" <<'FAKE'
#!/bin/sh
[ "$1" = --install-online ] || exit 41
shift
[ "$1" = --home ] || exit 42
acme_test_home=$2
shift 2
[ "$1" = --config-home ] && [ "$2" = "$acme_test_home" ] || exit 43
shift 2
[ "$1" = --nocron ] && [ "$2" = --noprofile ] || exit 44
printf '#!/bin/sh\\n[ "$1" = --version ]\\n' > "$acme_test_home/acme.sh"
chmod 700 "$acme_test_home/acme.sh"
FAKE
}
install_acme
printf 'ok'
""", dict(os.environ, TEST_ROOT=d))
            self.assertEqual(result.stdout, 'ok')

    def test_acme_installer_failure_and_missing_output_stop_immediately(self):
        for installer in ('exit 42', 'exit 0'):
            with self.subTest(installer=installer), tempfile.TemporaryDirectory() as d:
                code = f"""
source {shlex.quote(str(ROOT / 'install.sh'))}
ROOT=$TEST_ROOT; TMP=$TEST_ROOT/tmp; mkdir "$TMP"
curl() {{ printf '%s\\n' {shlex.quote(installer)} > "$TMP/acme-install.sh"; }}
install_acme
printf 'SHOULD_NOT_CONTINUE'
"""
                result = subprocess.run(['bash', '-c', code], text=True, capture_output=True,
                                        env=dict(os.environ, TEST_ROOT=d))
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('SHOULD_NOT_CONTINUE', result.stdout)
                self.assertNotIn('No such file or directory', result.stderr)

    def test_domain_validation(self):
        shell('''
for domain in node.example.com xn--e1afmkfd.xn--p1ai; do valid_domain "$domain"; done
for domain in '-bad.example' 'a..example' 'https://a.example' 'a.example/path' '1.2.3.4' 'a.example.'; do
  if valid_domain "$domain"; then exit 1; fi
done
''')

    def test_html_validation_and_no_randomization(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'index.html'
            p.write_text('{"error":"license"}')
            self.assertNotEqual(customize(p, 0).returncode, 0)
            original = '<html><head><title>Формат</title></head><body>Формат</body></html>'
            p.write_text(original)
            self.assertEqual(customize(p, 2, 0).returncode, 0)
            self.assertEqual(p.read_text(), original)

    def test_brand_and_palette_do_not_change_urls_or_scripts(self):
        original = '''<html><head><title>Формат — конвертер</title>
<style>:root{--acc:#3b5bfd;--text:#000;--bg:#fff}.a{background:rgba(30,80,230,.2)}</style>
</head><body><a href="https://example.com/#aabbcc">Формат</a><p>Формат для файла</p>
<script>const text='Формат';const color='#3b5bfd';</script></body></html>'''
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'index.html'; p.write_text(original)
            result = customize(p, 2)
            self.assertEqual(result.returncode, 0, result.stderr)
            changed = p.read_text()
            self.assertIn('<title>Формат — конвертер</title>', changed)
            self.assertIn('>Формат</a>', changed)
            self.assertIn('Формат для файла', changed)
            self.assertIn('href="https://example.com/#aabbcc"', changed)
            self.assertEqual(re.findall(r'<script>.*?</script>', original), re.findall(r'<script>.*?</script>', changed))
            self.assertNotIn('--acc:#3b5bfd', changed)

    def test_compose_escapes_secret_and_uses_host_network(self):
        with tempfile.TemporaryDirectory() as d:
            env = dict(os.environ, TEST_NODE=d, TEST_SECRET='a$VAR ${HOME} "quote" \\ colon: #value')
            shell('''
NODE=$TEST_NODE; NODE_PORT=2222; SECRET_KEY=$TEST_SECRET
docker() { [[ $* == *'config --quiet' ]]; }
write_compose
''', env)
            p = Path(d) / 'docker-compose.yml'
            service = json.loads(p.read_text())['services']['remnanode']
            self.assertEqual(service['environment']['SECRET_KEY'].replace('$$', '$'), env['TEST_SECRET'])
            self.assertEqual(service['network_mode'], 'host')
            self.assertEqual(service['environment']['NODE_PORT'], '2222')
            self.assertEqual(p.stat().st_mode & 0o777, 0o600)

    def test_firewall_order_and_restricted_node(self):
        result = shell('''
NODE_PORT=2222; PANEL_IPS=(203.0.113.8 2001:db8::8); SSH_PORTS=22
ufw() { printf '%s\\n' "$*"; }
firewall
''')
        lines = result.stdout.splitlines()
        self.assertIn('prepend deny proto tcp from any to any port 2222', lines[0])
        self.assertEqual(sum('allow proto tcp from' in x for x in lines), 2)
        self.assertFalse(any('allow 2222/tcp' in x for x in lines))
        self.assertIn('prepend allow 443/udp comment onehub-hy2-hysteria', lines)
        self.assertEqual(lines[-1], '--force enable')

    def test_empty_firewall_accepts_first_rule(self):
        result = shell('''
rule_count=0
ufw() {
  if [[ $1 == insert && $rule_count == 0 ]]; then
    printf "ERROR: Invalid position '1'\\n" >&2
    return 1
  fi
  [[ $1 == prepend ]] || return 1
  rule_count=$((rule_count+1))
}
add_rule deny proto tcp from any to any port 2222 comment onehub-hy2-node-deny
add_rule allow proto tcp from 203.0.113.8 to any port 2222 comment onehub-hy2-panel
add_rule allow proto tcp from 2001:db8::8 to any port 2222 comment onehub-hy2-panel
[[ $rule_count == 3 ]]
printf 'ok'
''')
        self.assertEqual(result.stdout, 'ok')

    def test_cleanup_only_owned_firewall_rules_when_inactive(self):
        result = shell('''
ufw() {
  if [[ $* == 'show added' ]]; then
    printf "%s\\n" "ufw allow 22/tcp" "ufw allow 80/tcp comment 'onehub-hy2-http'" "ufw deny 2222/tcp comment 'onehub-hy2-node-deny'" "ufw allow 9000/tcp comment 'another-service'"
  else printf '%s\\n' "$*"; fi
}
remove_rules
''')
        self.assertEqual(result.stdout.splitlines(), [
            '--force delete deny 2222/tcp comment onehub-hy2-node-deny',
            '--force delete allow 80/tcp comment onehub-hy2-http'])

    def test_cleanup_restores_existing_firewall_comment(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'ufw-before.txt').write_text("ufw allow 80/tcp comment 'old website'\nufw allow 443/tcp\n")
            result = shell("""
ROOT=$TEST_ROOT
ufw() {
  if [[ $* == 'show added' ]]; then
    printf '%s\\n' "ufw allow 80/tcp comment 'onehub-hy2-http'" "ufw allow 443/tcp comment 'onehub-hy2-https'"
  else printf '<%s>' "$@"; printf '\\n'; fi
}
remove_rules
""", dict(os.environ, TEST_ROOT=d))
            self.assertEqual(result.stdout.splitlines(), [
                '<allow><443/tcp><comment><>', '<allow><80/tcp><comment><old website>'])

    def test_palette_pool_size_and_luminance(self):
        # Execute the actual transformation once, then inspect its color functions.
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'index.html'
            p.write_text('<html><title>503</title><style>.x{color:#3b5bfd}</style><footer>503</footer></html>')
            code = '''
import sys,secrets
secrets.randbelow=lambda n:1234
''' + HTML_CODE + '''
variants=set()
for n in range(10000):
    shift=(n+1)/10001
    variants.add(css("#3b5bfd #e8890c"))
assert len(variants)==10000, len(variants)
for sample in ((.2,.4,.9),(.8,.1,.2),(.1,.8,.6)):
    assert abs(luminance(sample)-luminance(rotate(sample)))<1e-6
'''
            result = subprocess.run(['python3', '-c', code, str(p), '0', '1'], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_real_templates_if_available(self):
        fixtures = Path(os.environ.get('HY2_TEST_TEMPLATES', '/tmp/hy2-templates'))
        if not all((fixtures / f'{i}.html').is_file() for i in range(1, 11)):
            self.skipTest('Set HY2_TEST_TEMPLATES to downloaded HTML fixtures')
        with tempfile.TemporaryDirectory() as d:
            for i in range(10):
                with self.subTest(template=i + 1):
                    original = (fixtures / f'{i+1}.html').read_text()
                    p = Path(d) / f'{i}.html'; p.write_text(original)
                    result = customize(p, i)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    changed = p.read_text()
                    self.assertEqual(re.findall('<title>(.*?)</title>', original, re.S), re.findall('<title>(.*?)</title>', changed, re.S))
                    old_styles = re.findall(r'<style[^>]*>(.*?)</style>', original, re.S)
                    self.assertNotEqual(old_styles, re.findall(r'<style[^>]*>(.*?)</style>', changed, re.S))
                    self.assertEqual(re.findall(r'(?:src|href)="([^"]*)"', original),
                                     re.findall(r'(?:src|href)="([^"]*)"', changed))
                    self.assertEqual(re.findall(r'<script[^>]*>(.*?)</script>', original, re.S),
                                     re.findall(r'<script[^>]*>(.*?)</script>', changed, re.S))


if __name__ == '__main__':
    unittest.main()
