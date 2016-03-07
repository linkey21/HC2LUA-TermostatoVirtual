--[[ TermostatoVirtual
	Dispositivo virtual
	configMainLoop.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
if not thermostatId then thermostatId = 598 end
if not iconId then iconId = 1068 end

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
-- ID de este dispositivo virtual
if not _selfId then _selfId = fibaro:getSelfId() end

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

-- actualizar etiqueta identificador
fibaro:call(_selfId, "setProperty", "ui.idLabel.value", 'Termostato: '
 ..thermostatId..' Panel Config.:'.._selfId)
 -- actualizar icono
 fibaro:call(_selfId, 'setProperty', "currentIcon", iconId)

-- recuperar dispositivo
local termostatoVirtual = getDevice(thermostatId)
local K = termostatoVirtual.K
if not K.cyclesH then K.cyclesH = 3 end
-- actualizar etiquetas K
--fibaro:debug('Kp='..K.kP..' Ki='..K.kI..' Kd='..K.kD..' c/h='..K.cyclesH)
fibaro:call(_selfId, "setProperty", "ui.KLabel.value", 'Kp='..K.kP..' Ki='
 ..K.kI..' Kd='..K.kD..' c/h='..K.cyclesH)
fibaro:call(_selfId, "setProperty", "ui.hisWindLabel.value",
 'histeresis='..K.histeresis..' antiwindupReset='..K.antiwindupReset)
