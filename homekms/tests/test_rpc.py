"""Run: python -m unittest discover -s homekms/tests -v"""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
import json

HELPER = Path(__file__).resolve().parents[1] / 'files/usr/libexec/rpcd/homekms'


class RpcTests(unittest.TestCase):
    def load_rpc(self):
        loader = importlib.machinery.SourceFileLoader('homekms_rpc', str(HELPER))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module

    def test_pid_owned_listen_only(self):
        rpc = self.load_rpc()
        table = ('  sl local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n'
                 '0: 00000000:0698 00000000:0000 0A 0:0 00:0 0 1000 0 123\n'
                 '1: 00000000:0698 00000000:0000 01 0:0 00:0 0 1000 0 124\n'
                 '2: 00000000:0698 00000000:0000 0A 0:0 00:0 0 1000 0 125\n')
        self.assertEqual(rpc.listener_rows(table, {'123', '124'}, 1688, 'tcp'),
                         [{'family': 'tcp', 'address': '00000000', 'port': 1688}])
        self.assertEqual(rpc.listener_rows(table, {'125'}, 1689, 'tcp'), [])

    def test_logs_are_bounded_and_service_only(self):
        rpc = self.load_rpc()
        raw = ('date daemon.info other[1]: secret\n' +
               ''.join('date daemon.info homekms[2]: %d %s\n' % (i, '中' * 300) for i in range(80)))
        result = rpc.bound_logs(raw.encode())
        self.assertLessEqual(len(result['text'].encode()), 16384)
        self.assertLessEqual(len(result['text'].splitlines()), 50)
        self.assertNotIn('secret', result['text'])
        self.assertIn('79 ', result['text'])
        self.assertTrue(result['truncated'])

    def test_logs_filters_message_before_formatted_header_and_limits_after_filter(self):
        rpc = self.load_rpc()
        from unittest.mock import patch
        import re
        # logread -e sees the message (no date/facility prefix), while -l
        # selects the last ring records BEFORE applying the expression.
        messages = ['homekms: RPC log verification', 'homekms[42]: PID record']
        messages += ['other[1]: unrelated secret'] * 100

        def logread(argv):
            self.assertEqual(argv[0], '/sbin/logread')
            selected = messages
            if '-l' in argv:
                selected = selected[-int(argv[argv.index('-l') + 1]):]
            pattern = argv[argv.index('-e') + 1]
            return ''.join('Fri Oct 16 21:48:52 2026 user.notice ' + message + '\n'
                           for message in selected if re.search(pattern, message)).encode()

        with patch.object(rpc, 'command', side_effect=logread) as command:
            result = rpc.logs()
        self.assertIn('RPC log verification', result['text'])
        self.assertIn('PID record', result['text'])
        self.assertNotIn('secret', result['text'])
        self.assertFalse(result['truncated'])
        self.assertTrue(result['available'])
        command.assert_called_once_with(['/sbin/logread', '-e', '^homekms'])

    def test_logs_exact_tags_and_post_filter_line_limit(self):
        rpc = self.load_rpc()
        from unittest.mock import patch
        records = ['date daemon.info homekms: record %d' % i for i in range(60)]
        records += ['date daemon.info homekms[42]: newest PID record']
        records += ['date daemon.info homekms-other: unrelated secret',
                    'date daemon.info homekms[bad]: unrelated secret'] * 100
        with patch.object(rpc, 'command', return_value=('\n'.join(records)).encode()):
            result = rpc.logs()
        self.assertEqual(len(result['text'].splitlines()), 50)
        self.assertEqual(result['text'].splitlines()[0], records[11])
        self.assertTrue(result['text'].endswith('newest PID record'))
        self.assertNotIn('secret', result['text'])
        self.assertTrue(result['truncated'])

    def test_logs_unavailable_on_command_failure(self):
        rpc = self.load_rpc()
        from unittest.mock import patch
        import subprocess
        for error in [OSError('missing'), subprocess.TimeoutExpired('/sbin/logread', 3),
                      subprocess.CalledProcessError(1, '/sbin/logread')]:
            with self.subTest(error=type(error).__name__), \
                 patch.object(rpc, 'command', side_effect=error):
                self.assertEqual(rpc.logs(), {'text': '', 'truncated': False, 'available': False})

    def test_status_uses_main_pid_and_config_port(self):
        rpc = self.load_rpc()
        from unittest.mock import patch
        service = {'homekms': {'instances': {'main': {'running': True, 'pid': 42}}}}
        with patch.object(rpc, 'command', side_effect=[json.dumps(service).encode(), b'1689\n']), \
             patch.object(rpc, 'owned_listeners', return_value=([{'family':'tcp','address':'00000000','port':1689}], True)) as owned:
            result = rpc.status()
        owned.assert_called_once_with(42, 1689)
        self.assertTrue(result['listening'])
        self.assertEqual(result['pid'], 42)

    def test_dispatch_rejects_parameters_and_unknown_methods(self):
        rpc = self.load_rpc()
        import io
        from unittest.mock import patch
        for args, body in [(['call', 'status'], '{"path":"/etc/shadow"}'),
                           (['call', 'exec'], '{}'), (['call', 'logs'], '[]')]:
            with patch.object(rpc.sys, 'argv', ['homekms'] + args), \
                 patch.object(rpc.sys, 'stdin', io.StringIO(body)):
                self.assertEqual(rpc.main(), 1)
        with patch.object(rpc.sys, 'argv', ['homekms','call','status']), \
             patch.object(rpc.sys, 'stdin', io.StringIO('{}')), \
             patch.object(rpc, 'status', return_value={'listening':False}), \
             patch.object(rpc.sys, 'stdout', io.StringIO()) as output:
            self.assertEqual(rpc.main(), 0)
            self.assertEqual(json.loads(output.getvalue()), {'listening':False})

    def test_stopped_and_invalid_config_fail_closed(self):
        rpc = self.load_rpc()
        from unittest.mock import patch
        with patch.object(rpc, 'command', side_effect=[b'{}', b'1688']), \
             patch.object(rpc, 'owned_listeners') as owned:
            result = rpc.status()
        self.assertFalse(result['running'])
        self.assertFalse(result['listening'])
        self.assertTrue(result['checked'])
        owned.assert_not_called()
        with patch.object(rpc, 'command', side_effect=[b'{}', b'1688;id']):
            self.assertEqual(rpc.status()['error'], 'invalid_port')

    def test_read_acl_grants_only_two_methods(self):
        acl = json.loads((HELPER.parents[2] / 'share/rpcd/acl.d/homekms-read.json').read_text())
        self.assertEqual(acl['homekms-read']['read'], {'ubus': {'homekms': ['status', 'logs']}})
        self.assertNotIn('write', acl['homekms-read'])

    def test_rpc_exposes_only_read_methods(self):
        self.assertTrue(HELPER.is_file(), 'read-only rpcd helper is missing')
        loader = importlib.machinery.SourceFileLoader('homekms_rpc', str(HELPER))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        self.assertEqual(module.METHODS, {'status': {}, 'logs': {}})


if __name__ == '__main__':
    unittest.main()
