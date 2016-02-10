--[[ TermostatoVirtual
	Dispositivo virtual
	probeButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
-- obtener id del termostato
local idLabel = fibaro:get(fibaro:getSelfId(), 'ui.idLabel.value')
local p2 = string.find(idLabel, ' --')
local thermostatId =  tonumber(string.sub(idLabel, 13, p2))
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
--[[----- FIN CONFIGURACION AVANZADA -----------------------------------------]]

--[[----------------------------------------------------------------------------
isVariable(varName)
	comprueba si existe una variable global dada(varName)
--]]
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
-- obtener sensores de temperatura
response ,status, errorCode = HC2:GET("/api/devices")
local devices = json.decode(response)
local temperatureSensors = {}
for key, value in pairs(devices) do
  -- para la habitación fibaro:getRoomID(_selfId)
  -- todos los "type":"com.fibaro.temperatureSensor",
  if value["type"] == "com.fibaro.temperatureSensor" then
    local temperatureSensor = {id = value.id, name = value.name}
    table.insert(temperatureSensors, temperatureSensor)
  end
end
-- añadir sonda virtual
local temperatureSensor = {id = 0, name = 'Sonda Virtual'}
table.insert(temperatureSensors, temperatureSensor)

-- seleccionar el siguiete sensor que corresponda
temperatureSensor = fibaro:get(_selfId, 'ui.probeLabel.value')
local myKey = 1
for key, value in pairs(temperatureSensors) do
  fibaro:debug(value.name..' '..key..' '..myKey)
  if value.id..'-'..value.name == temperatureSensor then
    fibaro:debug(temperatureSensor)
    if key < #temperatureSensors then myKey = key + 1 else myKey = 1 end
    break
  else
    myKey = #temperatureSensors
  end
end

-- actualizar la etiqueta de sonda
fibaro:call(_selfId, "setProperty", "ui.probeLabel.value",
 temperatureSensors[myKey].id..'-'..temperatureSensors[myKey].name)
-- recuperar dispositivo
local termostatoVirtual = getDevice(thermostatId)
--actualizar dispositivo
termostatoVirtual.probeId = temperatureSensors[myKey].id
fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
--[[--------------------------------------------------------------------------]]
