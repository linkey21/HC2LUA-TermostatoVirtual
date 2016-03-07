--[[ TermostatoVirtual
	Dispositivo virtual
	downKpButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
-- obtener id del termostato
local idLabel = fibaro:get(_selfId, 'ui.idLabel.value')
local p2 = string.find(idLabel, ' Panel')
local thermostatId =  tonumber(string.sub(idLabel, 13, p2))
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
local K = termostatoVirtual.K

-- decrementar valor kP
--if K.kP > 0 then K.kP = K.kP - 1 else K.kP = 999 end
-- incrementar valor kI
--if K.kP < 999 then K.kP = K.kP + 1 else K.kP = 0 end
-- decrementar valor kI
--if K.kI > 0 then K.kI = K.kI - 1 else K.kI = 99 end
-- incrementar valor kI
--if K.kI < 99 then K.kI = K.kI + 1 else K.kI = 0 end
-- decrementar valor kD
--if K.kD > 0 then K.kD = K.kD - 1 else K.kD = 99 end
-- incrementar valor kD
--if K.kD < 99 then K.kD = K.kD + 1 else K.kD = 0 end
-- decrementar valor histeresis
--[[if K.histeresis > 0 then
  K.histeresis = K.histeresis - .01
else K.histeresis = 1
end]]
--[[incrementar valor histeresis
if K.histeresis < 1 then
  K.histeresis = K.histeresis + .01
else K.histeresis = 0
end]]
--[[decrementar valor antiwindupReset
if K.antiwindupReset > 0 then
  K.antiwindupReset = K.antiwindupReset - .01
else K.antiwindupReset = 1
end]]
--incrementar valor antiwindupReset
if K.antiwindupReset < 1 then
  K.antiwindupReset = K.antiwindupReset + .01
else K.antiwindupReset = 0
end

--actualizar dispositivo
termostatoVirtual.K = K
fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))

--[[ actualizar etiqueta
fibaro:call(_selfId, "setProperty", "ui.KLabel.value", 'Kp='..K.kP..' Ki='
 ..K.kI..' Kd='..K.kD..' c/h='..K.cyclesH)]]
fibaro:call(_selfId, "setProperty", "ui.hisWindLabel.value", 'histeresis='
 ..K.histeresis..' antiwindupRes='..K.antiwindupReset)
