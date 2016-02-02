--[[ TermostatoVirtual
	Dispositivo virtual
	mainLoop.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]

--[[isVariable(varName)
    (string) varName: nombre de la variable global
  comprueba si existe una variable global dada(varName) --]]
function isVariable(varName)
  -- comprobar si existe
  local valor, timestamp = fibaro:getGlobal(varName)
  if (valor and timestamp > 0) then return valor end
  return false
end

--[[resetDevice(nodeId)
    (number) nodeId: número del dispositivo a almacenar en la variable global
crea una varaible global para almacenar la tabla que representa el
dispositivo y lo inicializa. --]]
function resetDevice(nodeId)
  -- si no exite la variable global
  if not isVariable('dev'..nodeId) then
    -- intentar crear la variableGlobal
    local json = '{"name":"'..'dev'..nodeId..'", "isEnum":0}'
    if not HC2 then HC2 = Net.FHttp("127.0.0.1", 11111) end
    HC2:POST("/api/globalVariables", json)
    fibaro:sleep(1000)
    -- comprobar que se ha creado la variableGlobal
    if not isVariable('dev'..nodeId) then
      toolKit:log(DEBUG, 'No se pudo declarar variable global '..'dev'..nodeId)
      fibaro:abort()
    end
  end
  -- crear tabla vacía para dispositivo
  local PID = {result = 0, newErr = 0, acumErr = 0, proporcional = 0,
   integral = 0, derivativo = 0, lastInput = 0}
  local termostatoVirtual = {PID = PID, nodeId = nodeId, panelId = 0,
   probeId = 0, targetLevel = 0, value = 0, mode = 1, timestamp = os.time(),
   oN=false}
  -- guardar la tabla en la variable global
  fibaro:setGlobal('dev'..nodeId, json.encode(termostatoVirtual))
  return termostatoVirtual
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
  -- en cualquier otro caso iniciarlo y devolverlo
  return resetDevice(nodeId)
end

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
if not _selfId then
  _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
	-- recuperar dispositivo
	local termostatoVirtual = getDevice(_selfId)
	fibaro:debug('termostatoVirtual: '..json.encode(termostatoVirtual))
	-- actualizar etiqueta identificador
	fibaro:call(_selfId, "setProperty", "ui.labelId.value",'id: '.._selfId)
end
