--[[ TermostatoVirtual
	Dispositivo virtual
	configMainLoop.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
if not iconId then iconId = 1068 end

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='configurardorTermost', ver=2, mayor=0, minor=0}
-- ID de este dispositivo virtual
if not _selfId then _selfId = fibaro:getSelfId() end

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

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- obtener id del termostato
  local idLabel = fibaro:get(_selfId, 'ui.terostatLabel.value')
  local p2 = string.find(idLabel, '-')
  local thermostatId = tonumber(string.sub(idLabel, 1, p2 - 1))

  -- actualizar etiqueta identificador
  fibaro:call(_selfId, "setProperty", "ui.idLabel.value", 'id: '.._selfId)

   -- actualizar icono
   fibaro:call(_selfId, 'setProperty', "currentIcon", iconId)

  -- recuperar dispositivo
  local termostatoVirtual = getDevice(thermostatId)
  local PID = termostatoVirtual.PID
  if not PID.cyclesH then PID.cyclesH = 3 end

  -- actualizar etiquetas K
  fibaro:call(_selfId, "setProperty", "ui.KLabel.value", 'Kp='..PID.kP..' Ki='
   ..PID.kI..' Kd='..PID.kD..' c/h='..PID.cyclesH)
   fibaro:call(_selfId, "setProperty", "ui.hisWindLabel.value", 'his='
    ..PID.histeresis..' wUp='..PID.antiwindupReset..' mTa='..PID.minTimeAction
    ..' sTa='..PID.secureTimeAction)

   -- actualizar la etiqueta de sonda
   local probeName
   if termostatoVirtual.probeId == 0 then
     probeName = 'Sonda Virtual'
   else
     probeName = fibaro:getName(termostatoVirtual.probeId)
   end
   fibaro:call(_selfId, "setProperty", "ui.probeLabel.value",
   termostatoVirtual.probeId..'-'..probeName)

   -- actualizar la etiqueta de actuador
   local actuatorName
   if termostatoVirtual['actuator'].id == 0 then
     actuatorName ='🔧'
   else
     actuatorName = fibaro:getName(termostatoVirtual['actuator'].id)
   end
   fibaro:call(_selfId, "setProperty", "ui.actuatorLabel.value",
    termostatoVirtual['actuator'].id..'-'..actuatorName)

   -- actualizar etiqueta de modo del Actuador
   if termostatoVirtual['actuator'].maintenance then
     fibaro:call(_selfId, "setProperty", "ui.statusLabel.value", '🔧MANTEN')
   else
     fibaro:call(_selfId, "setProperty", "ui.statusLabel.value", '⚙ RUNNING')
   end

   -- esperar para evitar colapsar la CPU
   fibaro:sleep(1000)
   -- para control por watchdog
   fibaro:debug(release['name']..' OK')
end
