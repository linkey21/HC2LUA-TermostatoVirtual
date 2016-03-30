--[[ TermostatoVirtual
	Dispositivo virtual
	secTimeActButton.lua
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
local kLabel = fibaro:get(fibaro:getSelfId(), 'ui.hisWindLabel.value')
local actualTime = tonumber(string.sub(kLabel, string.find(kLabel, 'sTa=')+ 4))
kLabel = string.sub(kLabel, 1, string.find(kLabel, 'sTa=') + 3)
-- obtener id del termostato
local idLabel = fibaro:get(fibaro:getSelfId(), 'ui.terostatLabel.value')
local p2 = string.find(idLabel, '-')
local thermostatId = tonumber(string.sub(idLabel, 1, p2 - 1))
fibaro:debug(thermostatId)
-- rotar tiempo
if actualTime < 60 then
  actualTime = actualTime + 15
else
  actualTime = 15
end
-- recuperar dispositivo
local termostatoVirtual = getDevice(thermostatId)
local PID = termostatoVirtual.PID
PID.secureTimeAction = actualTime
-- actualizar dispositivo
fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
-- actualizar etiqueta K
fibaro:call(fibaro:getSelfId(), "setProperty", "ui.hisWindLabel.value",
 kLabel..actualTime)
 --
