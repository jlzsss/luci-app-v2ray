-- Copyright 2019-2020 Xingwang Liao <kuoruan@gmail.com>
-- Licensed to the public under the MIT License.

local dsp = require "luci.dispatcher"
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
		local outbounds = m.uci:get("v2ray", "main", "outbounds")
		if outbounds then
			if type(outbounds) == "table" then
				if not util.contains(outbounds, sid) then
					table.insert(outbounds, sid)
					m.uci:set("v2ray", "main", "outbounds", outbounds)
				end
			else
				if outbounds ~= sid then
					m.uci:set("v2ray", "main", "outbounds", { outbounds, sid })
				end
			end
		else
			m.uci:set("v2ray", "main", "outbounds", { sid })
		end
		m.uci:save("v2ray")
		luci.http.redirect(s.extedit % sid)
		return
	end
end
s.remove = function(self, sid)
	local outbounds = m.uci:get("v2ray", "main", "outbounds")
	if outbounds then
		if type(outbounds) == "table" then
			local new_outbounds = {}
			for _, v in ipairs(outbounds) do
				if v ~= sid then
					table.insert(new_outbounds, v)
				end
			end
			if #new_outbounds > 0 then
				m.uci:set("v2ray", "main", "outbounds", new_outbounds)
			else
				m.uci:delete("v2ray", "main", "outbounds")
			end
		else
			if outbounds == sid then
				m.uci:delete("v2ray", "main", "outbounds")
			end
		end
		m.uci:save("v2ray")
	end
	return TypedSection.remove(self, sid)
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
