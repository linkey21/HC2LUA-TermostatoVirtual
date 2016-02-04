--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local controlPanelId = 598

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
fibaro:call(_selfId, "setProperty", "ui.idLabel.value",'id: '.._selfId)
-- recuperar dispositivo
local termostatoVirtual = getDevice(controlPanelId)
local K = termostatoVirtual.K
-- actualizar etiqueta K
fibaro:call(_selfId, "setProperty", "ui.KLabel.value",'Kp='..K.kP..' Ki='..K.kI..' Kd='..K.kD)
