--[[ TermostatoVirtual
	Dispositivo virtual
	statusButton.lua
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

-- recuperar dispositivo
local termostatoVirtual = getDevice(thermostatId)

-- cambiar valor de mantenimiento
local myLabel = ' 🔧MANTEN'
if termostatoVirtual['actuator'].maintenance then
  termostatoVirtual['actuator'].maintenance = false
  -- actualizar etiqueta
  myLabel = ' ⚙ RUNNING'
else
  termostatoVirtual['actuator'].maintenance = true
end

--actualizar dispositivo
fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))

-- actualizar etiqueta
fibaro:call(_selfId, "setProperty", "ui.statusLabel.value", myLabel)

fibaro:debug(myLabel)
