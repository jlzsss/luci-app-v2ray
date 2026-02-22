-- Copyright 2019-2020 Xingwang Liao <kuoruan@gmail.com>
-- Licensed to the public under the MIT License.

local nixio = require "nixio"
local util = require "luci.util"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local json = require "luci.jsonc"

module("luci.model.v2ray", package.seeall)

local gfwlist_urls = {
	["github"] = "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt",
	["gitlab"] = "https://gitlab.com/gfwlist/gfwlist/raw/master/gfwlist.txt",
	["pagure"] = "https://pagure.io/gfwlist/raw/master/f/gfwlist.txt",
	["bitbucket"] = "https://bitbucket.org/gfwlist/gfwlist/raw/HEAD/gfwlist.txt"
}

local apnic_delegated_urls = {
	["apnic"] = "https://ftp.apnic.net/stats/apnic/delegated-apnic-latest",
	["arin"] = "https://ftp.arin.net/pub/stats/apnic/delegated-apnic-latest",
	["ripe"] = "https://ftp.ripe.net/pub/stats/apnic/delegated-apnic-latest",
	["iana"] = "https://ftp.iana.org/pub/mirror/rirstats/apnic/delegated-apnic-latest"
}

local apnic_delegated_extended_url = "https://ftp.apnic.net/stats/apnic/delegated-apnic-extended-latest"
local cn_zone_url = "http://www.ipdeny.com/ipblocks/data/countries/cn.zone"

local gfwlist_file = "/etc/v2ray/gfwlist.txt"
local chnroute_file_ipv4 = "/etc/v2ray/chnroute.txt"
local chnroute_file_ipv6 = "/etc/v2ray/chnroute6.txt"

function generate_gfwlist()
	local gfwlist_mirror = uci:get("v2ray", "main_transparent_proxy", "gfwlist_mirror") or "github"

	local gfwlist_url = gfwlist_urls[gfwlist_mirror]

	if not gfwlist_url then
		gfwlist_url = gfwlist_urls['github']
	end

	local f = sys.httpget(gfwlist_url, true)
	if not f then
		return false
	end

	local t = {}

	for line in f:lines() do
		t[#t+1] = line
	end

	f:close()

	if not next(t) then
		return false
	end

	local content = table.concat(t, "")

	local domains = {}

	local decoded = nixio.bin.b64decode(content)

	for line in util.imatch(decoded) do
		if not string.match(line, "^$") and
			not string.match(line, "^[!%[@]") and
			not string.match(line, "^%d+%.%d+%.%d+%.%d+") then
			local start, _, domain = string.find(line, "(%w[%w%-_]+%.%w[%w%.%-_]+)")

			if start then
				domains[domain] = true
			end
		end
	end

	if not next(domains) then
		return false
	end

	local result = false
	local temp = util.trim(sys.exec("mktemp /tmp/gfwlist.XXXXXX"))

	local out_temp = io.open(temp, "w")

	if not out_temp then
		return false
	end

	for k in util.kspairs(domains) do
		out_temp:write(k, "\n")
	end

	out_temp:flush()
	out_temp:close()

	local file_size = nixio.fs.stat(temp, "size")
	if file_size and file_size > 1 then
		local code = sys.call("cat %s >%s 2>/dev/null" % {
			util.shellquote(temp),
			util.shellquote(gfwlist_file)
		})

		result = (code == 0)
	end

	nixio.fs.remove(temp)

	return result
end

function generate_routelist()
	local apnic_delegated_mirror = uci:get("v2ray", "main_transparent_proxy", "apnic_delegated_mirror") or "apnic"

	local apnic_delegated_url = apnic_delegated_urls[apnic_delegated_mirror]

	if not apnic_delegated_url then
		apnic_delegated_url = apnic_delegated_urls['apnic']
	end

	local f = sys.httpget(apnic_delegated_url, true)
	if not f then
		return false, false
	end

	local result_ipv4, result_ipv6 = false, false

	local temp_ipv4 = util.trim(sys.exec("mktemp /tmp/chnroute.XXXXXX"))
	local temp_ipv6 = util.trim(sys.exec("mktemp /tmp/chnroute6.XXXXXX"))

	local out_temp_ipv4 = io.open(temp_ipv4, "w")
	local out_temp_ipv6 = io.open(temp_ipv6, "w")

	if not out_temp_ipv4 or not out_temp_ipv6 then
		return false, false
	end

	for line in f:lines() do
		local start, _, type, ip, value = string.find(line, "CN|(ipv%d)|([%d%.:]+)|(%d+)")

		if start then
			if type == "ipv4" then
				local mask = 32 - math.log(tonumber(value)) / math.log(2)
				out_temp_ipv4:write(string.format("%s/%d", ip, mask), "\n")
			elseif type == "ipv6" then
				out_temp_ipv6:write(string.format("%s/%s", ip, value), "\n")
			end
		end
	end

	f:close()

	out_temp_ipv4:flush()
	out_temp_ipv4:close()

	out_temp_ipv6:flush()
	out_temp_ipv6:close()

	local file_size_ipv4 = nixio.fs.stat(temp_ipv4, "size")
	local file_size_ipv6 = nixio.fs.stat(temp_ipv6, "size")

	if file_size_ipv4 and file_size_ipv4 > 1 then
		local code = sys.call("cat %s >%s 2>/dev/null" % {
			util.shellquote(temp_ipv4),
			util.shellquote(chnroute_file_ipv4)
		})

		result_ipv4 = (code == 0)
	end

	if file_size_ipv6 and file_size_ipv6 > 1 then
		local code = sys.call("cat %s >%s 2>/dev/null" % {
			util.shellquote(temp_ipv6),
			util.shellquote(chnroute_file_ipv6)
		})

		result_ipv6 = (code == 0)
	end

	nixio.fs.remove(temp_ipv4)
	nixio.fs.remove(temp_ipv6)

	return result_ipv4, result_ipv6
end

function get_gfwlist_status()
	local gfwlist_size = util.exec("cat %s | grep -v '^$' | wc -l" % util.shellquote(gfwlist_file))
	local gfwlist_time = util.exec("date -r %s '+%%Y/%%m/%%d %%H:%%M:%%S'" % util.shellquote(gfwlist_file))

	return {
		gfwlist = {
			size = tonumber(gfwlist_size),
			lastModify = gfwlist_time ~= "" and util.trim(gfwlist_time) or "-/-/-"
		}
	}
end

function get_routelist_status()
	local chnroute_size = util.exec("cat %s | grep -v '^$' | wc -l" % util.shellquote(chnroute_file_ipv4))
	local chnroute_time = util.exec("date -r %s '+%%Y/%%m/%%d %%H:%%M:%%S'" % util.shellquote(chnroute_file_ipv4))

	local chnroute6_size = util.exec("cat %s | grep -v '^$' | wc -l" % util.shellquote(chnroute_file_ipv6))
	local chnroute6_time = util.exec("date -r %s '+%%Y/%%m/%%d %%H:%%M:%%S'" % util.shellquote(chnroute_file_ipv4))

	return {
		chnroute = {
			size = tonumber(chnroute_size),
			lastModify = chnroute_time ~= "" and util.trim(chnroute_time) or "-/-/-"
		},
		chnroute6 = {
			size = tonumber(chnroute6_size),
			lastModify = chnroute6_time ~= "" and util.trim(chnroute6_time) or "-/-/-"
		}
	}
end

local function urldecode(str)
	if not str then return nil end
	str = string.gsub(str, "+", " ")
	str = string.gsub(str, "%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end)
	return str
end

function parse_vmess_links(link)
	local objs = {}
	string.gsub(link, "vmess://[%w%+/=_%-]+", function (l)
		local obj = vmess_to_object(l)
		if obj then
			obj.protocol = "vmess"
			table.insert(objs, obj)
		end
	end)
	string.gsub(link, "vless://[^%s\r\n]+", function (l)
		local obj = vless_to_object(l)
		if obj then
			obj.protocol = "vless"
			table.insert(objs, obj)
		end
	end)
	string.gsub(link, "trojan://[^%s\r\n]+", function (l)
		local obj = trojan_to_object(l)
		if obj then
			obj.protocol = "trojan"
			table.insert(objs, obj)
		end
	end)
	string.gsub(link, "ss://[^%s\r\n]+", function (l)
		local obj = shadowsocks_to_object(l)
		if obj then
			obj.protocol = "shadowsocks"
			table.insert(objs, obj)
		end
	end)

	return objs
end

function vmess_to_object(link)
	local content = string.match(link, "^vmess://(%S+)")

	if not content or content == "" then
		return nil
	end

	local decoded = nixio.bin.b64decode(content)

	if not decoded or decoded == "" then
		return nil
	end

	return json.parse(decoded)
end

function vless_to_object(link)
	local obj = {}
	local id, addr, port, rest
	
	id, addr, port, rest = string.match(link, "^vless://([^@]+)@%[([%x:]+)%]:(%d+)(.*)")
	if not id then
		id, addr, port, rest = string.match(link, "^vless://([^@]+)@([^:]+):(%d+)(.*)")
	end
	
	if id and addr and port then
		obj.id = urldecode(id)
		obj.add = addr
		obj.port = port
		obj.ps = string.format("%s:%s", addr, port)
		
		local remark = string.match(rest or "", "#(.+)$")
		if remark then
			obj.ps = urldecode(remark)
		end
		
		local params = {}
		local query = string.match(rest or "", "%?([^#]+)")
		if query then
			for k, v in string.gmatch(query, "([^&=]+)=([^&]*)") do
				params[k] = urldecode(v)
			end
		end
		
		obj.net = params.type or "tcp"
		obj.path = params.path or ""
		obj.host = params.host or ""
		obj.tls = params.security or ""
		obj.sni = params.sni or ""
		obj.flow = params.flow or ""
		obj.alpn = params.alpn or ""
		obj.publicKey = params.publicKey or params.pbk or ""
		obj.shortId = params.shortId or params.sid or ""
		obj.spiderX = params.spiderX or params.spx or ""
		obj.fp = params.fp or ""
		
		return obj
	end
	return nil
end

function trojan_to_object(link)
	local obj = {}
	local password, addr, port, rest
	
	password, addr, port, rest = string.match(link, "^trojan://([^@]+)@%[([%x:]+)%]:(%d+)(.*)")
	if not password then
		password, addr, port, rest = string.match(link, "^trojan://([^@]+)@([^:]+):(%d+)(.*)")
	end
	
	if password and addr and port then
		obj.password = urldecode(password)
		obj.add = addr
		obj.port = port
		obj.ps = string.format("%s:%s", addr, port)
		
		local remark = string.match(rest or "", "#(.+)$")
		if remark then
			obj.ps = urldecode(remark)
		end
		
		local params = {}
		local query = string.match(rest or "", "%?([^#]+)")
		if query then
			for k, v in string.gmatch(query, "([^&=]+)=([^&]*)") do
				params[k] = urldecode(v)
			end
		end
		
		obj.sni = params.sni or ""
		obj.allowInsecure = params.allowInsecure or "0"
		obj.alpn = params.alpn or ""
		obj.net = params.type or "tcp"
		obj.path = params.path or ""
		obj.host = params.host or ""
		
		return obj
	end
	return nil
end

function shadowsocks_to_object(link)
	local obj = {}
	
	local encoded, addr, port, rest
	
	encoded, addr, port, rest = string.match(link, "^ss://([^@]+)@%[([%x:]+)%]:(%d+)(.*)")
	if not encoded then
		encoded, addr, port, rest = string.match(link, "^ss://([^@]+)@([^:]+):(%d+)(.*)")
	end
	
	if encoded and addr and port then
		local remark = string.match(rest or "", "#(.+)$")
		local decoded = nixio.bin.b64decode(encoded)
		if decoded then
			local method, password = string.match(decoded, "^([^:]+):(.*)")
			if method and password then
				obj.method = method
				obj.password = password
				obj.add = addr
				obj.port = port
				obj.ps = remark and urldecode(remark) or string.format("%s:%s", addr, port)
				return obj
			end
		end
	end
	
	local main_part, remark = string.match(link, "^ss://([^#]+)#?(.*)$")
	if main_part then
		main_part = string.match(main_part, "^(%S+)")
		if main_part then
			local decoded = nixio.bin.b64decode(main_part)
			if decoded then
				local method, password, saddr, sport = string.match(decoded, "^([^:]+):([^@]+)@%[([%x:]+)%]:(%d+)")
				if not method then
					method, password, saddr, sport = string.match(decoded, "^([^:]+):([^@]+)@([^:]+):(%d+)")
				end
				if method and password and saddr and sport then
					obj.method = method
					obj.password = password
					obj.add = saddr
					obj.port = sport
					obj.ps = remark and #remark > 0 and urldecode(remark) or string.format("%s:%s", saddr, sport)
					return obj
				end
			end
			
			local method, password, saddr, sport = string.match(main_part, "^([^:]+):([^@]+)@%[([%x:]+)%]:(%d+)")
			if not method then
				method, password, saddr, sport = string.match(main_part, "^([^:]+):([^@]+)@([^:]+):(%d+)")
			end
			if method and password and saddr and sport then
				obj.method = method
				obj.password = password
				obj.add = saddr
				obj.port = sport
				obj.ps = remark and #remark > 0 and urldecode(remark) or string.format("%s:%s", saddr, sport)
				return obj
			end
		end
	end
	
	return nil
end

function textarea_parse(self, section, novld)
	local fvalue = self:formvalue(section)
	local cvalue = self:cfgvalue(section)

	if fvalue and #fvalue > 0 then
		local val_err
		fvalue, val_err = self:validate(fvalue, section)

		if not fvalue and not novld then
			self:add_error(section, "invalid", val_err)
			return false
		end

		if fvalue and fvalue ~= cvalue then
			if self:write(section, fvalue) then
				self.section.changed = true
				return true
			end
		end
	else
		if self:remove(section) then
			self.section.changed = true
			return true
		end
	end

	return false
end

function textarea_cfgvalue(self, section)
	if not self.filepath then
		return ""
	end
	return nixio.fs.readfile(self.filepath) or ""
end

function textarea_write(self, section, value)
	if not self.filepath then
		return false
	end

	value = value:gsub("\r\n?", "\n")
	return nixio.fs.writefile(self.filepath, value)
end

function textarea_remove(self, section)
	if not self.filepath then
		return false
	end

	return nixio.fs.writefile(self.filepath, "")
end
