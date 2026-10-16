import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';



const base = new URL('../', import.meta.url);

const translations = {

  'HomeKMS': 'HomeKMS',

  'Provides KMS services for Microsoft volume-licensed products.': '为MS批量产品许可提供KMS服务',

  'Enable service': '启用服务',

  'Save & Apply starts or stops the service.': '保存并应用后启动或停止服务。',

  'TCP port': 'TCP 端口',

  'DNS auto-discovery': 'DNS 自动发现',

  'Disabled by default. Save & Apply publishes a DNS SRV record through system dnsmasq in the local DNS domain while the service is enabled. Compatible clients must use this router as their DNS server and search the same domain. When disabled or stopped, the HomeKMS discovery record is removed from system dnsmasq. If a DNS proxy or a separate DNS instance handles client queries, refresh its configuration after SRV record changes and verify that it serves the record. Otherwise, specify the HomeKMS address and port manually on clients. HomeKMS does not automatically refresh other DNS services.': '默认关闭。服务启用时，保存并应用会通过系统 dnsmasq 在本地 DNS 域中发布 DNS SRV 记录。兼容的客户端须使用本路由器作为 DNS 服务器，并在同一域中查询。关闭此选项或停止服务后，会从系统 dnsmasq 移除 HomeKMS 自动发现记录。若客户端查询由 DNS 代理或独立 DNS 实例处理，须在 SRV 记录变更后同步刷新其配置，并确认该实例能够返回记录；否则请在客户端手动指定 HomeKMS 地址和端口。HomeKMS 不会自动刷新其他 DNS 服务。',

  'Allow WAN access': '允许 WAN 访问',

  'Disabled by default. Exposes this service to the WAN zone.': '默认关闭。开启后允许 WAN 区域访问此服务。',

  'Running': '运行中',

  'Stopped': '已停止',

  'Unavailable': '状态不可用',

  'Start': '启动',

  'Stop': '停止',

  'Restart': '重启',

  'Service status': '服务状态',

  'Engine': '引擎',

  'py-kms 1.0.1 (embedded product database)': 'py-kms 1.0.1（内置产品数据库）',

  'These controls do not change the saved enable setting. Start requires the service to be enabled.': '这些操作不改变已保存的启用设置；启动前须先启用服务。',

  'Listening': '正在监听',

  'Not listening': '未监听',

  'PID-associated TCP listener': '主进程关联的 TCP 监听状态',

  'Recent HomeKMS logs': '最近的 HomeKMS 日志',

  'Latest snapshot: at most 50 lines and 16 KiB of UTF-8 text.': '最新日志快照：最多 50 行、16 KiB UTF-8 文本。',

  'Logs unavailable.': '日志不可用。',

  'No HomeKMS log entries.': '暂无 HomeKMS 日志。',

  'Older log content was truncated.': '较早的日志内容已截断。',

  'A listening socket is verified against the main service PID and configured port.': '监听状态依据服务主进程 PID 和已配置端口核验。',

  'Service operation failed. Check the configuration and system log.': '服务操作失败，请检查配置和系统日志。'

};

const js = readFileSync(new URL('htdocs/luci-static/resources/view/homekms.js', base), 'utf8');

const menu = JSON.parse(readFileSync(new URL('root/usr/share/luci/menu.d/luci-app-homekms.json', base), 'utf8'));

const ids = [...new Set([...js.matchAll(/_\('([^']*)'\)/g)].map(m => m[1]).concat(Object.values(menu).map(m => m.title)))].sort();

for (const id of ids) if (!translations[id]) throw new Error('Missing Chinese translation: ' + id);

const quote = JSON.stringify;

for (const [dir, language] of [['zh_Hans', 'zh_Hans'], ['templates', '']]) {

  mkdirSync(new URL('po/' + dir + '/', base), { recursive: true });

  const header = 'msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Language: ' + language + '\\n"\n';

  const entries = ids.map(id => 'msgid ' + quote(id) + '\nmsgstr ' + quote(language ? translations[id] : '') + '\n');

  const text = [header, ...entries].join('\n').replace(/\n/g, '\r\n');

  writeFileSync(new URL('po/' + dir + '/homekms.' + (language ? 'po' : 'pot'), base), Buffer.from(text));

}

console.log('Generated Chinese PO and POT for ' + ids.length + ' current view/menu messages (CRLF).');
