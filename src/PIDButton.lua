--[[ TermostatoVirtual
	Dispositivo virtual
	PIDButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
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
  local termostatoVirtual = {nodeId = nodeId, panelId = 0, probeId = 0,
  targetLevel = 0, value = 0, mode = 1, timestamp = os.time()}
  -- guardar la tabla en la variable global
  fibaro:setGlobal('dev'..nodeId, json.encode(termostatoVirtual))
  return termostatoVirtual
end

--[[refreshLoook(termostatoVirtual)
  (table) termostatoVirtual: tabla que representa el termostato virtual
  actualiza los componentes visiales según el estado de la tabla--]]
function refreshLoook(termostatoVirtual)
  -- temperaturas
  fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value",
   '00.00ºC / 00.00ºC _')
  -- tiempo
  fibaro:call(_selfId, "setProperty", "ui.timeLabel.value", '00h 00m')
  -- estado
  fibaro:call(_selfId, "setProperty", "ui.modeLabel.value", '')
  -- sonda
  fibaro:call(_selfId, "setProperty", "ui.probeLabel.value", '0-🔧')
  -- actuador
  fibaro:call(_selfId, "setProperty", "ui.actuatorLabel.value", '0-🔧')
end

local termostatoVirtual = resetDevice(_selfId)
refreshLoook(termostatoVirtual)
--[[--------------------------------------------------------------------------]]
