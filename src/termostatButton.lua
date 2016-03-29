--[[ TermostatoVirtual
	Dispositivo virtual
	termostatButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
--[[----- FIN CONFIGURACION AVANZADA -----------------------------------------]]

-- isVariable(varName)
-- (string) varName: nombre de la variable global
-- comprueba si existe una variable global dada
function isVariable(varName)
  -- comprobar si existe
  local valor, timestamp = fibaro:getGlobal(varName)
  if (valor and timestamp > 0) then return valor end
  return false
end

--[[----------------------------------------------------------------------------
getDevice(nodeId)
	recupera el dispositivo virtual desde la variable global
  (number)
--]]
function getDevice(nodeId)
  -- si  exite la variable global recuperar dispositivo
  local device = isVariable('dev'..nodeId)
  if device then
    return json.decode(device)
  end
end

if not HC2 then
  HC2 = Net.FHttp("127.0.0.1", 11111)
end
-- obtener sensores interruptores / actuadores
response ,status, errorCode = HC2:GET("/api/devices")
local devices = json.decode(response)
local virtualDevices = {}
--table.insert(virtualDevices, {id = 0, name = '🔧'})
for key, value in pairs(devices) do
  -- para la habitación fibaro:getRoomID(_selfId)
  -- todos los "baseType":"com.fibaro.virtualDevices",
  if value["type"] == "virtual_device" and
  string.find(value["properties"].mainLoop, "termostat.linkey.es") then
    local virtualDevice = {id = value.id, name = value.name}
    table.insert(virtualDevices, virtualDevice)
  end
end

-- seleccionar el siguiete sensor que corresponda
local device = fibaro:get(_selfId, 'ui.terostatLabel.value')
local myKey = 1
for key, value in pairs(virtualDevices) do
  fibaro:debug(value.name..' '..key..' '..myKey)
  if value.id..'-'..value.name == device then
    fibaro:debug(device)
    if key < #virtualDevices then myKey = key + 1 else myKey = 1 end
    break
  else
    myKey = #virtualDevices
  end
end

-- actualizar la etiqueta de actuador
fibaro:call(_selfId, "setProperty", "ui.terostatLabel.value",
 virtualDevices[myKey].id..'-'..virtualDevices[myKey].name)
-- recuperar dispositivo
local termostatoVirtual = getDevice(virtualDevices[myKey].id)
-- si se ha seleccionado un termostatoVirtual
if termostatoVirtual then
  --actualizar dispositivo
  termostatoVirtual.nodeId = virtualDevices[myKey].id
  fibaro:setGlobal('dev'..virtualDevices[myKey].id,
  json.encode(termostatoVirtual))
end
--[[--------------------------------------------------------------------------]]
