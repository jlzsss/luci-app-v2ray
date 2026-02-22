-- Copyright 2019-2020 Xingwang Liao <kuoruan@gmail.com>
-- Licensed to the public under the MIT License.

local dsp = require "luci.dispatcher"
local http = require "luci.http"
local util = require "luci.util"

local m, s, o

m = Map("v2ray", "%s - %s" % { translate("V2Ray"), translate("Inbound") })

s = m:section(TypedSection, "inbound")
s.anonymous = true
s.addremove = true
s.sortable = true
s.template = "cbi/tblsection"
s.extedit = dsp.build_url("admin/services/v2ray/inbounds/%s")
s.create = function (...)
	local sid = TypedSection.create(...)
	if sid then
		local inbounds = m.uci:get_list("v2ray", "main", "inbounds") or {}
		if not util.contains(inbounds, sid) then
			inbounds[#inbounds + 1] = sid
			m.uci:set_list("v2ray", "main", "inbounds", inbounds)
		end
		m.uci:save("v2ray")
		http.redirect(s.extedit % sid)
		return
	end
end

s.remove = function (self, sid)
	local inbounds = m.uci:get_list("v2ray", "main", "inbounds") or {}
	local new_inbounds = {}
	for _, v in ipairs(inbounds) do
		if v ~= sid then
			new_inbounds[#new_inbounds + 1] = v
		end
	end
	TypedSection.remove(self, sid)
	if #new_inbounds > 0 then
		m.uci:set_list("v2ray", "main", "inbounds", new_inbounds)
	else
		m.uci:delete("v2ray", "main", "inbounds")
	end
	m.uci:save("v2ray")
end

o = s:option(DummyValue, "alias", translate("Alias"))
o.cfgvalue = function (...)
	return Value.cfgvalue(...) or "?"
end

o = s:option(DummyValue, "listen", translate("Listen"))
o.cfgvalue = function (...)
	return Value.cfgvalue(...) or "-"
end

o = s:option(DummyValue, "port", translate("Port"))
o.cfgvalue = function (...)
	return Value.cfgvalue(...) or "?"
end

o = s:option(DummyValue, "protocol", translate("Protocol"))
o.cfgvalue = function (...)
	return Value.cfgvalue(...) or "?"
end

o = s:option(DummyValue, "ss_network", translate("Stream Network"))
o.cfgvalue = function (...)
	return Value.cfgvalue(...) or "?"
end

o = s:option(DummyValue, "tag", translate("Tag"))
o.cfgvalue = function (...)
	return Value.cfgvalue(...) or "?"
end

return m
