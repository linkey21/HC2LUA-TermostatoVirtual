--[[ TermostatoVirtual
	Dispositivo virtual
	actuatorButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
-- obtener id del termostato
local idLabel = fibaro:get(_selfId, 'ui.terostatLabel.value')
local p2 = string.find(idLabel, '-')
local thermostatId = tonumber(string.sub(idLabel, 1, p2 - 1))
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
local binarySwitches = {}
table.insert(binarySwitches, {id = 0, name = '🔧'})
for key, value in pairs(devices) do
  -- para la habitación fibaro:getRoomID(_selfId)
  -- todos los "baseType":"com.fibaro.binarySwitch",
  if value["baseType"] == "com.fibaro.binarySwitch" or
     value["baseType"] == "com.fibaro.operatingMode" then
    local binarySwitch = {id = value.id, name = value.name}
    table.insert(binarySwitches, binarySwitch)
  end
end

-- seleccionar el siguiete sensor que corresponda
binarySwitch = fibaro:get(_selfId, 'ui.actuatorLabel.value')
local myKey = 1
for key, value in pairs(binarySwitches) do
  fibaro:debug(value.name..' '..key..' '..myKey)
  if value.id..'-'..value.name == binarySwitch then
    fibaro:debug(binarySwitch)
    if key < #binarySwitches then myKey = key + 1 else myKey = 1 end
    break
  else
    myKey = #binarySwitches
  end
end

-- actualizar la etiqueta de actuador
fibaro:call(_selfId, "setProperty", "ui.actuatorLabel.value",
 binarySwitches[myKey].id..'-'..binarySwitches[myKey].name)
-- recuperar dispositivo
local termostatoVirtual = getDevice(thermostatId)
--actualizar dispositivo
termostatoVirtual.actuatorId = binarySwitches[myKey].id
fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
--[[--------------------------------------------------------------------------]]
