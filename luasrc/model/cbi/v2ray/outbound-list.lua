-- Copyright 2019-2020 Xingwang Liao <kuoruan@gmail.com>
-- Licensed to the public under the MIT License.

local dsp = require "luci.dispatcher"
local http = require "luci.http"
local util = require "luci.util"

local m, s, o

m = Map("v2ray", "%s - %s" % { translate("V2Ray"), translate("Outbound") })
m:append(Template("v2ray/import_outbound"))

s = m:section(TypedSection, "outbound")
s.anonymous = true
s.addremove = true
s.sortable = true
s.template = "cbi/tblsection"
s.extedit = dsp.build_url("admin/services/v2ray/outbounds/%s")
s.create = function (...)
	local sid = TypedSection.create(...)
	if sid then
		local outbounds = m.uci:get_list("v2ray", "main", "outbounds") or {}
		if not util.contains(outbounds, sid) then
			outbounds[#outbounds + 1] = sid
			m.uci:set_list("v2ray", "main", "outbounds", outbounds)
		end
		m.uci:save("v2ray")
		http.redirect(s.extedit % sid)
		return
	end
end

s.remove = function (self, sid)
	local outbounds = m.uci:get_list("v2ray", "main", "outbounds") or {}
	local new_outbounds = {}
	for _, v in ipairs(outbounds) do
		if v ~= sid then
			new_outbounds[#new_outbounds + 1] = v
		end
	end
	TypedSection.remove(self, sid)
	if #new_outbounds > 0 then
		m.uci:set_list("v2ray", "main", "outbounds", new_outbounds)
	else
		m.uci:delete("v2ray", "main", "outbounds")
	end
	m.uci:save("v2ray")
end

o = s:option(DummyValue, "alias", translate("Alias"))
o.cfgvalue = function (...)
	return Value.cfgvalue(...) or "?"
end

o = s:option(DummyValue, "send_through", translate("Send Through"))
o.cfgvalue = function (...)
	return Value.cfgvalue(...) or "-"
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
