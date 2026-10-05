// Copyright 2026
// SPDX-License-Identifier: GPL-3.0-or-later
import { opendir, realpath, stat, lstat, popen, basename } from 'fs';

const MAX_ENTRIES = 256;
const MAX_CERTIFICATES = 32;
const MAX_FILE_SIZE = 65536;

function path_ok(path) {
	return type(path) == 'string' && length(path) < 1024 &&
		match(path, /^\/[A-Za-z0-9_.*\/-]+$/) &&
		!match(path, /(^|\/)\.\.?(\/|$)/);
}

function date_value(value) {
	let m = match(value || '', /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})Z$/);
	return m ? timegm({ year: +m[1], mon: +m[2], mday: +m[3], hour: +m[4], min: +m[5], sec: +m[6] }) : null;
}

function metadata(path) {
	let result = { status: 'parse_error', algorithm: '', bits: 0, curve: '', sans: [], issuer: '', not_before: null, not_after: null };
	let info = stat(path);
	if (!info || info.type != 'file' || info.size > MAX_FILE_SIZE || !path_ok(path))
		return result;

	// No client-supplied paths or options. The pathname alphabet excludes shell
	// syntax; quotes also prevent wildcard expansion. Only public certificates
	// are parsed, never private keys, combined files or acme.sh configuration.
	let command = "/usr/bin/timeout -k 1 1 /usr/bin/openssl x509 -in '" + path +
		"' -noout -text -issuer -dates -nameopt RFC2253 -dateopt iso_8601 2>/dev/null";
	let pipe = popen(command, 'r');
	if (!pipe)
		return result;
	let text = pipe.read(MAX_FILE_SIZE + 1) || '';
	let code = pipe.close();
	if (code != 0 || length(text) > MAX_FILE_SIZE)
		return result;

	let m = match(text, /Public Key Algorithm:\s*([^\n]+)/);
	result.algorithm = m ? (trim(m[1]) == 'rsaEncryption' ? 'RSA' : (trim(m[1]) == 'id-ecPublicKey' ? 'EC' : trim(m[1]))) : '';
	m = match(text, /Public-Key:\s*\((\d+) bit\)/);
	result.bits = m ? +m[1] : 0;
	m = match(text, /ASN1 OID:\s*([^\n]+)/);
	result.curve = m ? trim(m[1]) : '';
	m = match(text, /X509v3 Subject Alternative Name:[^\n]*\n\s*([^\n]+)/);
	if (m)
		for (let entry in split(m[1], ','))
			if (length(result.sans) < 100)
				push(result.sans, match(trim(entry), /^DNS:/) ? substr(trim(entry), 4) : trim(entry));
	m = match(text, /\nissuer=([^\n]*)/);
	result.issuer = m ? trim(m[1]) : '';
	m = match(text, /\nnotBefore=([^\n]*)/);
	result.not_before = date_value(m ? m[1] : null);
	m = match(text, /\nnotAfter=([^\n]*)/);
	result.not_after = date_value(m ? m[1] : null);
	if (result.algorithm && result.not_before != null && result.not_after != null)
		result.status = time() < result.not_before ? 'not_yet_valid' : (time() > result.not_after ? 'expired' : 'valid');
	return result;
}

function excluded(name) {
	return !match(name, /^[A-Za-z0-9*][A-Za-z0-9.*_-]*$/) ||
		match(name, /^(accounts|ca|private)$/) || match(name, /^failed-/) ||
		match(name, /(^|[._-])staging([._-]|$)/);
}

function public_path(path) {
	return path_ok(path) && !match(path, /\/(private|accounts|ca)\//) &&
		!match(path, /\/failed-[^/]*\//) && !match(path, /[\/._-]staging([\/._-]|$)/) &&
		!match(basename(path), /^(combined|key)\./) && match(path, /\.(cer|crt|pem)$/);
}

export function inventory(state_dir, configs, export_dir) {
	let result = { certificates: [], truncated: false };
	let rows = {}, directories = {};
	let root = path_ok(state_dir) && state_dir != '/' ? (realpath(state_dir) || replace(state_dir, /\/+$/, '')) : null;
	let started = time(), scanned = 0;

	function budget() {
		if (length(result.certificates) >= MAX_CERTIFICATES || time() - started >= 3) {
			result.truncated = true;
			return false;
		}
		return true;
	}

	function add(path, directory, layout) {
		let canonical = realpath(path);
		let id = canonical || path;
		if (rows[id])
			return rows[id];
		if (!budget() || !public_path(id))
			return null;
		let row = canonical ? metadata(canonical) : { status: 'missing', algorithm: '', bits: 0, curve: '', sans: [], issuer: '', not_before: null, not_after: null };
		row.id = id;
		row.certificate = id;
		row.configurations = [];
		row.exports = [];
		row.layout = layout;
		let domain = directory ? replace(basename(directory), /_ecc$/, '') : '';
		let key_path = layout == 'uacme' ? root + '/private/' + domain + '/key.pem' :
			(layout == 'acmesh' ? directory + '/' + domain + '.key' : replace(path, /\.fullchain\.crt$/, '.key'));
		row.private_key_present = stat(key_path)?.type == 'file';
		row.fullchain_present = (match(basename(id), /^(fullchain\.cer|cert\.pem)$/) || match(path, /\.fullchain\.crt$/)) && stat(id)?.type == 'file' ? true : false;
		rows[id] = row;
		push(result.certificates, row);
		if (directory)
			directories[directory] = row;
		return row;
	}

	function scan(path, callback) {
		let dir = path_ok(path) ? opendir(path) : null;
		if (!dir)
			return;
		for (let name = dir.read(); name != null; name = dir.read()) {
			if (++scanned > MAX_ENTRIES || !budget()) {
				result.truncated = true;
				break;
			}
			if (!excluded(name))
				callback(name);
		}
		dir.close();
	}

	if (root && root != '/' && path_ok(root)) {
		scan(root, (name) => {
			let directory = realpath(root + '/' + name);
			if (!directory || index(directory, root + '/') != 0 || stat(directory)?.type != 'directory')
				return;
			let domain = replace(name, /_ecc$/, '');
			for (let filename in ['fullchain.cer', domain + '.cer', 'cert.pem', 'leaf_cert.pem']) {
				let path = directory + '/' + filename;
				if (lstat(path)) {
					let canonical = realpath(path);
					if (canonical && index(canonical, root + '/') != 0)
						continue;
					add(path, directory, match(filename, /\.pem$/) ? 'uacme' : 'acmesh');
					break;
				}
			}
		});
	}

	// Export entries describe filesystem aliases, not active service usage.
	scan(export_dir, (name) => {
		if (!match(name, /\.fullchain\.crt$/))
			return;
		let path = export_dir + '/' + name;
		let canonical = realpath(path);
		let row = canonical ? rows[canonical] : null;
		if (!row)
			row = add(path, null, 'export');
		if (row)
			push(row.exports, path);
	});

	for (let i = 0; i < length(configs) && i < MAX_ENTRIES; i++) {
		let config = configs[i];
		let domain = type(config.domains) == 'array' ? config.domains[0] : config.domains;
		if (type(domain) != 'string' || length(domain) > 253 || excluded(domain) || !root)
			continue;
		let key = config.key_type || 'ec256';
		let directory = root + '/' + domain + (match(key, /^ec/) ? '_ecc' : '');
		let row = directories[directory];
		let uacme = directories[root + '/' + domain];
		if (uacme?.layout == 'uacme')
			row = uacme;
		if (!row)
			row = add(directory + '/fullchain.cer', directory, 'acmesh');
		if (row && index(row.configurations, config.name) < 0)
			push(row.configurations, config.name);
	}
	if (length(configs) > MAX_ENTRIES)
		result.truncated = true;
	return result;
}
