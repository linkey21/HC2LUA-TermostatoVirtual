--[[ TermostatoVirtual
	Dispositivo virtual
	cycleButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
--[[----- FIN CONFIGURACION AVANZADA -----------------------------------------]]


--[[isVariable(varName)
    (string) varName: nombre de la variable global
  comprueba si existe una variable global dada(varName) --]]
function isVariable(varName)
  -- comprobar si existe
  local valor, timestamp = fibaro:getGlobal(varName)
  if (valor and timestamp > 0) then return valor end
  return false
end

--[[getDevice(nodeId)
    (number) nodeId: número del dispositivo a recuperar de la variable global
  recupera el dispositivo virtual desde la variable global --]]
function getDevice(nodeId)
  -- si  exite la variable global recuperar dispositivo
  local device = isVariable('dev'..nodeId)
  if device and device ~= 'NaN' and device ~= 0 and device ~= '' then
    device = json.decode(device)
    -- si esta iniciado devolver el dispositivo
    if device.nodeId then
      return device
     end
  end
  -- en cualquier otro caso error
  return false
end

-- obtener etiqueta actual
local kLabel = fibaro:get(fibaro:getSelfId(), 'ui.KLabel.value')
local actualCycle = tonumber(string.sub(kLabel, string.find(kLabel, 'c/h=')+ 4))
kLabel = string.sub(kLabel, 1, string.find(kLabel, 'c/h=') + 3)
-- obtener id del termostato
local idLabel = fibaro:get(fibaro:getSelfId(), 'ui.idLabel.value')
fibaro:debug(idLabel)
local p2 = string.find(idLabel, ' Panel')
local thermostatId =  tonumber(string.sub(idLabel, 13, p2))
fibaro:debug(thermostatId)
-- aumentar ciclo
if actualCycle < 12 then
  actualCycle = actualCycle + 3
else
  actualCycle = 3
end
-- recuperar dispositivo
local termostatoVirtual = getDevice(thermostatId)
local K = termostatoVirtual.K
K.cyclesH = actualCycle
-- actualizar dispositivo
fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
-- actualizar etiqueta K
fibaro:call(fibaro:getSelfId(), "setProperty", "ui.KLabel.value",
 kLabel..actualCycle)
 --
