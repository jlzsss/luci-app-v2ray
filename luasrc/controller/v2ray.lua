-- Copyright 2019-2020 Xingwang Liao <kuoruan@gmail.com>
-- Licensed to the public under the MIT License.

local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local fs = require "nixio.fs"
local v2ray = require "luci.model.v2ray"
local i18n = require "luci.i18n"
local util = require "luci.util"

module("luci.controller.v2ray", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/v2ray") then
		return
	end

	entry({"admin", "services", "v2ray"},
		firstchild(), _("V2Ray")).dependent = false

	entry({"admin", "services", "v2ray", "global"},
		cbi("v2ray/main"), _("Global Settings"), 1)

	entry({"admin", "services", "v2ray", "inbounds"},
		arcombine(cbi("v2ray/inbound-list"), cbi("v2ray/inbound-detail")),
		_("Inbound"), 2).leaf = true

	entry({"admin", "services", "v2ray", "outbounds"},
		arcombine(cbi("v2ray/outbound-list"), cbi("v2ray/outbound-detail")),
		_("Outbound"), 3).leaf = true

	entry({"admin", "services", "v2ray", "dns"},
		cbi("v2ray/dns"), _("DNS"), 4)

	entry({"admin", "services", "v2ray", "routing"},
		arcombine(cbi("v2ray/routing"), cbi("v2ray/routing-rule-detail")),
		_("Routing"), 5)

	entry({"admin", "services", "v2ray", "policy"},
		arcombine(cbi("v2ray/policy"), cbi("v2ray/policy-level-detail")),
		_("Policy"), 6)

	entry({"admin", "services", "v2ray", "reverse"},
		cbi("v2ray/reverse"), _("Reverse"), 7)

	entry({"admin", "services", "v2ray", "transparent-proxy"},
		cbi("v2ray/transparent-proxy"), _("Transparent Proxy"), 8)

	entry({"admin", "services", "v2ray", "about"},
		form("v2ray/about"), _("About"), 9)

	entry({"admin", "services", "v2ray", "routing", "rules"},
		cbi("v2ray/routing-rule-detail")).leaf = true

	entry({"admin", "services", "v2ray", "policy", "levels"},
		cbi("v2ray/policy-level-detail")).leaf = true

	entry({"admin", "services", "v2ray", "status"}, call("action_status"))

	entry({"admin", "services", "v2ray", "version"}, call("action_version"))

	entry({"admin", "services", "v2ray", "list-status"},
		call("list_status")).leaf = true

	entry({"admin", "services", "v2ray", "list-update"}, call("list_update"))

	entry({"admin", "services", "v2ray", "import-outbound"}, call("import_outbound"))
end

function action_status()
	local running = false

	local pid = util.trim(fs.readfile("/var/run/v2ray.main.pid") or "")

	if pid ~= "" then
		local file = uci:get("v2ray", "main", "v2ray_file") or ""
		if file ~= "" then
			local file_name = fs.basename(file)
			running = sys.call("pidof %s 2>/dev/null | grep -q %s" % { file_name, pid }) == 0
		end
	end

	http.prepare_content("application/json")
	http.write_json({
		running = running
	})
end

function action_version()
	local file = uci:get("v2ray", "main", "v2ray_file") or ""

	local info

	if file == "" or not fs.stat(file) then
		info = {
			valid = false,
			message = i18n.translate("Invalid V2Ray file")
		}
	else
		if not fs.access(file, "rwx", "rx", "rx") then
			fs.chmod(file, 755)
		end

		local version = util.trim(sys.exec("%s version 2>/dev/null | head -n1" % file))

		if version ~= "" then
			info = {
				valid = true,
				version = version
			}
		else
			info = {
				valid = false,
				message = i18n.translate("Can't get V2Ray version")
			}
		end
	end

	http.prepare_content("application/json")
	http.write_json(info)
end

function list_status(type)
	if type == "chnroute" then
		http.prepare_content("application/json")
		http.write_json(v2ray.get_routelist_status())
	elseif type == "gfwlist" then
		http.prepare_content("application/json")
		http.write_json(v2ray.get_gfwlist_status())
	else
		http.status(500, "Bad address")
	end
end

function list_update()
	local type = http.formvalue("type")

	if type == "chnroute" then
		local chnroute_result, chnroute6_result = v2ray.generate_routelist()
		http.prepare_content("application/json")
		http.write_json({
			chnroute = chnroute_result,
			chnroute6 = chnroute6_result
		})
	elseif type == "gfwlist" then
		local result = v2ray.generate_gfwlist()
		http.prepare_content("application/json")
		http.write_json({
			gfwlist = result
		})
	else
		http.status(500, "Bad address")
	end
end

function import_outbound()
	local link = http.formvalue("link")

	local objs = v2ray.parse_vmess_links(link or "")

	if not objs or #objs == 0 then
		http.prepare_content("application/json")
		http.write_json({
			success = false,
			message = i18n.translate("Invalid link")
		})
		return
	end

	for i=1, #objs do
		local obj = objs[i]
		if not obj or not next(obj) then
			http.prepare_content("application/json")
			http.write_json({
				success = false,
				message = i18n.translate("Invalid link")
			})
			return
		end
	end

	local outbounds = uci:get_list("v2ray", "main", "outbounds") or {}
	local added_sections = {}

	for i=1, #objs do
		local obj = objs[i]
		local section_name = uci:add("v2ray", "outbound")

		if not section_name then
			http.prepare_content("application/json")
			http.write_json({
				success = false,
				message = i18n.translate("Failed to create new section")
			})
			return
		end

		local address = obj["add"] or "0.0.0.0"
		local port = obj["port"] or "0"
		local alias = obj["ps"] or string.format("%s:%s", address, port)
		local protocol = obj["protocol"] or "vmess"

		uci:set("v2ray", section_name, "alias", alias)
		uci:set("v2ray", section_name, "protocol", protocol)

		if protocol == "vmess" then
			import_vmess_outbound(section_name, obj)
		elseif protocol == "vless" then
			import_vless_outbound(section_name, obj)
		elseif protocol == "trojan" then
			import_trojan_outbound(section_name, obj)
		elseif protocol == "shadowsocks" then
			import_shadowsocks_outbound(section_name, obj)
		end

		table.insert(added_sections, section_name)
	end

	for _, sid in ipairs(added_sections) do
		local found = false
		for _, v in ipairs(outbounds) do
			if v == sid then
				found = true
				break
			end
		end
		if not found then
			table.insert(outbounds, sid)
		end
	end
	uci:set_list("v2ray", "main", "outbounds", outbounds)

	local success = uci:save("v2ray")

	if not success then
		http.prepare_content("application/json")
		http.write_json({
			success = false,
			message = i18n.translate("Failed to save section")
		})
		return
	end

	http.prepare_content("application/json")
	http.write_json({
		success = true
	})
end

function import_vmess_outbound(section_name, obj)
	local tls = obj["tls"] or ""
	uci:set("v2ray", section_name, "s_vmess_address", obj["add"] or "0.0.0.0")
	uci:set("v2ray", section_name, "s_vmess_port", obj["port"] or "0")
	uci:set("v2ray", section_name, "s_vmess_user_id", obj["id"] or "")
	uci:set("v2ray", section_name, "s_vmess_user_alter_id", obj["aid"] or "0")
	uci:set("v2ray", section_name, "s_vmess_user_security", "auto")
	uci:set("v2ray", section_name, "ss_security", tls)

	local network = obj["net"] or ""
	local header_type = obj["type"] or ""
	local path = obj["path"] or ""
	local hosts = {}

	for h in string.gmatch(obj["host"] or "", "([^,%s]+),?") do
		hosts[#hosts+1] = h
	end

	apply_network_settings(section_name, network, header_type, path, hosts, tls)
end

function import_vless_outbound(section_name, obj)
	local security = obj["tls"] or obj["security"] or ""
	uci:set("v2ray", section_name, "s_vless_address", obj["add"] or "0.0.0.0")
	uci:set("v2ray", section_name, "s_vless_port", obj["port"] or "0")
	uci:set("v2ray", section_name, "s_vless_user_id", obj["id"] or "")
	uci:set("v2ray", section_name, "s_vless_user_security", "auto")
	
	if security == "tls" then
		uci:set("v2ray", section_name, "ss_security", "tls")
	elseif security == "reality" then
		uci:set("v2ray", section_name, "ss_security", "reality")
	elseif security == "xtls" then
		uci:set("v2ray", section_name, "ss_security", "xtls")
	end
	
	if obj["sni"] then
		if security == "tls" then
			uci:set("v2ray", section_name, "ss_tls_server_name", obj["sni"])
		elseif security == "reality" then
			uci:set("v2ray", section_name, "ss_reality_server_name", obj["sni"])
		elseif security == "xtls" then
			uci:set("v2ray", section_name, "ss_xtls_server_name", obj["sni"])
		end
	end
	
	if obj["flow"] then
		uci:set("v2ray", section_name, "s_vless_flow", obj["flow"])
	end
	
	if obj["publicKey"] then
		uci:set("v2ray", section_name, "ss_reality_public_key", obj["publicKey"])
	end
	
	if obj["shortId"] then
		uci:set("v2ray", section_name, "ss_reality_short_id", obj["shortId"])
	end
	
	if obj["spiderX"] then
		uci:set("v2ray", section_name, "ss_reality_spider_x", obj["spiderX"])
	end

	local network = obj["net"] or "tcp"
	local path = obj["path"] or ""
	local hosts = {}
	if obj["host"] then
		for h in string.gmatch(obj["host"], "([^,%s]+),?") do
			hosts[#hosts+1] = h
		end
	end
	
	apply_network_settings(section_name, network, "", path, hosts, security)
end

function import_trojan_outbound(section_name, obj)
	uci:set("v2ray", section_name, "s_trojan_address", obj["add"] or "0.0.0.0")
	uci:set("v2ray", section_name, "s_trojan_port", obj["port"] or "0")
	uci:set("v2ray", section_name, "s_trojan_password", obj["password"] or "")
	uci:set("v2ray", section_name, "ss_security", "tls")
	
	if obj["sni"] then
		uci:set("v2ray", section_name, "ss_tls_server_name", obj["sni"])
	end
	
	if obj["allowInsecure"] == "1" or obj["allowInsecure"] == true then
		uci:set("v2ray", section_name, "ss_tls_allow_insecure", "1")
	end
	
	if obj["alpn"] then
		uci:set("v2ray", section_name, "ss_tls_alpn", obj["alpn"])
	end
	
	local network = obj["net"] or "tcp"
	local path = obj["path"] or ""
	local hosts = {}
	if obj["host"] then
		for h in string.gmatch(obj["host"], "([^,%s]+),?") do
			hosts[#hosts+1] = h
		end
	end
	
	apply_network_settings(section_name, network, "", path, hosts, "tls")
end

function import_shadowsocks_outbound(section_name, obj)
	uci:set("v2ray", section_name, "s_shadowsocks_address", obj["add"] or "0.0.0.0")
	uci:set("v2ray", section_name, "s_shadowsocks_port", obj["port"] or "0")
	uci:set("v2ray", section_name, "s_shadowsocks_password", obj["password"] or "")
	uci:set("v2ray", section_name, "s_shadowsocks_method", obj["method"] or "")
end

function apply_network_settings(section_name, network, header_type, path, hosts, security)
	if network == "tcp" then
		uci:set("v2ray", section_name, "ss_network", "tcp")
		if header_type and header_type ~= "" then
			uci:set("v2ray", section_name, "ss_tcp_header_type", header_type)
			if header_type == "http" and next(hosts) then
				local host_header = string.format("Host=%s", hosts[1])
				uci:set_list("v2ray", section_name, "ss_tcp_header_request_headers", host_header)
			end
		end
		if (security == "tls" or security == "reality") and next(hosts) then
			if security == "tls" then
				uci:set("v2ray", section_name, "ss_tls_server_name", hosts[1])
			elseif security == "reality" then
				uci:set("v2ray", section_name, "ss_reality_server_name", hosts[1])
			end
		end
	elseif network == "kcp" or network == "mkcp" then
		uci:set("v2ray", section_name, "ss_network", "kcp")
		if header_type then
			uci:set("v2ray", section_name, "ss_kcp_header_type", header_type)
		end
	elseif network == "ws" then
		uci:set("v2ray", section_name, "ss_network", "ws")
		if path and path ~= "" then
			uci:set("v2ray", section_name, "ss_websocket_path", path)
		end
		if next(hosts) then
			local host_header = string.format("Host=%s", hosts[1])
			uci:set_list("v2ray", section_name, "ss_websocket_headers", host_header)
		end
		if (security == "tls" or security == "reality") and next(hosts) then
			if security == "tls" then
				uci:set("v2ray", section_name, "ss_tls_server_name", hosts[1])
			elseif security == "reality" then
				uci:set("v2ray", section_name, "ss_reality_server_name", hosts[1])
			end
		end
	elseif network == "http" or network == "h2" then
		uci:set("v2ray", section_name, "ss_network", "http")
		if path and path ~= "" then
			uci:set("v2ray", section_name, "ss_http_path", path)
		end
		if next(hosts) then
			uci:set_list("v2ray", section_name, "ss_http_host", hosts)
			if security == "tls" then
				uci:set("v2ray", section_name, "ss_tls_server_name", hosts[1])
			end
		end
	elseif network == "quic" then
		uci:set("v2ray", section_name, "ss_network", "quic")
		if header_type then
			uci:set("v2ray", section_name, "ss_quic_header_type", header_type)
		end
		if path then
			uci:set("v2ray", section_name, "ss_quic_key", path)
		end
		if next(hosts) then
			uci:set("v2ray", section_name, "ss_quic_security", hosts[1])
			if security == "tls" then
				uci:set("v2ray", section_name, "ss_tls_server_name", hosts[1])
			end
		end
	end
end
