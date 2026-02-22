-- Copyright 2019-2020 Xingwang Liao <kuoruan@gmail.com>
-- Licensed to the public under the MIT License.

local dsp = require "luci.dispatcher"
local http = require "luci.http"
local nwm = require "luci.model.network".init()
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
		m.uci:set("v2ray", sid, "alias", "Inbound_" .. sid)
		
		local inbounds = m.uci:get("v2ray", "main", "inbounds")
		if inbounds then
			if type(inbounds) == "table" then
				if not util.contains(inbounds, sid) then
					table.insert(inbounds, sid)
					m.uci:set("v2ray", "main", "inbounds", inbounds)
				end
			else
				if inbounds ~= sid then
					m.uci:set("v2ray", "main", "inbounds", { inbounds, sid })
				end
			end
		else
			m.uci:set("v2ray", "main", "inbounds", { sid })
		end
		
		local lan_ifaces = m.uci:get("v2ray", "main_transparent_proxy", "lan_ifaces")
		local interfaces = {}
		for _, net in ipairs(nwm:get_networks()) do
			local net_name = net:name()
			if net_name ~= "loopback" and string.find(net_name, "wan") ~= 1 then
				local device = net:get_interface()
				if device then
					interfaces[#interfaces+1] = net_name
				end
			end
		end
		if not lan_ifaces then
			if #interfaces > 0 then
				m.uci:set("v2ray", "main_transparent_proxy", "lan_ifaces", table.concat(interfaces, " "))
			end
		else
			local current = {}
			for iface in lan_ifaces:gmatch("%S+") do
				current[iface] = true
			end
			local new_ifaces = {}
			for _, iface in ipairs(interfaces) do
				new_ifaces[#new_ifaces+1] = iface
				current[iface] = nil
			end
			for iface, _ in pairs(current) do
				new_ifaces[#new_ifaces+1] = iface
			end
			m.uci:set("v2ray", "main_transparent_proxy", "lan_ifaces", table.concat(new_ifaces, " "))
		end
		
		m.uci:save("v2ray")
		http.redirect(s.extedit % sid)
		return
	end
end
s.remove = function(self, sid)
	local inbounds = m.uci:get("v2ray", "main", "inbounds")
	if inbounds then
		if type(inbounds) == "table" then
			local new_inbounds = {}
			for _, v in ipairs(inbounds) do
				if v ~= sid then
					table.insert(new_inbounds, v)
				end
			end
			if #new_inbounds > 0 then
				m.uci:set("v2ray", "main", "inbounds", new_inbounds)
			else
				m.uci:delete("v2ray", "main", "inbounds")
			end
		else
			if inbounds == sid then
				m.uci:delete("v2ray", "main", "inbounds")
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
